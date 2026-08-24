"""
Contact Lambda — handles POST /contact.

Expected JSON body (shape varies by form_type):

  politician:
    { "form_type": "politician", "first_name", "last_name", "email",
      "office", "jurisdiction", "message" (optional), "turnstile_token" }

  media:
    { "form_type": "media", "name", "email", "organization", "role",
      "use_case", "message" (optional), "turnstile_token" }

  ai:
    { "form_type": "ai", "name", "email", "organization", "use_case",
      "scale", "turnstile_token" }

  partnership:
    { "form_type": "partnership", "name", "email", "organization",
      "role" (optional), "interest", "message" (optional), "turnstile_token" }

  support:
    { "form_type": "support", "name", "email", "topic", "message",
      "app_version" (optional), "device" (optional), "turnstile_token" }
    This is the App Store / Play Store support channel, so it is the one form
    type that is emailed immediately rather than waiting for the daily digest
    (see the note on delivery below).

  careers:
    { "form_type": "careers", "first_name", "last_name", "email",
      "phone" (optional), "position", "linkedin" (optional),
      "message" (optional), "resume_base64", "resume_filename",
      "turnstile_token" }
    The resume PDF is decoded server-side and parsed to plain text via pypdf;
    the original bytes are not retained. Hard size cap of 2 MiB on decoded
    bytes mirrors the client-side cap as defense in depth.

Each submission is written to the shared submissions table with a unique pk
("contact#<uuid>"), record_type matching the form type, submitted_at, and a
sparse `pending = "1"` flag that the daily drain Lambda will clear once it
emails the submission.

Delivery: support submissions are emailed inline here, before the DynamoDB
write, because a support address published to Apple and Google cannot have a
24-hour first-response floor. The row is still written for the record. If the
inline send fails we fall back to writing the row *with* `pending` set, so the
daily drain picks it up rather than the message being lost.

On success: 202 with { "ok": true }
On failure: 400 / 403 / 500 with { "ok": false, "error": "..." }
"""

import base64
import io
import json
import os
import re
import sys
import uuid
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# Vendored third-party deps (installed by deploy/build-lambdas.sh into vendor/).
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "vendor"))

import boto3

_dynamodb = boto3.resource("dynamodb")
_ssm = boto3.client("ssm")
_table = _dynamodb.Table(os.environ["SUBMISSIONS_TABLE"])

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_URL_RE = re.compile(r"^https?://", re.IGNORECASE)
_VALID_FORM_TYPES = {"politician", "media", "ai", "partnership", "careers", "support"}
_VALID_CAREERS_POSITIONS = {
    "Support, QA, and Deployment Engineer",
    "Marketing, Pricing, and Sales",
    "Policy & Content Specialist",
    "Other",
}
_MAX_MESSAGE_LEN = 2000
_MAX_SUPPORT_MESSAGE_LEN = 4000  # mirrors supportRequestSchema on the client
_MAX_USE_CASE_LEN = 2000
_MAX_INTEREST_LEN = 2000
_MAX_RESUME_BYTES = 2 * 1024 * 1024  # mirrors the client-side cap
_MAX_RESUME_TEXT_LEN = 200_000  # truncate absurdly long extracted text
_MAX_FILENAME_LEN = 240
_VALID_SUPPORT_TOPICS = {
    "Signing in or account access",
    "Voter verification",
    "Billing or subscription",
    "Something is broken",
    "Feedback or a feature request",
    "Something else",
}

_turnstile_secret_cache = None

# Only the support path sends mail, so the SES client is created on first use
# rather than at import — the other form types shouldn't pay for it on a cold
# start.
_ses_client = None


def _ses():
    global _ses_client
    if _ses_client is None:
        _ses_client = boto3.client("ses")
    return _ses_client


def _get_turnstile_secret() -> str:
    global _turnstile_secret_cache
    if _turnstile_secret_cache is None:
        resp = _ssm.get_parameter(
            Name=os.environ["TURNSTILE_SECRET_PARAM"], WithDecryption=True
        )
        _turnstile_secret_cache = resp["Parameter"]["Value"]
    return _turnstile_secret_cache


def _verify_turnstile(token: str, source_ip: str) -> bool:
    if not token:
        return False
    data = urllib.parse.urlencode(
        {"secret": _get_turnstile_secret(), "response": token, "remoteip": source_ip}
    ).encode()
    req = urllib.request.Request(
        "https://challenges.cloudflare.com/turnstile/v0/siteverify", data=data
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return bool(json.loads(resp.read()).get("success"))
    except Exception:
        return False


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": os.environ.get("ALLOWED_ORIGIN", "*"),
        },
        "body": json.dumps(body),
    }


