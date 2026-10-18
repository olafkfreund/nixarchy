---
status: draft
issue: 1342
spec: spec/2026-10-18-1342-launch-browser-self-call.md
---

# Plan: upgrading to Omarchy 4.0.5 must not turn a link into an endless process chain

## Approved decisions, carried over

1. **`~/.config/hyprland-mimeapps.list` is seeded at login, not at a switch.**
   The activation's `seed_dir` (`modules/home.nix:1132`) still copies
   `config/`; right after it, if the list did not exist **before** this run,
   the activation removes it and prints one line. A file or symlink the user
   already had is never touched.
2. **A user oneshot, `nixarchy-seed-mimeapps.service`**, `WantedBy`
   `graphical-session.target`, seeds the list when it is absent (a file or a
   symlink counts as present, `-e || -L`), through a new
   `pkgs/seed-hyprland-mimeapps.sh`.
3. **A carried guard in `omarchy-launch-browser`**: if the resolved
   `browser_exec` is `omarchy-launch-browser` itself, it notifies (critical)
   and exits 1. The text lives in `pkgs/omarchy/1342-launch-browser-self-call.sh`.
   `data/bin-ledger.nix` updates the existing `patch` row; `pkgs/AGENTS.md`
   gets a section with when to drop it.
4. **The release note:** log out and back in after the upgrade.
5. **Coexistence (§14):** a Home Manager symlink at the list's path is
   present, so it is never replaced. `mimeapps.list` is a different file.
   Mode A is unchanged.
6. **Verification:** two runCommand checks, each failing with its fix
   reverted (§1); `checks.session` asserts the list exists after login. The
   activation's "remove if absent before" branch has no cheap layer; the PR
   names that hole (§3).

### Found while planning

- **Nothing hand-written feeds the release body.** `release.yml:298-360`
  derives it with `nix run .#release-notes` (option and upstream deltas). So
  the note goes in `docs/manual/troubleshooting.md`, whose Session row already
  says "log out and in", plus a Discussions post the lead drafts for the owner
  to post. The PR asks whoever cuts the first 4.0.5 release to add the line to
  its body.
- **The guard's anchor.** `browser_exec=$(…)` is rewritten by the path loop
  at `pkgs/omarchy/default.nix:616`, so anchoring on it would depend on that
  edit's output. Anchor on the next line instead, which nothing else edits:
  `if $browser_exec --help 2>/dev/null | grep -q MOZ_LOG; then`.
- **The launcher check's control is the guard removed, not the 4.0.4 launcher.**
  The 4.0.4 source is not in the tree. The built 4.0.5 launcher with the guard
  deleted by `sed`, and a stub `omarchy-cmd-default-browser` that answers
  `omarchy-browser.desktop`, recurses exactly as 4.0.4's did. This is the §1
  form ("the bug reintroduced"), and it varies only the guard.
- **The seed check's symlink case must be dangling.** A symlink to an existing
  file passes `-e` on its own, so a control without `-L` could not fail. A
  Home Manager link whose target is gone is the case `-L` exists for.

## Who does what

Seven files across four editing steps, so the coder (Sonnet) does steps 1–4,
one `SendMessage` per step. The lead does 5–6, every commit and push, and
every build (§6 tiers).

## Steps

### 1. [coder] The launcher guard

- New `pkgs/omarchy/1342-launch-browser-self-call.sh`, exactly:
  ```sh
  if [[ ${browser_exec##*/} == omarchy-launch-browser ]]; then
    notify-send -u critical "No browser to open this in" "The default browser entry runs omarchy-launch-browser itself (#1342). Choose a browser with: omarchy default browser"
    exit 1
  fi
  if $browser_exec --help 2>/dev/null | grep -q MOZ_LOG; then
  ```
- `pkgs/omarchy/default.nix`: directly after the `for f in omarchy-launch-webapp
  omarchy-launch-browser` loop (`:616-621`), add a `substituteInPlace
  $out/share/omarchy/bin/omarchy-launch-browser --replace-fail 'if
  $browser_exec --help 2>/dev/null | grep -q MOZ_LOG; then' "$(cat
  ${./1342-launch-browser-self-call.sh})"`, with a one-line
  `# Why: pkgs/AGENTS.md#…` comment. Same shape as `:2090` (#1339).
- `data/bin-ledger.nix:319-322`: `reason` gains one sentence: it refuses a
  default browser entry that runs the launcher itself, which recursed without
  bound when a 4.0.4 session met 4.0.5's mimeapps list (#1342).
- `pkgs/AGENTS.md`: a section `### omarchy-launch-browser refuses to launch
  itself (#1342)` with an `<a id>` anchor, after the #1339 section. Carried;
  what it guards; that 4.0.5 never reaches it on the normal path; drop it
  when no supported upgrade crosses from a launcher without
  `omarchy-cmd-default-browser`; the check names.

Traps: the installPhase byte budget (`checks.install-phase-budget`): a path
costs ~60 bytes, which is why the text is a file. `nix fmt`, then read
`git diff --stat` (§5: an edit hook may reformat). `notify-send` must resolve:
check `omarchy-launch-browser`'s runtime PATH already has `libnotify` (grep
`runtimeDeps` in `default.nix`), and say so in the report.

### 2. [coder] The login seed

- New `pkgs/seed-hyprland-mimeapps.sh` (`#!/usr/bin/env bash`,
  `set -euo pipefail`): `src=$1 dest=$2`; if `[ -e "$dest" ] || [ -L "$dest" ]`,
  exit 0; else `mkdir -p "$(dirname "$dest")"` and
  `cp --no-preserve=mode,ownership "$src" "$dest"`.
