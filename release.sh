#!/bin/zsh
# Packages Mountie.app, publishes v$1 and creates the GitHub release.
# Usage: ./release.sh 1.3.0 notes-1.3.0.md   (notes file doubles as the GitHub
# release body and the appcast update description)
# Notarizes when a stored notarytool profile exists, and says so honestly otherwise.
# Apple ID, team, and profile name live in .env (copy from .env.example, fill in —
# it's gitignored); the one-time credential setup is then:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
set -e
cd "${0:A:h}"

if [[ -f .env ]]; then source .env; fi

VER=${1:?[usage] ./release.sh 1.3.0 notes-1.3.0.md}
NOTES=${2:?[usage] ./release.sh 1.3.0 notes-1.3.0.md}
APP="Mountie.app"
ZIP="Mountie-$VER.zip"
PROFILE="${NOTARY_PROFILE:-mountie-notary}"
print -r -- "$VER" > VERSION    # build.sh reads this into both plist version keys
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

./build.sh release
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Packaged $PWD/$ZIP"

# The website's download card names the asset and version this release
# creates; site.config.json is their single source (vite.config.ts reads it).
SITE_CONFIG="website/site.config.json"
if [[ -f "$SITE_CONFIG" ]]; then
  sed -i '' -e "s/\"version\": \"[^\"]*\"/\"version\": \"$VER\"/" \
            -e "s/\"mac\": \"Mountie-[^\"]*\.zip\"/\"mac\": \"$ZIP\"/" "$SITE_CONFIG"
  echo "Updated $SITE_CONFIG to $VER — republish the site: (cd website && npm run build && npm run publish)"
fi

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "Notarizing $ZIP (profile: $PROFILE)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  # The staple changed the app bundle, so the zip must be rebuilt to carry the
  # ticket — otherwise the published download has none and every first launch
  # would depend on Gatekeeper's online check.
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
else
  echo "No notarytool profile '$PROFILE' — publishing without notarization"
fi

if [[ -n $(git status --porcelain) ]]; then
  git add -A
  git commit -m "Release Mountie $VER

Co-Authored-By: Claude Code <noreply@anthropic.com>"
fi
git push

# The feed Sparkle downloads — one item is enough, the newest wins. Attaching it
# to the release is what makes the app's stable feed URL resolve:
#   https://github.com/marcolaux/mountie-macos/releases/latest/download/appcast.xml
SIG=$(deps/sparkle-bin/sign_update "$ZIP")    # → sparkle:edSignature="…" length="…"
cat > "$TMP/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mountie</title>
    <link>https://mountie.miniml.net</link>
    <description>Mountie updates</description>
    <item>
      <title>Mountie $VER</title>
      <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$VER</sparkle:version>
      <sparkle:shortVersionString>$VER</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$(cat "$NOTES")]]></description>
      <enclosure url="https://github.com/marcolaux/mountie-macos/releases/download/v$VER/$ZIP" type="application/zip" $SIG />
    </item>
  </channel>
</rss>
EOF

gh release create "v$VER" "$ZIP" "$TMP/appcast.xml" \
  --title "Mountie $VER" \
  --notes-file "$NOTES"

echo "Released: https://github.com/marcolaux/mountie-macos/releases/tag/v$VER"