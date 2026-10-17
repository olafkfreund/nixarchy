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
  is rejected, because it breaks three things:
  - how the helper identifies the shell, which is by its tree;
  - `omarchy-restart-shell`'s kill by the old path (#982);
  - GC liveness of the running tree.
- **The shell already reads its menu from its own tree** (`Menu.qml:13,50`),
  not from `/etc/nixarchy/omarchy-menu.jsonc`, so its rows and its scripts
  already agree. Two things are missing:
  1. any sign that the desktop is behind the system;
  2. an end to new scripts resolving old siblings through the pinned `bin`
     that sits first on PATH.

  A shell restart ends both. A re-login is not needed.
- **The fix: `nixarchy-shell-session sync --current TREE`.** After publishing
  (unchanged), compare `TREE` with the live shell's tree:
  - **Different, and the live tree is in the store:** send one notification
    whose click runs `$TREE/bin/omarchy-restart-shell`.
    - Its id is saved as `<live shell pid> <id>` in
      `$XDG_RUNTIME_DIR/nixarchy/restart-notice-id`, and passed back with `-r`
      **only if the pid still matches**. The shell's notification server
      numbers from 1 again after a restart (`Service.qml:295-298`), so an id
      from an earlier shell could replace another app's toast.
  - **Equal:** no notice, and the saved id is deleted.
  - **Live tree outside the store** (`omarchy dev link`): no notice. A restart
    would not move off a checkout, so the notice could never clear.
  - **No `--current`, or a failed notifier:** no notice and exit 0. The notice
    is advice, and the sync is the contract.
  - The notifier is called by name, like `qs`, `hyprctl` and
    `dbus-update-activation-environment`, so the test stubs it on PATH.
- **Home Manager activation** passes `--current ${omarchyPath}` **only when
  `osConfig != null`**, and puts `${cfg.package}/bin` on its PATH, because
  that is where `omarchy-notification-send` lives. A standalone Home Manager
  user's tree is not the one a restart would move to, so it gets no flag. The
  launcher's own `sync --pid` passes nothing, so a fresh launch never notifies.
- **Manual:** `docs/manual/plugins.md` stops telling people to log out, and
  says to restart the shell when the notice offers it.
- **Verification layer:** `checks.shell-session`, a `runCommand` that already
  runs a real process under one tree with stubbed services. It is the
  cheapest layer where the live tree and the activated tree can differ (§3).
  An on/off pair in `checks.options` holds the activation wiring. Bus
  delivery and the click are a manual p620 step, and the gap is written into
  `tests/AGENTS.md`.
- **bin-ledger: no row change is required.**
  - `tests/bin-ledger.nix` runs `.github/scripts/check-bin-ledger.py`.
  - The class is derived. A file in `pkgs/omarchy/nix-bin` derives as `new`,
    which `data/bin-ledger.nix:737-741` already says.
  - The other failure mode is the `PATTERNS` groups (`check-bin-ledger.py:84-107`).
    The new `mkdir -p` and `rm -f` act under `$XDG_RUNTIME_DIR` and match no
    group, since `etc-write` needs `/etc/`. `systemctl --user` is unchanged.
  - The row's `reason` is not machine-checked, but it would stop describing
    the command. Step 1 updates that one sentence so it stays true.

## Deviations from the spec

Review of the first draft of this plan corrected the approved spec in four
places. Each is recorded here, and the spec file stays as approved.

1. **Risks, "the Home Manager unit sets no `DBUS_SESSION_BUS_ADDRESS`", is
   wrong.** `hm-setup-env` imports `DBUS_SESSION_BUS_ADDRESS`,
   `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` from `systemctl --user
   show-environment` (home-manager `nixos/default.nix:91-112`), and p620 has
   it. The bus address is therefore present. Delivery is still not proven by
   any check and stays a manual step.
2. **The saved notice id is tied to the live shell's pid** and deleted when the
   trees match. The spec relied on `$XDG_RUNTIME_DIR` being per-login, but a
   shell *restart*, not a re-login, also resets the server's ids.
3. **`--current` is passed only with `osConfig`.** The spec passed it always,
   which would leave a standalone Home Manager user with a notice that no
   restart clears.
4. **No notice for a live tree outside the store** (dev link), for the same
   reason.

## Who does what

