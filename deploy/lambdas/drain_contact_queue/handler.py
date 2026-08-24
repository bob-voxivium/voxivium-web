"""
Drain Contact Queue Lambda — runs daily via EventBridge.

Despite the historical name, this no longer reads from SQS. It queries the
sparse `pending-index` GSI on the submissions table, which only contains
contact-form items that haven't been emailed yet.

Workflow:
    1. Query the GSI for all items where pending = "1".
    2. For each item: send a SES email; on success, REMOVE the `pending`
       attribute (which also removes the item from the sparse GSI).
    3. After the loop, if at least one email succeeded, send a single SMS
       via Textbelt.

Failure semantics:
    - Per-item idempotency: a failed SES send leaves `pending` intact, so
      that item gets retried on the next run. Successful items don't get
      re-emailed because they fall out of the GSI.
    - SMS is best-effort. SMS failure does not block anything.
"""

import json
import os
import urllib.parse
import urllib.request
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key

_dynamodb = boto3.resource("dynamodb")
_ses = boto3.client("ses")
_ssm = boto3.client("ssm")

_TABLE = _dynamodb.Table(os.environ["SUBMISSIONS_TABLE"])
_INDEX = os.environ.get("PENDING_INDEX_NAME", "pending-index")
_FROM = os.environ["SES_FROM_ADDRESS"]
_TO = os.environ["DIGEST_RECIPIENT"]
# Support rows only land here when the contact Lambda's inline send failed.
# Honor the same topic-based recipient split it uses, so a retried deletion
# request doesn't quietly end up in the general digest inbox.
_SUPPORT_TO = os.environ.get("SUPPORT_RECIPIENT", _TO)
_PRIVACY_TO = os.environ.get("PRIVACY_RECIPIENT", _TO)
_PRIVACY_TOPICS = {"Account deletion or data request"}
_SMS_NUMBER = os.environ["SMS_RECIPIENT_NUMBER"]
_SMS_ADMIN_EMAIL = os.environ["SMS_ADMIN_EMAIL"]
_TEXTBELT_PARAM = os.environ["TEXTBELT_KEY_PARAM"]

# Field display order per record_type, used to format the email body.
_FIELD_ORDER = {
    "politician": [
        "first_name",
        "last_name",
        "email",
        "office",
        "jurisdiction",
        "message",
    ],
    "media": [
        "name",
        "email",
        "organization",
        "role",
        "use_case",
        "message",
    ],
    "ai": [
        "name",
        "email",
        "organization",
        "use_case",
        "scale",
    ],
    "partnership": [
        "name",
        "email",
        "organization",
        "role",
        "interest",
        "message",
    ],
    "careers": [
        "first_name",
        "last_name",
        "email",
        "phone",
        "position",
        "linkedin",
        "message",
        "resume_filename",
        "resume_text",
    ],
    # Support requests are normally emailed inline by the contact Lambda. They
    # only reach this digest when that inline send failed, so the row stayed
    # pending — this entry is the retry path, not the usual one.
    "support": [
        "name",
        "email",
        "topic",
        "app_version",
        "device",
        "message",
    ],
}


def _query_pending() -> list[dict]:
    """Return every item in the sparse pending GSI."""
    items: list[dict] = []
    kwargs: dict[str, Any] = {
        "IndexName": _INDEX,
        "KeyConditionExpression": Key("pending").eq("1"),
    }
    while True:
        resp = _TABLE.query(**kwargs)
        items.extend(resp.get("Items", []))
        last_key = resp.get("LastEvaluatedKey")
        if not last_key:
            break
        kwargs["ExclusiveStartKey"] = last_key
    return items


def _format_body(item: dict) -> str:
    record_type = item.get("record_type", "unknown")
    submitted_at = item.get("submitted_at", "")
    field_order = _FIELD_ORDER.get(record_type, sorted(item.keys()))

    lines = [
        f"New {record_type} contact form submission",
        f"Submitted at: {submitted_at}",
        "",
    ]
    for field in field_order:
        if field in item and item[field]:
            label = field.replace("_", " ").title()
            lines.append(f"{label}: {item[field]}")
    return "\n".join(lines) + "\n"


def _recipient_for(item: dict) -> str:
    """Where this item's email goes. Only support rows deviate from the digest."""
    if item.get("record_type") != "support":
        return _TO
    return _PRIVACY_TO if item.get("topic") in _PRIVACY_TOPICS else _SUPPORT_TO


def _send_email(item: dict) -> None:
    """Raises on failure so the item stays pending and gets retried."""
    record_type = item.get("record_type", "unknown")
    email = item.get("email", "unknown")
    subject = f"[Voxivium {record_type}] new submission from {email}"
    kwargs = {
        "Source": _FROM,
        "Destination": {"ToAddresses": [_recipient_for(item)]},
        "Message": {
            "Subject": {"Data": subject},
            "Body": {"Text": {"Data": _format_body(item)}},
        },
    }
    # A retried support request should still be replyable in one click.
    if record_type == "support" and item.get("email"):
        kwargs["ReplyToAddresses"] = [item["email"]]
    _ses.send_email(**kwargs)


def _clear_pending(pk: str) -> None:
    """Drop the `pending` attribute so the item falls out of the GSI."""
    _TABLE.update_item(
        Key={"pk": pk},
        UpdateExpression="REMOVE pending",
    )


def _send_sms(count: int) -> bool:
    try:
        resp = _ssm.get_parameter(Name=_TEXTBELT_PARAM, WithDecryption=True)
        api_key = resp["Parameter"]["Value"]
    except Exception as e:
        print(f"Failed to read Textbelt key: {e}")
        return False

    body = f"Voxivium: {count} new contact form submission(s) emailed to {_SMS_ADMIN_EMAIL}"
    data = urllib.parse.urlencode(
        {"phone": _SMS_NUMBER, "message": body, "key": api_key}
    ).encode()
    req = urllib.request.Request("https://textbelt.com/text", data=data)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            result = json.loads(r.read())
            if not result.get("success"):
                print(f"Textbelt rejected send: {result}")
                return False
            print(f"SMS sent. Quota remaining: {result.get('quotaRemaining')}")
            return True
    except Exception as e:
        print(f"Textbelt error: {e}")
        return False


def lambda_handler(_event, _context):
    pending = _query_pending()
    print(f"Found {len(pending)} pending submission(s)")

    if not pending:
        return {"ok": True, "emailed": 0, "failed": 0}

    emailed = 0
    failed = 0
    for item in pending:
        pk = item.get("pk")
        if not pk:
            print(f"Skipping pending item without pk: {item}")
            continue
        try:
            _send_email(item)
        except Exception as e:
            failed += 1
            print(f"SES send failed for {pk}: {e}")
            continue
        try:
            _clear_pending(pk)
            emailed += 1
        except Exception as e:
            # Email went out but we couldn't clear the flag — log loudly.
            # The next run will re-email this item; pick a recipient who
            # tolerates the rare duplicate over a missed message.
            print(f"WARNING: emailed {pk} but failed to clear pending: {e}")
            emailed += 1

    sms_ok = False
    if emailed > 0:
        sms_ok = _send_sms(emailed)

    return {"ok": True, "emailed": emailed, "failed": failed, "sms_sent": sms_ok}
