#!/bin/bash
# Sourced by build and test scripts. Keep all compatibility changes inside .build.
SWIFT_COMPAT=()
SWIFT_INCLUDE="$(dirname "$(dirname "$(xcrun --find swiftc)")")/include/swift"
if [ -f "$SWIFT_INCLUDE/module.modulemap" ] && [ -f "$SWIFT_INCLUDE/bridging.modulemap" ] &&
   grep -q '^module SwiftBridging {' "$SWIFT_INCLUDE/module.modulemap" &&
   grep -q '^module SwiftBridging {' "$SWIFT_INCLUDE/bridging.modulemap"; then
  mkdir -p .build/compat
  : > .build/compat/empty.modulemap
  cat > .build/compat/overlay.json <<JSON
{"version":0,"roots":[{"type":"file","name":"$SWIFT_INCLUDE/bridging.modulemap","external-contents":"$PWD/.build/compat/empty.modulemap"}]}
JSON
  SWIFT_COMPAT=(-vfsoverlay "$PWD/.build/compat/overlay.json")
fi
