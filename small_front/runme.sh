#!/usr/bin/env bash
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

VENV_PATH="${VENV_PATH:-~/venv}"
VENV_PATH="${VENV_PATH/#\~/$HOME}"

if [[ ! -d "$VENV_PATH" ]]; then
  echo "Creating virtualenv at $VENV_PATH"
  python3 -m venv "$VENV_PATH"
  source "$VENV_PATH/bin/activate"
  python -m pip install -r requirements.txt
  sourced=true
fi

# shellcheck disable=SC1090
if [[ -z "${sourced:-}" ]]; then
  source "$VENV_PATH/bin/activate"
fi

# Enable import folder scanning for local dev (Docker uses the importer service instead).
export ENABLE_IMPORT_SCANNER="${ENABLE_IMPORT_SCANNER:-true}"

exec python app.py
