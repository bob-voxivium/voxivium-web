"""
PayPal Subscriptions API catalog provisioner.

ONE-OFF admin task. Run once per environment (sandbox + live, separately)
to create the PayPal Product + Plan records that the Voxivium subscription
flow references. The resulting `plan_id` values get pasted into the
voxivium-web environment as PUBLIC_PAYPAL_PLAN_ID_* variables.

This is NOT a Lambda. It's a one-shot script you invoke from your
workstation against the PayPal API directly.

Usage:
    # Sandbox (testing)
    export PAYPAL_ENV=sandbox
    export PAYPAL_CLIENT_ID=<sandbox client id>
    export PAYPAL_SECRET=<sandbox secret>
    python3 paypal_provision_catalog.py

    # Live (production)
    export PAYPAL_ENV=live
    export PAYPAL_CLIENT_ID=<live client id>
    export PAYPAL_SECRET=<live secret>
    python3 paypal_provision_catalog.py

Idempotency:
    The script is **NOT** automatically idempotent — running it twice will
    create two Products and two Plans, which is bad. PayPal's REST API
    does not have a "create-or-get by external id" semantic for these
    resources. The script prints the resulting product_id / plan_id so
    you can record them; subsequent runs should be intentional (e.g.,
    when adding a new tier).

References:
    https://developer.paypal.com/docs/api/catalog-products/v1/
    https://developer.paypal.com/docs/api/subscriptions/v1/
    voxivium-web/CLAUDE.md §2 (Python 3.14), features.md §2.6.1

Standard library only — Python 3.14.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.request
import urllib.error
from dataclasses import dataclass
from typing import Any


PAYPAL_LIVE_API = "https://api-m.paypal.com"
PAYPAL_SANDBOX_API = "https://api-m.sandbox.paypal.com"


@dataclass(frozen=True)
class PlanSpec:
    """A subscription plan to provision."""

    product_name: str
    product_description: str
    product_category: str  # PayPal category enum, e.g. "DIGITAL_GOODS"
    plan_name: str
    plan_description: str
    price_usd: str  # decimal string, e.g. "19.95"
    interval: str  # "YEAR" / "MONTH"
    env_key: str  # PUBLIC_PAYPAL_PLAN_ID_* — printed back to operator


# Add new tiers here when the portal track or media/AI Lab tiers ship.
PLANS_TO_PROVISION: list[PlanSpec] = [
    PlanSpec(
        product_name="Voxivium Premium Subscriber Yearly",
        product_description=(
            "Annual voter premium tier — AI-generated politician reviews, "
            "out-of-district report-card access."
        ),
        product_category="SOFTWARE",
        plan_name="Premium Subscriber Yearly",
        plan_description="Voxivium voter premium — $19.95 / year, auto-renewing.",
        price_usd="19.95",
        interval="YEAR",
        env_key="PUBLIC_PAYPAL_PLAN_ID_PREMIUM_SUBSCRIBER_YEARLY",
    ),
]


def get_oauth_token(api_base: str, client_id: str, secret: str) -> str:
    """OAuth2 client_credentials grant → access_token."""
    body = "grant_type=client_credentials".encode("ascii")
    auth = base64.b64encode(f"{client_id}:{secret}".encode("ascii")).decode("ascii")
    req = urllib.request.Request(
        f"{api_base}/v1/oauth2/token",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Basic {auth}",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req) as response:
        payload = json.loads(response.read())
    token = payload.get("access_token")
    if not token:
        raise RuntimeError(f"OAuth response missing access_token: {payload}")
    return token


def post_json(api_base: str, path: str, token: str, body: dict[str, Any]) -> dict[str, Any]:
    """Generic PayPal POST helper."""
    req = urllib.request.Request(
        f"{api_base}{path}",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"POST {path} failed: {e.code} {body_text}") from e


def create_product(api_base: str, token: str, spec: PlanSpec) -> str:
    """Create a PayPal Catalog Product. Returns product_id."""
    body = {
        "name": spec.product_name,
        "description": spec.product_description,
        "type": "SERVICE",
        "category": spec.product_category,
    }
    result = post_json(api_base, "/v1/catalogs/products", token, body)
    return result["id"]


def create_plan(api_base: str, token: str, spec: PlanSpec, product_id: str) -> str:
    """Create a Subscriptions Plan against the supplied Product. Returns plan_id."""
    body = {
        "product_id": product_id,
        "name": spec.plan_name,
        "description": spec.plan_description,
        "status": "ACTIVE",
        "billing_cycles": [
            {
                "frequency": {"interval_unit": spec.interval, "interval_count": 1},
                "tenure_type": "REGULAR",
                "sequence": 1,
                "total_cycles": 0,  # 0 = unlimited (auto-renewing forever)
                "pricing_scheme": {
                    "fixed_price": {"value": spec.price_usd, "currency_code": "USD"}
                },
            }
        ],
        "payment_preferences": {
            "auto_bill_outstanding": True,
            "setup_fee": {"value": "0", "currency_code": "USD"},
            "setup_fee_failure_action": "CONTINUE",
            "payment_failure_threshold": 3,
        },
        "taxes": {"percentage": "0", "inclusive": False},
    }
    result = post_json(api_base, "/v1/billing/plans", token, body)
    return result["id"]


def main() -> int:
    env = os.environ.get("PAYPAL_ENV", "").lower()
    if env not in ("sandbox", "live"):
        print("ERROR: set PAYPAL_ENV=sandbox or PAYPAL_ENV=live", file=sys.stderr)
        return 1
    client_id = os.environ.get("PAYPAL_CLIENT_ID")
    secret = os.environ.get("PAYPAL_SECRET")
    if not client_id or not secret:
        print("ERROR: set PAYPAL_CLIENT_ID and PAYPAL_SECRET", file=sys.stderr)
        return 1

    api_base = PAYPAL_LIVE_API if env == "live" else PAYPAL_SANDBOX_API
    print(f"Provisioning against PayPal {env} ({api_base})...")
    print("WARNING: This script is NOT idempotent. Running twice creates duplicates.")
    print("Press Ctrl-C in the next 5 seconds to abort.")
    try:
        import time
        time.sleep(5)
    except KeyboardInterrupt:
        print("Aborted by operator.")
        return 0

    token = get_oauth_token(api_base, client_id, secret)
    print(f"Got OAuth token ({len(token)} chars).")

    print("\n# Paste these into voxivium-web .env (or AWS SSM):")
    print(f"# Provisioned against PayPal {env}")
    for spec in PLANS_TO_PROVISION:
        print(f"\n# {spec.plan_name}")
        product_id = create_product(api_base, token, spec)
        print(f"#   product_id = {product_id}")
        plan_id = create_plan(api_base, token, spec, product_id)
        print(f"{spec.env_key}={plan_id}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
