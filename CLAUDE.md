# CLAUDE.md — Voxivium Marketing Site

This file is the source of truth for how Claude should work in this repository. Read it fully before making changes. If anything here conflicts with a user instruction in the moment, follow the user but flag the conflict.

## 1. Project at a glance

**What this is:** The public-facing marketing website for Voxivium — a Public Benefit Corporation building a non-partisan political accountability platform. The site's job is to inform visitors, build anticipation for the app launch, and capture early-access signups across four audiences.

**What this is NOT:** The app itself. No user accounts, no voter verification, no report cards, no political data. Those live in a separate Android codebase (Kotlin/Compose).

**Primary goals, in priority order:**
1. Explain what Voxivium does clearly enough that a first-time visitor "gets it" in under 30 seconds.
2. Drive early-access signups via the voter email form on the home page.
3. Capture leads from four distinct audiences: voters, politicians, media/research organizations, and AI labs.
4. Showcase the launch trailer prominently once it exists.

**Note on Kickstarter:** Kickstarter framing has been removed from all user-facing copy and navigation. The `/kickstarter` page file and the `KickstarterCTA` component still exist in the repo for possible future reuse, but they are not linked from anywhere and should not be reintroduced into nav, hero, or page flows without an explicit conversation.

**Audiences (treat each as a first-class persona):**
- **Voters** — want to know what's in it for them; lightweight email signup.
- **Politicians** — want to understand the constituent insights they'd gain; need a richer contact form (office, jurisdiction, message).
- **Media & Research** — want data licensing details; contact form with organization, role, use case.
- **AI Labs** — want the "ground truth alignment" pitch; contact form with org, use case, scale.

## 2. Tech stack — locked decisions

Do not change these without an explicit conversation. They were chosen for AI-friendliness, low ops burden, and long-term maintainability.

- **Framework:** Astro (latest stable). Use `.astro` files for pages and static layout. Use React islands (`client:load`, `client:visible`) only where genuine interactivity is required (forms, tabbed audience sections, video modals).
- **Styling:** Tailwind CSS via the official Astro integration. No CSS-in-JS, no styled-components. Custom design tokens live in `tailwind.config.mjs` mapped from the Voxivium palette (see §4).
- **Language:** TypeScript everywhere. `strict: true` in `tsconfig.json`. No `any` without an inline justification comment.
- **Forms / backend:** AWS Lambda behind API Gateway. New Lambda functions are defined in `deploy/terraform/lambdas.tf`. Forms will use Cloudflare Turnstile for bot protection.
- **Hosting:** AWS S3 bucket is the default hosting provider with Cloudflare for DNS and DDoS/WAF protection. Build output must be a static site plus serverless functions — no always-on servers.
- **Deployment:** Terraform to set up backend infrastructure. Deployment of the website to AWS S3 bucket. See `deploy/README.md` for more information.

## 3. What "best practices" means here

When in doubt, prefer boring, well-documented patterns over clever ones. Specifically:

- **Accessibility is not optional.** Target WCAG 2.2 AA. Every interactive element must be keyboard-reachable. Every image needs meaningful alt text or `alt=""` if decorative. Color contrast must pass against both light and dark themes. Run `axe` mentally before declaring a component done.
- **Performance budget:** Lighthouse Performance ≥ 95 on mobile, LCP < 2.0s on a simulated 4G connection. Ship zero JS by default; add interactivity only via Astro islands. Images go through Astro's `<Image />` component with explicit width/height.
- **SEO:** Every page has a unique `<title>`, meta description, OpenGraph image, and canonical URL. A `sitemap.xml` is generated at build via the official Astro sitemap integration. `robots.txt` lives in `public/`.
- **Privacy:** Voxivium's brand promise includes privacy-by-design. No third-party analytics that fingerprint users. Use Cloudflare Web Analytics or Plausible. No Google Analytics, no Meta pixel, no marketing cookies without consent.
- **Security:** No secrets in the repo. Environment variables go in `.env.local` (gitignored) and are documented in `.env.example`. Forms have CSRF protection and basic rate limiting at the function layer. All endpoints validate input with `zod`.
- **Code quality:** ESLint + Prettier configured and enforced. Husky pre-commit hook runs `pnpm lint` and `pnpm typecheck`. Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`).

## 4. Design system

### Brand tokens (single source of truth)

Mirror these from the existing Android `Color.kt`. They live in `tailwind.config.mjs` as `theme.extend.colors.brand` and are referenced everywhere via Tailwind utilities — never hardcode hex.

**Light mode:**
- `brand-primary`: `#0B5996` (logo blue)
- `brand-dark`: `#040707`
- `bg`: `#F0F6FA`
- `surface`: `#DDEAF4`
- Elevation 1/2/3: `#C9DDF0` / `#B5D1EB` / `#A2C4E5`
- Text: `#040707` / `#19252E` / `#334552` / `#4D6171`

