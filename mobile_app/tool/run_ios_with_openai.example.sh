#!/usr/bin/env bash
# Copy to run_ios_with_openai.sh (gitignored) and run, or export OPENAI_API_KEY here
# for a one-off — never commit real keys.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Export OPENAI_API_KEY first, e.g.:" >&2
  echo "  export OPENAI_API_KEY=sk-..." >&2
  echo "  ./tool/run_ios_with_openai.sh" >&2
  exit 1
fi
exec flutter run --dart-define="OPENAI_API_KEY=$OPENAI_API_KEY"
