/**
 * Helpers shared by /subscribe and /subscribe/complete: origin allowlist
 * (anti-open-redirect), plan catalog, and the post-PayPal entitlement
 * polling loop.
 *
 * See voxivium-web/CLAUDE.md §5 Phase 3, features.md §2.6.1.
 */

/** Plan IDs the shared /subscribe page knows about. */
export type SubscribePlanID = 'premium-subscriber-yearly'
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
  'premium-subscriber-yearly': {
    id: 'premium-subscriber-yearly',
    displayName: 'Premium Subscriber Yearly',
    description:
      'Annual voter premium tier — a personalized monthly analysis of how your elected officials are representing your most important beliefs, out-of-district report-card access, and shared-beliefs-in-your-community reports as they ship.',
    priceUSD: 19.95,
    priceLabel: '$19.95 / year',
    paypalPlanIdEnvKey: 'PUBLIC_PAYPAL_PLAN_ID_PREMIUM_SUBSCRIBER_YEARLY',
    allowedOrigins: ['kmp-web'],
  },
}

/**
 * One voter Premium tier as the marketing surfaces present it.
 *
 * Deliberately separate from SUBSCRIBE_PLANS above. That map is the
 * *purchasable* catalog — /subscribe validates ?plan= against it and refuses
 * anything it can't take money for. Web can only sell the yearly tier
 * (PayPal's Subscriptions API caps interval_count at 1 YEAR, so the two
 * one-time tiers have no billing path here), but the site should still
 * *show* all three. Listing only the most expensive-per-year option is the
 * worst of both worlds.
 *
 * Adding a tier here must never make it purchasable; that requires a
 * SUBSCRIBE_PLANS entry with a real paypalPlanIdEnvKey.
 */
export interface PremiumTier {
  /** Product identity — matches subscription_plan.name and the store product. */
  name: string
  priceLabel: string
  /** "per year" / "one-time" — the billing shape, spelled out. */
  termLabel: string
  /** Comparative value. Null for the baseline tier. */
  valueLabel: string | null
  /** Ribbon. Null for tiers that get none. */
  badge: string | null
  /** What the duration means in civic terms rather than calendar terms. */
  cycleLine: string
  /** Renewal truth — a five-year buyer must not assume it renews. */
  renewalLine: string
  /** True when web can actually sell it; false routes to the mobile apps. */
  purchasableOnWeb: boolean
}

/**
 * The three voter tiers, in ladder order.
 *
 * Prices mirror subscription_plan and the store products ($19.95 / $49.95 /
 * $99.00, CEO 2026-07-30). They are duplicated here rather than fetched
 * because this is a static marketing page — but they are the *list* prices,
 * and the amount charged always comes from PayPal or the store.
 *
 * Election-cycle framing is deliberately conservative: a 5-year entitlement
 * bought at any point covers a whole 4-year presidential term with a year to
 * spare, so that claim holds regardless of purchase date. Anything more
 * specific would be false for some buyers.
 */
export const PREMIUM_TIERS: PremiumTier[] = [
  {
    name: 'Premium Subscriber Yearly',
    priceLabel: '$19.95',
    termLabel: 'per year',
    valueLabel: null,
    badge: null,
    cycleLine: 'Through the next election.',
    renewalLine: 'Renews automatically. Cancel anytime.',
    purchasableOnWeb: true,
  },
  {
    name: 'Premium Subscriber 5-Year',
    priceLabel: '$49.95',
    termLabel: 'one payment, five years',
    valueLabel: '$9.99/year equivalent — save 50%',
    badge: 'Best value',
    cycleLine: 'Covers a full presidential term.',
    renewalLine: 'One payment. Does not renew automatically.',
    purchasableOnWeb: false,
  },
  {
    name: 'Premium Subscriber Lifetime',
    priceLabel: '$99.00',
    termLabel: 'one payment, forever',
    valueLabel: 'One payment. Never pay again.',
    badge: 'Founding supporter',
    cycleLine: 'Every election, for good.',
    renewalLine: 'One payment. Never expires.',
    purchasableOnWeb: false,
  },
]

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
