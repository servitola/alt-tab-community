#!/usr/bin/env bash
# Static gates for an upstream merge (see MERGE-POLICY.md). Run inside the checkout being merged, after
# conflicts are resolved and before or after the merge is committed. The script itself may live elsewhere.
#
#   scripts/community/check-merge.sh v11.8.0 [base]
#
# base is what the merge started from (default: HEAD, or HEAD^1 once the merge is committed). Prints every
# failure, exits non-zero if there was one. The build, tests and binary checks live in the caller and release.sh.
set -uo pipefail
tools=$(cd "$(dirname "$0")" && pwd)
cd "$(git rev-parse --show-toplevel)" || exit 1

tag="${1:?usage: scripts/community/check-merge.sh <upstream-tag> [base]}"
if [ -n "${2:-}" ]; then base=$2
elif git rev-parse -q --verify MERGE_HEAD >/dev/null; then base=HEAD
else base=HEAD^1
fi
failures=0
fail() { echo "✗ $*"; failures=$((failures + 1)); }
pass() { echo "✓ $*"; }

markers=$(git grep -lE '^(<<<<<<<|>>>>>>>) ' -- . ':!*.pbxproj' 2>/dev/null; grep -lE '^(<<<<<<<|>>>>>>>) ' alt-tab-macos.xcodeproj/project.pbxproj 2>/dev/null)
[ -z "$markers" ] && pass "no conflict markers" || fail "conflict markers in: $(echo $markers)"

[ ! -e src/pro ] && pass "src/pro is gone" || fail "src/pro exists again"

removed='\b(LicenseManager|LicenseState|RemoteLicenseClient|ProFeature|ProTransition[A-Za-z]*|ProGatedPreferences|PreferenceDefinition|UpgradeTab|UpgradeButton|ProBadgeView|ProGradient[A-Za-z]*|ProPrompt[A-Za-z]*|EmailLineWrap|QAMenu|QaSurfaces|isProLocked|Day[0-9]+[A-Za-z]*(Window|Popover))\b'
# Whole-line comments may still name the old concepts (upstream's own tests explain themselves that way).
hits=$(grep -rnE --include='*.swift' "$removed" src 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)')
[ -z "$hits" ] && pass "no references to removed Pro code" || fail "references to removed Pro code:
$hits"

before=$failures
for path in src/switcher/state/DisplaySelectionResolver.swift scripts/community/release.sh MERGE-POLICY.md; do
  [ -e "$path" ] || fail "fork file missing: $path"
done
grep -q 'preferredScreen' src/switcher/state/Screens.swift || fail "Screens.swift lost preferredScreen"
for probe in 'src/api/Endpoints.swift:appcastUrl' 'Info.plist:SUPublicEDKey'; do
  file=${probe%%:*} key=${probe#*:}
  was=$(git show "$base:$file" 2>/dev/null | grep -A1 "$key" | tr -d '[:space:]')
  now=$(grep -A1 "$key" "$file" | tr -d '[:space:]')
  [ "$was" = "$now" ] || fail "$key in $file changed from $base"
done
[ "$failures" = "$before" ] && pass "fork features and update feed intact"

urls=$(git diff "$tag" -- src Info.plist config | grep '^+' | grep -oE 'https?://[^" )<>]+' | sort -u \
  | grep -vE '^https://(raw\.githubusercontent\.com|github\.com)/servitola/alt-tab-community' || true)
[ -z "$urls" ] && pass "no network endpoints beyond upstream's" || fail "URLs this fork adds on top of $tag:
$urls"

top=$(grep -m1 -oE '^# \[?[0-9]+\.[0-9]+\.[0-9]+' changelog.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ "v$top" = "$tag" ] && pass "changelog is at $tag" || fail "changelog.md starts at $top, not ${tag#v}"

project=alt-tab-macos.xcodeproj/project.pbxproj
if plutil -lint -s "$project"; then pass "project file parses"; else fail "project file does not parse"; fi
scratch=$(mktemp -d)
cp "$project" "$scratch/before"
python3 "$tools/prune-pbxproj.py" >/dev/null
if cmp -s "$scratch/before" "$project"; then pass "project file has no stale references"
else fail "project file had stale references (prune-pbxproj.py has now removed them; commit that)"; fi
missing=$(git ls-files 'src/*.swift' | while read -r f; do grep -q "path = \"\{0,1\}$(basename "$f")\"\{0,1\};" "$project" || echo "$f"; done)
[ -z "$missing" ] && pass "every source file is in the project" || fail "source files not in the project:
$missing"
rm -rf "$scratch"

[ "$failures" = 0 ] && { echo "check-merge: all gates pass"; exit 0; }
echo "check-merge: $failures gate(s) failed"
exit 1
