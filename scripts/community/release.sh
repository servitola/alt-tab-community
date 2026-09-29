#!/usr/bin/env bash
# Builds, signs, notarizes and publishes one community release, then adds it to appcast.xml.
#
#   scripts/community/release.sh 11.8.0          # a merge of upstream v11.8.0
#   scripts/community/release.sh 11.8.0.1        # a community fix on top of it
#   DRY_RUN=1 scripts/community/release.sh 11.8.0  # build, sign and verify only; nothing leaves the machine
#
# Signing happens on the maintainer's Mac on purpose: CI would need the Developer ID private key as a
# GitHub secret. Needs, once per machine:
#   - config/local.xcconfig naming a "Developer ID Application" identity and its team (see local.xcconfig.example)
#   - xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id … --team-id …
#   - the Sparkle EdDSA private key at $SPARKLE_ED_KEY_FILE (its public half is SUPublicEDKey)
set -euo pipefail
cd "$(dirname "$0")/../.."

version="${1:?usage: scripts/community/release.sh <version>}"
notaryProfile="${NOTARY_PROFILE:-alttab-notary}"
edKeyFile="${SPARKLE_ED_KEY_FILE:-$HOME/.config/alttab-community/sparkle_ed25519_private.key}"
remote="${RELEASE_REMOTE:-origin}"
dryRun="${DRY_RUN:-}"

repo=$(git remote get-url "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
tag="community-$version"
buildDir="build/release-$version"
app="$buildDir/Build/Products/Release/AltTab.app"
zip="$buildDir/AltTab-$version.zip"

fail() { echo "release: $*" >&2; exit 1; }

# The key file holds the raw 32-byte Ed25519 seed in base64, as Sparkle's generate_keys exports it.
# Prefixing the fixed PKCS#8 header lets openssl derive the public half to compare with SUPublicEDKey.
publicKey() {
  { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'; base64 -d < "$edKeyFile"; } \
    | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64
}

preflight() {
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "version must look like 11.8.0 or 11.8.0.1"
  git diff --quiet && git diff --cached --quiet || fail "tracked files have uncommitted changes"
  [ -r "$edKeyFile" ] || fail "no Sparkle key at $edKeyFile"
  grep -q '^CODE_SIGN_IDENTITY *= *Developer ID Application' config/local.xcconfig 2>/dev/null \
    || fail "config/local.xcconfig must set CODE_SIGN_IDENTITY to a Developer ID Application identity"
  grep -q "<sparkle:version>$version<\|sparkle:version=\"$version\"" appcast.xml && fail "$version is already in appcast.xml"
  [ -n "$dryRun" ] && return
  [ "$(git branch --show-current)" = master ] || fail "release from master"
  git fetch -q "$remote"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "$remote/master")" ] || fail "master is not in sync with $remote/master"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "tag $tag exists"
  gh release view "$tag" -R "$repo" >/dev/null 2>&1 && fail "release $tag exists on $repo"
  xcrun notarytool history --keychain-profile "$notaryProfile" >/dev/null || fail "notary profile '$notaryProfile' is missing"
}

build() {
  rm -rf "$buildDir"
  # Command-line settings beat config/local.xcconfig, where --timestamp=none would make notarization fail.
  xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -configuration Release -derivedDataPath "$buildDir" \
    CURRENT_PROJECT_VERSION="$version" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --deep --options runtime" APPCENTER_SECRET= \
    -quiet build
}

verify() {
  codesign --verify --deep --strict "$app"
  local signature
  signature=$(codesign -dv --verbose=2 "$app" 2>&1)
  grep -q "^Runtime Version=" <<<"$signature" || fail "hardened runtime is off"
  grep -q "^Authority=Developer ID Application" <<<"$signature" || fail "not signed with Developer ID"
  grep -q "^Timestamp=" <<<"$signature" || fail "signature has no secure timestamp"
  [ "$(defaults read "$PWD/$app/Contents/Info.plist" CFBundleShortVersionString)" = "$version" ] || fail "bundle version is not $version"
  [[ $(lipo -archs "$app/Contents/MacOS/AltTab") =~ x86_64 && $(lipo -archs "$app/Contents/MacOS/AltTab") =~ arm64 ]] || fail "binary is not universal"
  [ "$(defaults read "$PWD/$app/Contents/Info.plist" SUPublicEDKey)" = "$(publicKey)" ] || fail "SUPublicEDKey does not match $edKeyFile"
  if strings -a "$app/Contents/MacOS/AltTab" | grep -E "Get Pro|Trial expired|license_key|LicenseManager" >/dev/null; then fail "licensing strings in the binary"; fi
}

package() {
  ditto -c -k --keepParent "$app" "$zip"
}

notarize() {
  xcrun notarytool submit "$zip" --keychain-profile "$notaryProfile" --wait --timeout 30m
  xcrun stapler staple "$app"
  spctl --assess --type execute --verbose "$app"
  package
}

appcastItem() {
  local signature
  signature=$(vendor/Sparkle/bin/sign_update -f "$edKeyFile" "$zip")
  local minimumSystemVersion
  minimumSystemVersion=$(awk -F ' = ' '/^MACOSX_DEPLOYMENT_TARGET/ { print $2 }' config/base.xcconfig)
  cat <<ITEM
    <item>
      <title>Version $version</title>
      <pubDate>$(LC_ALL=C date +'%a, %d %b %Y %H:%M:%S %z')</pubDate>
      <sparkle:minimumSystemVersion>$minimumSystemVersion</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/$repo/releases/download/$tag/AltTab-$version.zip"
        sparkle:version="$version"
        sparkle:shortVersionString="$version"
        $signature
        type="application/octet-stream"/>
    </item>
ITEM
}

releaseNotes() {
  local upstream=$version
  [[ $version =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$ ]] && upstream=${BASH_REMATCH[1]}
  printf 'AltTab %s with every former Pro feature free. Signed with Developer ID and notarized by Apple.\n\n' "$version"
  printf 'Based on upstream [v%s](https://github.com/lwouis/alt-tab-macos/releases/tag/v%s); its changes are in [changelog.md](https://github.com/%s/blob/%s/changelog.md).\n\n' "$upstream" "$upstream" "$repo" "$tag"
  printf 'Install: download `AltTab-%s.zip`, unzip, move AltTab.app to /Applications. Later versions arrive through the built-in updater.\n' "$version"
}

# The tag marks the commit that was built, and the zip is public before the feed mentions it, so no
# updater ever follows an appcast entry to a missing file.
publish() {
  git tag -a "$tag" -m "AltTab community $version"
  git push -q "$remote" "$tag"
  gh release create "$tag" "$zip" -R "$repo" --title "AltTab $version (community)" --notes "$(releaseNotes)"
  appcastItem > "$buildDir/item.xml"
  sed -i '' -e "/<language>/r $buildDir/item.xml" appcast.xml
  xmllint --noout appcast.xml
  git add appcast.xml
  git commit -q -m "chore(release): community $version"
  git push -q "$remote" master
}

preflight
build
verify
package
if [ -n "$dryRun" ]; then
  appcastItem
  echo "release: dry run done, $zip is signed but not notarized"
  exit 0
fi
notarize
publish
echo "release: https://github.com/$repo/releases/tag/$tag"
