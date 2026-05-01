#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_VERSION="$(cat VERSION)"
APP="dist/Display Mini.app"
if [ ! -d "$APP" ]; then
  printf 'Build the app with ./scripts/build.sh first.\n' >&2
  exit 1
fi
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$APP_VERSION" ]; then
  printf 'The app version does not match VERSION. Rebuild before packaging.\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
ARCHIVE="Display-Mini-v${APP_VERSION}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ARCHIVE"
cd dist
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf 'Packaged %s and %s.sha256\n' "$ARCHIVE" "$ARCHIVE"
