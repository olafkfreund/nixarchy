---
status: draft
issue: 1646
spec: spec/2026-11-07-1646-stock-iso-install.md
coders:
  1: codex  # the gate and the flags in install.sh: small, and a slip either wipes a stock-ISO disk or makes checks.install refuse
  2: codex  # stubs whose breaks must really fail, inside a Nix indented string where `${` needs escaping
  3: coder  # three small test edits whose content this plan spells out line by line
reviewers:
  - codex  # reads the diff against this plan and the code, independent of the coders
  - agy    # a second model's read of the gate's edge cases (empty, whitespace, failing `nix config show`)
---

# Plan: Part A of #1646, the preflight runs wherever a network is expected

Worktree `/mnt/data/vmtest/wt-1646`, branch `feat/1646-stock-iso-install`.
The owner approved the intent and the spec on 2026-11-07, and asked for
**Part A only** in this plan. Part B (the stock-ISO VM check and the manual
section) is a later plan; see Follow-up.

## Decisions carried from the approved spec

1. **Part A lands alone, first.** It removes the hazard: today
   `nix run …#install` from a stock NixOS ISO skips the network preflight,
   because the stock ISO has no `/etc/nixarchy-iso-net`, and an install can
   then fail after `format_disk` has wiped the disk (#300's failure).
2. **The switch is "this machine has no substituter configured", not the
   marker.** That is what separates the offline install checks:
   `tests/install.nix:188`, `tests/free-space.nix:194` and
   `tests/install-encrypted.nix:191` set `substituters = mkForce [ ]` because
   they have no network. A stock ISO, `iso-net` and `installer-refusal` all
   have one. Measured while planning: `checks.install`'s installer node
   evaluates `nix.settings.substituters` to `[]`; `installer-refusal`'s and
   `installer-wizard`'s nodes to `["https://cache.nixos.org/"]`.
3. **The gate fails closed.** If `nix config show` fails, the preflight runs.
   `nix` is a runtime input of the `install` package (`flake.nix:978`), so the
   subcommand exists whatever the medium ships. `NIX_CONFIG` counts, which
   `install-iso-net`'s `substituters =` override relies on
   (`tests/install-iso-net.nix:138-140`).
4. **Our caches on every nix call that plans or builds.** `SUBSTITUTE_FLAGS`
   gains `extra-substituters "$SUBSTITUTERS"` and `extra-trusted-public-keys
   "$TRUSTED_KEYS"`, so the preflight dry-run, `run_install`'s dry-run and the
   toplevel build use them, and `nixos-install`'s two now-duplicate `--option`
   lines go. (The intent said the build already passed them; it did not.)
5. **Wording.** Messages that say "this image" about downloading become "this
   install", true on both media. `installer-refusal`'s positive assertions
   (`cannot reach https://nixarchy.cachix.org`, `network`,
   `disk has not been touched`) are unchanged.
6. **The marker stays** in `installer/cd.nix:458`. After Part A no installer
   code reads it; `checks.iso-source` and `install-iso-net`'s `MARKER` step
   still assert it, and the iso-net decision (spec decision 5) owns removing it.
7. **`installer-refusal` loses the marker**, which makes its node
   stock-shaped (base NixOS, default `cache.nixos.org`, no marker). No new VM
   check for that case.
8. **Coexistence: none.** No NixOS option of the installed system changes; the
   installed closure is unchanged.
9. Out of scope (the spec's decisions 3-5): no manual section before Part B's
   check exists; rescue from a stock ISO; dropping `iso-net`.

### Found while planning: one more check depends on the old gate

`checks.installer-wizard` (`tests/installer-wizard.nix`) runs
`nixarchy-install --dry-run` interactively in a VM with no network and no
marker. `main()` calls `ask_network` after the greeter
(`installer/install.sh:2961`), before the dry-run exits (`:2997`). Today the
marker gate returns at once. After step 1 its node, which keeps the default
`cache.nixos.org`, is not offline by design, `network_ready` fails, and the
wizard sits on "Let's get you online..." while the test waits 180 s for
"Let's set up your keyboard" and fails. The spec did not name this file. Step
3 gives that node `nix.settings.substituters = mkForce [ ]`, the same
statement the offline install checks make for the same reason (it has no
network). The owner should confirm this when approving the plan.

## Steps

Each step is one commit. Before every commit: `nix fmt` then `git diff --stat`
(a hook reformats `.nix` files with `nixpkgs-fmt`, and only `nix fmt` restores
the house style, CLAUDE.md §5); `git add` before any evaluation (a flake sees
only tracked files).

### 1. `installer/install.sh`: the gate, the flags, the wording

All line numbers are against the branch head at plan time (`origin/main`
`23d70d4c` merged).

- **`:65-71`, `SUBSTITUTE_FLAGS`.** Keep it **one line** (the store-space
  check extracts it with `grep '^SUBSTITUTE_FLAGS='`):

  ```bash
  SUBSTITUTE_FLAGS=(--option always-allow-substitutes true --option extra-substituters "$SUBSTITUTERS" --option extra-trusted-public-keys "$TRUSTED_KEYS")
  ```

  Add one comment line above it, after the existing paragraph: our caches
  ride along on every plan and build, because a stock ISO's `nix.conf` names
  only `cache.nixos.org` and the preflight must plan with the caches the
  build fetches from.
- **`:2728-2734`, `nixos-install`.** Delete the two lines
  `--option extra-substituters "$SUBSTITUTERS"` and
  `--option extra-trusted-public-keys "$TRUSTED_KEYS"`; keep
  `"${SUBSTITUTE_FLAGS[@]}" || return 1`. `nixos-install` already takes
  `--option name value` pairs (it is given `always-allow-substitutes` that way
  today).
- **`:2594`, `:2628`, `:2708`** need no edit: each already passes
  `"${SUBSTITUTE_FLAGS[@]}"`. Do not touch the diskoScript build at `:1953`
  (not in the spec).
- **`:2507-2509`, the gate.** Replace the two-line comment and
  `on_net_image() { [ -f /etc/nixarchy-iso-net ]; }` with:

  ```bash
  # No substituter configured means the machine says it has no network
  # (checks.install and its siblings), so there is nothing to probe or ask.
  offline_by_design() {
    local subs
    subs=$(nix "${NIX_FLAGS[@]}" config show substituters 2>/dev/null) || return 1
    [ -z "${subs//[[:space:]]/}" ]
  }
  ```

  `|| return 1` on the assignment is load-bearing: `set -e` does not reach
  inside `$(...)` and is suppressed in a function called from `&&`, so without
  it a failing `nix config show` leaves `subs` empty and reads as "offline",
  skipping the preflight (CLAUDE.md §5, "`set -e` does not reach inside").
- **`:463-465`, `ask_network`.** Comment becomes "No substituter configured
  (checks.install's shape): no network to ask for."; the line becomes
  `offline_by_design && return 0`.
- **`:2572-2573`, `preflight_build`.** `on_net_image || return 0` becomes
  `offline_by_design && return 0`.
- **`:2536-2537`, the comment above.** Becomes: "Skipped only when no
  substituter is configured. checks.install runs with no network, no
  substituters and a seeded store; its preflight must remain skipped."
- **Wording**, exact replacements:
  - `:474` `this image installs over the network and there is none.` →
    `this install downloads the desktop, and there is no network.`
  - `:481` `This image downloads the desktop as it installs, so it needs a network.` →
    `This install downloads the desktop as it runs, so it needs a network.`
  - `:2502` `This image downloads the desktop as it installs, so a fetch this` →
    `This install downloads the desktop as it runs, so a fetch this`
  - `:2560` `No cache this image can reach has these $count, so they would be` →
    `No cache this machine can reach has these $count, so they would be`
  - `:2580` `This image downloads the desktop from that cache as it installs,` →
    `This install downloads the desktop from that cache as it runs,`
- **After the edit**, `grep -n 'on_net_image\|nixarchy-iso-net' installer/install.sh`
  prints nothing, and `grep -rn on_net_image tests/` lists only the two lines
  steps 2 and 3 replace.

Check: `bash -n installer/install.sh`; then (cheap tier, under the lock)
`checks.installer-store-space` is expected **red** until step 2 (it still
greps `^on_net_image()`), so commit steps 1-3 before building it, and build
the rest of the `installer-*` cheap checks now (tests/AGENTS.md: moving code
in `install.sh` reddens checks that look unrelated), plus
`checks.grep-q-pipefail` (memory: it failed CI twice after shell edits).

Traps: the one-line `SUBSTITUTE_FLAGS` above; `$SUBSTITUTERS` and
`$TRUSTED_KEYS` are defined at `:52-53`, before `:71`, so the array expands
them at assignment; never call `offline_by_design` inside `$(...)` with
`set -e` expectations; `preflight_build || exit 1` still runs in the main
shell.

### 2. `tests/installer-store-space.nix:291-345`: drive the new gate

- **Extraction (`:303`).** Replace `grep '^on_net_image()' … >> pf.sh` with:
  `grep -E '^(SUBSTITUTERS|TRUSTED_KEYS|SUBSTITUTE_FLAGS)=' ${installScript} >> pf.sh`
  then `sed -n '/^offline_by_design()/,/^}/p' ${installScript} >> pf.sh`, each
  followed by a `grep -q` that fails loudly if missing (the file's own
  pattern: `grep -q 'offline_by_design()' pf.sh || { echo …; exit 1; }`, and
  the same for `^SUBSTITUTE_FLAGS=`). File order puts `SUBSTITUTERS` and
  `TRUSTED_KEYS` before `SUBSTITUTE_FLAGS`, which the array needs.
- **`pt.sh` (`:306-307`).** `NIX_FLAGS=()` stays; delete
  `SUBSTITUTE_FLAGS=()` and the `SUBSTITUTERS=` line, so both come from
  `install.sh`.
- **Stubs.** `curl() { touch curl-called; [ "$CURL_OK" = 1 ]; }`. The `nix`
  stub first handles `config show substituters`: when `$1 = config`, fail if
  `SUBS_FAIL=1`, else `printf '%s\n' "$SUBS"` and return 0. Otherwise it
  writes its arguments one per line to `nix-args`, touches `nix-called`, and
  keeps today's two behaviours (the long failing plan is the #273 race; keep
  it).
- **`t()`** takes `want name subs curlok nixok [subsfail]` instead of `img`;
  it removes `curl-called nix-called nix-args` first and runs
  `SUBS=$subs SUBS_FAIL=${6:-0} CURL_OK=… NIX_OK=… preflight_build`. The
  `on_net_image` redefinitions go.
- **Cases** (keep each existing comment, with "net image" spelled
  "substituters present"):
  1. `t proceed "no substituters, network dead" "" 0 0`, then assert
     `! test -e curl-called && ! test -e nix-called`, else a FAILED line.
     **Break:** `offline_by_design() { return 1; }` → refuse → red.
  2. `t proceed "only whitespace in substituters" " " 0 0`: the trim. **Break:**
     `[ -z "$subs" ]` → refuse → red.
  3. `t refuse "substituters present, substituter unreachable" "https://cache.nixos.org/" 0 1`
     plus the existing `network` grep. This is the stock-ISO case with no
     marker anywhere. **Break:** `offline_by_design() { return 0; }` →
     proceed → red.
  4. `t refuse "substituters present, flake input unreachable" … 1 0` plus the
     existing grep and the Broken-pipe absence check.
  5. `t refuse "nix config show fails" "" 0 1 1`: fails closed. **Break:** drop
     `|| return 1` → `subs` empty → proceed → red.
  6. `t proceed "substituters present, everything answers" … 1 1`, then assert
     `nix-args` has a line `extra-substituters`, a line equal to
     `https://nixarchy.cachix.org https://hyprland.cachix.org`, and a line
     `extra-trusted-public-keys`. **Break:** take the two options out of
     `SUBSTITUTE_FLAGS` → red.
- **`run_install` carries the flags.** After the cases:
  `sed -n '/^run_install()/,/^}/p' ${installScript} > ri-flags.sh`; take its
  lines matching `nix "''${NIX_FLAGS[@]}" build`; require at least two
  (the dry-run and the toplevel build, so an empty extraction cannot pass),
  and that every one contains `"''${SUBSTITUTE_FLAGS[@]}"`. **Break:** delete
  it from the toplevel build at `install.sh:2708` → red.

Check: `checks.installer-store-space` green, then each break above red, one
at a time, proving with `git diff` that the break landed, `git checkout HEAD --
installer/install.sh` to restore (not `git checkout --`, which restores the
index, CLAUDE.md §5), green again. Capture the red output for the PR.

Traps: this is a Nix indented string, so every `${` the shell must see is
written `''${` (`$VAR` and `$(...)` are already literal; `\$` is a literal
backslash); `pt.sh` is already a quoted heredoc, add no new heredoc
(CLAUDE.md §5: nixfmt reindents the file); the line-order assertion that
`preflight_build` precedes `format_disk` stays; run the script under bash,
which the check already does.

### 3. Three small test edits

- **`tests/installer-network.nix:102-110`.** The comment says "No substituter
  configured (checks.install's shape) skips the network prompt; unattended
  installs with one refuse when no connection is available." The grep becomes
  `grep -Fq 'offline_by_design && return 0' ask_network.txt`, its failure text
  "installs with no substituter configured no longer skip the network prompt",
  and the `ok` line to match. **Break:** delete that line from `ask_network`
  → red.
- **`tests/installer-refusal.nix`.**
  - Delete `:60-62` (the marker comment and `etc."nixarchy-iso-net".text = "";`).
  - `:194`: the absence assertion's string becomes step 1's new `:474` text,
    `this install downloads the desktop, and there is no network`. Left as it
    is, it would assert the absence of a sentence nothing prints, and could
    never fail (CLAUDE.md §1).
  - Comments: the header (`:12-28`) says the node has no marker and the
    default `cache.nixos.org`, as a stock ISO does; the guard keys on a
    configured substituter. `:172-177`'s break becomes "restore
    `on_net_image || return 0` in both functions".
  - **Break (VM tier):** restore the marker gate in `ask_network` and
    `preflight_build` → the install reaches `format_disk` → `after == "vdb"`
    fails with partitions. That red is the stock-ISO hazard reproduced.
- **`tests/installer-wizard.nix:30`**, in `nodes.machine`: add
  `nix.settings.substituters = pkgs.lib.mkForce [ ];` with one comment line:
  this VM has no network, and saying so is what keeps `ask_network` from
  asking for one (as `tests/install.nix:188` does). The node is written
  `_: { … }`; make it `{ pkgs, ... }: { … }` or use the outer `pkgs`, which is
  in scope from the file's argument. **Break:** remove the line → the wizard
  stops on "Let's get you online..." and `screen("Let's set up your keyboard")`
  times out → red.

Check: `checks.installer-network` (cheap); `checks.installer-refusal` and
`checks.installer-wizard` (VM tier, see Tests).

Traps: `nix fmt` after each file; the node's argument change is the kind of
edit deadnix and statix read, so run both.

## Tests

By CLAUDE.md §6 tier. Every check `.github/scripts/generated-checks.sh`
prints, plus the claimed ones these files reach.

**Cheap, any time, one at a time under
`flock /mnt/data/vmtest/codex-build.lock`:**

```sh
nix fmt -- --ci
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
for c in installer-store-space installer-network installer-from-repo \
         installer-disk-identity installer-failure-hints installer-answers \
         installer-ui installer-lock installer-input-validation installer-disk-list \
         installer-keymaps installer-layout-eval installer-network-profiles grep-q-pipefail; do
  nix build ".#checks.x86_64-linux.$c" --print-build-logs || break
done
```

(Run as a `#!/usr/bin/env bash` script, CLAUDE.md §1; then
`ls tests/installer-*.nix` and build any installer runCommand check missing
from that list.) Each break in steps 2-3 red, then green.

**VM tier** (at most two at once, no p620 system build, and
`gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'`
prints `0`; an API failure reads as busy):

- `checks.installer-wizard` green; its break red.
- `checks.installer-refusal` green; its break red.
- `checks.install` green (the other side of the gate). Its break,
  `offline_by_design() { return 1; }`, refuses with
  `cannot reach https://cache.nixos.org`; run once locally, by
  `nix eval --raw .#checks.x86_64-linux.install.drvPath` then
  `nix build '<drv>^*'` (a background build re-evaluates the tree, §5).
  `install` requires a committed tree (`installer/mkFlake.nix`).

**Not run locally, named in the PR:** `free-space` and `install-encrypted`
(the install job builds them with `install`; locally they would take two VM
slots for the same property `install` shows); `install-iso-net` (nightly; its
toplevel build now names the https caches, which its daemon disables on the
TLS failure; watch its `FETCHED` step and run time on the next nightly). Watch
the elapsed time in `checks.install`'s `state.json` against previous runs:
the offline checks now try `nixarchy.cachix.org` on the build, as
`nixos-install` already does there.

**CI:** no workflow change. `installer-refusal` is already in the install job
(`install-check.yml:514`) and `installer-wizard` in `build.yml:1711`.

## PR notes

- Body says `Refs #1646`, not a closing keyword: Part B remains (CLAUDE.md §8,
  "closes in part" closes).
- Names that coders did which step, the breaks' red output, the wizard finding
  above, and the checks not run locally.

## Rollback

Revert the PR's commits. Nothing persistent changes: no option, no state, no
installed-closure change. Reverting restores the marker gate, and the marker
is still written by `installer/cd.nix:458`, so `iso-net` behaves as before.

## Follow-up: Part B, a later plan

Not in this plan: `tests/install-stock-iso.nix` (a stock NixOS minimal ISO
pinned by URL and hash; a dark-cache case asserting the refusal and a bare
target, then an install case printing time to first log line, bytes served
and peak overlay use), its CI placement (`nightly_only` in
`generated-checks.sh` and a `nightly.yml` entry, a human's call, CLAUDE.md §4,
§11), and the "From a stock NixOS ISO" section in `docs/manual/the-iso.md`.
Written after Part A merges and the owner's queue is clear.
