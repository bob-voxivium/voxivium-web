# One-off admin scripts

Scripts that are run from an operator's workstation against a live service.
**Not Lambdas, not part of the runtime.** Each script documents its own
prerequisites in a header comment.

## `paypal_provision_catalog.py`

Creates PayPal Catalog Products + Subscriptions Plans for the off-mobile
subscription tiers. Run once per environment (sandbox + live).

After running, paste the printed `PUBLIC_PAYPAL_PLAN_ID_*` lines into:

- **Local dev**: `voxivium-web/.env`
- **Production**: AWS SSM Parameter Store under `/voxivium/web/`

See features.md §2.6.1 for the full architecture and CEO decisions
behind this.

### Workflow

```bash
cd voxivium-web/deploy/scripts

# 1. Sandbox first (testing)
export PAYPAL_ENV=sandbox
export PAYPAL_CLIENT_ID=<sandbox client id from developer.paypal.com>
export PAYPAL_SECRET=<sandbox secret>
python3 paypal_provision_catalog.py
# → copy the printed env vars into voxivium-web/.env

# 2. Once end-to-end works in sandbox, repeat against live
export PAYPAL_ENV=live
export PAYPAL_CLIENT_ID=<live client id from developer.paypal.com>
export PAYPAL_SECRET=<live secret>
python3 paypal_provision_catalog.py
# → store the printed env vars in AWS SSM
```

### Idempotency

The script is **NOT** automatically idempotent — running it twice will
create two Products and two Plans. PayPal's REST API does not support
"create or get by external id" for these resources. Record the resulting
`plan_id` values immediately and treat subsequent runs as deliberate
(e.g., adding a new tier).

### Adding new tiers

Edit `PLANS_TO_PROVISION` in the script, add a new `PlanSpec`, run the
script (sandbox first), and update `src/lib/subscribe.ts:SUBSCRIBE_PLANS`
to reference the new plan + its `paypalPlanIdEnvKey`.
