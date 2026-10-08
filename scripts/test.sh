#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks .build/native-cache
source scripts/toolchain.sh
xcrun swiftc "${SWIFT_COMPAT[@]}" -swift-version 5 -parse-as-library -emit-object -emit-module \
  -module-name DisplayCore Sources/DisplayCore/*.swift -o .build/checks/DisplayCore.o \
  -emit-module-path .build/checks/DisplayCore.swiftmodule -module-cache-path .build/native-cache
xcrun swiftc "${SWIFT_COMPAT[@]}" -swift-version 5 -parse-as-library -I .build/checks .build/checks/DisplayCore.o \
  Tests/DisplayCoreTests/*.swift -o .build/checks/ControlChecks -module-cache-path .build/native-cache
.build/checks/ControlChecks
