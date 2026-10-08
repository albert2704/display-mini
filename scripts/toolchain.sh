#!/bin/bash
# Sourced by build and test scripts. Keep all compatibility changes inside .build.
# Bash 3.2 treats an empty array as unset under `set -u`. Keep the shared
# language option here so the array remains usable on an unmodified toolchain.
SWIFT_COMPAT=(-swift-version 5)
SWIFT_INCLUDE="$(dirname "$(dirname "$(xcrun --find swiftc)")")/include/swift"
if [ -f "$SWIFT_INCLUDE/module.modulemap" ] && [ -f "$SWIFT_INCLUDE/bridging.modulemap" ] &&
   grep -q '^module SwiftBridging {' "$SWIFT_INCLUDE/module.modulemap" &&
   grep -q '^module SwiftBridging {' "$SWIFT_INCLUDE/bridging.modulemap"; then
  mkdir -p .build/compat
  : > .build/compat/empty.modulemap
  cat > .build/compat/overlay.json <<JSON
{"version":0,"roots":[{"type":"file","name":"$SWIFT_INCLUDE/bridging.modulemap","external-contents":"$PWD/.build/compat/empty.modulemap"}]}
JSON
  SWIFT_COMPAT+=(-vfsoverlay "$PWD/.build/compat/overlay.json")
fi
