---
status: draft
issue: 1319
spec: spec/2026-10-17-1319-provisioning-refresh-applications.md
---

# Plan: First-login provisioning must not overwrite the user's launchers or links

Worktree: `/mnt/data/vmtest/wt-1319`, branch
`fix/1319-provisioning-refresh-applications`. Line numbers are at `8d5fc587`.
The built tree used for evidence is
`/nix/store/ygd3l8hlwfclzrr9slna8caaqs953yy3-omarchy-4.0.4/share/omarchy`,
written `$B`.

## Approved decisions, carried over

1. **There are two paths to the hazard, and both are covered.**
   `omarchy-provision-user` (launched by `default/hypr/autostart.lua:7` →
   `omarchy-provision-first-run:46`) does two things:
   - at `:116` it sources `install/user/all.sh`, whose `:14` runs
     `install/user/mise.sh`;
   - at `:118` it runs `omarchy-refresh-applications`. That script
     `cp -f`'s the launchers (`:7`, `:10`) and runs `mise.sh` a second time
     (`:13-15`).

   `omarchy-provision-user` itself is not edited.
2. **`omarchy-refresh-applications` is replaced** by a new
   `pkgs/omarchy/nix-bin/omarchy-refresh-applications`. It seeds each shipped
   launcher only where no file or link of that name exists, and runs no
   `mise.sh`. This covers provisioning and `omarchy refresh applications`.
   The other two callers in `$B` cannot run here:
   `migrations/1786183928.sh`, and `omarchy-upgrade-to-quattro:2371`.
