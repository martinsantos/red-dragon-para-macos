#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build_and_run.sh" --build-only
"$ROOT_DIR/work/build/${CONFIGURATION:-debug}/protocol-checks"
plutil -lint "$ROOT_DIR/dist/RedragonMac.app/Contents/Info.plist"
codesign --verify --deep --strict "$ROOT_DIR/dist/RedragonMac.app"
echo "PASS: build, protocol checks, plist and bundle signature."
