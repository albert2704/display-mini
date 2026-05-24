#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/native-cache"
export MACOSX_DEPLOYMENT_TARGET=14.0
APP_VERSION="$(cat VERSION)"
if ! [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'VERSION must contain a numeric major.minor.patch version.\n' >&2
  exit 1
fi
source scripts/toolchain.sh
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
# Rebuild to avoid retaining an object compiled for a different SDK or architecture.
make -C Vendor clean
make -C Vendor CC="xcrun clang -arch arm64"
# Compile directly as well as providing Package.swift. This works with Command
# Line Tools installations whose SwiftPM manifest module and dylib are mismatched.
mkdir -p .build/release
xcrun swiftc "${SWIFT_COMPAT[@]}" -O -whole-module-optimization -parse-as-library -emit-object -emit-module \
  -module-name DisplayCore Sources/DisplayCore/*.swift \
  -o .build/release/DisplayCore.o -emit-module-path .build/release/DisplayCore.swiftmodule \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -target arm64-apple-macosx14.0
xcrun swiftc "${SWIFT_COMPAT[@]}" -parse-as-library -O -I .build/release .build/release/DisplayCore.o \
  Sources/DisplayMini/*.swift -framework Carbon -o .build/release/DisplayMini \
  -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -target arm64-apple-macosx14.0
APP="$PWD/dist/Display Mini.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp .build/release/DisplayMini "$APP/Contents/MacOS/DisplayMini"
cp Vendor/m1ddc "$APP/Contents/Helpers/m1ddc"
cp Vendor/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
cp LICENSE "$APP/Contents/Resources/Display-Mini-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Display Mini</string>
<key>CFBundleDisplayName</key><string>Display Mini</string>
<key>CFBundleIdentifier</key><string>dev.albert.DisplayMini</string>
<key>CFBundleExecutable</key><string>DisplayMini</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Helpers/m1ddc"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
printf 'Built %s\n' "$APP"