- `modules/home.nix`, a `let` binding near `omarchyPath`:
  `seedMimeapps = pkgs.writeShellApplication { name = "nixarchy-seed-mimeapps";
  runtimeInputs = [ pkgs.coreutils ]; text = builtins.readFile ../pkgs/seed-hyprland-mimeapps.sh; }`
  (precedent: `modules/apps.nix:2957`).
- `modules/home.nix`, the activation (`:1132`): before `seed_dir "${omarchyPath}/config" …`,
  record `mimeapps_absent=1` when `${config.xdg.configHome}/hyprland-mimeapps.list`
  is neither `-e` nor `-L`. After it, if `mimeapps_absent` is set and the file
  now exists, `run rm -f` it and echo
  `nixarchy: hyprland-mimeapps.list is seeded at your next login (#1342)`.
  Two-line comment: why (a running session keeps its launcher until login;
  #1342). Use `run`, like the rest of the activation, so `--dry-run` works.
- `modules/home.nix`, `systemd.user.services` (next to `omarchy-theme-gnome`,
  `:1332`): `nixarchy-seed-mimeapps` — `Unit.Description`,
  `Unit.After`/`PartOf` `graphical-session.target`, `Service.Type = "oneshot"`,
  `ExecStart = "${seedMimeapps}/bin/nixarchy-seed-mimeapps ${omarchyPath}/config/hyprland-mimeapps.list ${config.xdg.configHome}/hyprland-mimeapps.list"`,
  `Install.WantedBy = [ "graphical-session.target" ]`. Guard it by the same
  condition the seed activation has, so Mode A gets neither.

Traps: §7 — plain assignment for the attrset, no `mkDefault`. Read how the
seed activation is conditioned (`lib.mkIf …`) and mirror it exactly. `nix fmt`.

### 3. [coder] The checks

- `tests/launch-browser-self-call.nix` (`{ pkgs, omarchy }:` runCommand,
  `bash coreutils gnugrep gnused` in `nativeBuildInputs`). Fixture:
  `HOME=$PWD/home`, `home/.local/share/applications/omarchy-browser.desktop`
  with `Exec=omarchy-launch-browser %U`. A `bin/` on `PATH` holding stubs:
  `omarchy-cmd-default-browser` (prints `omarchy-browser.desktop`),
  `notify-send` (appends its args to `notified`), `systemd-run`, `uwsm-app`,
  `omarchy-cmd-browser-handoff` (exit 1), and an `omarchy-launch-browser`
  wrapper that increments a `count` file and exits 99 at 20, else execs
  `$LAUNCHER "$@"`. Run `LAUNCHER=<built> timeout 60 omarchy-launch-browser https://example.org`:
  - patched (`${omarchy}/share/omarchy/bin/omarchy-launch-browser`): exit 1,
    `count` is 1, `notified` names #1342;
  - control: `sed` deletes the guard's four lines into `unguarded.sh`, `grep`
    proves they are gone (§1), and the run must bring `count` to 20. If not,
    fail with "the control did not recurse, so this check cannot see #1342".
  `printf '%s\n'` for the fixture files, never a heredoc (§5).
- `tests/seed-hyprland-mimeapps.nix` (runCommand, the script by path):
  absent → copied; a regular file → bytes unchanged; a **dangling** symlink →
  still a symlink to the same target, and the target not created. Control:
  the script with `|| [ -L "$dest" ]` removed (prove with `grep`) must break
  the dangling case.
- `flake.nix`: two `checks` entries beside `menu-model-merge` (`:2552`),
  `omarchy = self.packages.${system}.omarchy` for the first. They are built by
  the `omarchy` job's generated step with no workflow edit (§4).
- `tests/session.nix`: after the desktop is up, near `:297`'s
  `wait_for_file`, add
  `machine.wait_for_file("/home/omarchy/.config/hyprland-mimeapps.list")`
  with a one-line `# #1342: seeded at login by nixarchy-seed-mimeapps` comment.

Traps: `git add` the new files before any build (§5). Do not use `pgrep` in
any wait loop.

### 4. [coder] Docs

- `docs/manual/troubleshooting.md`: under the table (`:20-26`), one short
  paragraph: after upgrading to Omarchy 4.0.5, log out and back in; until then
  links open with the browser the session started with, and
  `hyprland-mimeapps.list` appears at the next login (#1342).

### 5. [lead] Builds and break proofs

Cheap tier, one at a time under `flock /mnt/data/vmtest/codex-build.lock`:
`checks.seed-hyprland-mimeapps`, then (package tier: load below 12, no p620
system build) `checks.launch-browser-self-call`, which builds the `omarchy`
tree, plus `checks.bin-ledger` and `checks.install-phase-budget`. Then the §1
proofs: remove the guard substitution from `default.nix` and watch
`launch-browser-self-call` fail; remove `|| [ -L "$dest" ]` and watch the seed
check fail; restore with `git checkout HEAD --`. `statix`, `deadnix`,
`nix fmt -- --ci`. `checks.session` is a VM: leave it to CI.

### 6. [lead] PR

One PR, `Closes #1342`. Body: intent, spec and plan; which steps the coder
did; the failing outputs; the hole (the activation's remove branch is
unexercised by any check); a request to add the log-out line to the first
4.0.5 release's body. Draft the Discussions post to a file for the owner. Run
`merge-when-green.sh` once green, since this is no CI-gate change.

## Tests

| command | expect |
|---|---|
| `checks.launch-browser-self-call` | passes; fails with the guard removed |
| `checks.seed-hyprland-mimeapps` | passes; fails without `-L` |
| `checks.bin-ledger`, `checks.install-phase-budget` | pass |
| `checks.session` (CI) | the list exists after login |
| statix, deadnix, `nix fmt -- --ci` | clean |

## Rollback

Revert the PR. The activation seeds the list at the switch again, and the
launcher loses its guard. A list already seeded stays, harmlessly.
