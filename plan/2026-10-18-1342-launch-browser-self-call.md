---
status: approved
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
2. **A session-start hook, `~/.config/omarchy/hooks/post-boot.d/seed-mimeapps`**,
   seeds the list when it is absent (a file or a symlink counts as present,
   `-e || -L`), through a new `pkgs/seed-hyprland-mimeapps.sh`. **Not a
   systemd unit:** Home Manager's `startServices` (default `true`) would start
   a new `WantedBy` unit at the switch, inside the 4.0.4 session.
3. **A carried guard in `omarchy-launch-browser`**: if the resolved
   `browser_exec` is `omarchy-launch-browser` itself, it notifies (critical)
   and exits 1. The text lives in `pkgs/omarchy/1342-launch-browser-self-call.sh`;
   it notifies with `omarchy-notification-send`, as the rest of 4.0.5 does.
   `data/bin-ledger.nix` updates the existing `patch` row; `pkgs/AGENTS.md`
   gets a section with when to drop it.
4. **The release note:** log out and back in after the upgrade.
5. **Coexistence (§14):** a Home Manager symlink at the list's path is
   present, so it is never replaced. `mimeapps.list` is a different file.
   Mode A is unchanged.
6. **Verification:** `checks.launch-browser-self-call` and
   `checks.seed-hyprland-mimeapps`, plus the hold block run from the
   activation's own text in `tests/home-activation-writes.nix`; each fails
   with its fix reverted (§1). `checks.session` asserts the list is absent
   before login and present after.

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
- **The seed check's symlink case must be dangling, and asserts an exit
  status.** A symlink to an existing file passes `-e` on its own. And GNU `cp`
  refuses to write through a dangling symlink (exit 1, link untouched), so
  without `-L` the link is not replaced; the seed fails at every login
  instead. The control asserts that non-zero exit.
- **The hold has a cheap layer after all** (plan review):
  `tests/home-activation-writes.nix:72-82` already extracts a block of
  `nixarchySeed` with `awk` and runs it with `run()` and `DRY_RUN`. The hold
  goes there, so it is tested rather than named as a hole.

## Who does what

Eight files across four editing steps, so the coder (Sonnet) does steps 1–4,
one `SendMessage` per step. The lead does 5–6, every commit and push, and
every build (§6 tiers).

## Steps

### 1. [coder] The launcher guard

