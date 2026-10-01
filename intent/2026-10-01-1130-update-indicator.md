---
status: draft
issue: 1130
author: olafkfreund
---

# Intent: Show available Nixarchy releases in the bar

## Problem

`omarchy-update-available` always exits 1. The shipped Omarchy shell's
`SystemUpdate.qml` runs it at startup and every six hours, and after an IPC
refresh; it shows the icon only when the command exits 0. The icon therefore
never reports a Nixarchy release. This is the shell bar widget, not Waybar.

The current comment says the answer requires flake evaluation. The installed
flake already records the Nixarchy input's update target in
`flake.lock` (`original`) and installed commit in `locked.rev`, so a bounded
read of the lock and release refs can answer the narrower question of whether
a newer Nixarchy release is available. It cannot answer whether nixpkgs or
other inputs have updates.

## Proposed outcome

On a machine tracking Nixarchy's `release` branch, the icon appears when a
newer released commit is available and disappears when the installed commit
is current. It stays hidden offline, when the lock cannot be read, or when
the user's pin has no moving Nixarchy release target. Clicking it continues
to launch `omarchy update`.

## Affected users and systems

- Omarchy shell users on installed Nixarchy machines; the check runs at shell
  startup, then every six hours, and on explicit widget refresh.
- The replacement command in `pkgs/omarchy/nix-bin/`, its package runtime
  dependencies, and one cheap command check. No host rebuild path or Waybar
  configuration is involved in the behavior being detected.
- The installer writes `flake.nix` with
  `github:olafkfreund/nixarchy/release` and a matching lock `original.ref`;
  `locked.rev` is the exact installed commit. Older installations can have an
  `original.rev` that stays frozen. Users can choose a tag, another branch,
  an exact revision, or a local path instead.

## Constraints

- Read `${NIXARCHY_FLAKE:-/etc/nixos}/flake.lock` as JSON without evaluating
  the flake. `programs.nixarchy.flake` supplies `NIXARCHY_FLAKE` in a session;
  `/etc/nixos` is the default, not a universal location.
- Use at most one network operation with a short deadline. Treat timeout,
  offline state, malformed output, missing lock, and an unsupported pin as
  exit 1; reserve exit 0 for proven availability. Emit no error spinner.
- Only a user whose lock `original` names this repository's `release` ref
  should get an actionable icon. A tag, fixed rev, local path, or other branch
  is the user's choice; a newer release would not be selected by their normal
  update. Do not silently reinterpret that choice.
- Check that the selected commit is a newer published release, rather than
  assuming any unequal SHA is newer. Release tags can be annotated; their
  peeled commit matters. The release workflow moves `release` to the tag only
  after publishing and verifying its assets.
- Keep the package's command dependencies explicit. `jq` and `git` already
  occur in `pkgs/omarchy/default.nix`'s shared `runtimeDeps`; verify the
  packaged command gets them before adding duplicate dependencies.
- Add the smallest check that first fails against the present `exit 1` and
  then covers newer, same, offline, unreadable lock, and a non-release pin.
  No implementation, build, or workflow edit is authorized at this gate.

## Open questions

1. **What counts as an available release?** Recommend the published tag whose
   commit is the `release` branch tip. A single timeout-bound
   `git ls-remote --heads --tags` can fetch both refs; compare peeled tag
   commits with `locked.rev` and their release versions. If the installed
   commit cannot be placed in that release sequence, answer no rather than
   claiming an unrelated or older commit is newer. Avoid GitHub's
   `/releases/latest`, which omits this project's prereleases.
2. **Should fixed or custom pins light the icon?** Recommend no for tags,
   revs, paths, and non-`release` branches. The icon launches an update that
   follows the user's declared input, and those inputs do not follow this
   release stream. A separate informational release notice would be a
   different feature.
3. **Should the icon also cover nixpkgs updates?** Recommend no. This issue
   can make a precise statement about the Nixarchy release at low cost;
   comparing arbitrary package-set inputs would change the meaning and cost
   of the six-hour check.
