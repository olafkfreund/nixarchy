---
status: draft
issue: 1306
spec: spec/2026-10-17-1306-stale-session-scripts.md
---

# Plan: After a switch, the menu and the scripts it runs come from one generation

## Approved decisions, self-contained

- **Keep the pinned `OMARCHY_PATH`.** #1255's model stands: the running
  Quickshell defines the live generation, and `nixarchy-shell-session sync`
  publishes its tree to Hyprland and the user manager on every activation.
  A stable path (`/run/current-system/sw/share/omarchy`, `/etc/nixarchy/tree`)
  is rejected. It breaks shell identification by tree, kill-by-old-path in
  `omarchy-restart-shell` (#982), and GC liveness of the running tree.
- **The shell already reads its menu from its own tree** (`Menu.qml:13,50`),
  not from `/etc/nixarchy/omarchy-menu.jsonc`. So its rows and its scripts
  already agree. What is missing is (1) any sign that the desktop is behind the
  system, and (2) an end to new scripts resolving old siblings through the
  pinned `bin` that sits first on PATH. A shell restart ends both. A re-login
  is not needed.
- **The fix: `nixarchy-shell-session sync --current TREE`.** After publishing
  (unchanged), if `TREE` differs from the live shell's tree, send one
  notification whose click runs `$TREE/bin/omarchy-restart-shell`.
  - Its id lives in `$XDG_RUNTIME_DIR/nixarchy/restart-notice-id` and is
    passed back with `-r`, so repeated switches replace the notice rather than
    stack it.
  - No `--current`, equal trees, or a failed notifier: no notice and exit 0.
    The notice is advice, and the sync is the contract.
  - The notifier is called by name, like `qs`, `hyprctl` and
    `dbus-update-activation-environment`, so the test stubs it on PATH.
- **Home Manager activation** passes `--current ${omarchyPath}` and puts
  `${cfg.package}/bin` on its PATH, because that is where
  `omarchy-notification-send` lives. The launcher's own `sync --pid` passes
  nothing, so a fresh launch never notifies.
- **Manual:** `docs/manual/plugins.md` stops telling people to log out, and
  says to restart the shell when the notice offers it.
- **Verification layer:** `checks.shell-session`, a `runCommand` that already
  runs a real process under one tree with stubbed services. It is the
  cheapest layer where the live tree and the activated tree can differ (§3).
  An on/off pair in `checks.options` holds the activation wiring. The bus
  delivery and the click are a manual p620 step, and the gap is written into
  `tests/AGENTS.md`.
- **bin-ledger: no row change is required.**
  - `tests/bin-ledger.nix` runs `.github/scripts/check-bin-ledger.py`.
  - The class is derived. A file in `pkgs/omarchy/nix-bin` derives as `new`,
    which `data/bin-ledger.nix:737-741` already says.
  - The other failure mode is the `PATTERNS` groups (`check-bin-ledger.py:84-107`).
    The new code adds `mkdir -p` under `$XDG_RUNTIME_DIR`, which matches no
    group, since `etc-write` needs `/etc/`. `systemctl --user` is unchanged,
    so `allow = "systemctl-user"` stays true.
  - The row's `reason` is not machine-checked, but it would stop describing
    the command. Step 1 updates that one sentence so it stays true.

## Who does what

| step | edits files | owner |
|---|---|---|
| 1 helper | yes | coder |
| 2 helper test | yes | coder |
| 3 activation | yes | coder |
| 4 options pair | yes | coder |
| 5 docs | yes | coder |
| 6 commit, then the §1 break proofs | no (scratch worktree) | **lead** |
| 7 manual p620 check, PR | no | **lead** + owner |

Four files are edited by steps 1–5. Per the model split, that is a coder
hand-off.

## Steps

### 1. `pkgs/omarchy/nix-bin/nixarchy-shell-session`: add `--current` (coder)

- **Line 13**: the usage string becomes
  `usage: nixarchy-shell-session {pid|tree|sync} [--if-running] [--pid PID] [--wait SECONDS] [--current TREE]`.
- **Lines 14-16**: add `current_tree=` beside `expected_pid=`.
- **Lines 18-25**: add a case before `*)`:

  ```bash
      --current)
        (($# >= 2)) && [[ -n $2 ]] || fail '--current requires a tree'
        current_tree=$2
        shift 2 ;;
  ```

  `pid` and `tree` accept the flag and ignore it, which is not worth a
  refusal.
- **After line 118** (the `dbus-update-activation-environment` line, the
  file's last), append:

  ```bash
  # Advice, never a failure: the publication above is the contract (#1306).
  if [[ -n $current_tree && $current_tree != "$selected_tree" ]]; then
    notice_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixarchy/restart-notice-id
    notice_id=$(cat "$notice_file" 2>/dev/null) || notice_id=0
    [[ $notice_id =~ ^[0-9]+$ ]] || notice_id=0
    if notice_new=$(run omarchy-notification-send -u normal -r "$notice_id" -p \
        'Restart the shell to finish this update' \
        'The menu and its commands are from the generation you logged in with. Windows already open keep the old commands until reopened.' \
        --exec "$current_tree/bin/omarchy-restart-shell"); then
      { mkdir -p "${notice_file%/*}" && printf '%s\n' "$notice_new" > "$notice_file"; } 2>/dev/null || true
    fi
  fi
  ```

  `run` is the file's own `timeout 2s` wrapper, so a hung bus cannot hang a
  switch.
- **`data/bin-ledger.nix:739`**: the `reason` becomes
  `"Resolve the live Quickshell process on the selected Wayland display, publish its tree and PATH to Hyprland, D-Bus and the systemd user manager, and offer a shell restart when a switch activated a different tree."`.
  `class` and `allow` stay as they are.
- **Verify:**
  `nix run nixpkgs#shellcheck -- pkgs/omarchy/nix-bin/nixarchy-shell-session`
  must come back clean, then step 2's check.
- **Traps:**
  - This is a plain nix-bin script, not `writeShellApplication`, so PATH stubs
    reach it (`tests/AGENTS.md`, *"A PATH stub loses to runtimeInputs"*: this
    is the upstream-side case where PATH is the mechanism).
  - Under `set -euo pipefail`, every new command that may fail sits inside an
    `if` or an `||`. Check that by reading, not just by running the test.
  - `git add` the file before any flake build (§5: *"A flake in a worktree
    sees only tracked or staged files"*).

### 2. `tests/shell-session.sh`: vary the generation (coder)

- **Line 15** (the stub block): add a notifier stub that logs its argv as
  JSON to its own file, so the existing `length == 3` assertion on
  `$TEST_CALLS` is untouched. It fails on request and otherwise prints id `42`:

  ```bash
  printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_NOTICES"\n[[ -z ${TEST_NOTICE_FAIL:-} ]] || exit 1\necho 42\n' "$TEST_BASH" > stub/omarchy-notification-send
  ```

  `chmod +x stub/*` on line 16 already covers it.
- **Line 9**: extend the `export` with
  `TEST_NOTICES=$PWD/notices.jsonl XDG_RUNTIME_DIR=$PWD/runtime`.
- **After line 66** (the existing `bash "$helper" sync` and its assertion):

  ```bash
  [[ ! -e $TEST_NOTICES ]] || { echo 'FAIL: a sync without --current sent a notice'; exit 1; }
  echo 'PASS: the launcher-style sync never notifies'
  ```
- **At the end of the file**, append:

  ```bash
  printf '%s\n' "$one" > "$TEST_LIST"
  bash "$helper" sync --current "$new"
  [[ ! -e $TEST_NOTICES ]] || { echo 'FAIL: equal trees sent a notice'; exit 1; }
  echo 'PASS: a switch that keeps the live tree says nothing'
  bash "$helper" sync --current "$old"
  jq -se --arg exec "$old/bin/omarchy-restart-shell" '
    length == 1 and (.[0] | .[index("--exec") + 1] == $exec and .[index("-r") + 1] == "0")
  ' "$TEST_NOTICES" >/dev/null || { echo 'FAIL: a different tree did not offer a restart into it'; exit 1; }
  echo 'PASS: a different tree offers one restart into the new tree'
  bash "$helper" sync --current "$old"
  jq -se 'length == 2 and (.[1] | .[index("-r") + 1] == "42")' "$TEST_NOTICES" >/dev/null \
    || { echo 'FAIL: a second switch stacked a notice instead of replacing it'; exit 1; }
  echo 'PASS: a second switch replaces the notice'
  : > "$TEST_CALLS"
  TEST_NOTICE_FAIL=1 bash "$helper" sync --current "$old" \
    || { echo 'FAIL: a failed notifier failed the sync'; exit 1; }
  jq -se 'length == 3' "$TEST_CALLS" >/dev/null \
    || { echo 'FAIL: a failed notifier stopped publication'; exit 1; }
  echo 'PASS: a failed notifier changes nothing else'
  ```

  The first line rewrites `$TEST_LIST` because the compositor-rejection case
  just above leaves it pointing at the same single instance. It is harmless,
  but it states the precondition.
- **Verify:** run this under `flock`, as one build:

  ```bash
  flock /mnt/data/vmtest/codex-build.lock \
    nix build .#checks.x86_64-linux.shell-session --print-build-logs
  ```

  Every `PASS:` line must print, the four new ones included.
- **Traps:**
  - It builds the `omarchy` package, which is §6's middle tier: no p620 system
    build running (`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'`
    prints 0), and a 1-minute load below 12.
  - Never pipe `nix build` into `tail` without `set -o pipefail` (§1).
  - Each assertion ends in an `echo 'FAIL: …'` before `exit 1`, so a red build
    says which case failed (`tests/AGENTS.md`, *"A check that dies before its
    first echo"*).
  - Confirm `jq`'s `index` on an array returns the element's position. If it
    returns null, `null + 1` errors and the case fails loudly, not silently.

### 3. `modules/home.nix:2299-2307`: pass the activated tree (coder)

Change the two lines of the `run` invocation to:

```nix
        PATH="${cfg.package}/bin:${lib.makeBinPath cfg.package.passthru.runtimeDeps}:$PATH" \
          run ${cfg.package}/bin/nixarchy-shell-session sync --if-running --current ${lib.escapeShellArg omarchyPath} \
```

Keep the `|| echo …` line. Extend the comment above it by one line:
`# --current: a different live tree gets one restart offer (#1306).`

- **Verify:** this is an evaluation-only check, so it is the cheap tier,
  under `flock`:

  ```bash
  nix eval --raw .#nixosConfigurations.vm.config.home-manager.users.omarchy.home.activation.nixarchySyncSession.data \
    | grep -E -- "--current '/nix/store/[a-z0-9]{32}-nixarchy-omarchy-tree'"
  ```

  It must print the line. Run `nix eval` alone first and read its status; do
  not trust the `grep` (§1, pipelines).
- **Traps:**
  - Afterwards run `nix fmt` and read `git diff --stat`. A managed hook may
    have reformatted the file with `nixpkgs-fmt` (§5, #897).
  - `omarchyPath` is `osConfig.programs.nixarchy.tree or …` (`home.nix:17`),
    which is the generated tree on a NixOS machine. That is what the grep's
    `-nixarchy-omarchy-tree` suffix proves.

### 4. `tests/options.nix`: hold the wiring (coder)

Add a pair beside `nixSkillsInertWithoutOsConfig` (around line 858). It uses
the fixtures already bound there and adds no new evaluation (#738/#747):

```nix
    # #1306: activation offers a restart into the tree it activated, which on
    # a NixOS machine is the generated one -- not the package's own.
    syncSessionOffersActivatedTree =
      let
        offers =
          home:
          builtins.any (l: builtins.match ".*--current '/nix/store/[a-z0-9]{32}-nixarchy-omarchy-tree'.*" l != null) (
            pkgs.lib.splitString "\n" (activationText home)
          );
      in
      {
        on = offers defaultHomeOn;
        off = offers defaultHome;
      };
```

`off` is a real state. `defaultHome` has no `osConfig`, so `omarchyPath`
falls back to `${cfg.package}/share/omarchy`, which does not end in
`-nixarchy-omarchy-tree`.

- **Verify:** read how the file consumes `on`/`off` pairs, and confirm the new
  attribute sits in that set. Then leave the run to CI. `options` is 8 minutes
  and 11.5 GB, so it is §6's third tier: run it locally only when
  `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
  prints `0`.
- **Traps:**
  - Do not bind a new fixture (`tests/options.nix:101-107`, #738).
  - Do not write a heredoc into the file (§5, the reindentation trap).
  - Run `nix fmt -- --ci` before handing back.

### 5. Docs (coder)

- **`docs/manual/plugins.md:278-280`**: replace the paragraph with:

  > **After the switch that brings it in,** restart the shell when the
  > notification offers it (or run `omarchy-restart-shell`). Until you do,
  > Add Plugin still opens the old prompt: the running shell keeps the
  > generation it started with, so the desktop never changes under you.
- **`tests/AGENTS.md`**: append a section at the end, after the last one
  (CLAUDE.md's "append, never insert" habit):

  > ## The restart notice: decided in a runCommand, delivered by nothing here
  >
  > `checks.shell-session` varies the variable #1306 is about: the live
  > shell's tree against the tree a switch activated. Every other check logs in
  > after the switch, so the two are always equal there. It proves the
  > decision, the replace-not-stack id and that a failed notifier fails
  > nothing. `checks.options` (`syncSessionOffersActivatedTree`) proves
  > activation passes the generated tree. **Nothing proves delivery**: that the
  > notice crosses from Home Manager activation to the shell over
  > `busctl --user`, whose unit sets no `DBUS_SESSION_BUS_ADDRESS`, or that
  > clicking it moves the menu and new terminals. `checks.session` could do it
  > with a switch inside the VM, which is a VM run for one notice. It is a
  > manual step on a real desktop, recorded in #1306's PR.
- **Verify:** none beyond reading it. `docs/AGENTS.md`'s house style applies.

### 6. Commit, then the §1 break proofs (lead)

First, commit steps 1–5 as one commit with a full-sentence subject, for
example: *"A switch that leaves the shell on an older tree offers one restart
into the new one"*. Then run every break in a **scratch worktree**:

```bash
git worktree add --detach /mnt/data/vmtest/wt-1306-break HEAD
```

The traps that apply here:

- A `cp -a` of the worktree shares its index (§5).
- Restore each break with `git checkout HEAD -- <path>`. Plain `git checkout
  --` restores the index, which may hold the break (§5).

Wait for each break to land, then build. **Before** every build, run
`git diff` and `grep` to confirm the break is in the file (§1: *a break that
stays green may be a break that never applied*). Use `--print-build-logs`, no
pipe, under `flock`. Capture the output for the PR.

| break | how | must fail with |
|---|---|---|
| B1: never notify | delete the appended `if … fi` block | `FAIL: a different tree did not offer a restart into it` |
| B2: inverted test | `!= "$selected_tree"` → `== "$selected_tree"` | `FAIL: equal trees sent a notice` |
| B3: stacking | delete `-r "$notice_id"` | `FAIL: a second switch stacked a notice …` (the stub logs no `-r`, so `index` is null and the case errors red) |
| B4: notifier fatal | replace the `if notice_new=$(…); then … fi` with a bare `notice_new=$(run omarchy-notification-send …)` | `FAIL: a failed notifier failed the sync` |
| B5: wiring dropped | in `modules/home.nix`, delete `--current ${lib.escapeShellArg omarchyPath}` | `checks.options`: `syncSessionOffersActivatedTree` reports `on` false |

Then restore and confirm each case is green again. B1–B4 build
`checks.x86_64-linux.shell-session`, at the middle tier (no p620 system build,
load below 12). B5 is `options`, at the top tier: nothing in flight on CI. If
CI stays busy, the step 3 `nix eval … | grep` going empty under B5 is the
cheap stand-in, but say in the PR which one ran.

Also build `checks.x86_64-linux.bin-ledger` once on the fixed tree. It must
pass, which confirms the "no row change" finding. A failure there means a
`PATTERNS` group matched: read its message and add that group to `allow`.

Finally, run `git worktree remove /mnt/data/vmtest/wt-1306-break`.

### 7. Manual check on p620, then the PR (lead, with the owner)

This is the hole that step 5 names.

1. With CI idle, switch p620 to a generation whose tree differs from the
   running shell's (§6: a switch kills any install in flight, so check
   `gh run list` first and announce on the bus).
2. The notice appears.
3. Switch again. The notice is replaced, not doubled.
4. Click it, then compare the new Quickshell's
   `tr '\0' '\n' < /proc/$(pgrep -f quickshell-wrapped)/environ | grep ^OMARCHY_PATH`
   with `/run/current-system/etc/set-environment`. They must match. Also check
   that `systemctl --user show-environment | grep ^OMARCHY_PATH` matches.
5. If the notice never shows, the bus is the cause (spec Risks). The switch is
   unaffected. Record it, and treat it as a follow-up, not a blocker.

The PR links the intent, the spec and this plan. It says that steps 1–5 were
the coder's, pastes B1–B5's failing output, and records step 7's result. Use
`Closes #1306` only if step 7 passed; otherwise use `Refs #1306` (§8).

## Tests

| command | expect |
|---|---|
| `nix build .#checks.x86_64-linux.shell-session -L` | every `PASS:` line, 4 new |
| `nix build .#checks.x86_64-linux.bin-ledger -L` | passes, ledger unchanged except the reason |
| `nix eval --raw .#nixosConfigurations.vm.config.home-manager.users.omarchy.home.activation.nixarchySyncSession.data` | contains `--current '/nix/store/…-nixarchy-omarchy-tree'` |
| `nix build .#checks.x86_64-linux.options -L` | passes (CI, or locally with nothing in flight) |
| `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`, `shellcheck` on the helper | clean |
| B1–B5 (step 6) | each red with its message, then green when restored |

## Rollback

Revert the one implementation commit. Nothing is stateful except
`$XDG_RUNTIME_DIR/nixarchy/restart-notice-id`, which is per-login and is
ignored by the reverted helper. No option was added or renamed, so no user
configuration changes on rollback. The intent and spec files stay.
