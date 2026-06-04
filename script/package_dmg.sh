#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex TaskGuard"
VOL_NAME="Codex TaskGuard"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
BACKGROUND_SOURCE="$ROOT_DIR/Assets/DMG/taskguard-dmg-background-1064x768.png"
BACKGROUND_SCRIPT="$ROOT_DIR/script/make_dmg_background.swift"
INSTALL_README="$ROOT_DIR/Assets/DMG/安装说明.txt"
FINAL_DMG="$DIST_DIR/Codex-TaskGuard.dmg"
RW_DMG="$DIST_DIR/Codex-TaskGuard-rw.dmg"
SHOULD_BUILD=0

case "${1:-}" in
  --build|build)
    SHOULD_BUILD=1
    ;;
  "" )
    ;;
  * )
    echo "usage: $0 [--build]" >&2
    exit 2
    ;;
esac

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-taskguard-dmg.XXXXXX")"

cleanup() {
  if [[ -n "${DMG_DEVICE:-}" ]]; then
    hdiutil detach "$DMG_DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR" "$RW_DMG"
}
trap cleanup EXIT

if [[ "$SHOULD_BUILD" == "1" ]]; then
  "$ROOT_DIR/script/build_and_run.sh" --bundle
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  echo "run: $0 --build" >&2
  exit 1
fi

rm -rf "$STAGING_DIR"/*
mkdir -p "$STAGING_DIR/.background"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build-current/clang-module-cache" /usr/bin/swift "$BACKGROUND_SCRIPT" "$BACKGROUND_SOURCE"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$INSTALL_README" "$STAGING_DIR/安装说明.txt"
cp "$BACKGROUND_SOURCE" "$STAGING_DIR/.background/taskguard-dmg-background.png"

rm -f "$RW_DMG" "$FINAL_DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -size 48m \
  -ov \
  "$RW_DMG"

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
DMG_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | sed -nE 's#^(/dev/[^[:space:]]+).*Apple_HFS[[:space:]]+(/.*)$#\2#p' | head -n 1)"

if [[ -z "$DMG_DEVICE" || -z "$MOUNT_DIR" ]]; then
  echo "failed to attach writable dmg" >&2
  printf '%s\n' "$ATTACH_OUTPUT" >&2
  exit 1
fi

chflags hidden "$MOUNT_DIR/.background"

osascript <<APPLESCRIPT
tell application "Finder"
  delay 1
  set dmgDisk to disk "$VOL_NAME"
  open dmgDisk
  set containerWindow to container window of dmgDisk
  set current view of containerWindow to icon view
  set toolbar visible of containerWindow to false
  set statusbar visible of containerWindow to false
  set the bounds of containerWindow to {120, 100, 1184, 868}
  set viewOptions to the icon view options of containerWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set background picture of viewOptions to file ".background:taskguard-dmg-background.png" of dmgDisk
  set position of item "$APP_NAME.app" of dmgDisk to {226, 400}
  set position of item "Applications" of dmgDisk to {838, 400}
  set position of item "安装说明.txt" of dmgDisk to {532, 545}
  update dmgDisk without registering applications
  delay 1
  close containerWindow
end tell
APPLESCRIPT

sync
hdiutil detach "$DMG_DEVICE" -quiet
unset DMG_DEVICE

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$FINAL_DMG"

hdiutil verify "$FINAL_DMG"
echo "$FINAL_DMG"
