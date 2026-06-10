#!/usr/bin/env bash
# Install third-party Python dependencies into each Lambda's vendor/ directory.
# terraform's archive_file zips the lambda source directory verbatim, so anything
# under vendor/ ships into the deployment package and is importable at runtime
# (handler.py adds vendor/ to sys.path).
#
# Run this whenever a lambda's requirements.txt changes. Idempotent.
#
# Usage:
#   ./deploy/build-lambdas.sh

set -euo pipefail

cd "$(dirname "$0")"
LAMBDAS_DIR="$(pwd)/lambdas"

PY="${PYTHON:-python3}"
"$PY" --version >/dev/null 2>&1 || {
  echo "error: python3 not found on PATH" >&2
  exit 1
}

shopt -s nullglob
for dir in "$LAMBDAS_DIR"/*/; do
  req="$dir/requirements.txt"
  if [[ -f "$req" ]]; then
    name="$(basename "$dir")"
    echo "→ ${name}: installing into vendor/"
    rm -rf "$dir/vendor"
    "$PY" -m pip install \
      --quiet \
      --upgrade \
      --target "$dir/vendor" \
      --requirement "$req"
  fi
done

echo "Done. You may now run \`terraform apply\` from deploy/terraform/."