**Dark mode:**
- `brand-primary`: `#6BB6E8` (lightened for legibility)
- `bg`: `#0A1117`
- `surface`: `#121E29`
- Elevation 1/2/3: `#1A2A38` / `#223647` / `#2A4257`
- Text: `#F0F6FA` / `#DDEAF4` / `#B5D1EB` / `#9CB8D1`

Dark mode is the default look-and-feel for this site. Honor `prefers-color-scheme` and provide a manual toggle in the header.

### Visual identity — important nuance

The user's vision is "red and blue circles converging in a flash of light at the center" as a hero motif, inspired by the app splash screen.

**Execute this carefully.** Voxivium is non-partisan — the entire pitch is bridging divides. A hero that leads with strong red-vs-blue framing risks reading as partisan in a half-second glance, before the visitor reads any copy. Apply these guardrails:

- **Blue is dominant.** Brand blue carries the visual weight. Red is an accent that exists *to be resolved* into the unity moment, not to compete with blue.
- **The convergence is the focal point**, not the opposing sides. The "flash of light" / merged center should be the largest, brightest, most attention-grabbing element. The red and blue circles are supporting players that lead the eye inward.
- **Avoid US-political shorthand.** No stars, no flag motifs, no donkey/elephant. This is about citizens uniting, not about Democrats vs. Republicans specifically.
- **Implement as SVG with subtle CSS animation** (respecting `prefers-reduced-motion`). Circles fade/scale toward the center; the flash is a soft radial glow, not a literal explosion. No autoplaying video for the hero.

If the user pushes for a more partisan-coded execution, build it but raise the concern once.

### Typography

Single font family for the whole site. Use **Inter** (variable font, self-hosted via `@fontsource-variable/inter`) for body and headings. No second display font unless the user explicitly asks. Tight headings, generous body line-height (1.6+).

## 5. Information architecture

Plan for these routes. Build them in this order — don't scaffold pages that aren't needed yet.

**Phase 1 (launch-critical):**
- `/` — Hero, "what is Voxivium," audience tabs, video showcase, footer.
- `/faq` — Common questions, grouped by audience.
- `/about` — Mission, PBC structure, internal governance commitments (5:1 pay ratio, profit sharing, living wage).
- `/kickstarter` — Dormant. Page exists for possible future reactivation; not linked from anywhere.

**Phase 2 (post-launch):**
- `/partnerships` — For media/research/AI labs.
- `/careers` — Job listings, culture, the governance commitments again.
- `/press` — Press kit, logos, founder bio.
- `/legal/privacy` and `/legal/terms`.

**Phase 3 (when ready):**
- Payment / API subscription flows for politicians, media, AI labs. These will likely warrant their own subdomain or app — discuss before building inline.

### Audience tabs

The home page uses a tabbed component (React island) with four tabs: Voters | Politicians | Media & Research | AI Labs. Each tab shows tailored copy and a tailored CTA / form. URL hash should reflect the active tab (`/#voters`, `/#politicians`, etc.) so it's linkable.

## 6. Forms — current and future

Terraform defines the lambda functions, API Gateway endpoints, and SQS queues that will be used for the forms. Lambda functions should be written in Python 3.14.

