# Voxivium Website Infrastructure

Terraform configuration for the voxivium.com static site, contact forms, and mailing list. AWS-backed, fronted by Cloudflare.

## Architecture

```
voxivium.com (Cloudflare DNS + DDoS/WAF, "Full (strict)" SSL)
    ├── Static site → CloudFront → private S3 (OAC)
    └── /api/* → API Gateway HTTP API
                    ├── POST /subscribe → Lambda → DynamoDB (record_type=voter)
                    └── POST /contact   → Lambda → DynamoDB
                                                   (record_type=politician|media|ai
                                                     |partnership|careers|support,
                                                    pending="1" until emailed)
                                          └→ SES (support only, sent inline)

EventBridge cron (daily) → drain Lambda
    └── Query sparse `pending-index` GSI →
        for each item: SES email → REMOVE pending →
        finally: one Textbelt SMS

Admin: aws lambda invoke voxivium-list-subscribers (CLI only)
```

`support` is the exception to the daily-digest flow: the `/support` page is the
Support URL registered with App Store Connect and the Play Console, so those
submissions are emailed by the contact Lambda immediately (to
`support@voxivium.com`, Reply-To set to the requester) instead of waiting up to
24 hours for the drain. The row is still written for the record. If the inline
send fails, `pending` is left set so the drain retries it — the message is
never lost, only delayed to the digest.

All form submissions live in a single DynamoDB table `voxivium-submissions`,
keyed by a composite `pk` (`voter#<email>` or `contact#<uuid>`). A sparse GSI
on the `pending` attribute keeps the daily drain cheap: only un-emailed
contact records sit in the index, and they fall out automatically when the
flag is removed after a successful email send. Records are retained
indefinitely so the dataset is queryable forever.

## Project layout

```
voxivium-infra/
├── terraform/
│   ├── bootstrap/main.tf      # Run ONCE to create remote state backend
│   ├── providers.tf           # AWS + Cloudflare providers
│   ├── backend.tf             # S3 remote state
│   ├── variables.tf           # All configurable inputs
│   ├── terraform.tfvars.example
│   ├── website.tf             # static_site module (S3 + CloudFront + OAC) + outputs
│   ├── modules/static_site/   # Reusable CloudFront-fronted-S3 module (mirrored from voxivium-mvp)
│   ├── storage.tf             # DynamoDB submissions table + sparse pending GSI
│   ├── secrets.tf             # SSM SecureString parameters
│   ├── lambdas.tf             # 4 Lambda functions + IAM + EventBridge
│   ├── api.tf                 # API Gateway HTTP API + throttling
│   ├── dns.tf                 # Cloudflare DNS records
│   └── monitoring.tf          # CloudWatch alarms + SNS
└── lambdas/
    ├── subscribe/handler.py             # voter signups
    ├── list_subscribers/handler.py      # admin export of voters only
    ├── contact/handler.py               # politician/media/AI submissions
    └── drain_contact_queue/handler.py   # daily: pending GSI → emails + SMS
```

## Prerequisites

- Terraform ≥ 1.6
- AWS CLI configured with credentials for the new business account
- Cloudflare account, voxivium.com added (free plan), API token created with Zone:DNS:Edit + Zone:Zone:Read scoped to voxivium.com
- A Cloudflare Turnstile site (free) — note the **site key** (public, goes in your HTML) and **secret key** (private, goes in SSM)

## Step-by-step deployment

### Step 1 — Bootstrap the Terraform state backend

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Note the `state_bucket` output. Then:

```bash
cd ..   # back to terraform/
# Edit backend.tf and replace REPLACE-WITH-ACCOUNT-ID with the real bucket name
```

### Step 2 — Switch Cloudflare to be authoritative for DNS

In the Cloudflare dashboard:
1. Add voxivium.com as a site (Free plan)
2. Cloudflare will give you 2 nameservers
3. In Route 53 (your registrar), update the domain's nameservers to Cloudflare's. Propagation takes anywhere from a few minutes to 24 hours.
4. Do NOT add any DNS records yet — Terraform will create them

Grab your Cloudflare zone ID (right sidebar of the zone overview page).

