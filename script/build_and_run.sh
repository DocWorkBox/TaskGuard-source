#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexProcessManager"
DISPLAY_NAME="Codex TaskGuard"
BUNDLE_ID="work.doxora.CodexProcessManager"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
OLD_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_RESOURCES="$APP_CONTENTS/Resources"
ICON_NAME="TaskGuardIcon"
ICON_SOURCE="$ROOT_DIR/Assets/IconSources/taskguard-options-board.png"
BUILD_DIR="$ROOT_DIR/.build"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFTPM_HOME="$BUILD_DIR/swiftpm-home"

if PIDS="$(pgrep -x "$APP_NAME" 2>/dev/null)"; then
  for pid in $PIDS; do
    pkill -P "$pid" >/dev/null 2>&1 || true
  done
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build --scratch-path "$BUILD_DIR"
BUILD_BINARY="$(swift build --scratch-path "$BUILD_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$OLD_APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

/usr/bin/swift "$ROOT_DIR/script/make_icon_from_raster.swift" "$ICON_SOURCE" "$APP_RESOURCES" "$ICON_NAME"
/usr/bin/iconutil -c icns "$APP_RESOURCES/$ICON_NAME.iconset" -o "$APP_RESOURCES/$ICON_NAME.icns"
rm -rf "$APP_RESOURCES/$ICON_NAME.iconset"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
