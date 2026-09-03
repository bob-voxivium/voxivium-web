# Changelog

Release history for the Voxivium marketing site, newest first. Sections
are written by `deploy/deploy.sh` from the git log, so an entry appears
when the site is actually deployed rather than when someone remembers to
write it down.

The version comes from the `VERSION` file at the repository root and
advances by one on every deploy. The short SHA in each heading is the
commit that was deployed, and is what the next deploy uses to work out
which commits are new — leave it in place when editing an entry by hand.

<!-- releases below -->

## site 0.4 — 2026-09-02 (17b1426)

- feat: add temporary fictional campaign page for scraper testing
- Rebrand the report card as the Accountability Scorecard

<sub>since 79bf142</sub>

## site 0.3 — 2026-08-25 (79bf142)

- fix: remove the support email address from the support page
- chore: record site 0.2 deploy

<sub>since 723cbd6</sub>

## site 0.2 — 2026-08-25 (723cbd6)

- feat: route account deletion requests through the support form
- feat: add support page for App Store Connect submission
- chore: version each deploy and record it in a changelog
- feat: add account deletion page for Google Play data safety
- Describe the yearly plan by what it delivers, not how it is made
- Say "official" for the person a sample report card grades
- Read /premium prices from the API instead of hardcoding them
- Add a public pricing page for the voter Premium tiers
- Quote $0.25 per voter and stop publishing the onboarded count
- Add SPF, DKIM and DMARC records for voxivium.com
- fix: capture approved PayPal donations instead of abandoning them
- feat(security): public security page, FAQ section, and RFC 9116 contact
- content(insights): explain the report card in the senator-vote how-to
- docs(seo): runbook and CLAUDE.md amendment for /insights
- feat(insights): editorial section at /insights
- fix(a11y): white text on primary buttons failed WCAG AA in dark mode
- perf(seo): cut image weight on every page
- feat(seo): crawler policy and sitemap hygiene
- feat(seo): structured data across the site
- feat(seo): complete page metadata and index control

<sub>most recent 20 commits — no prior site entry to measure from</sub>
