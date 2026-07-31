/**
 * Shared identity constants for structured data (JSON-LD).
 *
 * These strings are asserted to search engines as facts about the company, so
 * they must match what the site says elsewhere and what a third party could
 * verify. Don't add a `sameAs` entry for a profile that isn't live — an
 * unresolvable URL weakens the whole entity rather than strengthening it.
 */

export const SITE_URL = 'https://voxivium.com'

/** Stable @id anchors so nodes across pages resolve to one entity. */
export const ORG_ID = `${SITE_URL}/#organization`
export const SITE_ID = `${SITE_URL}/#website`
export const FOUNDER_ID = `${SITE_URL}/#founder`

export const ORG_NAME = 'Voxivium'
export const ORG_LEGAL_NAME = 'Voxivium, PBC'

export const ORG_DESCRIPTION =
  'Voxivium is a non-partisan political accountability platform. It shows verified voters how their elected officials actually vote, graded against the issues each voter says matter most.'

/**
 * Public profiles only. LinkedIn is the sole live presence as of 2026-07-31;
 * add X / YouTube here as they go live rather than guessing handles.
 */
export const ORG_SAME_AS = ['https://www.linkedin.com/company/voxivium-pbc/']

export const FOUNDER_NAME = 'Bob Seamon'
export const FOUNDER_TITLE = 'Founder, Voxivium'

/** Byline used on /insights posts. Kept here so it can't drift per-post. */
export const DEFAULT_AUTHOR = FOUNDER_NAME

export interface Breadcrumb {
  name: string
  /** Site-relative path, e.g. `/insights`. */
  path: string
}

export function absoluteUrl(path: string): string {
  return new URL(path, SITE_URL).toString()
}

/** The founder node, referenced by both the Organization and article bylines. */
export function personSchema() {
  return {
    '@type': 'Person',
    '@id': FOUNDER_ID,
    name: FOUNDER_NAME,
    jobTitle: FOUNDER_TITLE,
    url: absoluteUrl('/about'),
    worksFor: { '@id': ORG_ID },
  }
}

export function organizationSchema() {
  return {
    '@type': 'Organization',
    '@id': ORG_ID,
    name: ORG_NAME,
    legalName: ORG_LEGAL_NAME,
    url: SITE_URL,
    description: ORG_DESCRIPTION,
    logo: {
      '@type': 'ImageObject',
      url: absoluteUrl('/press/voxivium-logo-light.png'),
      width: 4557,
      height: 1565,
    },
    image: absoluteUrl('/og/default.png'),
    founder: { '@id': FOUNDER_ID },
    sameAs: ORG_SAME_AS,
    // Delaware-style Public Benefit Corporation. Signals the mission-first
    // charter that the /about page describes in prose.
    additionalType: 'https://en.wikipedia.org/wiki/Benefit_corporation',
    knowsAbout: [
      'Congressional voting records',
      'Political accountability',
      'Civic technology',
      'Non-partisan political transparency',
    ],
  }
}

export function websiteSchema() {
  return {
    '@type': 'WebSite',
    '@id': SITE_ID,
    url: SITE_URL,
    name: ORG_NAME,
    description: ORG_DESCRIPTION,
    publisher: { '@id': ORG_ID },
    inLanguage: 'en-US',
  }
}

export function breadcrumbSchema(crumbs: Breadcrumb[]) {
  return {
    '@type': 'BreadcrumbList',
    itemListElement: crumbs.map((crumb, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: crumb.name,
      item: absoluteUrl(crumb.path),
    })),
  }
}
