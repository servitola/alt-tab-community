# Merging an upstream AltTab release

This fork takes every release of [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos) and ships it
without the paid tier, and also takes what [TroopJostle/alt-tab-community](https://github.com/TroopJostle/alt-tab-community)
adds (see the last section). This file is the rulebook for that merge, for people and for the agent that does most
of it unattended. The worked example is the v11.8.0 merge (`48588223`); when a rule here is unclear, look at
what that commit did.

## Shape

- One merge commit of the release tag into `master`, titled `Merge AltTab vX.Y.Z improvements into the community build`.
  Never rebase `master`, never cherry-pick upstream commits one by one.
- Change as few upstream lines as possible. Every line that differs from upstream is a conflict at the next
  merge. When there is a choice between editing a hot file (`App.swift`, `TilesView.swift`, `SettingsWindow.swift`)
  and editing a file only the feature uses, edit the latter.

## What stays out

The fork removed these, and they stay removed however upstream reshapes them:

- licensing: `src/pro/**` (`LicenseManager`, `LicenseState`, keychain storage, `RemoteLicenseClient`, machine fingerprint);
- the trial and its prompts: `ProTransition*`, the `Day*Window` / `Day*Popover` series, `ProPrompt*`;
- feature gates: `ProFeature`, `PreferenceDefinition` / `ProGatedPreferences`, every `isProLocked` check;
- upsell UI: `UpgradeTab`, `UpgradeButton`, `ProBadgeView`, `ProGradient*`, "Get Pro" / "My Account" menu items,
  the `alttab://` activation URL scheme, `EmailLineWrap`;
- usage tracking of Pro features: `UsageStats` records `triggers` only;
- QA tooling built around license states: `QAMenu`, `QaSurfaces`.

## Resolving conflicts

| Conflict | Resolution |
| --- | --- |
| upstream modified a file this fork deleted | keep it deleted |
| `appcast.xml`, `README.md`, `Info.plist` Sparkle keys (`SUPublicEDKey`, `SUEnableAutomaticChecks`) | ours |
| `changelog.md` | upstream's, verbatim |
| `alt-tab-macos.xcodeproj/project.pbxproj` | upstream's, then `scripts/community/prune-pbxproj.py`; never by hand |
| a hunk that is Pro on upstream's side | drop the Pro part, keep everything else upstream changed in that hunk |
| upstream refactored code this fork edited | take the refactor, then remove the Pro parts from it (as `ShortcutEditor`'s `ShortcutOverrideBinding` in v11.8.0) |

## New upstream code

- A new feature that upstream gates on Pro: keep it and make it available to everyone. Where the gate asks for a
  license state, answer as a Pro user (`SearchDiscoveryHint` passes `access: .pro`) instead of rewriting the policy
  code and its tests.
- A new file that exists only to sell, activate or display the license: delete it with its specs and tests.
- New code that calls something this fork removed: remove the call. If it needs data the fork no longer records
  (Pro usage counters), find the smallest local substitute, as `TilesView` marks the search hint "used" directly.
- Upstream deleting something this fork still uses is caught only by the build: restore the smallest piece
  (`CachedUserDefaults.string` for `preferredScreen` in v11.8.0).

## This fork's own changes, which must survive

- Updates: `Endpoints.appcastUrl` points at this repository's `appcast.xml`; `SUPublicEDKey` is this fork's key;
  the default update policy is `autoCheck`.
- "Show the switcher on a specific screen": `DisplaySelectionResolver*`, `preferredScreen` in `Preferences`,
  `AppearanceTab`, `Screens`, `ScreensEvents`, `PreferencesEvents`, `MacroPreferences`.
- The focus fix in `SkyLight.framework.swift` (`3e638464`).
- `scripts/community/`, `MERGE-POLICY.md`, the CI guard `if: github.repository == 'lwouis/alt-tab-macos'`.

## Merging TroopJostle/alt-tab-community

This fork grew out of [TroopJostle/alt-tab-community](https://github.com/TroopJostle/alt-tab-community), which
removes the paid tier too. New commits on its `master` are merged the same way (one merge commit, same gates) and
released as the next build on top of the current upstream version: 11.8.0.1, 11.8.0.2, …

- Their bug fixes, Pro removals and features: take them.
- Where they decided differently from this file, this file wins: the update feed and key, the default update
  policy, the free search hint, `appcast.xml`, `README.md`, `scripts/community/`.
- If they merged an upstream release in their own way, keep the resolution that follows this policy and changes
  fewer upstream lines.

## Before the merge counts as done

`scripts/community/check-merge.sh vX.Y.Z` passes, the Release build succeeds, and no unit test fails that does
not also fail on plain upstream `vX.Y.Z`. Tests are deleted only together with the Pro code they test.
Comments follow `AGENTS.md`: say what the code cannot, never narrate history.
