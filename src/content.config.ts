import { defineCollection, z } from 'astro:content'
import { glob } from 'astro/loaders'

/**
 * Editorial content at /insights.
 *
 * Named "insights" rather than "blog" deliberately — CLAUDE.md §7 asks for a
 * trusted-utility voice, and "blog" reads scrappy-startup. Same SEO value.
 *
 * `sources` is required and must be non-empty. Voxivium's entire claim is that
 * it reports verifiable facts rather than opinion; an editorial page making
 * factual claims without citations undercuts that, and Google's quality
 * guidance for civic/political content weights sourcing heavily. The schema
 * enforces it so it can't be skipped under deadline.
 */
const insights = defineCollection({
  loader: glob({ base: './src/content/insights', pattern: '**/*.md' }),
  schema: z.object({
    title: z.string().max(70, 'Keep titles under 70 chars so they survive SERP truncation.'),
    description: z
      .string()
      .min(70, 'Too short to earn a click.')
      .max(165, 'Google truncates meta descriptions past ~160 chars.'),
    publishDate: z.coerce.date(),
    updatedDate: z.coerce.date().optional(),
    author: z.string().default('Bob Seamon'),
    /** Short label shown on cards and used for on-page grouping. */
    topic: z.enum(['How to', 'Methodology', 'Research', 'Product']),
    /** Cited sources. Non-empty by design — see note above. */
    sources: z
      .array(z.object({ label: z.string(), url: z.string().url() }))
      .min(1, 'Every insights post must cite at least one verifiable source.'),
    /** Set true to keep a post out of the build entirely. */
    draft: z.boolean().default(false),
    /** Per-post social card. Falls back to the site default when omitted. */
    ogImage: z.string().optional(),
  }),
})

export const collections = { insights }
