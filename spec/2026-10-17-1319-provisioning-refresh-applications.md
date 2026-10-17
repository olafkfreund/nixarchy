---
status: draft
issue: 1319
intent: intent/2026-10-17-1319-provisioning-refresh-applications.md
---

# Spec: First-login provisioning must not overwrite the user's launchers or links

## Design

Evidence comes from `.#omarchy` built at `f15c9e6a` (main `7e0ceac5` plus the
intent), `/nix/store/ygd3l8hlwfclzrr9slna8caaqs953yy3-omarchy-4.0.4/share/omarchy`,
written `$B` below. Repo line numbers are at the same commit.

### What provisioning actually runs

`default/hypr/autostart.lua:7` runs `omarchy-provision-first-run`, and its
line 46 runs `omarchy-provision-user`. That script reaches the two hazards
by **two** paths, not one:

| `$B/bin/omarchy-provision-user` | runs | hazard |
|---|---|---|
| `:116` `source "$OMARCHY_INSTALL/user/all.sh"` | `$B/install/user/all.sh:14` → `run_logged …/user/mise.sh` | mise stubs |
| `:118` `omarchy-refresh-applications` | `$B/bin/omarchy-refresh-applications:7,10` `cp -f --no-preserve=mode` | launchers |
| | `$B/bin/omarchy-refresh-applications:13-15` `bash …/user/mise.sh` (a second time) | mise stubs |

So patching `omarchy-refresh-applications` alone fixes the launchers and
leaves the mise hazard live through `all.sh:14`. The issue and the intent
both describe only the second path.

The mise hazard is one line, `$B/bin/omarchy-mise-install:51`, which is
nixarchy's own #707 patch (`pkgs/omarchy/default.nix:607-614`). It exits when
a command outside `~/.local/bin` provides `<cmd>`, and otherwise runs
`rm -f "$HOME/.local/bin/$command"` and writes the stub. A Home Manager link
at `~/.local/bin/claude`, with no `claude` in a profile, takes the `rm`.

### Every caller of `omarchy-refresh-applications` in `$B`

`grep -RIn omarchy-refresh-applications $B`:

| caller | reachable here? |
|---|---|
| `bin/omarchy-provision-user:118` | yes, at every login until `finalize-user` is marked |
| `omarchy refresh applications` (bin/omarchy dispatches `omarchy-<group>-*`, `bin/omarchy:345-399`) | yes, by hand |
| `migrations/1786183928.sh:3` | no: `omarchy-migrate` is replaced and runs no migration (`data/bin-ledger.nix:359-363`) |
| `bin/omarchy-upgrade-to-quattro:2371` | no: Arch upgrade path, vendored and unreachable (`data/bin-ledger.nix:697-702`) |
| `bin/omarchy-install-preinstalls:5` | a comment only: #1304 replaced Restore |

No menu row names it (`/etc/nixarchy/omarchy-menu.jsonc` has no match), and
no menu row reaches `omarchy-mise-install` either (0 matches), so
`data/menu-actions.nix` carries no reason that depends on either script.

### What exists today

- **#1304's Restore** is `pkgs/omarchy/nix-bin/omarchy-install-preinstalls`.
  Lines 15-23 seed launchers: for each `$OMARCHY_PATH/applications/*.desktop`,
  `[[ -e $dst || -L $dst ]] && continue`, else
  `cp --no-preserve=mode`, then `update-desktop-database` if
  `omarchy-cmd-present` finds it. It skips mise by never calling
  `omarchy-refresh-applications` or `mise.sh` at all (`:5-8` say why).
- **The current patch** is `pkgs/omarchy/default.nix:580-605`: a
  `substituteInPlace --replace-fail` that turns both upstream `cp` lines into
  `cp -f --no-preserve=mode`. Its comment gives the reason: a plain `cp` left
  444 files that the next run could not overwrite, which aborted provisioning
  under `set -euo pipefail` before `finalize-user` was marked. `-f` is what
  now replaces edited launchers and Home Manager links.
- **The ledger** row, `data/bin-ledger.nix:433-436`, is `class = "patch"` with
  that 444 reason. `omarchy-mise-install` is `class = "patch"` at `:364-367`,
  with the #707 reason.

