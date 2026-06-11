/**
 * Helpers shared by /subscribe and /subscribe/complete: origin allowlist
 * (anti-open-redirect), plan catalog, and the post-PayPal entitlement
 * polling loop.
 *
 * See voxivium-web/CLAUDE.md §5 Phase 3, features.md §2.6.1.
 */

/** Plan IDs the shared /subscribe page knows about. */
export type SubscribePlanID = 'civic-contributor'
// Future tiers (politician-federal / -state / -local) land here when the
// portal track ships. The page rejects unknown plan IDs.

/** Origin IDs allowed on the ?origin=… query param. */
export type SubscribeOrigin = 'kmp-web' | 'politician-portal'

/** Plan-catalog entry surfaced to the UI. */
export interface SubscribePlan {
  id: SubscribePlanID
  displayName: string
  description: string
  priceUSD: number
  priceLabel: string
  /** PayPal plan_id from the catalog provisioning. Loaded from import.meta.env at runtime. */
  paypalPlanIdEnvKey: string
  /** Origins permitted to subscribe to this plan (matches features.md §2.6.1). */
  allowedOrigins: SubscribeOrigin[]
}

export const SUBSCRIBE_PLANS: Record<SubscribePlanID, SubscribePlan> = {
  'civic-contributor': {
    id: 'civic-contributor',
    displayName: 'Premium Subscriber',
    description:
      'Annual voter premium tier — AI-generated politician reviews, out-of-district report-card access, and shared-beliefs-in-your-community reports as they ship.',
    priceUSD: 19.95,
    priceLabel: '$19.95 / year',
    paypalPlanIdEnvKey: 'PUBLIC_PAYPAL_PLAN_ID_CIVIC_CONTRIBUTOR',
    allowedOrigins: ['kmp-web'],
  },
}

/**
 * Parse the comma-separated PUBLIC_SUBSCRIBE_ALLOWED_ORIGINS env var into an
 * allowlist of full origin strings (e.g. "https://app.voxivium.com").
 */
export function allowedOriginURLs(): Set<string> {
  const raw = import.meta.env.PUBLIC_SUBSCRIBE_ALLOWED_ORIGINS ?? ''
  return new Set(
    raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  )
}

/** Mapping from human origin slug → return-redirect origin URL. */
const ORIGIN_RETURN_URLS: Record<SubscribeOrigin, string> = {
  'kmp-web': 'https://app.voxivium.com',
  'politician-portal': 'https://politician.voxivium.com',
}

/**
 * Resolve and validate the return URL for an origin slug. Returns null when
 * the slug is unrecognized OR when the resolved URL is not in the
 * PUBLIC_SUBSCRIBE_ALLOWED_ORIGINS allowlist (open-redirect guard). The
 * returned URL is the bare origin — callers append /subscribe/complete or
 * similar.
 */
export function resolveReturnOrigin(originSlug: string | null): string | null {
  if (!originSlug) return null
  const url = ORIGIN_RETURN_URLS[originSlug as SubscribeOrigin]
  if (!url) return null
  if (!allowedOriginURLs().has(url)) return null
  return url
}

/** Parsed + validated query-string state for /subscribe. */
export interface SubscribeQuery {
  plan: SubscribePlan
  originSlug: SubscribeOrigin
  returnURL: string
}

/**
 * Validate the /subscribe query string. Returns null when:
 *   - plan is missing or unknown
 *   - origin is missing or unknown
 *   - origin is not in the allowlist for the requested plan
 *   - origin is not in the global PUBLIC_SUBSCRIBE_ALLOWED_ORIGINS allowlist
 *
 * Callers should surface a "this link is not valid for this plan" message
 * when null is returned, NOT silently default.
 */
export function parseSubscribeQuery(search: URLSearchParams): SubscribeQuery | null {
  const planSlug = search.get('plan')
  const originSlug = search.get('origin') as SubscribeOrigin | null
  if (!planSlug || !originSlug) return null

  const plan = SUBSCRIBE_PLANS[planSlug as SubscribePlanID]
  if (!plan) return null

  if (!plan.allowedOrigins.includes(originSlug)) return null

  const returnURL = resolveReturnOrigin(originSlug)
  if (!returnURL) return null

  return { plan, originSlug, returnURL }
}
