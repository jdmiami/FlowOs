#!/bin/bash
set -euo pipefail
mkdir -p Vendor BonsaiResources
ARCHIVE=$(mktemp -t clitert.XXXXXX)
trap 'rm -f "$ARCHIVE"' EXIT
curl -fL --retry 3 'https://github.com/google-ai-edge/LiteRT/releases/download/v2.4.0/CLiteRT.xcframework.zip' -o "$ARCHIVE"
echo "71c4e4643f65a307bc3de6a0dcc82bf97576153b2c2c51e693a1623316392b53  $ARCHIVE" | shasum -a 256 -c -
unzip -q -o "$ARCHIVE" -d Vendor
test -d Vendor/CLiteRT.xcframework
python3 Scripts/bonsai-manifest.py
