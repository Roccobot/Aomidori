#!/usr/bin/env bash
# Runs the unit tests. With the Command Line Tools only (no Xcode), SwiftPM 6.4 may not find
# the Swift Testing framework and macros on its own; the flags below point it there.
#
#   scripts/test.sh            # same arguments as `swift test`
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  exec swift test "$@"
fi

DEVELOPER="$(xcode-select -p)"
if [[ "$DEVELOPER" != *CommandLineTools* ]]; then
  exec swift test "$@" # Xcode: nothing to add
fi
FRAMEWORKS="$DEVELOPER/Library/Developer/Frameworks"
exec swift test --build-system native \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" "$@"
