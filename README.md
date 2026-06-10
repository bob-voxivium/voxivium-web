# Voxivium — Marketing Site

The public-facing website for Voxivium, a Public Benefit Corporation building a non-partisan
political accountability platform. See [CLAUDE.md](CLAUDE.md) for the full product brief, brand
guardrails, and engineering conventions.

## Stack

- **Astro 5** — static site generation, zero JS by default, React/other islands when needed
- **TypeScript (strict)**
- **Tailwind CSS v4** via `@tailwindcss/vite`, with brand tokens in [tailwind.config.mjs](tailwind.config.mjs)
- **Inter** (variable, self-hosted via `@fontsource-variable/inter`)
- **AWS S3** for static hosting, fronted by **Cloudflare** (DNS, CDN, WAF). Form endpoints run as AWS Lambda behind API Gateway. See [deploy/README.md](deploy/README.md) for the full infra layout.

## Prerequisites

- Node 22 (see [.nvmrc](.nvmrc))
- pnpm 10

```bash
pnpm install
cp .env.example .env.local
pnpm dev
```

## Scripts

| Command             | What it does                                          |
| ------------------- | ----------------------------------------------------- |
| `pnpm dev`          | Start the local dev server at `http://localhost:4321` |
| `pnpm build`        | Build the static site to `dist/`                      |
| `pnpm preview`      | Serve the built site locally                          |
| `pnpm typecheck`    | Run `astro check` (TS + Astro diagnostics)            |
| `pnpm lint`         | ESLint over the repo                                  |
| `pnpm format`       | Prettier write                                        |
| `pnpm format:check` | Prettier check (CI-friendly)                          |
| `pnpm run deploy`   | Build, sync to S3, and purge Cloudflare cache         |

## Deploying

After your first-time infrastructure setup (see [deploy/README.md](deploy/README.md)), every
subsequent site update is one command:

```bash
pnpm run deploy
```

(The explicit `run` is required because pnpm reserves the bare `pnpm deploy` for its built-in
workspace-deploy command.) That runs [deploy/deploy.sh](deploy/deploy.sh), which:

1. **Confirms `.env` exists** at the repo root. Without it the build embeds placeholder API URLs
   and the forms break, so the script bails early if it's missing.
2. **Builds the site** with `pnpm build` → `dist/`.
3. **Syncs to S3** with `aws s3 sync ./dist/ s3://voxivium.com/ --delete`. The `--delete` flag
   removes anything in the bucket that no longer exists in `dist/`, so deleted/renamed pages
   don't linger.
4. **Purges Cloudflare's edge cache** so visitors see the new HTML immediately. Astro's hashed
   asset filenames (`/_astro/*.hash.js`) make CSS/JS cache-bust on their own; this purge is
   really only about the unhashed HTML pages.

### Flags

| Flag         | Effect                                                                  |
| ------------ | ----------------------------------------------------------------------- |
| `--no-purge` | Skip the Cloudflare cache purge. Useful if you're iterating quickly and don't care about stale HTML at the edge for a few minutes. |
| `--dry-run`  | Show what `aws s3 sync` would upload/delete without actually changing the bucket, and skip the purge. |
| `--help`     | Print usage.                                                            |

Flags pass through after `--`:

```bash
pnpm run deploy -- --dry-run
pnpm run deploy -- --no-purge
```

Or invoke the script directly: `./deploy/deploy.sh --dry-run`.

### Prerequisites in your shell

The script assumes you already have valid AWS and Cloudflare credentials in the current shell:

```bash
export AWS_PROFILE=voxivium-business        # or whichever profile owns the S3 bucket
export CLOUDFLARE_API_TOKEN='your-token'    # only needed for cache purge
```

If `CLOUDFLARE_API_TOKEN` is unset, the script skips the purge and tells you to do it manually
from the Cloudflare dashboard. If the token is set but lacks `Zone:Cache Purge` permission, the
purge step prints the error and continues — the deploy itself still succeeded.

## Repository layout

```
src/
  pages/              Astro routes
  layouts/            Page layouts
  components/
    ui/               Buttons, inputs, primitives
    sections/         Hero, AudienceTabs, VideoShowcase, etc.
    forms/            One per audience
  content/            Astro content collections
  lib/
    forms/            Hosting-agnostic form module (schemas, submit, endpoints)
  styles/             global.css with Tailwind directives + tokens
  assets/             Imported images, SVGs (optimized via Astro)
public/
  favicon/            PWA icons + manifest
  robots.txt
```

## Form abstraction

Form endpoints are read from `PUBLIC_*` env vars, so swapping the backend (AWS Lambda → Cloudflare
Pages Functions, etc.) is a config change, not a code change. See [src/lib/forms/](src/lib/forms/):

- `schemas.ts` — zod schemas shared between client and server
- `endpoints.ts` — env-var lookup for each audience
- `submit.ts` — generic JSON POST helper with timeout + typed result

## Roadmap

- **Milestone 1 (this commit):** project scaffolding, brand tokens, base layout, forms scaffolding
- **Milestone 2:** Phase 1 pages (`/`, `/faq`, `/about`, `/kickstarter`), hero animation, audience
  tabs, four forms wired up
- **Milestone 3:** deploy to hosting (Cloudflare Pages preferred), spam protection, observability

The legacy single-file site is preserved on the `old` branch.
