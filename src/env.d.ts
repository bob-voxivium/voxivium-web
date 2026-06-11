/// <reference path="../.astro/types.d.ts" />

interface ImportMetaEnv {
  readonly PUBLIC_VOTER_FORM_ENDPOINT: string
  readonly PUBLIC_POLITICIAN_FORM_ENDPOINT: string
  readonly PUBLIC_MEDIA_FORM_ENDPOINT: string
  readonly PUBLIC_AI_LAB_FORM_ENDPOINT: string
  readonly PUBLIC_PARTNERSHIP_FORM_ENDPOINT: string
  readonly PUBLIC_CAREERS_FORM_ENDPOINT: string
  readonly PUBLIC_KICKSTARTER_URL: string
  readonly PUBLIC_TURNSTILE_SITE_KEY: string
  // Firebase Web SDK — same Firebase project as the KMP client. Used to
  // sign voter / future-politician users into the off-mobile payment
  // flows (see voxivium-web/CLAUDE.md §5 Phase 3, features.md §2.6.1).
  readonly PUBLIC_FIREBASE_API_KEY: string
  readonly PUBLIC_FIREBASE_AUTH_DOMAIN: string
  readonly PUBLIC_FIREBASE_PROJECT_ID: string
  readonly PUBLIC_FIREBASE_APP_ID: string
  // PayPal Smart Buttons client-id (sandbox or live). Loaded as a query
  // param onto the PayPal JS SDK <script> tag. Only the client-id is
  // permitted in browser JS — the PayPal secret stays server-side.
  readonly PUBLIC_PAYPAL_CLIENT_ID: string
  // Allowlist of origin sites that may redirect into /subscribe with
  // ?origin=… set. Comma-separated. Used to prevent open-redirect on the
  // /subscribe/complete return path. e.g.
  // "https://app.voxivium.com,https://politician.voxivium.com".
  readonly PUBLIC_SUBSCRIBE_ALLOWED_ORIGINS: string
  // Voxivium backend base URL used by /subscribe to confirm entitlement
  // post-PayPal (server-validated; client never trusts a redirect alone).
  readonly PUBLIC_VOXIVIUM_API_BASE: string
  // PayPal plan IDs (one per tier) — output of
  // deploy/scripts/paypal_provision_catalog.py. Empty value means the
  // corresponding tier's Smart Buttons won't mount.
  readonly PUBLIC_PAYPAL_PLAN_ID_CIVIC_CONTRIBUTOR: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
