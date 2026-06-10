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
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
