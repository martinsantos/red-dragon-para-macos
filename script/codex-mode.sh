#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/dist/RedragonMac.app}"
COMMAND="${1:-toggle}"
case "$COMMAND" in on|off|toggle|status|show) ;; *) echo "Uso: $0 on|off|toggle|status|show [--json]" >&2; exit 2 ;; esac
CLI="$APP_BUNDLE/Contents/MacOS/s136ctl"
if [[ ! -x "$CLI" ]]; then echo "Compilá la app una vez con script/build_and_run.sh --build-only." >&2; exit 1; fi
if [[ "$COMMAND" != status ]]; then
  open -g "$APP_BUNDLE"
  for attempt in {1..60}; do
    if "$CLI" micro status --json >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
fi
exec "$CLI" micro "$COMMAND" "${@:2}"
