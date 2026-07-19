#!/usr/bin/env bash
# Build the Astro site and deploy to AWS S3, then invalidate the CloudFront
# and Cloudflare caches so the new bundle serves at the edge immediately.
#
# Usage:
#   ./deploy/deploy.sh             build + sync + invalidate CloudFront + purge Cloudflare
#   ./deploy/deploy.sh --no-purge  skip the Cloudflare edge purge (CloudFront invalidation still runs)
#   ./deploy/deploy.sh --dry-run   show what would change without writing
#   ./deploy/deploy.sh --help

set -euo pipefail

CLOUDFLARE_ZONE_ID="db1548373f1b0aa81cc6d18bfb50fdfc"

usage() {
  cat <<'EOF'
Build the Astro site and deploy to AWS S3, then invalidate CloudFront and
purge the Cloudflare edge cache.

Usage:
  ./deploy/deploy.sh             build + sync + invalidate CloudFront + purge Cloudflare
  ./deploy/deploy.sh --no-purge  skip the Cloudflare edge purge (CloudFront invalidation still runs)
  ./deploy/deploy.sh --dry-run   show what would change without writing
  ./deploy/deploy.sh --help      this message
EOF
}

PURGE=true
DRYRUN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-purge) PURGE=false; shift ;;
    --dry-run)  DRYRUN="--dryrun"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)
      echo "error: unknown flag: $1" >&2
      echo "  run with --help for usage." >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
cd "$REPO_ROOT"

if [[ ! -f .env ]]; then
  echo "error: .env not found at $REPO_ROOT/.env" >&2
  echo "  Without it the build embeds placeholder API URLs and the forms break." >&2
  echo "  Copy .env.example to .env and fill in real values (PUBLIC_*_FORM_ENDPOINT, etc.)." >&2
  exit 1
fi

echo "→ Reading bucket + CloudFront distribution id from terraform outputs..."
BUCKET=$(terraform -chdir="$TF_DIR" output -raw site_bucket_name 2>/dev/null || true)
DIST_ID=$(terraform -chdir="$TF_DIR" output -raw site_cloudfront_distribution_id 2>/dev/null || true)

if [[ -z "$BUCKET" || -z "$DIST_ID" ]]; then
  echo "error: could not read 'site_bucket_name' / 'site_cloudfront_distribution_id' from terraform state." >&2
  echo "  Run 'terraform -chdir=$TF_DIR apply' first, then retry." >&2
  exit 1
fi

echo "  bucket=$BUCKET"
echo "  distribution=$DIST_ID"

echo "→ Building site (pnpm build)..."
pnpm build

echo "→ Syncing dist/ to s3://${BUCKET}/ ..."
aws s3 sync ./dist/ "s3://${BUCKET}/" --delete ${DRYRUN}

if [[ -n "$DRYRUN" ]]; then
  echo "(dry-run; skipping CloudFront invalidation and Cloudflare cache purge)"
  exit 0
fi

echo "→ Invalidating CloudFront cache (${DIST_ID})..."
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths '/*' \
  --output text --query 'Invalidation.Id' \
  | sed 's/^/  invalidation id: /'

if [[ "$PURGE" != "true" ]]; then
  echo "→ Skipping Cloudflare cache purge (--no-purge)."
elif [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "→ CLOUDFLARE_API_TOKEN not set; skipping Cloudflare cache purge."
  echo "  To force-refresh Cloudflare edge, run 'Purge Everything' from the Cloudflare dashboard."
else
  echo "→ Purging Cloudflare cache..."
  response=$(curl -s -X POST \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
    --data '{"purge_everything":true}')
  if echo "$response" | grep -q '"success":true'; then
    echo "  cache purged."
  else
    echo "  cache purge failed (token may lack Zone:Cache Purge permission):" >&2
    echo "$response" | sed 's/^/    /' >&2
    echo "  Purge manually: Cloudflare dashboard → Caching → Configuration → Purge Everything." >&2
  fi
fi

echo "Deployed. https://voxivium.com/"
