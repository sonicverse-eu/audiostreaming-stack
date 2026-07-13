#!/usr/bin/env bash
set -euo pipefail

PYTHONPATH="/opt/sonicverse/status-api:${PYTHONPATH:-}"
export PYTHONPATH

python3 - <<'PY'
from stack.apply import pre_render_config
from stack.store import read_config

pre_render_config(read_config())
print("[render] Stack config rendered")
PY