### Step 3 — Configure variables 

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set cloudflare_zone_id
```

Set the Cloudflare API token as an env var (do NOT put it in tfvars):

```bash
export CLOUDFLARE_API_TOKEN='your-token'
export AWS_PROFILE=voxivium-business   # or whichever profile has the new account
```

### Step 4 — Build Lambda dependencies

Some Lambdas vendor third-party Python packages (currently just `pypdf` for
parsing uploaded resumes in the careers flow). Run the build script once,
and again any time a `requirements.txt` in a Lambda directory changes:

```bash
cd deploy
./build-lambdas.sh
```

The script installs each Lambda's requirements into a sibling `vendor/`
directory; `handler.py` adds that directory to `sys.path` at import time.
Terraform's `archive_file` then zips the whole Lambda directory (including
`vendor/`) into the deployment package automatically. Vendor directories
are gitignored.

### Step 5 — Initialize and apply

```bash
cd terraform
terraform init
terraform plan      # always review the plan before applying
terraform apply
```

This creates everything: S3 bucket, DynamoDB submissions table (with sparse `pending-index` GSI), SSM parameters (with placeholder values), 4 Lambdas, API Gateway, EventBridge schedule, Cloudflare DNS, alarms.

### Step 6 — Set the real secret values

The SSM parameters were created with placeholder strings. Replace them with the real values:

```bash
aws ssm put-parameter --name /voxivium/textbelt-api-key \
    --value 'YOUR_REAL_TEXTBELT_KEY' \
    --type SecureString --overwrite

aws ssm put-parameter --name /voxivium/turnstile-secret-key \
    --value 'YOUR_REAL_TURNSTILE_SECRET' \
    --type SecureString --overwrite
```

These are stored encrypted with AWS-managed KMS and are never visible in Terraform state.

### Step 7 — Verify SES domain in Cloudflare

You mentioned SES is already verified, but since Cloudflare is now authoritative for DNS, the existing DKIM CNAMEs (which were on Route 53) need to exist in Cloudflare. Check the SES console (Verified identities → voxivium.com → Authentication tab) for the three DKIM CNAME records and add them in Cloudflare DNS.

If they're already migrated, you can skip this.

### Step 8 — Subscribe to the alarms SNS topic

```bash
aws sns subscribe \
  --topic-arn $(terraform output -raw alarms_topic_arn) \
  --protocol email \
  --notification-endpoint your-email@example.com
```

Confirm via the email link.

### Step 9 — Deploy the website content

The S3 bucket is empty until you upload your site. The site needs to be built
*after* `terraform apply` so the real API Gateway URL is baked into the bundle.

```bash
# From the repo root (voxivium-web/), get the API endpoint and bake it into .env.
cd ../..                                                    # back to repo root
terraform -chdir=deploy/terraform output -raw api_endpoint  # note the URL

cp .env.example .env
# Edit .env and set:
#   PUBLIC_VOTER_FORM_ENDPOINT=<api_endpoint>/subscribe
#   PUBLIC_POLITICIAN_FORM_ENDPOINT=<api_endpoint>/contact
#   PUBLIC_MEDIA_FORM_ENDPOINT=<api_endpoint>/contact
#   PUBLIC_AI_LAB_FORM_ENDPOINT=<api_endpoint>/contact
#   PUBLIC_PARTNERSHIP_FORM_ENDPOINT=<api_endpoint>/contact
#   PUBLIC_CAREERS_FORM_ENDPOINT=<api_endpoint>/contact

pnpm install
pnpm build

aws s3 sync ./dist/ "s3://$(terraform -chdir=deploy/terraform output -raw site_bucket_name)/" --delete

aws cloudfront create-invalidation \
  --distribution-id "$(terraform -chdir=deploy/terraform output -raw site_cloudfront_distribution_id)" \
  --paths '/*'
```

Astro outputs to `dist/`, not `build/`. In practice you can just run
`./deploy/deploy.sh` which does the sync + CloudFront invalidation +
Cloudflare cache purge for you.

### Step 10 — Test

Static site: `https://voxivium.com` should serve your `index.html` through Cloudflare. (Check `dig +short voxivium.com` — you should see Cloudflare IPs, not S3.)

Form endpoints: get the API endpoint with `terraform output api_endpoint`, then wire your forms to POST to:
- `${api_endpoint}/subscribe`
- `${api_endpoint}/contact`

Each request body must include a `turnstile_token` from the Turnstile widget.

You can verify by submitting a test entry, then checking DynamoDB:

```bash
# All submissions (voter + contact records together)
aws dynamodb scan --table-name voxivium-submissions

# Just the contact submissions waiting to be emailed
aws dynamodb query \
  --table-name voxivium-submissions \
  --index-name pending-index \
  --key-condition-expression 'pending = :p' \
  --expression-attribute-values '{":p":{"S":"1"}}'
```

For the drain Lambda, you can trigger it manually to verify before the daily cron kicks in:

```bash
aws lambda invoke --function-name voxivium-drain-contact-queue \
  --cli-binary-format raw-in-base64-out \
  /tmp/drain-output.json
cat /tmp/drain-output.json
```

Each pending contact record will be sent as its own email, the `pending`
attribute will be removed (so the record falls out of the GSI but stays in
the table for history), and a single SMS summary will be sent if at least
one email succeeded.

### Step 11 — Pull the mailing list whenever you need it

```bash
aws lambda invoke --function-name voxivium-list-subscribers \
  --cli-binary-format raw-in-base64-out \
  /tmp/subs.json
cat /tmp/subs.json | jq -r '.subscribers[] | "\(.first_name), \(.email), \(.state)"'
```