def _bounded(value, max_len: int) -> str:
    s = (value or "").strip()
    if not s or len(s) > max_len:
        raise ValueError("bounded string out of range")
    return s


def _optional_bounded(value, max_len: int) -> str:
    s = (value or "").strip()
    if len(s) > max_len:
        raise ValueError("optional string too long")
    return s


def _decode_resume(b64: str) -> bytes:
    if not b64 or not isinstance(b64, str):
        raise ValueError("missing resume")
    # Reject obviously oversized payloads before decoding (base64 inflates ~33%).
    if len(b64) > int(_MAX_RESUME_BYTES * 1.5):
        raise ValueError("resume too large")
    try:
        raw = base64.b64decode(b64, validate=True)
    except Exception:
        raise ValueError("invalid resume encoding")
    if len(raw) == 0:
        raise ValueError("empty resume")
    if len(raw) > _MAX_RESUME_BYTES:
        raise ValueError("resume too large")
    if not raw.startswith(b"%PDF-"):
        raise ValueError("resume is not a PDF")
    return raw


def _extract_pdf_text(pdf_bytes: bytes) -> str:
    """Extract plain text from a PDF. Raises ValueError on unreadable input."""
    # Lazy-import so the dependency is only resolved when actually needed;
    # this keeps cold start fast for non-careers form types.
    try:
        from pypdf import PdfReader
        from pypdf.errors import PdfReadError
    except ImportError as e:
        print(f"pypdf import failed: {e}")
        raise ValueError("server cannot parse PDF")

    try:
        reader = PdfReader(io.BytesIO(pdf_bytes))
    except PdfReadError as e:
        print(f"pypdf could not read PDF: {e}")
        raise ValueError("could not read PDF")
    except Exception as e:
        print(f"pypdf unexpected error opening PDF: {e}")
        raise ValueError("could not read PDF")

    if getattr(reader, "is_encrypted", False):
        raise ValueError("encrypted PDFs are not supported")

    parts = []
    for page in reader.pages:
        try:
            parts.append(page.extract_text() or "")
        except Exception as e:
            print(f"pypdf page extract failed: {e}")
            # Don't blow up the whole submission for one bad page.
            continue

    text = "\n\n".join(p.strip() for p in parts if p.strip())
    if not text:
        raise ValueError("could not extract text from PDF")
    if len(text) > _MAX_RESUME_TEXT_LEN:
        text = text[:_MAX_RESUME_TEXT_LEN] + "\n\n[... truncated ...]"
    return text


