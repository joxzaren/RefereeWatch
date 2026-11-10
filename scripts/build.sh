#!/bin/zsh
# Build both app schemes for the simulators. Prints only diagnostics and the result.
set -u
cd "${0:A:h}/.."
rc=0
for pair in "RefereeWatch|generic/platform=iOS Simulator" "RefereeWatchWatch|generic/platform=watchOS Simulator"; do
  scheme=${pair%%|*}; dest=${pair#*|}
  echo "== $scheme"
  out=$(xcodebuild -project RefereeWatch.xcodeproj -scheme "$scheme" -destination "$dest" \
        -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build 2>&1)
  print -r -- "$out" | grep -E "^/.*: (error|warning): |^(error|warning): " | sort -u
  print -r -- "$out" | grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" || rc=1
  print -r -- "$out" | grep -q "BUILD SUCCEEDED" || rc=1
done
exit $rc
