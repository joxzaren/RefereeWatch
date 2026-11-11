#!/bin/bash
# Selects the newest installed Xcode 27 on a GitHub macOS runner and fails
# clearly when none is installed, since the apps need the iOS and watchOS 27 SDKs.
set -euo pipefail

echo "Installed Xcode versions:"
ls -d /Applications/Xcode*.app 2>/dev/null || true

candidate=$(ls -d /Applications/Xcode_27*.app 2>/dev/null | sort -V | tail -n 1 || true)
if [[ -z "$candidate" ]]; then
  current=$(xcodebuild -version 2>/dev/null | sed -n 1p || true)
  if [[ "$current" == "Xcode 27"* ]]; then
    echo "Using default $current"
    exit 0
  fi
  echo "::error::No Xcode 27 found on this runner (default is $current). Pin a newer runs-on image."
  exit 1
fi

sudo xcode-select -s "$candidate/Contents/Developer"
xcodebuild -version
sdks=$(xcodebuild -showsdks)
printf "%s\n" "$sdks" | grep -E "iphonesimulator|watchsimulator" || true
