#!/bin/bash
set -euo pipefail
TOOLCHAIN_SCRIPT="$(cd "$(dirname "$0")" && pwd)/toolchain.sh"
FIXTURE_ROOT="$(mktemp -d)"
CHECK_STATUS=1
# Bash 3.2 can report status zero for an array expansion error. Only an
# explicitly completed check may succeed, even when EXIT follows that error.
trap 'rm -rf "$FIXTURE_ROOT"; exit "$CHECK_STATUS"' EXIT
mkdir -p "$FIXTURE_ROOT/bin" "$FIXTURE_ROOT/include/swift"
cd "$FIXTURE_ROOT"
# Only source the option detector. No real compiler or SDK is changed.
xcrun() { printf '%s/bin/swiftc\n' "$FIXTURE_ROOT"; }
source "$TOOLCHAIN_SCRIPT"
set -- "${SWIFT_COMPAT[@]}"
test "$#" = 2
test "$1" = -swift-version
test "$2" = 5
test ! -e .build/compat/overlay.json

printf 'module SwiftBridging {\n}\n' > include/swift/module.modulemap
cp include/swift/module.modulemap include/swift/bridging.modulemap
source "$TOOLCHAIN_SCRIPT"
set -- "${SWIFT_COMPAT[@]}"
test "$#" = 4
test "$1" = -swift-version
test "$2" = 5
test "$3" = -vfsoverlay
test -f "$4"
printf 'Passed clean and duplicate module map option checks.\n'
CHECK_STATUS=0
