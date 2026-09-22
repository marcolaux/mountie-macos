#!/bin/zsh
# Builds "Mountie.app" (universal) next to this script. Usage: ./build.sh [install|release]
#   install - also copies the app to ~/Applications
#   release - signs with the Developer ID certificate (hardened runtime) for notarization,
#             and links + embeds Sparkle for auto-updates (`VERSION` is the version's
#             single source; release.sh bumps it)
# Also downloads rclone (universal, checksum-verified) for S3 shares; cached in deps/.
set -e
cd "${0:A:h}"
APP="Mountie.app"
RCLONE_VERSION="${RCLONE_VERSION:-1.75.1}"
VERSION=$(<VERSION)
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
# Public EdDSA key of the release signing key; its private half lives only in the login
# keychain (deps/sparkle-bin/generate_keys created it and printed this string).
SPARKLE_PUBKEY="qm8OiKtPqC3l8Z2Jze3wc5TwhKObmohB6t1vNuCSYYw="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- rclone (S3 shares are served through it as NFS on localhost) ---
if [[ ! -x deps/rclone ]]; then
  echo "Fetching rclone v$RCLONE_VERSION (cached in deps/)…"
  mkdir -p deps
  fetched=0
  sums=$(curl -fsSL "https://downloads.rclone.org/v$RCLONE_VERSION/SHA256SUMS") || true
  for arch in arm64 amd64; do
    f="rclone-v$RCLONE_VERSION-osx-$arch.zip"
    curl -fsSL "https://downloads.rclone.org/v$RCLONE_VERSION/$f" -o "$TMP/$f" || continue
    expected=$(print -r -- "$sums" | awk -v f="$f" '$2==f {print $1}')
    actual=$(shasum -a 256 "$TMP/$f" | awk '{print $1}')
    if [[ -z $expected || $actual != $expected ]]; then echo "Checksum mismatch for $f" >&2; continue; fi
    unzip -oq "$TMP/$f" "*/rclone" -d "$TMP/$arch" || continue
    mv "$TMP/$arch/rclone-v$RCLONE_VERSION-osx-$arch/rclone" "deps/rclone.$arch" && fetched=$((fetched+1))
  done
  if (( fetched == 2 )); then
    lipo -create deps/rclone.arm64 deps/rclone.amd64 -output deps/rclone && rm -f deps/rclone.arm64 deps/rclone.amd64
  else
    echo "warning: couldn't fetch rclone; S3 shares won't work (brew install rclone to use them)" >&2
    rm -f deps/rclone.arm64 deps/rclone.amd64
  fi
fi

# --- Sparkle (auto-updates; embedded and linked only in release builds) ---
if [[ ! -d deps/Sparkle.framework ]]; then
  echo "Fetching Sparkle v$SPARKLE_VERSION (cached in deps/)…"
  mkdir -p deps
  f="Sparkle-$SPARKLE_VERSION.tar.xz"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/$f" -o "$TMP/$f"
  print -r -- "$SPARKLE_SHA256  $TMP/$f" | shasum -a 256 -c -
  tar -xJf "$TMP/$f" -C "$TMP"
  cp -R "$TMP/Sparkle.framework" deps/Sparkle.framework
  mkdir -p deps/sparkle-bin
  cp "$TMP/bin/generate_keys" "$TMP/bin/sign_update" deps/sparkle-bin/
fi

# Sparkle is only linked into Developer ID release builds — an ad-hoc signed host
# can't pass Sparkle's validation of downloaded updates anyway.
FLAGS=()
if [[ ${1:-} == release ]]; then
  FLAGS=(-DRELEASE -F deps -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi
for arch in arm64 x86_64; do
  # CoreServices is linked explicitly: its LSSharedFileList symbols are only dlsym'd at
  # runtime (see the Sidebar enum), so nothing else would pull the image into the process.
  swiftc -O -parse-as-library -swift-version 5 -target "$arch-apple-macos14.0" \
    Model.swift Mountie.swift -framework CoreServices $FLAGS -o "$TMP/Mountie-$arch"
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" \
    netfsmount.swift -o "$TMP/netfsmount-$arch"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$TMP"/Mountie-* -output "$APP/Contents/MacOS/Mountie"
lipo -create "$TMP"/netfsmount-* -output "$APP/Contents/Resources/netfsmount"
cp mountiectl "$APP/Contents/Resources/mountiectl"
if [[ -x deps/rclone ]]; then
  cp deps/rclone "$APP/Contents/Resources/rclone"
fi
[[ icon/AppIcon.icns -nt icon/make-icon.swift ]] || icon/build-icon.sh
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/Resources/mountiectl" "$APP/Contents/Resources/netfsmount"
[[ -x $APP/Contents/Resources/rclone ]] && chmod +x "$APP/Contents/Resources/rclone"
if [[ ${1:-} == release ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R deps/Sparkle.framework "$APP/Contents/Frameworks/"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Mountie</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>wtf.laux.mountie</string>
  <key>CFBundleName</key><string>Mountie</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocationUsageDescription</key><string>Mountie reads the name of the Wi-Fi network you're on, so it can mount shares only on the networks you choose.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Mountie reads the name of the Wi-Fi network you're on, so it can mount shares only on the networks you choose.</string>
  <key>NSLocationAlwaysAndWhenInUseUsageDescription</key><string>Mountie reads the name of the Wi-Fi network you're on, so it can mount shares only on the networks you choose.</string>
  <key>SUFeedURL</key><string>https://github.com/marcolaux/mountie-macos/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBKEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
EOF

if [[ ${1:-} == release ]]; then
  ID=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')
  [[ -n $ID ]] || { echo "No Developer ID Application certificate found" >&2; exit 1; }
  # Nested binaries must be signed before the bundle, so the outer signature covers them.
  BINS=("$APP/Contents/MacOS/Mountie" "$APP/Contents/Resources/netfsmount")
  [[ -x $APP/Contents/Resources/rclone ]] && BINS+=("$APP/Contents/Resources/rclone")
  for BIN in $BINS; do
    codesign --force --sign "$ID" --timestamp --options runtime "$BIN" >/dev/null 2>&1
  done
  # Sparkle ships signed by the Sparkle team; hardened runtime's library validation
  # would reject that, so it's re-signed with our identity before the bundle seals
  # it in — innermost first (XPC services, then the helper binaries and framework).
  FW="$APP/Contents/Frameworks/Sparkle.framework"
  for NESTED in "$FW/Versions/B/XPCServices"/*.xpc(N) \
                "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app"; do
    codesign --force --sign "$ID" --timestamp --options runtime "$NESTED" >/dev/null 2>&1
  done
  codesign --force --sign "$ID" --timestamp --options runtime "$FW" >/dev/null 2>&1
  # Signing the bundle re-signs the main executable, so its entitlements go here: without
  # the Location one, hardened runtime silently denies Location (no prompt, ever).
  codesign --force --sign "$ID" --timestamp --options runtime \
    --entitlements Mountie.entitlements "$APP" >/dev/null 2>&1
  echo "Signed (Developer ID, hardened runtime)"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "Signed (ad-hoc)"
fi
echo "Built: $PWD/$APP"

if [[ ${1:-} == install ]]; then
  rm -rf "$HOME/Applications/$APP"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications"
fi