### Decisions

1. **Replace `omarchy-refresh-applications` itself (the intent's Q1).**
   A new `pkgs/omarchy/nix-bin/omarchy-refresh-applications` covers every
   reachable caller, provisioning and `omarchy refresh applications`, and
   any future one. It:
   - keeps upstream's `# omarchy:summary=` line, reworded to drop "mise
     wrappers" (`bin/omarchy` discovers subcommands by that line,
     `pkgs/omarchy/default.nix:1063-1064`);
   - seeds `$OMARCHY_PATH/applications/*.desktop`, and upstream's
     `default/alacritty/Alacritty.desktop` when `omarchy-cmd-present alacritty`,
     each **only where no file or link of that name exists**
     (`[[ -e $dst || -L $dst ]]` skips), with `cp --no-preserve=mode`;
   - runs `update-desktop-database` guarded by `omarchy-cmd-present`, as
     Restore does;
   - **does not run `mise.sh`.** On the provisioning path that call is the
     duplicate: `all.sh:14` already ran it two lines earlier. On the manual
     path, refreshing stubs is what #707 exists to stop.

   **Restore reuses it.** `nix-bin/omarchy-install-preinstalls:15-23` becomes
   one call to `omarchy-refresh-applications`. That is #1304's logic moved,
   not copied, so there is one seeding loop. Restore still writes no stubs,
   which keeps #1304's decision 2. It gains the Alacritty seed, which it
   lacked; that adds a launcher only where none exists.

   The `substituteInPlace` at `pkgs/omarchy/default.nix:580-605` is deleted.
   It would patch a file the `nix-bin` loop (`:1065-1072`) then overwrites.
   Its 444 reasoning moves with the behaviour: a skipped file is never
   rewritten, so a 444 seed can no longer abort the next run.

