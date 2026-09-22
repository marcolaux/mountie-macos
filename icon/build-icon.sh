#!/bin/zsh
# Renders icon/AppIcon.icns from icon/make-icon.swift. Usage: icon/build-icon.sh
set -e
cd "${0:A:h}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
swiftc -O make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/AppIcon.iconset" >/dev/null
iconutil -c icns "$TMP/AppIcon.iconset" -o AppIcon.icns
echo "Built icon/AppIcon.icns"
