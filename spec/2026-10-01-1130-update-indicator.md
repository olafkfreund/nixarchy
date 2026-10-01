---
status: approved
issue: 1130
intent: intent/2026-10-01-1130-update-indicator.md
---

# Spec: Detect an available Nixarchy release for the bar

## Design

Replace the unconditional `exit 1` in
`pkgs/omarchy/nix-bin/omarchy-update-available:6-18`. Preserve the command's
exit-only interface: 0 means a proven newer Nixarchy release, and 1 means
no actionable release, including any uncertainty. The shipped
`SystemUpdate.qml` executes it on startup and every six hours and checks only
that exit code. It is an Omarchy shell widget, not Waybar.

Read the user's `${NIXARCHY_FLAKE:-/etc/nixos}/flake.lock` with `jq`, without
flake evaluation. Resolve `root.inputs.nixarchy` to its node rather than
assuming the node is literally named `nixarchy`; require that node's
`original` to be `github:olafkfreund/nixarchy` with `ref: release`, and its
`locked.rev` to be a full commit SHA. This matches the installer output in
`installer/mkFlake.nix:122-148`. `programs.nixarchy.flake` defaults to
`/etc/nixos` in `modules/apps.nix:1114-1117` and sets `NIXARCHY_FLAKE` in
`modules/nixos.nix:1185-1189`. A missing, malformed, or unreadable lock, a
missing input, or a different source or ref returns 1 before network access.
No parsing of `flake.nix` syntax is needed.

For an eligible lock, make one `git ls-remote --heads --tags` invocation to
the fixed Nixarchy repository URL, under `timeout` with Git prompting
disabled. Read the `release` branch tip and all `v<major>.<minor>.<patch>-<revision>`
tags. For annotated tags use the peeled `^{}` commit, and for lightweight
tags use the tag ref's commit. The branch tip must match a release tag; the
installed `locked.rev` must match a release tag too. Compare numeric version
components, including the revision after `-`, and return 0 only when the tip's
tag is higher than every matching installed tag. Empty or malformed refs,
timeout, Git failure, a tip with no tag, an installed SHA with no release tag,
or an equal or older tip returns 1. This avoids treating any different SHA as
newer. The release workflow publishes and verifies assets before advancing
`release` (`docs/internals/workflows.md:297-301`); it is the moving target the
installer writes (`installer/mkFlake.nix:35-39`).

Use the existing `jq`, `git`, and `coreutils` entries in
`pkgs/omarchy/default.nix:184-195,282`; do not duplicate them. The replacement
scripts are copied unwrapped into the Omarchy package at
`pkgs/omarchy/default.nix:1013-1034`, and the shared dependencies enter the
system through `flake.nix:1320-1329`. Add a small check in `tests/` and register
it in `flake.nix:1751-1760`. Clarify the icon's release-only meaning in
`docs/manual/updates.md:43-44`. No workflow gate changes are needed: the
repository's generated-checks step includes newly registered checks.

## Alternatives rejected

- `nix flake update`, `nix eval`, or GitHub's `/releases/latest`: the first
  mutates the user's lock, evaluation is too costly for a six-hour bar poll,
  and `/releases/latest` omits this project's prereleases.
- Compare only the branch tip SHA with `locked.rev`: a changed SHA can be
  older, unrelated, or an unpublished source commit. It does not prove a newer
  release.
- Light the icon for a tag, exact rev, local path, another branch, or a
  nixpkgs-only update: `omarchy update` follows the user's declared input and
  would not select a newer Nixarchy release in those cases.
- Wrap this one script as `writeShellApplication`: the existing Omarchy CLI
  discovers its unwrapped sibling scripts by metadata; a wrapper would need
  packaging changes for a check that can be expressed in the script itself.

## Risks

- A release branch move can land just after refs are fetched. The icon can
  remain hidden until the next six-hour refresh; this is a freshness delay,
  not a false positive.
- Git ref lookup can time out or fail offline. The icon then remains hidden,
  per the approved offline meaning.
- A machine installed from an untagged development commit can follow
  `release` yet has no position in the release sequence. It remains hidden
  until it updates to a tagged release. Guessing from the SHA would mislead.
- A user who edits `flake.nix` without updating `flake.lock` can leave lock
  metadata stale. The check reports the last resolved lock state; it cannot
  safely parse arbitrary Nix source without evaluation.
- The Omarchy package's unwrapped script does not receive ShellCheck from
  `writeShellApplication`. The new check must invoke ShellCheck explicitly;
  building the package verifies installation, not shell syntax quality.

## Verification

1. Write a stubbed, network-free check that runs the real command with a
   fixture lock and a fake `git ls-remote` response. Before editing the
   command, run it with a newer tagged release and record its failure on the
   current `exit 1`. Confirm the failure is the newer-case exit assertion,
   then prove the same fixture and fake Git are exercised on the green run;
   an unrelated early failure proves nothing. This is the required red proof in
   `AGENTS.md` section 1 and `tests/AGENTS.md:10-16`.
2. After implementation, run the same check for newer, same, older,
   untagged, annotated-tag, offline/timeout, unreadable or malformed lock,
   and tag/rev/path/other-branch pins. Assert 0 only for newer and exactly
   one Git invocation only for eligible locks; no case makes a live network
   request. The test includes an explicit `shellcheck` invocation for the
   replacement script.
3. Build the Omarchy package to verify its replacement file is installed,
   and build the cheap check. Verify `omarchy-runtime` still includes `jq`,
   `git`, and `timeout` from `coreutils`. If the implementation later uses a
   `writeShellApplication`, build that package too: its build runs ShellCheck.
4. Review the diff for only the command, its focused check and registration,
   and the manual sentence. No CI workflow edit or host build is required to
   verify this behavior.
