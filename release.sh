#!/bin/zsh
# Packages Mountie.app, publishes v$1 and creates the GitHub release.
# Usage: ./release.sh 1.3.0 notes-1.3.0.md   (notes file doubles as the GitHub
# release body and the appcast update description)
#
#   ./release.sh --appcast 1.3.0 notes-1.3.0.md
#     Rewrites the appcast of an existing release and re-uploads it, without
#     publishing a new one — for when the feed needs fixing (a bad pubDate, a
#     wrong URL) and the app itself is fine.
#
# Notarizes when a stored notarytool profile exists, and says so honestly otherwise.
# Apple ID, team, and profile name live in .env (copy from .env.example, fill in —
# it's gitignored); the one-time credential setup is then:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
set -e
cd "${0:A:h}"

if [[ -f .env ]]; then source .env; fi

APP="Mountie.app"
PROFILE="${NOTARY_PROFILE:-mountie-notary}"
TMP=$(mktemp -d)
# Cleanup is a move into the repo's .trash/, not a delete: this project deletes nothing
# (see CLAUDE.md). The scratch dir holds the appcast until the release is published.
trap 'mkdir -p .trash; mv "$TMP" .trash/release-$$ 2>/dev/null' EXIT

# The feed Sparkle downloads — one item is enough, the newest wins. Attaching it
# to the release is what makes the app's stable feed URL resolve:
#   https://github.com/marcolaux/mountie-macos/releases/latest/download/appcast.xml
#
# The date must be RFC 822 ("Tue, 27 Oct 2026 09:27:32 +0000"). Sparkle parses pubDate
# with an en_US_POSIX formatter and drops the whole item when it cannot read it, which
# the app then reports as "An error occurred in retrieving update information" — so the
# locale is pinned below. On a German machine date writes "Di., 27 Okt. 2026 …", which
# Sparkle cannot read, and the feed comes back empty.
write_appcast() {  # write_appcast VER ZIP NOTES -> $TMP/appcast.xml
  local ver=$1 zip=$2 notes=$3 sig
  sig=$(deps/sparkle-bin/sign_update "$zip")
  cat > "$TMP/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mountie</title>
    <link>https://mountie.miniml.net</link>
    <description>Mountie updates</description>
    <item>
      <title>Mountie $ver</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$ver</sparkle:version>
      <sparkle:shortVersionString>$ver</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$(cat "$notes")]]></description>
      <enclosure url="https://github.com/marcolaux/mountie-macos/releases/download/v$ver/$zip" type="application/zip" $sig />
    </item>
  </channel>
</rss>
EOF
}

if [[ ${1:-} == --appcast ]]; then
  VER=${2:?[usage] ./release.sh --appcast 1.3.0 notes-1.3.0.md}
  NOTES=${3:?[usage] ./release.sh --appcast 1.3.0 notes-1.3.0.md}
  ZIP="Mountie-$VER.zip"
  if [[ ! -f $ZIP ]]; then
    print -u2 -- "No $ZIP in the repo — the release has to be built first."
    exit 1
  fi
  write_appcast "$VER" "$ZIP" "$NOTES"
  # Sparkle reads the date with an English formatter; a localized one leaves the app
  # with an empty feed and "An error occurred in retrieving update information".
  if ! grep -q "<pubDate>[A-Z][a-z][a-z], " "$TMP/appcast.xml"; then
    print -u2 -- "The pubDate is not RFC 822 — Sparkle would not read the feed."
    exit 1
  fi
  gh release upload "v$VER" "$TMP/appcast.xml" --clobber
  echo "Appcast for v$VER rewritten: https://github.com/marcolaux/mountie-macos/releases/tag/v$VER"
  exit 0
fi

VER=${1:?[usage] ./release.sh 1.3.0 notes-1.3.0.md}
NOTES=${2:?[usage] ./release.sh 1.3.0 notes-1.3.0.md}
ZIP="Mountie-$VER.zip"
print -r -- "$VER" > VERSION    # build.sh reads this into both plist version keys

./build.sh release
codesign --verify --strict "$APP"
# Tahoe stamps com.apple.provenance xattrs on everything; ditto -c -k would store
# them as AppleDouble ._ files inside the bundle — unsealed contents in embedded
# frameworks' roots, which newer Gatekeeper rejects after Archive Utility extracts
# them as literal files. Strip them and sequester any rest into __MACOSX/.
xattr -cr "$APP"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
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
  ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
else
  echo "No notarytool profile '$PROFILE' — publishing without notarization"
fi

# Only what the release touches plus already-tracked edits: never `git add -A`, which
# would sweep in untracked scratch dirs (and whatever a scratch conf names).
git add VERSION "$NOTES" "$SITE_CONFIG"
git add -u
if [[ -n $(git diff --cached --name-only) ]]; then
  git commit -m "Release Mountie $VER

Co-Authored-By: Claude Code <noreply@anthropic.com>"
fi
git push --set-upstream origin main

# The feed Sparkle downloads — write_appcast() above builds it; see there for the
# date format, which Sparkle has to be able to read.
write_appcast "$VER" "$ZIP" "$NOTES"

gh release create "v$VER" "$ZIP" "$TMP/appcast.xml" \
  --title "Mountie $VER" \
  --notes-file "$NOTES"

echo "Released: https://github.com/marcolaux/mountie-macos/releases/tag/v$VER"