3. **Restore reuses it.** In `nix-bin/omarchy-install-preinstalls`, the loop
   at `:15-23` becomes a call to `omarchy-refresh-applications`. That leaves
   one seeding loop. Restore still writes no stubs (#1304's decision 2).
4. **The old patch is deleted.** That is the `substituteInPlace` on
   `omarchy-refresh-applications` at `pkgs/omarchy/default.nix:580-605`. The
   `nix-bin` loop at `:1065-1072` overwrites the file after the patch, so the
   patch is dead code.
5. **`omarchy-mise-install` writes into empty names only.** The existing #707
   replacement at `pkgs/omarchy/default.nix:607-614` is extended. After the
   Nix check, it exits 0 when `~/.local/bin/<cmd>` exists or is a link, and
   it no longer runs `rm -f`. Stubs are still written into empty names,
   because `data/apps.nix` has entries for only 4 of the 15 commands in
   `mise.sh`.
6. **Ledger** (`data/bin-ledger.nix`):
   - `omarchy-refresh-applications`: `patch` → `replace`;
   - `omarchy-mise-install`: the reason gains the no-replace clause;
   - `omarchy-install-preinstalls`: the reason is reworded.
7. **`tests/session.nix:1627-1628`** asserts `"cp -f" in refresh`, which
   checks how the code is written, not what it does (CLAUDE.md §1, read
   backwards). Drop that assertion and keep `--no-preserve=mode`. The
   property it stood for, "a second run does not fail on a 444 seed", moves
   to the new check.
8. **New check `checks.provision-launchers`**, a cheap `runCommand` with a
   fixture home. No `tests/coexistence/` fixture is added, because that
   check never runs first login and so could not fail.

## Who does what

Steps marked **[coder]** edit files. Steps marked **[lead]** run checks and
proofs and commit. Each **[lead]** step names the commit it makes.

## Steps

### 1. [coder] Write the check: `tests/provision-launchers.nix` (new file)

Write the check first. It must go red on today's tree.

Header comment, at most 8 lines:
- #1319;
- the two paths: all.sh:14, and provision-user:118 → refresh-applications;
- the 444 history the deleted `default.nix` comment carried. A copy at the
  store's 444 left files the next run could not rewrite. That aborted
  provisioning under `set -euo pipefail` before `finalize-user` was marked.
  The fix is to skip existing files, and this check runs everything twice.

Shape: copy `tests/remove-preinstalls.nix`, the same `{ inputs, pkgs }`
signature and `shipped` binding. Copy its `state`, `compare`, `pick`, `join`,
`fail` and `report` helpers verbatim; they are local to that file.
`nativeBuildInputs`: bash, coreutils, diffutils, findutils, gawk, gnugrep,
gnused. Attributes: `tree = "${shipped}/share/omarchy"`, `refresh =
"${shipped}/share/omarchy/bin/omarchy-refresh-applications"`, `shell =
pkgs.runtimeShell`.

Isolation, exactly as `remove-preinstalls.nix:35-47`:
- `set -euo pipefail` and `LC_ALL=C`;
- `real_home=$HOME`, then `HOME=$TMPDIR/home`;
- `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME`
  all under that `HOME`;
- `OMARCHY_PATH=$tree`.

Stubs in `$TMPDIR/stubs`, each recording its call to `$TMPDIR/calls` and
exiting 0: `mise`, `update-desktop-database`, `omarchy-install-hermes-cli`.
Then `PATH=$TMPDIR/stubs:$tree/bin:$PATH`.

The provisioning run, as a function `provision`, in this order:

```sh
bash -eE -c 'source "$1"' bash "$tree/install/user/mise.sh"   # all.sh:14, run_logged's form
bash "$refresh"                                               # provision-user:118
```

Each call's exit status is captured with `|| rc=$?`, and a non-zero one is a
failure.

Fixture home, in `$TMPDIR/home`, with Home Manager targets in `$TMPDIR/hm`.
Let `A=$HOME/.local/share/applications` and `B=$HOME/.local/bin`.
- `A/Basecamp.desktop`: the shipped file with `sed`'s URL edit, as
  `remove-preinstalls.nix:73`.
- `A/Zoom.desktop` → a link to `$TMPDIR/hm/Zoom.desktop`, which is a copy of
  the shipped file.
- `A/YouTube.desktop`: the shipped file, then `chmod 444`.
- `B/claude` → a link to `$TMPDIR/hm/claude`, which holds
  `#!/bin/bash\nexec /opt/claude "$@"`.

Assertions on the dirty home. Take `state` before, run `provision`, take
`state` after, and run `compare`:
- every `provision` call exits 0;
- no `D` lines and no `C` lines. This covers Basecamp's hash, the targets of
  Zoom and claude, and YouTube's content;
- `readlink "$A/Zoom.desktop"` = `$TMPDIR/hm/Zoom.desktop`, with failure text
  `Zoom.desktop is no longer a link`;
- `readlink "$B/claude"` = `$TMPDIR/hm/claude`, with failure text
  `.local/bin/claude is no longer a link`;
- `Basecamp.desktop changed` is a separate, named failure taken from the `C`
  set, so that the proof output reads plainly;
- every `A` path is under `home/.local/share/applications/` or
  `home/.local/bin/`. Anything else is `wrote unexpected files: …`;
- `B/codex` exists and contains `^exec mise x `. This is the empty-name case,
  `stub not written into an empty name`;
- every `$tree/applications/*.desktop` other than the three fixtures is
  `cmp`-equal in `A`.

Then run `provision` **a second time** and compare. It must exit 0 and show
no `D`, `C` or `A` at all: `second run changed: …`.

Clean home: `HOME=$TMPDIR/clean`, with `XDG_*` re-pointed. Run `provision`
once. Every `$tree/applications/*.desktop` must be present and `cmp`-equal,
otherwise `clean home missing <name>`.

End: `[ ! -e "$real_home" ] || fail "wrote outside the fixture: $real_home"`,
then `report`, then `touch $out`.

Traps:
- **Never name a shell variable `out`** (tests/AGENTS.md).
- A `runCommand` has `pipefail` on. A command substitution that fails ends
  the script with no message, so capture with `|| rc=$?` before you read it.
- **Heredocs:** a heredoc inside this `''…''` string makes nixfmt re-indent
  the whole file. Write fixture files with `printf` (CLAUDE.md §5).
- Escape bash's `${…}` as `''${…}` inside the Nix string, as
  `remove-preinstalls.nix:110` does.

Verify: `nix-instantiate --parse tests/provision-launchers.nix >/dev/null`.

### 2. [coder] Register it: `flake.nix:2026`

Add `"provision-launchers"` to `uniformChecks`, right after
`"preview-variant"` (`:2026`), with a one-line comment above it:
`# First login seeds only missing launchers and stubs (#1319).`
Add no workflow edit. `build.yml`'s generated step builds an unclaimed
check (CLAUDE.md §4).

Verify: `git add tests/provision-launchers.nix flake.nix && nix eval --raw
.#checks.x86_64-linux.provision-launchers.drvPath`.

Trap: an untracked file "does not exist" to the flake (§5). Run `git add`
first.

### 3. [lead] Prove the check red on today's tree (§1, part 1)

At this point steps 1 and 2 are staged and nothing else has changed. Run:

```sh
flock /mnt/data/vmtest/codex-build.lock \
  nix build .#checks.x86_64-linux.provision-launchers -L 2>&1 | tee /mnt/data/vmtest/1319-red-baseline.log
echo "exit ${PIPESTATUS[0]}"
```

It is expected to go red with all three:
- `Basecamp.desktop changed`;
- `Zoom.desktop is no longer a link`;
- `.local/bin/claude is no longer a link`.

The clean-home half and `stub not written into an empty name` should
already pass. If anything else is red, the check is wrong: send it back to
the coder.

Run it under bash, and read `PIPESTATUS`, not the pipeline's status (§1).

Commit: `The provisioning check that sees edited launchers and Home Manager
links being replaced (red until the fix)`, with a temporary subject (§8).

### 4. [coder] Replace the script: `pkgs/omarchy/nix-bin/omarchy-refresh-applications` (new file, mode 755)

```bash
#!/usr/bin/env bash

# omarchy:summary=Ensure default application launchers are installed.

# Upstream's cp -f replaced an edited launcher or a home-manager link, and its
# second mise.sh run deleted a home-manager ~/.local/bin entry (#1319).
# Provisioning runs mise.sh itself (all.sh). This only adds missing launchers.
set -uo pipefail

apps="$HOME/.local/share/applications"
mkdir -p "$apps"
srcs=("$OMARCHY_PATH"/applications/*.desktop)
if omarchy-cmd-present alacritty; then
  srcs+=("$OMARCHY_PATH/default/alacritty/Alacritty.desktop")
fi
for src in "${srcs[@]}"; do
  dst=$apps/${src##*/}
  [[ -e $dst || -L $dst ]] && continue
  cp --no-preserve=mode "$src" "$dst" && echo "Added ${src##*/}"
done
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$apps" &>/dev/null || true
fi
```

Traps:
- Keep the `# omarchy:summary=` line. `bin/omarchy` finds subcommands by it
  (`pkgs/omarchy/default.nix:1063-1064`).
- No `set -e`. A failed copy must not abort provisioning before
  `finalize-user`, which is #997's history. The last command is the `if`, so
  the script exits 0.
- Keep `--no-preserve=mode`. Step 7's retargeted assertion reads it.

Verify: `bash -n pkgs/omarchy/nix-bin/omarchy-refresh-applications && git add
pkgs/omarchy/nix-bin/omarchy-refresh-applications`.

### 5. [coder] Restore reuses it: `pkgs/omarchy/nix-bin/omarchy-install-preinstalls:5-23`

- Lines 5-8, the comment: replace with these three lines:
  ```
  # Upstream reseeds through mise stubs and then exits on omarchy-pkg-add, so the
  # marker never cleared (#1304). Launchers come from nix-bin's
  # omarchy-refresh-applications, which adds only missing ones (#1319).
  ```
- Delete line 11 (`apps=…`).
- Replace lines 15-23, from `mkdir -p "$apps"` through the
  `update-desktop-database` block's `fi`, with:
  ```
  omarchy-refresh-applications
  ```
- Keep everything else: the confirm, the app-selection message, `rm -f` of
  the marker, and `hyprctl reload`.

Trap: `data/menu-actions.nix:8-9` says Restore "adds missing launchers only,
never overwrites; its one rm is its own marker". That stays true. Leave the
reason as it is.

Verify: `bash -n pkgs/omarchy/nix-bin/omarchy-install-preinstalls`.

### 6. [coder] Remove the patch and extend the mise patch: `pkgs/omarchy/default.nix:580-614`

- **Delete `:580-605`**: the comment block that opens with "The third site
  of the same store-mode problem", plus the `substituteInPlace
  …/omarchy-refresh-applications` with its two `--replace-fail` pairs. Also
  delete the blank line that follows it (`:606`).
- **Extend `:607-614`.** Add one sentence to the comment, `# It never
  replaces an existing ~/.local/bin entry either, which may be a home-manager
  link (#1319).` Keep the comment to five lines at most.

  In the `--replace-fail` *replacement* string (`:614`), change the tail.
  The current tail is:
  ```
  …exit 0; }; rm -f "$HOME/.local/bin/$command"'
  ```
  It becomes:
  ```
  …exit 0; }; [[ -e $HOME/.local/bin/$command || -L $HOME/.local/bin/$command ]] && { echo "omarchy-mise-install: ~/.local/bin/$command exists, left as is"; exit 0; }'
  ```
  The *search* string (`'rm -f "$HOME/.local/bin/$command"'`, `:613`) does
  not change.

Traps:
- **The install-phase budget.** Measured at `8d5fc587`,
  `builtins.stringLength omarchy.installPhase` is **122,935 bytes** against a
  budget of 123,000. That is 65 bytes of headroom, not the ~900 the brief
  assumed. The deletion removes about 1,300 bytes, and the extension adds
  about 130, so the net is about −1,200. **Do the deletion in the same
  step.** An extension committed alone breaks `checks.install-phase-budget`.
  Measure after the edit:
  `nix eval --raw .#packages.x86_64-linux.omarchy.installPhase | wc -c`.
  It must print less than 122,935.
- **The formatter hook.** The editor hook on this machine runs
  `nixpkgs-fmt` on every `.nix` edit. Run `nix fmt` afterwards, and read
  `git diff --stat`. It must show only these lines (CLAUDE.md §5, #897).
- `${…}` is Nix interpolation in a `''` string. The new text uses only
  `$HOME` and `$command`, and no braces, so it needs no escaping.
- Grep `default.nix` for any other build-time assertion on
  `omarchy-refresh-applications` or `cp -f`. At `8d5fc587` there are none:
  `grep -n 'refresh-applications' pkgs/omarchy/default.nix` returns only the
  lines being deleted.

Verify: `bash -n` cannot reach this text, so verify by building, in step 9.

### 7. [coder] Retarget the session assertion: `tests/session.nix:1619-1629`

- Keep the comment at `:1619-1622`, and append one line: `# nix-bin's
  replacement skips existing files instead; checks.provision-launchers runs
  it twice.`
- Keep `:1623-1626`, which reads the script and asserts
  `--no-preserve=mode`.
- Delete `:1627-1628`, the `assert "cp -f" in refresh` and its message.
- Keep `:1629`.

Trap: this is a VM check. **Do not build it locally** (§6). CI runs it.

Verify: `nix-instantiate --parse tests/session.nix >/dev/null`.

### 8. [coder] Ledger: `data/bin-ledger.nix`

- `:286-289`, `omarchy-install-preinstalls`: change `reason` to:
  `"Upstream reseeds through omarchy-refresh-applications and its mise stubs, then exits on omarchy-pkg-add so the marker never clears. Seeds through nix-bin's omarchy-refresh-applications, writes no stubs, and clears the marker (#1304, #1319).";`
- `:364-367`, `omarchy-mise-install`: append to `reason`:
  ` Never removes or replaces an existing ~/.local/bin entry, which may be a home-manager link (#1319).`
- `:433-436`, `omarchy-refresh-applications`:
  `class = "replace";` and
  `reason = "Upstream's cp -f replaces an edited launcher or a home-manager link, and it reruns install/user/mise.sh, whose stubs replaced a home-manager ~/.local/bin entry. Copies only missing launchers and runs no mise.sh; provisioning already runs it from install/user/all.sh (#1319).";`

Verify: step 9's `checks.bin-ledger`.

### 9. [lead] Build, then the §1 break proofs

First, make sure the formatter hook did not reformat anything (CLAUDE.md §5).
Commit a known-good baseline (temporary subject) before breaking anything.
Restore every break with `git checkout HEAD -- <files>`, **never**
`git checkout -- <path>`, because it restores the index and not the commit
(§5). Before each run, prove the break landed with `git diff`. Before each
build, `git add -A`.

All builds are cheap or package tier, one at a time, under `flock
/mnt/data/vmtest/codex-build.lock`. Before the `.#omarchy` build, check that
no p620 build is running and that the load is below 12 (§6 tiers).

Green first:

```sh
for c in omarchy checks.x86_64-linux.provision-launchers \
         checks.x86_64-linux.remove-preinstalls checks.x86_64-linux.mise-launchers \
         checks.x86_64-linux.bin-ledger checks.x86_64-linux.menu-actions \
         checks.x86_64-linux.install-phase-budget; do
  flock /mnt/data/vmtest/codex-build.lock nix build ".#$c" -L || { echo "RED: $c"; break; }
done
```

Then three breaks, each restored before the next:

1. **The launchers only.** `git rm --cached` and delete
   `pkgs/omarchy/nix-bin/omarchy-refresh-applications`. Then re-add **only**
   the `substituteInPlace` lines (`:599-605` of
   `git show 8d5fc587:pkgs/omarchy/default.nix`) at the same place. Do not
   check out the whole file, which would revert the mise half too. This
   puts the shipped `cp -f` back. Without the `-f` patch, the 444
   `YouTube.desktop` makes the run exit 1 instead, which is a different red
   and not the one this break is meant to show. Expected red: `Basecamp.desktop changed`
   and `Zoom.desktop is no longer a link`. `.local/bin/claude` stays green,
   because the two halves are independent. It still runs `mise.sh` twice,
   which the second run absorbs.
2. **mise only.** In `default.nix`, put the tail of the replacement string
   back to `rm -f "$HOME/.local/bin/$command"`. Expected red:
   `.local/bin/claude is no longer a link`. The launchers stay green.
3. **The clean home.** In the new nix-bin script, change
   `[[ -e $dst || -L $dst ]] && continue` to plain `continue`. Expected red:
   `clean home missing …` for every launcher. The dirty-home assertions
   about files that already exist stay green.

Restore, and see green. Every red output, together with step 3's, goes in
the PR.

### 10. [lead] Format, lint, commit, and PR

```sh
nix fmt -- --ci
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
```

- Squash to one commit with a real sentence subject (no `wip:`, §8), for
  example: `First login adds only missing launchers and stubs, leaving edited
  launchers and home-manager links alone (#1319)`.
- Check `git merge-base origin/main HEAD` and `git show --stat HEAD`. The
  stat must list only these files: the two nix-bin scripts, `default.nix`,
  `bin-ledger.nix`, `session.nix`, the new test, `flake.nix`, and the three
  artifacts.
- The PR body links intent, spec and plan, says which steps the coder did,
  and carries the red outputs.
- Name the session retarget in the PR as "measured the arrangement" (§1).
- Name the two holes from the spec: the check runs two calls, not all of
  provision-user; and no check runs a real Home Manager activation followed
  by first login.
- Use `Closes #1319`. Do not write a skip-CI marker anywhere (§8).

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.provision-launchers` | green after step 8, red at step 3 with the three named failures |
| `nix build .#checks.x86_64-linux.remove-preinstalls` | green: Restore still adds only launchers, changes nothing |
| `nix build .#checks.x86_64-linux.mise-launchers` | green: (a)-(e) unchanged; (b) writes into an empty name |
| `nix build .#checks.x86_64-linux.bin-ledger` | green with the `replace` class |
| `nix build .#checks.x86_64-linux.menu-actions` | green: no row reaches either script, no reason goes stale |
| `nix build .#checks.x86_64-linux.install-phase-budget` | green, and its printed bytes are lower than 122,935 |
| `nix build .#omarchy` | builds: the `nix-bin` loop finds an upstream `omarchy-refresh-applications` to replace |
| `checks.session` | CI only; green with the retargeted assertion |

## Rollback

Revert the squash commit. Nothing writes state outside a home directory, and
no option or default changes. Homes provisioned while the fix was in place
keep whatever they had. A revert restores upstream's `cp -f` and stub
rewrite at the next `omarchy refresh applications` or first login.
