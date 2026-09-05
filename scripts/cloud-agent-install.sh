#!/usr/bin/env bash
set -euo pipefail

# Idempotent Cloud Agent bootstrap for Health-App.
# System packages and Flutter live in the snapshot; this script refreshes
# repo-tied dependencies after checkout.

if ! command -v flutter >/dev/null 2>&1; then
  if [ -x /opt/flutter/bin/flutter ]; then
    export PATH="/opt/flutter/bin:$PATH"
  fi
fi

if command -v flutter >/dev/null 2>&1; then
  (cd /workspace/apps/verity_dashboard && flutter pub get)
fi

if [ -f /workspace/package-lock.json ]; then
  (cd /workspace && npm ci)
fi