For CSV:

```bash
aws lambda invoke --function-name voxivium-list-subscribers \
  --payload '{"format":"csv"}' --cli-binary-format raw-in-base64-out \
  /tmp/subs.json
cat /tmp/subs.json | jq -r '.csv' > subscribers.csv
```

The `list_subscribers` Lambda only returns voter records. To pull the full
contact-form history (politician/media/AI), scan the table directly with the
AWS CLI as shown in the verification section above.

## Front-end form snippets

The Astro form components in `src/components/forms/` already POST to these
endpoints with the correct shape. The snippets below document the wire
format if you need to reproduce a request by hand (or in another client).

All requests need a `turnstile_token` from the Turnstile widget, and all
field names on the wire are snake_case.

### Subscribe (POST /subscribe)

```json
{
  "first_name": "Jane",
  "email": "jane@example.com",
  "state": "CA",
  "turnstile_token": "..."
}
```

### Contact (POST /contact) — politician

```json
{
  "form_type": "politician",
  "first_name": "Jane",
  "last_name": "Doe",
  "email": "jane@example.com",
  "office": "U.S. House",
  "jurisdiction": "CA-12",
  "message": "Optional, ≤ 2000 chars",
  "turnstile_token": "..."
}
```

### Contact (POST /contact) — media

```json
{
  "form_type": "media",
  "name": "Jane Doe",
  "email": "jane@example.com",
  "organization": "Example News",
  "role": "Politics editor",
  "use_case": "How you'd use the data",
  "message": "Optional, ≤ 2000 chars",
  "turnstile_token": "..."
}
```

### Contact (POST /contact) — AI lab

```json
{
  "form_type": "ai",
  "name": "Jane Doe",
  "email": "jane@example.com",
  "organization": "Example AI",
  "use_case": "What you're evaluating",
  "scale": "~10k queries/month",
  "turnstile_token": "..."
}
```

### Contact (POST /contact) — partnership / grants

```json
{
  "form_type": "partnership",
  "name": "Jane Doe",
  "email": "jane@example.com",
  "organization": "Example Foundation",
  "role": "Program officer",
  "interest": "Civic engagement, democracy infrastructure",
  "message": "Optional, ≤ 2000 chars",
  "turnstile_token": "..."
}
```

### Contact (POST /contact) — careers

```json
{
  "form_type": "careers",
  "first_name": "Jane",
  "last_name": "Doe",
  "email": "jane@example.com",
  "phone": "Optional",
  "position": "Support, QA, and Deployment Engineer",
  "linkedin": "https://www.linkedin.com/in/jane-doe (optional)",
  "message": "Optional, ≤ 2000 chars",
  "resume_filename": "jane-doe-resume.pdf",
  "resume_base64": "JVBERi0xLjQK...",
  "turnstile_token": "..."
}
```

`position` must be one of: `Support, QA, and Deployment Engineer`,
`Marketing, Pricing, and Sales`, `Policy & Content Specialist`, or `Other`.
`resume_base64` is the raw base64 of a PDF file, 2 MiB or less. The Lambda
decodes it, extracts plain text with `pypdf`, stores the text on the
DynamoDB record as `resume_text`, and discards the binary.

## Security notes

- All Lambda IAM roles follow least privilege — `subscribe` and `contact` only get PutItem on the submissions table, `list_subscribers` only gets Scan, the drain role only gets Query (on the GSI) + UpdateItem, etc.
- S3 bucket is fully private; only CloudFront (via OAC + SourceArn condition) can read from it. Public traffic reaches the site through Cloudflare → CloudFront only.
- All form endpoints require Cloudflare Turnstile verification server-side
- Turnstile and Textbelt secrets stored encrypted in SSM, never in Terraform state, never in env vars
- SES `SendEmail` permission is conditioned on the From address — even if the drain or contact Lambda were compromised, it can only send as no-reply@voxivium.com
- The `/support` page publishes no literal address or `mailto:` href in its static HTML, so address harvesters have nothing to scrape; the fallback link is assembled client-side
- API Gateway is throttled (10 req/sec sustained, 20 burst) to cap abuse cost
- DynamoDB has point-in-time recovery and deletion protection
- Lambda errors trigger CloudWatch alarms via SNS
- Drain Lambda is idempotent: a transient SES failure leaves the `pending` flag intact and the next run picks the item back up; successful items fall out of the GSI so they won't be re-emailed

## Cost estimate (rough)

At low traffic this should be well under $5/month, dominated by:
- DynamoDB PITR backup storage (~$0.20)
- CloudWatch Logs storage (~$0.50)
- API Gateway requests ($1/million; effectively $0)
- Everything else in the free tier or pay-per-request

Cloudflare free tier covers DDoS, CDN, SSL, and DNS at $0.
