#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CONFIGURATION=release
"$ROOT_DIR/script/check.sh"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE:-$ROOT_DIR/dist/RedragonMac.app}" "$ROOT_DIR/dist/RED-DRAGON-PARA-MACOS-0.4.1-$(uname -m).zip"
(
  cd "$ROOT_DIR/dist"
  shasum -a 256 "RED-DRAGON-PARA-MACOS-0.4.1-$(uname -m).zip" > SHA256SUMS.txt
)
