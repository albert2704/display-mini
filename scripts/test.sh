#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks .build/native-cache
source scripts/toolchain.sh
xcrun swiftc "${SWIFT_COMPAT[@]}" -parse-as-library -emit-object -emit-module \
  -module-name DisplayCore Sources/DisplayCore/*.swift -o .build/checks/DisplayCore.o \
  -emit-module-path .build/checks/DisplayCore.swiftmodule -module-cache-path .build/native-cache
xcrun swiftc "${SWIFT_COMPAT[@]}" -parse-as-library -I .build/checks .build/checks/DisplayCore.o \
  Tests/DisplayCoreTests/*.swift -o .build/checks/ControlChecks -module-cache-path .build/native-cache
.build/checks/ControlChecks
xcrun swiftc "${SWIFT_COMPAT[@]}" -parse-as-library -I .build/checks .build/checks/DisplayCore.o \
  Sources/DisplayMini/DisplayStore.swift Sources/DisplayMini/ShortcutController.swift Sources/DisplayMini/ShortcutPreferences.swift Sources/DisplayMini/ShortcutRecorder.swift Tests/DisplayStoreTests/*.swift \
  -framework Carbon -o .build/checks/StoreChecks -module-cache-path .build/native-cache
.build/checks/StoreChecks
xcrun swiftc "${SWIFT_COMPAT[@]}" -parse-as-library -I .build/checks .build/checks/DisplayCore.o \
  Sources/DisplayMini/DDCClient.swift Tests/DDCProcessTests/*.swift \
  -o .build/checks/ProcessChecks -module-cache-path .build/native-cache
.build/checks/ProcessChecks
xcrun clang -fmodules -fmodules-cache-path="$PWD/.build/clang-cache" -IVendor/headers \
  -F/System/Library/PrivateFrameworks -framework CoreDisplay \
  Vendor/sources/i2c.m Vendor/sources/ioregistry.m Tests/HelperTests/ProtocolTests.m \
  -o .build/checks/ProtocolChecks
.build/checks/ProtocolChecks
