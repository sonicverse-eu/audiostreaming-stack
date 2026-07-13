#!/usr/bin/env bash
set -euo pipefail

RELOAD_MARKER="${STACK_RELOAD_MARKER_PATH:-/run/sonicverse/reload-request}"
mkdir -p "$(dirname "$RELOAD_MARKER")"
date +%s > "$RELOAD_MARKER"
echo "[reload] Requested streaming reload at $(cat "$RELOAD_MARKER")"
