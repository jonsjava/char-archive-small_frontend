#!/usr/bin/env bash
# Rebuild the tag index (run once after restoring the database, or after bulk imports).
#
# Linux/macOS:  cp rebuild_tags.example.sh rebuild_tags.sh && ./rebuild_tags.sh
# Windows:      .\rebuild_tags.ps1

set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example to .env and edit it." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

# shellcheck disable=SC1090
. "${VENV_PATH:-~/venv}/bin/activate"
exec python rebuild_tag_index.py
