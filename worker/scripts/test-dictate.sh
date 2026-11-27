#!/usr/bin/env bash
# Usage: scripts/test-dictate.sh <audio.m4a> [worker-url] [token]
# Defaults hit `wrangler dev` with the token from .dev.vars.example.
set -euo pipefail

AUDIO="${1:?usage: $0 <audio.m4a> [worker-url] [token]}"
URL="${2:-http://localhost:8787}"
TOKEN="${3:-test-token}"

curl -sS -X POST "$URL/dictate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: audio/mp4" \
  -H "X-Duration-Seconds: 15" \
  --data-binary "@$AUDIO"
echo
