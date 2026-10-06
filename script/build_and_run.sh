#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_DIR="$ROOT_DIR/work/build"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/dist/RedragonMac.app}"
BUNDLE_ID="local.redragonmac.S136"
case "$MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry|--preview) ;;
  *) echo "Uso: $0 [run|--build-only|--verify|--debug|--logs|--telemetry|--preview RESPALDO.json]" >&2; exit 2 ;;
esac
if [[ "$MODE" == "--preview" && $# -ne 2 ]]; then echo "Indicá un respaldo JSON." >&2; exit 2; fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/work/swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
swift build --package-path "$ROOT_DIR" --configuration "$BUILD_CONFIGURATION" --scratch-path "$BUILD_DIR" --cache-path "$ROOT_DIR/work/package-cache" --config-path "$ROOT_DIR/work/package-config" --security-path "$ROOT_DIR/work/package-security" --disable-sandbox
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$BUILD_CONFIGURATION/RedragonMac" "$APP_BUNDLE/Contents/MacOS/RedragonMac.next"
mv -f "$APP_BUNDLE/Contents/MacOS/RedragonMac.next" "$APP_BUNDLE/Contents/MacOS/RedragonMac"
cp "$BUILD_DIR/$BUILD_CONFIGURATION/s136ctl" "$APP_BUNDLE/Contents/MacOS/s136ctl"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RedragonMac</string>
<key>CFBundleIdentifier</key><string>local.redragonmac.S136</string>
<key>CFBundleName</key><string>RED DRAGON PARA MACOS</string>
<key>CFBundleDisplayName</key><string>RED DRAGON PARA MACOS</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSInputMonitoringUsageDescription</key><string>La app utiliza el canal USB de configuración del kit S136 y descarta los informes normales de teclas y movimiento.</string>
</dict></plist>
PLIST
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP_BUNDLE/Contents/MacOS/s136ctl"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
case "$MODE" in
  run) open "$APP_BUNDLE" ;;
  --build-only) ;;
  --preview) open "$APP_BUNDLE" --args --preview "$2" ;;
  --verify) open "$APP_BUNDLE"; sleep 1; pgrep -x RedragonMac >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/RedragonMac" ;;
  --logs|--telemetry) open "$APP_BUNDLE"; log stream --info --style compact --predicate "process == \"RedragonMac\"" ;;
esac