- New `pkgs/omarchy/1342-launch-browser-self-call.sh`, exactly:
  ```sh
  if [[ ${browser_exec##*/} == omarchy-launch-browser ]]; then
    omarchy-notification-send -u critical "No browser to open this in" "The default browser entry runs omarchy-launch-browser itself (#1342). Choose a browser with: omarchy default browser"
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
costs ~60 bytes, which is why the text is a file. The phase is at 120,884 of
123,000 bytes; report the new figure. `nix fmt`, then read `git diff --stat`
(§5: an edit hook may reformat).

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
  set `mimeapps_absent=` and then `mimeapps_absent=1` when
  `${config.xdg.configHome}/hyprland-mimeapps.list` is neither `-e` nor `-L`.
  The activation runs under `set -eu`, so initialise it first and test
  `[ -n "$mimeapps_absent" ]`, never an unset variable. After `seed_dir`, if
  it is set and the file now exists, `run rm -f` it and echo
  `nixarchy: hyprland-mimeapps.list is seeded at your next login (#1342)`.
  Open the block with the comment line `# #1342: hold the mimeapps list until
  login` (the test extracts from it) and one more line of why. The block is
  contiguous: the `mimeapps_absent` test, then the `seed_dir "${omarchyPath}/config"`
  call, then the hold's `if … fi` **directly** after it, before `note_kept`,
  so the extract needs no `note_kept`. Use `run`, like
  the rest of the activation, so a dry run writes nothing.
- `modules/home.nix`, `xdg.configFile` (beside `default-plugins`, `:2161`):
  `"omarchy/hooks/post-boot.d/seed-mimeapps"` with `executable = true` and
  `text` a two-line bash script: `#!/usr/bin/env bash` and
  `exec ${seedMimeapps}/bin/nixarchy-seed-mimeapps ${omarchyPath}/config/hyprland-mimeapps.list ${config.xdg.configHome}/hyprland-mimeapps.list`,
  the same baked path the hold removes from (the spec's form).
  No extra guard: it sits under the module's `lib.mkIf cfg.enable`, as the
  seed does, so Mode A gets neither.

Traps: §7, plain assignment for the attrset, no `mkDefault`. `nix fmt`.

### 3. [coder] The checks

- `tests/launch-browser-self-call.nix` (`{ pkgs, omarchy }:` runCommand,
  `bash coreutils gnugrep gnused` in `nativeBuildInputs`). Fixture:
  `HOME=$PWD/home`, `home/.local/share/applications/omarchy-browser.desktop`
  with `Exec=omarchy-launch-browser %U`. A `bin/` on `PATH` holding stubs:
  `omarchy-cmd-default-browser` (prints `omarchy-browser.desktop`),
  `omarchy-notification-send` (appends its args to `notified`), `systemd-run`, `uwsm-app`,
  `omarchy-cmd-browser-handoff` (exit 1), and an `omarchy-launch-browser`
  wrapper that increments a `count` file and exits 99 at 20, else runs
  `exec bash "$LAUNCHER" "$@"` (so a `sed` copy needs no mode bit). The
  `systemd-run` and `uwsm-app` stubs append their arguments to a file and
  exit 0, and never exec anything: after the cap every level unwinds through
  them. Run `LAUNCHER=<built> timeout 60 omarchy-launch-browser https://example.org`:
  - patched (`${omarchy}/share/omarchy/bin/omarchy-launch-browser`): exit 1,
    `count` is 1, `notified` names #1342;
  - control: `sed` deletes the guard's four lines into `unguarded.sh`, `grep`
    proves they are gone (§1), and the run must bring `count` to 20. If not,
    fail with "the control did not recurse, so this check cannot see #1342".
  `printf '%s\n'` for the fixture files, never a heredoc (§5).
- `tests/seed-hyprland-mimeapps.nix` (runCommand, the script by path):
  absent → copied; a regular file → bytes unchanged; a **dangling** symlink →
  the script exits 0, the link is unchanged, the target not created. Control:
  the script with `|| [ -L "$dest" ]` removed (prove with `grep`) must exit
  non-zero on the dangling link.
- `tests/home-activation-writes.nix`: a section `# ---- #1342: the mimeapps
  hold ----`. Extract from `rehome ${act "nixarchySeed"}` with `awk`, from
  `#1342: hold the mimeapps list` through the hold's closing `fi` (the file's
  reconcile extraction, `:72-82`, is the pattern). Define a stub `seed_dir`
  that copies one fixture list through `run` (as the real one does), so the
  extract's `seed_dir` call runs it. Source the extract under
  `( set -eu; . ./hold.sh )`: activation runs under `set -eu`, and
  `runCommand`'s shell does not, so only this catches an unset variable.
  `grep` that the extract holds `run rm -f`, or fail saying the hold moved.
  Cases: absent before → absent after, and the message printed; a file
  present → bytes unchanged; a symlink present → still the link. The dry case:
  `DRY_RUN=1` (`run` echoes instead of executing, `:44`), the list absent,
  and a stub `seed_dir` that copies **without** `run`, standing in for "a file
  appeared". The file must survive, which fails if the hold's `rm` loses its
  `run`. Control: the extract with its `rm`
  line deleted must leave the file.
- `flake.nix`: two `checks` entries beside `menu-model-merge` (`:2552`),
  `omarchy = self.packages.${system}.omarchy` for the first. They are built by
  the `omarchy` job's generated step with no workflow edit (§4).
- `tests/session.nix`, two assertions (the hold runs before `apps.nix` is
  seeded, `home.nix:~1303`, so `:297` proves it already ran):
  - right after `:297`'s `wait_for_file` (Home Manager has run; no session
    yet): `machine.succeed("test ! -e /home/omarchy/.config/hyprland-mimeapps.list")`,
    comment `# #1342: held back until login`;
  - after the 75 s sleep at `:510`, before the user-unit loop:
    `machine.wait_for_file("/home/omarchy/.config/hyprland-mimeapps.list")`,
    comment `# #1342: the post-boot.d hook seeded it at login`.
  The pair is what fails on a full revert.