2. **Keep writing mise stubs, but only into empty names (the intent's Q2).**
   Patch `omarchy-mise-install` once, extending the existing #707
   replacement at `pkgs/omarchy/default.nix:611-614`. After the Nix check, it
   exits 0 with a message when `~/.local/bin/<cmd>` exists or is a link, and
   it no longer runs `rm -f`. Every writer goes through this one script:
   `all.sh:14`, upstream's own migrations, and any later caller.

   Recommended over dropping stubs, because `install/user/mise.sh` names 15
   commands and `data/apps.nix` has an app entry for only four of them
   (`codex`, `claude-code`, `opencode`, `gemini-cli`, at `:352-414`; its
   `grok` hits are `grok-bot`, a different app). Dropping `mise.sh` would
   leave a fresh install without the other eleven (crush, gh, copilot,
   playwright, pi, omp, grok, cursor-agent, ghui, hunk, muse) unless the
   user's own configuration provides them, and with no menu route back. That is a behaviour change the intent did not
   ask for. Writing into an empty name deletes and replaces nothing, which is
   the intent's outcome. Restore dropped stubs for its own reason: it is a
   menu action whose honest route is the app selection.

   What this costs: a stub upstream changes the shape of is no longer
   rewritten in place. On nixarchy only provisioning ever rewrote them,
   because `omarchy-migrate` runs no migration. A stub whose shape is old is
   kept, and `omarchy-remove-preinstalls` then keeps it too, which is the safe
   direction #1304's risks already name.

3. **Ledger.** `omarchy-refresh-applications` moves from `patch` to `replace`,
   with a reason that names the overwrite and the duplicate mise call.
   `omarchy-mise-install` stays `patch`, and its reason adds "never removes or
   replaces an existing `~/.local/bin` entry (#1319)". The
   `omarchy-install-preinstalls` reason is reworded: it now seeds through the
   replaced `omarchy-refresh-applications`. `omarchy-provision-user` is
   unchanged; it is called as is.

4. **Mode A.** Both scripts run only from the Omarchy session's autostart, or
   from a command a user types. Nothing here changes a NixOS option or a file
   outside the vendored tree.

Files touched: `pkgs/omarchy/nix-bin/omarchy-refresh-applications` (new),
`pkgs/omarchy/nix-bin/omarchy-install-preinstalls`,
`pkgs/omarchy/default.nix` (delete `:580-605`, extend `:607-614`),
`data/bin-ledger.nix`, `tests/session.nix:1619-1629` (see Verification), the
new check and its `flake.nix` entry. No workflow edit: an unclaimed check is
built by `build.yml`'s generated step (CLAUDE.md §4).

## Alternatives rejected

- **Patch only provisioning's call** (`omarchy-provision-user:118`). It leaves
  `omarchy refresh applications` overwriting by hand. It also leaves
  `all.sh:14`, which is the larger half of the bug.
- **Patch `omarchy-refresh-applications` in place** with `substituteInPlace`.
  The change replaces both `cp` lines with a loop and removes the `mise.sh`
  block. That is most of the file, and a multi-line `--replace-fail` breaks
  on any upstream reflow. `nix-bin` is where #1304 put the same logic.
- **Keep a second loop in Restore.** The intent forbids a second copy.
- **Drop `mise.sh` from provisioning** (patch `all.sh:14`). This is rejected
  for the reason in decision 2: eleven commands with no app entry would be
  lost. It would also leave `omarchy-mise-install`'s `rm -f` live for every
  other caller.
- **Rewrite a file in `~/.local/bin` if it is our exact stub.** That keeps
  stub refresh, but it adds a shape test to a script that writes the shape.
  No reachable path on nixarchy refreshes stubs, so it buys nothing.
- **Keep `-f` and skip only symlinks.** An edited regular launcher would
  still be overwritten, which is half of the bug.

## Risks

- **A launcher upstream changes is not updated** in a home that already has
  it. That is the same safe direction as Restore. A user gets the new one by
  deleting theirs and running `omarchy refresh applications`.
- **A 444 seed from before the `-f` fix stays 444.** Nothing rewrites it now,
  so nothing fails on it. A user who wants to edit it needs `chmod u+w`. The
  check carries a 444 fixture and runs the script twice, so the #997-style
  abort cannot come back unseen.
- **A dangling Home Manager link** (its target gone after a generation
  change) is skipped by `-L`. That is deliberate: it is still the user's name.
- **A copy that fails** inside the loop no longer aborts provisioning. The
  script exits 0, and the marker is written. Upstream's unguarded
  `cp`/`update-desktop-database` could abort it. This is the direction
  #997's history asks for, and the failure is still printed.
- **`checks.session` goes red** on `assert "cp -f" in refresh`
  (`tests/session.nix:1627-1628`). That assertion encoded the arrangement,
  not the property (CLAUDE.md §1, read backwards). It is retargeted: keep
  `--no-preserve=mode`, which the replacement still uses, and drop `cp -f`.
  The property, "a second run does not fail on a 444 seed", moves to the new
  `runCommand`, which can make it fail. The PR says so.
- **Hosts.** Every Omarchy-session user at first login, and anyone whose
  `finalize-user` marker is missing. Nothing changes for a user already
  provisioned until they run `omarchy refresh applications`.

## Coexistence

This is a §14 case at runtime, not at evaluation. A Home Manager user
owns names in the same directories provisioning writes:

- `home.file.".local/bin/claude"` (or `xdg.dataFile."applications/…"`) puts
  a link to the store in `~/.local/bin` or `~/.local/share/applications`.
- Home Manager activates before the first graphical login, so the link is
  there when `omarchy-provision-user` runs.

Before this change, the launcher `cp -f` replaced such a link with a regular
file. `omarchy-mise-install` `rm -f`'d the `~/.local/bin` link and wrote a
stub over it. Home Manager's next activation then refuses to clobber the
regular file, which is a second, louder failure.

After it, both writers skip any existing name, link or file. Nixarchy wins
nothing by collision: the user's entry stands.

**Which check answers it:** the new `runCommand` below, whose fixture is
exactly a Home Manager link in both directories. No fixture is added to
`tests/coexistence/fixtures.nix`. Those are NixOS modules evaluated against
the reference config, and they never run first login, so a fixture there
could not fail on this bug (§14: a fixture that cannot fail is worse than
none). No release-note default changes: no option default moves.

## Verification

### New check: `checks.provision-launchers` (`tests/provision-launchers.nix`)

A `runCommand`, seconds, built on the shape of `tests/remove-preinstalls.nix`:
the same `shipped` tree, and a fixture home. The isolation follows
`tests/AGENTS.md` and the devenv lesson in CLAUDE.md §4:

- `real_home=$HOME`, then `HOME=$TMPDIR/home` and `XDG_DATA_HOME`,
  `XDG_STATE_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` all under it;
  `OMARCHY_PATH=$tree`.
- Stubs that record their calls and succeed: `mise`, `update-desktop-database`,
  and `omarchy-install-hermes-cli`. `PATH=$TMPDIR/stubs:$tree/bin:$PATH`.
  Nothing on PATH provides `claude` or `codex`, so `omarchy-mise-install`
  reaches its write path. That path is exactly the Home Manager-only case.
- The end asserts `[ ! -e "$real_home" ]`, as `remove-preinstalls` does. The
  sandbox `HOME` does not exist, so any write outside the fixture creates it.

It runs **what provisioning runs**, in its order: `run_logged`'s form,
`bash -eE -c 'source "$1"' bash "$tree/install/user/mise.sh"` (all.sh:14).
Then it runs `omarchy-refresh-applications` (provision-user:118). It runs
both twice, to prove the second run is clean.

**Fixture home (`dirty`):**

| path | state before | asserted after |
|---|---|---|
| `applications/Basecamp.desktop` | a regular file, edited by `sed` | byte-identical (`sha256sum`) |
| `applications/Zoom.desktop` | a link to `$TMPDIR/hm/Zoom.desktop` | still that link (`readlink`); target unchanged |
| `applications/YouTube.desktop` | an unmodified seed, `chmod 444` | unchanged; both runs exit 0 |
| `.local/bin/claude` | a link to `$TMPDIR/hm/claude`, a wrapper | still that link; target unchanged |
| `.local/bin/codex` | absent | a stub is written (the empty-name case still works) |
| every other shipped `*.desktop` | absent | present, and `cmp`-equal to the shipped file |

A tree listing with hashes before and after, as `remove-preinstalls` takes
it, catches a change nobody asserted on: only the expected new names may
appear.

**Clean home:** a second empty `HOME`. After the run, every
`$tree/applications/*.desktop` is present and `cmp`-equal. This proves the
desktop does not come up empty.

**Restore still works:** `checks.remove-preinstalls` already runs the Restore
half, and it must stay green with Restore calling the replaced script.

### Proving it fails (§1)

Write the check first, on the current tree, before any fix. Commit a known-good
baseline, and restore with `git checkout HEAD -- <files>`, never
`git checkout -- <path>` (CLAUDE.md §5). `git add` the new test so the flake
sees it. Check that each break landed with `git diff`.

1. **The current tree (no fix):** expected red, captured for the PR:
   - `Basecamp.desktop changed`, from the `cp -f`;
   - `Zoom.desktop is no longer a link`;
   - `.local/bin/claude is no longer a link`, from `rm -f` and the stub.
2. **After the fix, three separate breaks**, each restored before the next:
   - delete `nix-bin/omarchy-refresh-applications` and restore the
     `substituteInPlace` → the launcher asserts go red, and claude stays green.
     That proves the two halves are independent;
   - revert only the `omarchy-mise-install` skip → `claude` goes red, and the
     launchers stay green;
   - change the loop's skip to an unconditional `continue` → the clean-home
     half goes red, `YouTube.desktop missing`.
3. Restore, and watch it go green. Every red output goes in the PR.

### Also run

Run these one at a time under `flock /mnt/data/vmtest/codex-build.lock`
(the cheap tier): `checks.provision-launchers`, `checks.remove-preinstalls`,
`checks.bin-ledger`, `checks.menu-actions`, and the `.#omarchy` package. Also
run `nix fmt -- --ci`, statix and deadnix. `checks.session` is a VM check, so
CI runs it, not a local build. It must go green with the retargeted
assertion.

### Holes, stated

- The check runs the two calls provisioning makes, not the whole of
  `omarchy-provision-user`. If upstream adds a third writer to `all.sh` or
  provision-user, this check will not see it.
- Whether a real Home Manager activation and a real first login, in that
  order, leave the links intact is answerable only in a VM with Home
  Manager, and no check boots that order today.
