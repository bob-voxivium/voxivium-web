# SEO runbook — voxivium.com

What is in place, what only the CEO can finish, and what to check before shipping
a new page. Written 2026-07-31.

---

## 1. What the site does automatically

Handled by `BaseLayout.astro` and `astro.config.mjs`. You do not need to think
about these when adding a page.

| Concern | Where |
| --- | --- |
| Canonical URL | `BaseLayout` derives it from `Astro.url` unless overridden |
| `robots` meta | `index, follow` by default; `noindex` via the `noindex` prop |
| OpenGraph + Twitter cards | Full set, including image dimensions and alt |
| Organization / WebSite / Person JSON-LD | Emitted on every indexable page |
| Breadcrumbs | Pass the `breadcrumbs` prop; schema is generated |
| Sitemap | Auto-generated, with `lastmod`, `changefreq`, `priority` |
| Font preload | Inter latin woff2, preloaded in the head |

### Adding a page: the four-item checklist

1. **Unique `title`**, under ~60 characters so it survives SERP truncation.
2. **Unique `description`**, 70 to 165 characters. Not optional. A missing one
   silently falls back to the generic site default, which is what the home page
   was doing before this work.
3. **`breadcrumbs` prop**, unless the page is the home page.
4. **`noindex`** if the page is transactional, a form-return target, or
   otherwise not something a stranger should land on from Google.

### Adding an /insights post

Drop a Markdown file in `src/content/insights/`. The Zod schema in
`src/content.config.ts` enforces title length, description length, and at least
one cited source. The build fails if any is missing, which is intentional.

Set `draft: true` to keep a post out of the build entirely.

---

## 2. Owner tasks (CEO only)

These need account access. Nothing else in this document is blocked on them,
but organic search performance cannot be measured until they are done.

### 2.1 Google Search Console

1. Go to <https://search.google.com/search-console> and add a **Domain**
   property for `voxivium.com` (domain, not URL-prefix — it covers every
   subdomain and both protocols).
2. Google supplies a TXT record. Add it in Cloudflare DNS for the
   `voxivium.com` zone (zone ID `db1548373f1b0aa81cc6d18bfb50fdfc`, referenced
   in `deploy/deploy.sh`).
3. Verify, then submit `https://voxivium.com/sitemap-index.xml` under
   **Sitemaps**.

Check back after about a week. The reports that matter early:

- **Pages** — how many URLs are indexed, and the reason for any exclusions.
- **Performance** — the queries actually bringing people in.
- **Enhancements → FAQ / Breadcrumbs** — confirms the structured data parsed.

### 2.2 Bing Webmaster Tools

<https://www.bing.com/webmasters>. Supports importing directly from Search
Console, so do it second and the setup takes about a minute. Worth doing:
Bing's index also feeds several AI assistants.

### 2.3 Rich result validation

After the next deploy, run these against the live URLs:

- Google Rich Results Test — <https://search.google.com/test/rich-results>
  - `https://voxivium.com/faq/` should report **FAQ** (27 questions)
  - any `/insights/` post should report **Article** and **Breadcrumbs**
- Schema.org validator — <https://validator.schema.org/>
- Social cards — paste a URL into LinkedIn's Post Inspector
  (<https://www.linkedin.com/post-inspector/>) to confirm the OG image renders
  and to prime LinkedIn's cache.

---

## 3. Pre-deploy verification

`pnpm build` catches schema violations. These two are worth running by hand
before a deploy that touches metadata, routing, or images.

### Broken internal links

```bash
node -e "
const fs=require('fs'),path=require('path');
const files=[];(function w(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);e.isDirectory()?w(p):e.name.endsWith('.html')&&files.push(p)}})('dist');
const bad=new Set();
for(const f of files){const h=fs.readFileSync(f,'utf8');
  for(const m of h.matchAll(/href=\"(\/[^\"#?]*)\"/g)){const href=m[1];
    if(href.startsWith('/_astro'))continue;
    if(!['dist'+href,'dist'+href+'index.html','dist'+href+'/index.html'].some(c=>fs.existsSync(c)))bad.add(href);}}
console.log(bad.size?[...bad].join('\n'):'no broken internal links');
"
```

### Lighthouse

```bash
pnpm build && pnpm preview --port 4321 &
sleep 3
export CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
npx -y lighthouse http://localhost:4321/ --quiet \
  --chrome-flags="--headless=new" \
  --only-categories=performance,accessibility,best-practices,seo --view
```

Lighthouse is deliberately not a project dependency — it is ~100 MB and only
needed occasionally. `npx -y` fetches it transiently.

**Baseline, 2026-07-31, mobile, local production build:**

| Page | Perf | A11y | Best practices | SEO | LCP |
| --- | --- | --- | --- | --- | --- |
| `/` | 100 | 100 | 96 | 100 | 1.7 s |
| `/insights/how-candidate-scoring-works/` | 100 | 100 | 100 | 100 | 1.5 s |

The home page's 96 on best practices is four Cloudflare Turnstile console
errors (code 110200, "domain not allowed"), which is expected on `localhost`
because the Turnstile sitekey is bound to `voxivium.com`. **This has not been
confirmed against production** — re-run against the live URL after the next
deploy and confirm the errors are absent.

---

## 4. Decisions on record

**AI crawlers are allowed.** Decided by CEO, 2026-07-31. `public/robots.txt`
names GPTBot, ClaudeBot, PerplexityBot, CCBot, Google-Extended and others
explicitly. The reasoning is in the file's header comment. Do not tighten this
incidentally.

**`/subscribe` is crawlable but noindexed.** A `noindex` directive can only be
obeyed if the crawler is allowed to fetch the page and read it. Disallowing the
path in `robots.txt` would leave the URL eligible for indexing with no
description. Leave it as is.

**The home page `<h1>` stays brand copy.** "Common ground, made visible."
carries no keyword signal, and that is a deliberate trade. Search intent is
carried by the `<title>`, the meta description, and section `<h2>`s. Decided by
CEO, 2026-07-31.

---

## 5. Known gaps

- **`sameAs` lists only LinkedIn.** `src/lib/seo.ts` holds the array. Add X,
  YouTube, and others as they go live. Never add a URL that does not resolve.
- **No per-post OG images.** Every `/insights` post falls back to the site
  default card. The `ogImage` frontmatter field accepts a path when per-post
  cards are worth making.
- **`public/press/bob_corporate.png` is 6.2 MB** and ships to S3 on every
  deploy. Nothing links to it — the press page lives in `src/_archive/`. It is
  not an SEO problem, but it is dead weight at the edge. Deleting it needs CEO
  sign-off since it is a deliberate press asset.
- **No analytics.** CLAUDE.md §3 permits Cloudflare Web Analytics or Plausible
  and rules out Google Analytics. Search Console covers search performance;
  it does not cover on-site behavior.