| step | edits files | owner |
|---|---|---|
| 1 helper | yes | coder |
| 2 helper test | yes | coder |
| 3 activation | yes | coder |
| 4 options pair | yes | coder |
| 5 docs | yes | coder |
| 6 commit, then the §1 break proofs | no (scratch copies and worktree) | **lead** |
| 7 manual p620 check, PR | no | **lead** + owner |

Steps 1–5 edit six files. Per the model split, that is a coder hand-off.

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
  notice_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixarchy/restart-notice-id
  if [[ -n $current_tree ]]; then
    if [[ $current_tree == "$selected_tree" ]]; then
      rm -f "$notice_file" 2>/dev/null || true
    # A dev-linked checkout is not in the store, and a restart would not move off it.
    elif [[ $selected_tree == "${NIX_STORE_DIR:-/nix/store}"/* ]]; then
      # The server renumbers from 1 when the shell restarts: reuse an id only for this shell.
      notice_id=0 saved_pid='' saved_id=''
      read -r saved_pid saved_id 2>/dev/null < "$notice_file" || true
      if [[ $saved_pid == "$selected_pid" && $saved_id =~ ^[0-9]+$ ]]; then notice_id=$saved_id; fi
      if notice_new=$(run omarchy-notification-send -u normal -r "$notice_id" -p \
          'Restart the shell to finish this update' \
          'The menu and its commands are from the generation you logged in with. Windows already open keep the old commands until reopened.' \
          --exec "$current_tree/bin/omarchy-restart-shell"); then
        { mkdir -p "${notice_file%/*}" && printf '%s %s\n' "$selected_pid" "$notice_new" > "$notice_file"; } 2>/dev/null || true
      fi
    fi
  fi
  ```

  - `run` is the file's own `timeout 2s` wrapper, so a hung bus cannot hang a
    switch.
  - `NIX_STORE_DIR` is Nix's own variable for the store location. Real
    sessions leave it unset, and the test sets it so its trees count as
    in-store.
  - `2>/dev/null` comes **before** `< "$notice_file"`, so a missing file prints
    nothing. Bash applies redirections left to right.
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
    `if` or an `||`. `saved_pid` and `saved_id` are initialised so `set -u`
    holds when `read` fails.
  - `git add` the file before any flake build (§5).

### 2. `tests/shell-session.sh`: vary the generation (coder)

- **Line 10** (the `export`): append
  `TEST_NOTICES=$PWD/notices.jsonl XDG_RUNTIME_DIR=$PWD/runtime NIX_STORE_DIR=$PWD`.
  The fixture trees sit under `$PWD`, so this makes them "in the store" for
  the helper's dev-link guard.
- **Before line 15** (`chmod +x stub/*`): add a notifier stub. It logs its
  argv as JSON to its own file, so the existing `length == 3` assertion on
  `$TEST_CALLS` is untouched. It fails on request and otherwise prints id `42`:

  ```bash
  printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_NOTICES"\n[[ -z ${TEST_NOTICE_FAIL:-} ]] || exit 1\necho 42\n' "$TEST_BASH" > stub/omarchy-notification-send
  ```
- **After line 67** (`echo 'PASS: quoted paths are published consistently …'`,
  which ends the existing `bash "$helper" sync` case):

  ```bash
  [[ ! -e $TEST_NOTICES ]] || { echo 'FAIL: a sync without --current sent a notice'; exit 1; }
  echo 'PASS: the launcher-style sync never notifies'
  ```
- **At the end of the file**, append the block below.
  - Every `jq` asserts `index("-r") != null` explicitly. In jq, `null + 1` is
    `1`, so without the guard a missing `-r` would read the wrong element
    instead of erroring.
  - The first line rewrites `$TEST_LIST`, because the compositor-rejection case
    just above may have left it otherwise. The rewrite states the
    precondition.

  ```bash
  printf '%s\n' "$one" > "$TEST_LIST"
  notice_file=$XDG_RUNTIME_DIR/nixarchy/restart-notice-id
  notices() { jq -se "$@" "$TEST_NOTICES" >/dev/null; }
  bash "$helper" sync --current "$new"
  [[ ! -e $TEST_NOTICES ]] || { echo 'FAIL: equal trees sent a notice'; exit 1; }
  echo 'PASS: a switch that keeps the live tree says nothing'
  bash "$helper" sync --current "$old"
  notices --arg exec "$old/bin/omarchy-restart-shell" '
    length == 1 and (.[0] | index("-r") != null and .[index("--exec") + 1] == $exec and .[index("-r") + 1] == "0")
  ' || { echo 'FAIL: a different tree did not offer a restart into it'; exit 1; }
  echo 'PASS: a different tree offers one restart into the new tree'
  bash "$helper" sync --current "$old"
  notices 'length == 2 and (.[1] | index("-r") != null and .[index("-r") + 1] == "42")' \
    || { echo 'FAIL: a second switch stacked a notice instead of replacing it'; exit 1; }
  echo 'PASS: a second switch replaces the notice'
  printf '99999999 42\n' > "$notice_file"
  bash "$helper" sync --current "$old"
  notices 'length == 3 and (.[2] | index("-r") != null and .[index("-r") + 1] == "0")' \
    || { echo 'FAIL: an id saved by a previous shell was reused'; exit 1; }
  echo 'PASS: an id from a restarted shell is not reused'
  bash "$helper" sync --current "$new"
  { [[ ! -e $notice_file ]] && notices 'length == 3'; } \
    || { echo 'FAIL: equal trees left the saved id behind'; exit 1; }
  echo 'PASS: catching up clears the saved id'
  NIX_STORE_DIR=/nix/store bash "$helper" sync --current "$old"
  notices 'length == 3' || { echo 'FAIL: a tree outside the store was offered a restart'; exit 1; }
  echo 'PASS: a dev-linked tree is never offered a restart'
  : > "$TEST_CALLS"
  TEST_NOTICE_FAIL=1 bash "$helper" sync --current "$old" \
    || { echo 'FAIL: a failed notifier failed the sync'; exit 1; }
  jq -se 'length == 3' "$TEST_CALLS" >/dev/null \
    || { echo 'FAIL: a failed notifier stopped publication'; exit 1; }
  echo 'PASS: a failed notifier changes nothing else'
  ```

- **Verify:** first the fast loop, which takes seconds and needs no package
  rebuild. The check's derivation runs exactly this script against the
  packaged helper:

  ```bash
  d=$(mktemp -d /mnt/data/vmtest/ss.XXXX) && cd "$d" && \
    TEST_BASH=$(command -v bash) TEST_SLEEP=$(command -v sleep) \
    bash /mnt/data/vmtest/wt-1306/tests/shell-session.sh /mnt/data/vmtest/wt-1306/pkgs/omarchy/nix-bin/nixarchy-shell-session
  ```

  Then the real check, once, under `flock`:

  ```bash
  flock /mnt/data/vmtest/codex-build.lock \
    nix build .#checks.x86_64-linux.shell-session --print-build-logs
  ```

  Every `PASS:` line must print, the seven new ones included.
- **Traps:**
  - The real check builds the `omarchy` package, which is §6's middle tier:
    no p620 system build running
    (`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` prints 0), and
    a 1-minute load below 12.
  - Do not pipe `nix build` without `set -o pipefail` (§1).
  - Run the fast loop **under bash as a script**, not pasted into zsh (§1).
  - Each assertion ends in an `echo 'FAIL: …'` before `exit 1`, so a red build
    says which case failed (`tests/AGENTS.md`, *"A check that dies before its
    first echo"*).

### 3. `modules/home.nix:2299-2307`: pass the activated tree (coder)

Change the two lines of the `run` invocation to:

```nix
        PATH="${cfg.package}/bin:${lib.makeBinPath cfg.package.passthru.runtimeDeps}:$PATH" \
          run ${cfg.package}/bin/nixarchy-shell-session sync --if-running${lib.optionalString (osConfig != null) " --current ${omarchyPath}"} \
```

- Interpolate the path plainly, as the surrounding lines do.
  `lib.escapeShellArg` leaves a plain store path unquoted, so a pattern that
  expects quotes never matches. A store path holds no characters that need
  quoting.
- Keep the `|| echo …` line. Extend the comment above it with one line:
  `# --current: a different live tree gets one restart offer; only a NixOS tree is one a restart reaches (#1306).`
- **Verify:** this is an evaluation-only check, so it is the cheap tier,
  under `flock`. Run `nix eval` alone and read its exit status before trusting
  any grep (§1):

  ```bash
  nix eval --raw .#nixosConfigurations.vm.config.home-manager.users.omarchy.home.activation.nixarchySyncSession.data > /mnt/data/vmtest/sync.txt
  grep -E -- '--current /nix/store/[a-z0-9]{32}-nixarchy-omarchy-tree( |$)' /mnt/data/vmtest/sync.txt
  ```

  The grep must print the line.
- **Traps:**
  - Afterwards run `nix fmt` and read `git diff --stat`. A managed hook may
    have reformatted the file with `nixpkgs-fmt` (§5, #897).
  - `osConfig ? null` is the module argument's declared default
    (`home.nix:6`), so `osConfig != null` is the right test. Do not add a
    `?` default anywhere new (§5).

### 4. `tests/options.nix`: hold the wiring (coder)

Add a case beside `nixSkillsInertWithoutOsConfig` (around line 858). It uses
the fixtures already bound there and adds no new evaluation (#738/#747).

The file reads every case as `on && !off` (`tests/options.nix:3354`):

```nix
    # #1306: activation offers a restart into the tree it activated -- the
    # generated one on NixOS -- and offers none without a NixOS tree to reach.
    syncSessionOffersActivatedTree =
      let
        sync = home: home.home.activation.nixarchySyncSession.data;
      in
      {
        on = builtins.any (
          l: builtins.match ".*--current /nix/store/[a-z0-9]{32}-nixarchy-omarchy-tree( .*)?" l != null
        ) (pkgs.lib.splitString "\n" (sync defaultHomeOn));
        off = pkgs.lib.hasInfix "--current" (sync defaultHome);
      };
```

- `off` is a real state. `defaultHome` has no `osConfig`, so after step 3
  its sync line carries no `--current` at all.
- `builtins.match` anchors the whole string, hence `( .*)?` where grep uses
  `( |$)`.
- **Verify:** leave the run to CI. `options` is 8 minutes and 11.5 GB, which
  is §6's third tier: run it locally only when
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
  > decision, the replace-not-stack id, that an id from a restarted shell is
  > never reused, that a dev-linked tree is left alone and that a failed
  > notifier fails nothing. `checks.options` (`syncSessionOffersActivatedTree`)
  > proves activation passes the generated tree, and only on NixOS.
  >
  > **Nothing proves delivery.** Home Manager's activation does receive the
  > session bus: `hm-setup-env` imports `DBUS_SESSION_BUS_ADDRESS`,
  > `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` from the user manager. But no check
  > shows the shell's server accepting the notice, or a click moving the menu
  > and new terminals. `checks.session` could, with a switch inside the VM,
  > which is a VM run for one notice. It is a manual step on a real desktop,
  > recorded in #1306's PR.
- **Verify:** none beyond reading it. `docs/AGENTS.md`'s house style applies.

### 6. Commit, then the §1 break proofs (lead)

First, commit steps 1–5 as one commit with a full-sentence subject, for
example: *"A switch that leaves the shell on an older tree offers one restart
into the new one"*.

**B1–B4 and B6–B8: the fast loop.** These break the helper only, so they run
`tests/shell-session.sh` against a **scratch copy** of the helper, as step 2's
fast loop does. Nothing in the worktree is edited, and the `omarchy` package is
not rebuilt per break.

- Before each run, `diff` the copy against the fixed helper to prove the
  break landed (§1).
- Capture each run's `FAIL:` line for the PR.
- Then build the real check once on B1's copy, swapped into a scratch worktree
  (`git worktree add --detach /mnt/data/vmtest/wt-1306-break HEAD`; never
  `cp -a`, §5), to prove the derivation goes red too. Restore it with
  `git checkout HEAD -- <path>` (§5) and remove the worktree.

| break | how (in the helper copy) | must fail with |
|---|---|---|
| B1: never notify | delete the `elif … fi` branch's body (keep `rm -f`) | `FAIL: a different tree did not offer a restart into it` |
| B2: inverted test | `== "$selected_tree"` → `!= "$selected_tree"` | `FAIL: equal trees sent a notice` |
| B3: always stack | `-r "$notice_id"` → `-r 0` | `FAIL: a second switch stacked a notice instead of replacing it` |
| B4: notifier fatal | unwrap the `if notice_new=$(…); then … fi` into a bare `notice_new=$(run omarchy-notification-send …)` followed by the **same** `{ mkdir -p … } … \|\| true` save line. Drop the save as well and the id is never stored, so the earlier "stacked" case goes red instead, which proves nothing about B4 | `FAIL: a failed notifier failed the sync` |
| B6: any pid | drop `$saved_pid == "$selected_pid" &&` | `FAIL: an id saved by a previous shell was reused` |
| B7: id kept | delete the `rm -f` line (leave `:` in its place) | `FAIL: equal trees left the saved id behind` |
| B8: dev link offered | `elif [[ $selected_tree == … ]]` → `else` | `FAIL: a tree outside the store was offered a restart` |

**B5: the wiring dropped.** In `modules/home.nix`, delete the
`lib.optionalString … " --current ${omarchyPath}"` interpolation, in the
scratch worktree. Do not run `checks.options` for this; it is the top tier.
Run the pair's own `on` predicate against the vm's activation text instead:

```bash
nix eval --impure --expr '
  let
    f = builtins.getFlake (toString /mnt/data/vmtest/wt-1306-break);
    t = f.nixosConfigurations.vm.config.home-manager.users.omarchy.home.activation.nixarchySyncSession.data;
  in builtins.any (l: builtins.match ".*--current /nix/store/[a-z0-9]{32}-nixarchy-omarchy-tree( .*)?" l != null)
       (builtins.filter builtins.isString (builtins.split "\n" t))'
```

It must print `true` on the fixed tree and `false` under B5. The PR states
plainly that `checks.options` itself was not run against B5.

Also build `checks.x86_64-linux.bin-ledger` once on the fixed tree. It must
pass, which confirms the "no row change" finding. A failure there means a
`PATTERNS` group matched: read its message and add that group to `allow`.

### 7. Manual check on p620, then the PR (lead, with the owner)

This is the hole that step 5 names.

1. With CI idle, switch p620 to a generation whose tree differs from the
   running shell's. §6 applies: a switch kills any install in flight, so check
   `gh run list` first and announce on the bus.
2. The notice appears.
3. Switch again. The notice is replaced, not doubled.
4. Restart the shell **from the menu, not the toast**. Then check:
   - no stale restart notice is restored by the new shell
     (`Service.qml:317-319, 430-435` restore notices);
   - the new Quickshell's
     `tr '\0' '\n' < /proc/$(pgrep -f quickshell-wrapped)/environ | grep ^OMARCHY_PATH`
     matches `/run/current-system/etc/set-environment`;
   - `systemctl --user show-environment | grep ^OMARCHY_PATH` matches too.
5. Switch to a differing tree once more, and this time click the toast. The
   same three checks must hold.
6. If the notice never shows, or a stale one is restored, record it as a
   follow-up, not a blocker. The switch itself is unaffected.

The PR links the intent, the spec and this plan. It says:
- that steps 1–5 were the coder's;
- the spec deviations listed above;
- the failing output for B1–B4 and B6–B8, the B5 stand-in, and that
  `options` was not run against B5;
- step 7's result.

Use `Closes #1306` only if step 7 passed; otherwise use `Refs #1306` (§8).

## Tests

| command | expect |
|---|---|
| step 2's fast loop | every `PASS:` line, 7 new |
| `nix build .#checks.x86_64-linux.shell-session -L` | the same, inside the derivation |
| `nix build .#checks.x86_64-linux.bin-ledger -L` | passes, ledger unchanged except the reason |
| step 3's `nix eval` + `grep -E` | prints the `--current /nix/store/…-nixarchy-omarchy-tree` line |
| `nix build .#checks.x86_64-linux.options -L` | passes (CI, or locally with nothing in flight) |
| `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`, `shellcheck` on the helper | clean |
| B1–B4, B6–B8 (step 6) | each red with its message, then green when restored |
| B5 stand-in (step 6) | `true` fixed, `false` broken |

## Rollback

Revert the one implementation commit. Nothing is stateful except
`$XDG_RUNTIME_DIR/nixarchy/restart-notice-id`, which is per-login and is
ignored by the reverted helper. No option was added or renamed, so no user
configuration changes on rollback. The intent and spec files stay.
