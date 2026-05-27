#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/toolchain.sh
mkdir -p .build/docs .build/native-cache docs/media
xcrun swiftc "${SWIFT_COMPAT[@]}" -whole-module-optimization -parse-as-library -emit-object -emit-module \
  -module-name DisplayCore Sources/DisplayCore/*.swift -o .build/docs/DisplayCore.o \
  -emit-module-path .build/docs/DisplayCore.swiftmodule -module-cache-path .build/native-cache
xcrun swiftc "${SWIFT_COMPAT[@]}" -parse-as-library -I .build/docs .build/docs/DisplayCore.o \
  .build/docs/DocumentationViews.swift -framework Carbon -o .build/docs/DocumentationRenderer \
  -module-cache-path .build/native-cache
.build/docs/DocumentationRenderer docs/media
