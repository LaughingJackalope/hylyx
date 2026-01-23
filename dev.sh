#!/bin/bash
set -e
cd "$(dirname "$0")"

[[ -f .env ]] && source .env
[[ -d build/Hylyx.app ]] || { echo "Run ./build.sh first"; exit 1; }

swiftc -O $(find src -name '*.swift') -o build/Hylyx.app/Contents/MacOS/hylyx
codesign --force --options runtime --entitlements pkg/entitlements.plist \
    --sign "Developer ID Application: Samespace Inc. (${TEAM_ID})" build/Hylyx.app
sudo ln -sf "$(pwd)/build/Hylyx.app/Contents/MacOS/hylyx" /usr/local/bin/hylyx
echo "✓ Ready"
