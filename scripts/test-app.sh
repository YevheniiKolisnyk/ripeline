#!/bin/bash
# Runs the app's unit tests and prints only what matters.
# Usage: scripts/test-app.sh [TestSuiteName]
set -u
cd "$(dirname "$0")/.."

log="${TMPDIR:-/tmp}/ripeline-test-app.log"
args=(test -project Ripeline.xcodeproj -scheme Ripeline -destination 'platform=macOS')
if [ $# -gt 0 ]; then
    args+=("-only-testing:RipelineTests/$1")
fi

xcodebuild "${args[@]}" > "$log" 2>&1
status=$?

# Hide Xcode-environment noise that is not about this project.
noise='CoreDevice|CoreSimulator|appintentsmetadataprocessor|DVTPlugIn|iOSSimulator'
sed 's/\x1b\[[0-9;]*m//g' "$log" \
    | grep -E "error:|warning:|\*\* TEST|Test case .* failed|✘" \
    | grep -Ev "$noise" | sort -u
if [ $status -ne 0 ] && ! grep -q "TEST FAILED" "$log"; then
    echo "xcodebuild failed before running tests (exit $status). Last lines of $log:"
    tail -5 "$log"
fi
exit $status
