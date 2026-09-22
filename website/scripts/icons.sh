#!/bin/zsh
# Extracts the site's icon assets from icon/AppIcon.icns (drawn by
# icon/make-icon.swift): a 64px favicon, a 180px apple-touch-icon, and the
# 512px mark the nav and hero render. Re-run after icon/build-icon.sh.
set -e
cd "${0:A:h}/../.."

ICNS="icon/AppIcon.icns"
SET="website/.iconset.tmp.iconset"

iconutil --convert iconset --output "$SET" "$ICNS"
# The iconset's largest tile (icon_512x512.png is 512; icon_512x512@2x is 1024).
sips -z 512 512 "$SET/icon_512x512@2x.png" --out website/src/assets/app-icon.png >/dev/null
sips -z 64 64 "$SET/icon_512x512@2x.png" --out website/public/favicon.png >/dev/null
sips -z 180 180 "$SET/icon_512x512@2x.png" --out website/public/apple-touch-icon.png >/dev/null
rm -rf "$SET"
echo "icons: website/src/assets/app-icon.png, website/public/{favicon,apple-touch-icon}.png"