def _build_item(form_type: str, body: dict) -> dict:
    """Return a DynamoDB item for the given form_type, raising ValueError on bad input."""
    email = (body.get("email") or "").strip().lower()
    if not _EMAIL_RE.match(email) or len(email) > 254:
        raise ValueError("invalid email")

    item = {
        "pk": f"contact#{uuid.uuid4()}",
        "record_type": form_type,
        "email": email,
        "submitted_at": datetime.now(timezone.utc).isoformat(),
        "pending": "1",
    }

    if form_type == "politician":
        item["first_name"] = _bounded(body.get("first_name"), 48)
        item["last_name"] = _bounded(body.get("last_name"), 48)
        item["office"] = _bounded(body.get("office"), 120)
        item["jurisdiction"] = _bounded(body.get("jurisdiction"), 120)
        message = _optional_bounded(body.get("message"), _MAX_MESSAGE_LEN)
        if message:
            item["message"] = message

    elif form_type == "media":
        item["name"] = _bounded(body.get("name"), 96)
        item["organization"] = _bounded(body.get("organization"), 120)
        item["role"] = _bounded(body.get("role"), 120)
        item["use_case"] = _bounded(body.get("use_case"), _MAX_USE_CASE_LEN)
        message = _optional_bounded(body.get("message"), _MAX_MESSAGE_LEN)
        if message:
            item["message"] = message

    elif form_type == "ai":
        item["name"] = _bounded(body.get("name"), 96)
        item["organization"] = _bounded(body.get("organization"), 120)
        item["use_case"] = _bounded(body.get("use_case"), _MAX_USE_CASE_LEN)
        item["scale"] = _bounded(body.get("scale"), 120)

    elif form_type == "partnership":
        item["name"] = _bounded(body.get("name"), 96)
        item["organization"] = _bounded(body.get("organization"), 120)
        item["interest"] = _bounded(body.get("interest"), _MAX_INTEREST_LEN)
        role = _optional_bounded(body.get("role"), 120)
        if role:
            item["role"] = role
        message = _optional_bounded(body.get("message"), _MAX_MESSAGE_LEN)
        if message:
            item["message"] = message

    elif form_type == "careers":
        item["first_name"] = _bounded(body.get("first_name"), 48)
        item["last_name"] = _bounded(body.get("last_name"), 48)

        position = (body.get("position") or "").strip()
        if position not in _VALID_CAREERS_POSITIONS:
            raise ValueError("invalid position")
        item["position"] = position

        phone = _optional_bounded(body.get("phone"), 40)
        if phone:
            item["phone"] = phone

        linkedin = _optional_bounded(body.get("linkedin"), 300)
        if linkedin:
            if not _URL_RE.match(linkedin):
                raise ValueError("invalid linkedin url")
            item["linkedin"] = linkedin

        message = _optional_bounded(body.get("message"), _MAX_MESSAGE_LEN)
        if message:
            item["message"] = message

        filename = _bounded(body.get("resume_filename"), _MAX_FILENAME_LEN)
        item["resume_filename"] = filename

        pdf_bytes = _decode_resume(body.get("resume_base64") or "")
        item["resume_text"] = _extract_pdf_text(pdf_bytes)

    elif form_type == "support":
        item["name"] = _bounded(body.get("name"), 96)

        topic = (body.get("topic") or "").strip()
        if topic not in _VALID_SUPPORT_TOPICS:
            raise ValueError("invalid topic")
        item["topic"] = topic

        item["message"] = _bounded(body.get("message"), _MAX_SUPPORT_MESSAGE_LEN)

        app_version = _optional_bounded(body.get("app_version"), 40)
        if app_version:
            item["app_version"] = app_version

        device = _optional_bounded(body.get("device"), 120)
        if device:
            item["device"] = device

    else:  # pragma: no cover — guarded by caller
        raise ValueError("invalid form_type")

    return item


_SUPPORT_FIELD_ORDER = ["name", "email", "topic", "app_version", "device", "message"]


def _send_support_email(item: dict) -> None:
    """Email a support request immediately. Raises on failure.

    Reply-To is the requester so a reply from the support inbox reaches them
    directly. From stays the verified SES sender — sending as the requester
    would fail DMARC.
    """
    subject = f"[Voxivium support] {item['topic']} — {item['email']}"
    lines = [
        "New support request",
        f"Submitted at: {item['submitted_at']}",
        "",
    ]
    for field in _SUPPORT_FIELD_ORDER:
        if item.get(field):
            lines.append(f"{field.replace('_', ' ').title()}: {item[field]}")
    body = "\n".join(lines) + "\n"

    _ses().send_email(
        Source=os.environ["SES_FROM_ADDRESS"],
        Destination={"ToAddresses": [os.environ["SUPPORT_RECIPIENT"]]},
        ReplyToAddresses=[item["email"]],
        Message={
            "Subject": {"Data": subject},
            "Body": {"Text": {"Data": body}},
        },
    )


def lambda_handler(event, _context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"ok": False, "error": "invalid json"})

    form_type = (body.get("form_type") or "").strip().lower()
    token = body.get("turnstile_token") or ""

    if form_type not in _VALID_FORM_TYPES:
        return _response(400, {"ok": False, "error": "invalid form_type"})

    try:
        item = _build_item(form_type, body)
    except ValueError as e:
        return _response(400, {"ok": False, "error": str(e)})

    source_ip = event.get("requestContext", {}).get("http", {}).get("sourceIp", "")
    if not _verify_turnstile(token, source_ip):
        return _response(403, {"ok": False, "error": "captcha failed"})

    # Support is emailed inline rather than by the daily drain. On a send
    # failure we leave `pending` set so the drain retries it; the requester
    # still gets a success response because their message is durably stored.
    if form_type == "support":
        try:
            _send_support_email(item)
            item.pop("pending", None)
        except Exception as e:
            print(f"Immediate support email failed, leaving pending for drain: {e}")

    try:
        _table.put_item(Item=item)
    except Exception as e:
        print(f"DynamoDB error: {e}")
        return _response(500, {"ok": False, "error": "internal error"})

    return _response(202, {"ok": True})
