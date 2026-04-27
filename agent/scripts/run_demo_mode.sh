#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")/.."
source .venv/bin/activate
export SAFETY_INTEL_DEMO_MODE=1
uvicorn app:app --reload --port 8080