Traps: `git add` the new files before any build (§5). Do not use `pgrep` in
any wait loop.

### 4. [coder] Docs

- `docs/manual/troubleshooting.md`: under the table (`:20-26`), one short
  paragraph: after upgrading to Omarchy 4.0.5, log out and back in; until then
  links open with the browser the session started with, and
  `hyprland-mimeapps.list` appears at the next login (#1342). A shell restart
  does not seed the list.

### 5. [lead] Builds and break proofs

Cheap tier, one at a time under `flock /mnt/data/vmtest/codex-build.lock`:
`checks.seed-hyprland-mimeapps`, `checks.home-activation-writes`, then (package tier: load below 12, no p620
system build) `checks.launch-browser-self-call`, which builds the `omarchy`
tree, plus `checks.bin-ledger` and `checks.install-phase-budget`. Then the §1
proofs: remove the guard substitution from `default.nix` and watch
`launch-browser-self-call` fail; remove `|| [ -L "$dest" ]` and watch the seed
check fail; remove the hold's `rm` and watch `home-activation-writes` fail; restore with
`git checkout HEAD --`. `statix`, `deadnix`,
`nix fmt -- --ci`. `checks.session` is a VM: leave it to CI.

### 6. [lead] PR

One PR, `Closes #1342`. Body: intent, spec and plan; which steps the coder
did; the failing outputs; that the hold is tested in `home-activation-writes`; the `installPhase` byte
figure; in its §14 section, that a plain Hyprland session with the user's own
`hypr` config never runs `post-boot.d`, so the list is never seeded there,
which is safe (links route as in 4.0.4); a request to add the log-out line to the first
4.0.5 release's body. Draft the Discussions post to a file for the owner. Run
`merge-when-green.sh` once green, since this is no CI-gate change.

## Tests

| command | expect |
|---|---|
| `checks.launch-browser-self-call` | passes; fails with the guard removed |
| `checks.seed-hyprland-mimeapps` | passes; fails without `-L` |
| `checks.home-activation-writes` | passes; fails without the hold's `rm` |
| `checks.bin-ledger`, `checks.install-phase-budget` | pass |
| `checks.session` (CI) | absent before login, present after |
| statix, deadnix, `nix fmt -- --ci` | clean |

## Rollback

Revert the PR. The activation seeds the list at the switch again, and the
launcher loses its guard. A list already seeded stays, harmlessly.

## Deviations (implemented)

- Step 1: the `pkgs/AGENTS.md` section sits before the `#948` anchor, which is
  where the #1339 section ends, not "after the #1339 section" literally.
- Step 5: removing the guard makes `launch-browser-self-call` fail on its own
  precondition ("the built launcher carries no guard"), not on the patched
  assertion. The control in the same check runs that unguarded launcher and
  asserts it recurses to the cap, which is the behaviour the patched assertion
  rules out. The hold break that kept the block's shape was
  `mimeapps_absent=1` → `mimeapps_absent=`; deleting the `rm` line also failed,
  but on the extraction, not on the behaviour.
- Found in CI: `checks.grep-q-pipefail` flagged the guard's re-emitted anchor
  (`… | grep -q MOZ_LOG`) in the new `.sh` and in the `--replace-fail` needle.
  Both are allowlisted in `tests/grep-q-allowlist.txt` with reasons: the
  launcher runs without `pipefail`, and the needle is a string literal.