- **Voter form:** Same fields as today (first name, email). Posts to existing endpoint.
- **Politician form:** Name, email, office sought/held, jurisdiction, optional message. New endpoint, new collection.
- **Media/Research form:** Name, email, organization, role, intended use, optional message.
- **AI Lab form:** Name, email, organization, use case, scale (rough # of queries / users).

All forms:
- Use progressive enhancement — they must function with JS disabled (server-rendered POST).
- Validate with `zod` both client-side (for UX) and server-side (for trust).
- Honeypot field + Cloudflare Turnstile for spam.
- Show clear success and error states; never leave the user wondering if it submitted.
- Confirmation email is a nice-to-have for v1, mandatory for v2.

## 7. Content & copy guidelines

When Claude writes copy:

- **Tone:** Confident, plainspoken, civically minded. Think "trusted utility" not "scrappy startup" and not "government bureaucracy." Read like the editorial voice of a respected non-partisan institution.
- **Strict non-partisanship.** No language that codes left or right. No examples that single out one party as the problem. When illustrating a point, use issues with genuine cross-partisan support (infrastructure, prescription drug pricing, etc.) rather than wedge issues.
- **Avoid jargon and AI tells.** No "in today's fast-paced world," no "revolutionizing," no "leveraging," no "unlock." No em-dashes used as a stylistic crutch. No three-item lists where every item starts with the same word.
- **Concrete over abstract.** "See how often your senator votes the way you'd vote" beats "personalized accountability metrics."
- **Reading level:** Aim for 8th-grade reading level on marketing pages, slightly higher on B2B-focused tabs (politicians, media, AI).
- **Headlines are short.** 8 words max for hero, 6 words max for section heads.

## 8. Working agreements with Claude

These are how I want you to behave in this codebase:

- **Plan before you build.** For any task touching more than one file, write a 3–6 line plan as the first thing in your response, then execute. For trivial edits, skip the plan.
- **Read before you write.** Before editing a file, view it. Before creating a component, check `src/components/` for something similar.
- **Small, reversible commits.** One concern per commit. If you find yourself touching ten unrelated files, stop and split the work.
- **Ask when stakes are high, decide when they're low.** Color choice on a button: just pick. Deciding whether to introduce a new dependency, restructure routes, or change the data model: ask first.
- **No new dependencies without justification.** When you add a package, note in the commit message why a stdlib / existing-dep solution wouldn't work. Prefer dependencies with >1k weekly downloads, recent commits, and TypeScript types.
- **Don't invent infrastructure.** If a service or API isn't documented in this file or visible in the repo, it doesn't exist yet. Ask before assuming.
- **Honest progress reports.** If something is half-done, say "I built X and Y, but Z is still TODO." Don't claim completion you haven't earned.
- **Push back on me.** If I ask for something that contradicts this file, the brand, or good engineering practice, say so once before complying. The non-partisan brand integrity in particular is worth defending.

## 9. Repository layout (target state)

```
/
├── CLAUDE.md
├── README.md
├── astro.config.mjs
├── tailwind.config.mjs
├── tsconfig.json
├── package.json
├── .env.example
├── .nvmrc
├── deploy/
│   ├── lambdas/             # Lambda functions
│   ├── terraform/           # terraform files
│   └── README.md            # How to deploy
├── public/
│   ├── robots.txt
│   ├── favicon.svg
│   └── og/                  # OpenGraph images
├── src/
│   ├── pages/               # Astro routes
│   ├── layouts/             # Page layouts
│   ├── components/
│   │   ├── ui/              # Buttons, inputs, primitives
│   │   ├── sections/        # Hero, AudienceTabs, VideoShowcase, etc.
│   │   └── forms/           # One per audience
│   ├── content/             # Astro content collections (FAQ, etc.)
│   ├── lib/                 # Utilities, validation schemas
│   ├── styles/              # global.css with Tailwind directives
│   └── assets/              # Imported images, SVGs
└── functions/               # Cloudflare Pages Functions (or /api for Lambda)
```

## 10. Out of scope (don't build these without asking)

- App-like features (user accounts, dashboards, report cards). Those belong in the app, not the marketing site.
- A blog or CMS. If content needs change frequency, we'll add Astro content collections; we don't need a headless CMS yet.
- Internationalization. English only for v1. Architect routes so i18n is feasible later, but don't ship it.
- A/B testing infrastructure. Premature.
- Live chat widgets. They hurt performance and clash with the trusted-utility tone.

---

*Last updated: when this file was created. Update the date and a one-line changelog entry at the bottom of any meaningful change.*