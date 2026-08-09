# =============================================================================
# Cloudflare DNS records
# =============================================================================
# Prerequisite: voxivium.com is added to Cloudflare and its nameservers are
# changed at the registrar (Route 53 in your case) to Cloudflare's.
#
# The apex record (voxivium.com) is created by the static_site module in
# website.tf. The www record is created here because the module only takes
# a single hostname; both point at the same CloudFront distribution.
#
# Records are PROXIED (orange cloud) so traffic flows through Cloudflare's
# edge — that's what gives you DDoS, WAF, and (now) valid end-to-end TLS
# when the zone is set to "Full (strict)".
# =============================================================================

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  content = module.site.cloudfront_domain
  proxied = true
  ttl     = 1 # 1 = automatic when proxied
  comment = "www subdomain fronted by same CloudFront distribution as the apex"
}

# SES domain verification: TXT record. After `terraform apply`, get the
# verification token from the SES console (Verified identities → voxivium.com)
# and store it in terraform.tfvars as `ses_verification_token`. Or skip this
# resource if you've already verified the domain via a different method.

# =============================================================================
# Email authentication (SPF / DKIM / DMARC)
# =============================================================================
# Voxivium sends transactional mail that people are owed: donation and
# subscription receipts are proof of payment. A receipt in a spam folder
# is functionally a receipt that was never sent, so these records are a
# payment-integrity concern, not a marketing one.
#
# The three mechanisms do different jobs:
#
#   SPF   — lists which servers may send for this domain. Checked against
#           the envelope sender, not the visible From address.
#   DKIM  — cryptographically signs each message. This is what makes SES
#           mail pass DMARC, because SES signs as voxivium.com while its
#           default envelope sender is amazonses.com (so SPF alone does
#           not "align" for DMARC purposes).
#   DMARC — tells receivers what to do when neither aligns, and asks them
#           to send you reports.
#
# ORDER MATTERS. Publish DMARC at p=none first and read the reports for a
# couple of weeks before tightening. A p=reject policy published before
# DKIM and SPF are correct causes receivers to discard your own outbound
# mail — including receipts.
# =============================================================================

# ── DKIM (SES) ───────────────────────────────────────────────────────────
# Three CNAMEs from SES console → Verified identities → voxivium.com →
# Authentication / DKIM. Cloudflare is authoritative for this zone, so
# they must live here; DKIM records left behind in Route 53 do nothing.
#
# Defaults to an empty list, which creates no records — fill in
# ses_dkim_tokens in terraform.tfvars to activate.
resource "cloudflare_record" "ses_dkim" {
  for_each = toset(var.ses_dkim_tokens)

  zone_id = var.cloudflare_zone_id
  name    = "${each.value}._domainkey"
  type    = "CNAME"
  content = "${each.value}.dkim.amazonses.com"
  proxied = false # Cloudflare must never proxy an authentication record
  ttl     = 3600
  comment = "SES Easy DKIM — signs outbound mail as voxivium.com so it aligns for DMARC"
}

# ── SPF ──────────────────────────────────────────────────────────────────
# There is currently NO SPF record on voxivium.com. That is not itself a
# failure (absent SPF evaluates to "none", not "fail"), but it leaves the
# domain easier to spoof and weakens deliverability.
#
# CHECK BEFORE APPLYING: this record must name every service that sends
# mail as @voxivium.com. The default covers Google Workspace (the zone's
# MX is smtp.google.com) and Amazon SES. If anything else sends as this
# domain — a CRM, a helpdesk, a newsletter tool — add its include first,
# or that mail starts failing SPF the moment this is published.
#
# Ends in ~all (softfail) rather than -all (hardfail) deliberately: a
# missed sender degrades to "suspicious" rather than "rejected". Tighten
# to -all once DMARC reports show a couple of clean weeks.
resource "cloudflare_record" "spf" {
  count = var.spf_record == "" ? 0 : 1

  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  content = var.spf_record
  proxied = false
  ttl     = 3600
  comment = "SPF — authorizes Google Workspace + Amazon SES to send as voxivium.com"
}

# ── DMARC ────────────────────────────────────────────────────────────────
# Published at _dmarc.voxivium.com. Starts at p=none: receivers change
# nothing about their handling, but they mail you aggregate reports on
# what is being sent as voxivium.com and whether it authenticates. That is
# the point of starting here — you find out what you actually send before
# you start telling receivers to discard anything.
#
# Ramp once reports are clean: none → quarantine → reject, by changing
# dmarc_policy and re-applying. Do not skip to reject.
resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=${var.dmarc_policy}; rua=mailto:${var.dmarc_report_email}; fo=1; adkim=r; aspf=r; pct=100"
  proxied = false
  ttl     = 3600
  comment = "DMARC — policy is ${var.dmarc_policy}; ramp to quarantine then reject once reports are clean"
}
