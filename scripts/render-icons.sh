#!/bin/bash
# Regenerates the app icon set from the SVGs in docs/brand.
# Edit docs/brand/make_icons.py, then run this script.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 docs/brand/make_icons.py
out=Shared/Assets.xcassets/AppIcon.appiconset
render() { swift scripts/render-icons.swift "docs/brand/$1.svg" "$out/$2" "$3" ${4:-}; }
render icon-light  icon_ios_1024.png        1024 opaque
render icon-dark   icon_ios_dark_1024.png   1024 opaque
render icon-tinted icon_ios_tinted_1024.png 1024 opaque
render icon-mac    icon_mac_1024.png        1024
for s in 16 32 64 128 256 512; do render icon-mac "mac_$s.png" "$s"; done
echo "Icons written to $out"
swift scripts/render-icons.swift docs/brand/wordmark.svg      docs/brand/wordmark.png      1600x480
swift scripts/render-icons.swift docs/brand/wordmark-dark.svg docs/brand/wordmark-dark.png 1600x480
swift scripts/render-icons.swift docs/brand/icon-light.svg    docs/brand/icon.png          1024 opaque
echo "Wordmarks written to docs/brand"
# The goat on its tile for in-app use, such as the welcome screen (112 points).
mascot=Shared/Assets.xcassets/Mascot.imageset
swift scripts/render-icons.swift docs/brand/icon-light.svg "$mascot/mascot.png"    112
swift scripts/render-icons.swift docs/brand/icon-light.svg "$mascot/mascot@2x.png" 224
swift scripts/render-icons.swift docs/brand/icon-light.svg "$mascot/mascot@3x.png" 336
echo "Mascot written to $mascot"
