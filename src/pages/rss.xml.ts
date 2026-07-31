import type { APIRoute } from 'astro'
import { getCollection } from 'astro:content'
import { ORG_NAME, SITE_URL, absoluteUrl } from '@lib/seo'

/**
 * RSS 2.0 feed for /insights.
 *
 * Written by hand rather than pulling in @astrojs/rss: the feed is ~30 lines
 * of string building, and CLAUDE.md §8 asks that a dependency earn its place.
 */

/** Escapes the five XML predefined entities. Applied to every interpolated value. */
function xmlEscape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

export const GET: APIRoute = async () => {
  const posts = (await getCollection('insights', ({ data }) => !data.draft)).sort(
    (a, b) => b.data.publishDate.valueOf() - a.data.publishDate.valueOf()
  )

  const items = posts
    .map((post) => {
      const link = absoluteUrl(`/insights/${post.id}/`)
      return `    <item>
      <title>${xmlEscape(post.data.title)}</title>
      <link>${xmlEscape(link)}</link>
      <guid isPermaLink="true">${xmlEscape(link)}</guid>
      <description>${xmlEscape(post.data.description)}</description>
      <pubDate>${post.data.publishDate.toUTCString()}</pubDate>
      <category>${xmlEscape(post.data.topic)}</category>
      <dc:creator>${xmlEscape(post.data.author)}</dc:creator>
    </item>`
    })
    .join('\n')

  // Newest post's date, not build time — a feed whose lastBuildDate churns on
  // every deploy trains readers to re-poll for nothing.
  const lastBuild = posts[0]?.data.publishDate ?? new Date(0)

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${xmlEscape(ORG_NAME)} Insights</title>
    <link>${SITE_URL}/insights</link>
    <atom:link href="${SITE_URL}/rss.xml" rel="self" type="application/rss+xml" />
    <description>Plain explanations of how political accountability data works — how votes are tracked, how scores are built, and what the numbers do and do not show.</description>
    <language>en-us</language>
    <lastBuildDate>${lastBuild.toUTCString()}</lastBuildDate>
${items}
  </channel>
</rss>
`

  return new Response(xml, {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  })
}
