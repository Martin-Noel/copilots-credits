#!/usr/bin/env bash
# Runs the tests (Swift Testing), including with the Command Line Tools only.
#   ./test.sh                 -> all tests, output also written to test.log
#   ./test.sh --filter Parser -> arguments passed as is to `swift test`
#
# Why this script: with the Command Line Tools (no full Xcode), SwiftPM doesn't always
# find the Swift Testing macro plugin (@Test, @Suite, #expect), stored separately in
# .../host/plugins/testing. We locate it and pass it to the compiler.
set -euo pipefail
cd "$(dirname "$0")"

DEV_DIR="$(xcode-select -p)"
ARGS=()

echo "▸ Developer tools: ${DEV_DIR}"
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    PLUGIN="$(find "$DEV_DIR/usr/lib/swift" -name 'libTestingMacros.dylib' -print -quit 2>/dev/null || true)"
    if [[ -n "$PLUGIN" ]]; then
        echo "▸ Swift Testing plugin: ${PLUGIN}"
        ARGS+=(-Xswiftc -plugin-path -Xswiftc "$(dirname "$PLUGIN")")
    else
        echo "⚠︎ libTestingMacros.dylib not found under ${DEV_DIR}/usr/lib/swift"
    fi
fi

swift test ${ARGS[@]+"${ARGS[@]}"} "$@" 2>&1 | tee test.log
exit "${PIPESTATUS[0]}"
