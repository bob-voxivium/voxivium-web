"""
Subscribe Lambda — handles POST /subscribe.

Expected JSON body:
    {
      "first_name": "Jane",
      "email": "jane@example.com",
      "state": "CA",
      "turnstile_token": "..."
    }

On success: 201 with { "ok": true }
On failure: 400 / 403 / 500 with { "ok": false, "error": "..." }

Stores the record in the shared submissions table with pk = "voter#<email>"
so the same table can hold contact-form records (pk = "contact#<uuid>")
without collisions. Uses a conditional write so re-subscribing keeps the
original signup timestamp.
"""

import json
import os
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

_dynamodb = boto3.resource("dynamodb")
_ssm = boto3.client("ssm")
_table = _dynamodb.Table(os.environ["SUBMISSIONS_TABLE"])

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_STATE_RE = re.compile(r"^[A-Z]{2}$")
_MAX_NAME_LEN = 100

_turnstile_secret_cache = None


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


def lambda_handler(event, _context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"ok": False, "error": "invalid json"})

    first_name = (body.get("first_name") or "").strip()
    email = (body.get("email") or "").strip().lower()
    state = (body.get("state") or "").strip().upper()
    token = body.get("turnstile_token") or ""

    if not first_name or len(first_name) > _MAX_NAME_LEN:
        return _response(400, {"ok": False, "error": "invalid first_name"})
    if not _EMAIL_RE.match(email) or len(email) > 254:
        return _response(400, {"ok": False, "error": "invalid email"})
    if not _STATE_RE.match(state):
        return _response(400, {"ok": False, "error": "invalid state"})

    source_ip = event.get("requestContext", {}).get("http", {}).get("sourceIp", "")
    if not _verify_turnstile(token, source_ip):
        return _response(403, {"ok": False, "error": "captcha failed"})

    try:
        _table.put_item(
            Item={
                "pk": f"voter#{email}",
                "record_type": "voter",
                "email": email,
                "first_name": first_name,
                "state": state,
                "submitted_at": datetime.now(timezone.utc).isoformat(),
            },
            ConditionExpression="attribute_not_exists(pk)",
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            # Already subscribed — return success without leaking that fact.
            return _response(201, {"ok": True})
        print(f"DynamoDB error: {e}")
        return _response(500, {"ok": False, "error": "internal error"})

    return _response(201, {"ok": True})
