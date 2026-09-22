---
status: approved
issue: 765
spec: spec/2026-09-18-765-rebuild-window.md
---

# Plan: the rebuild asks for its password through the Omarchy polkit dialog (PR 1)

## Decisions this plan carries over from the approved spec

- **Only the rebuild changes.** Two scripts run nh's switch: `nixarchy-apply`
  (`modules/apps.nix:3326`) and `omarchy-update`
  (`pkgs/omarchy/nix-bin/omarchy-update:225`). Each exports
  `NH_ELEVATION_STRATEGY="${NH_ELEVATION_STRATEGY:-/run/wrappers/bin/pkexec}"`
  before calling nh. There is no session variable and no `programs.nh`
  change. A user's own export wins, and `auto` restores sudo. A path makes nh
  "prefer" pkexec, so if the wrapper is missing nh falls back to sudo with a
  warning (nh `command.rs:337-345`) instead of failing.
- **The setuid wrapper:** `security.polkit.enablePkexecWrapper = lib.mkDefault true`
  in `modules/nixos.nix`, inside `mkIf cfg.enable`. It is off by default in
  the pinned nixpkgs (`polkit.nix:31`), and `reference` evaluates it to
  `false` today.
- **One password per switch.** A `security.polkit.extraConfig` rule returns
  `polkit.Result.AUTH_ADMIN_KEEP` for `org.freedesktop.policykit.exec` when
  all of these hold:
  - the subject is local, active and in `wheel`;
  - the `program` detail's basename is `env`. nh always elevates `env ...`
    (`command.rs:659`), and the basename is used because the resolved path of
    `env` depends on the caller's PATH.

  The rule never returns `YES`. Everything else keeps pkexec's `auth_admin`
  default.
- **Without a graphical session:** over SSH or a text console, pkexec's own
  text agent prompts, as sudo does today. With no agent and no tty,
  authentication fails, which is also what sudo does.
- **Unchanged callers:** `checks.session` (`echo n | nixarchy-apply`),
  `tests/install.nix:930` (`nixos-rebuild` as root) and the installer.
  nixarchy-pkg's bare `pkexec` export starts working once the wrapper
  exists.
- **Mode A:** every change sits under `cfg.enable`.
- **No new `checks.<name>`, so no workflow edit.**

## Steps

0. **Before anything local:** read the bus (`read_new #nixarchy-agents`), and
   check nothing is running with
   `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
   (§6). Repeat that check before every build or VM run below, and wait while
   the count is not 0. Work only in `/mnt/data/vmtest/nixarchy-765`.
1. **The assertions first, against the unchanged modules (§1).**
   `tests/options.nix`: add to the evaluated set, beside `modeAInert` (`:2159`):
   - `pkexecWrapperOn = boolToString defaultMachine.security.polkit.enablePkexecWrapper`;
   - `pkexecWrapperModeA = boolToString loaderOff.security.polkit.enablePkexecWrapper`;
   - `pkexecKeepRule = boolToString (hasInfix "org.freedesktop.policykit.exec" defaultMachine.security.polkit.extraConfig)`.

   In the shell section, next to the Mode A block (`:3729`):
   - `pkexecWrapperOn` and `pkexecKeepRule` must be `true`;
   - `pkexecWrapperModeA` must be `false`;
   - `grep -q 'NH_ELEVATION_STRATEGY' "$vm/sw/bin/nixarchy-apply"`, the same
     way the file already reads `$vm/sw/bin/nixarchy-search` (`:2989`, `vm`
     at `:1244`);
   - the same grep on `omarchy-update`, resolved through `$vm/sw/bin`.

   Each failure prints what is missing and why it matters.
   → Verify by building `checks.options` on this unchanged tree. It must fail
   on `pkexecWrapperOn`, the first check to run. Save the log to
   `$scratch/765-fail-options.log`, unpiped, and read the exit status (§1).
2. **The wrapper and the rule.** `modules/nixos.nix`, inside `mkIf cfg.enable`
   and next to the other `security` settings:
   - `security.polkit.enablePkexecWrapper = lib.mkDefault true;`
   - `security.polkit.extraConfig` with the rule. It is a string, and NixOS
     concatenates polkit `extraConfig` strings, so this is plain assignment
     and a user's rules still merge in.
   - A one-line `# Why: modules/AGENTS.md#the-rebuild-asks-through-polkit`.

   - **gpu-screen-recorder side effect.** `modules/nixos.nix:866` says that
     recorder has no fallback because its fallback is pkexec, "which wants a
     setuid helper that NixOS' polkit does not ship". This step ships that
     helper, so the fallback now exists: without its own setcap wrapper, the
     recorder asks for a password through the polkit dialog instead of
     exiting 127. Correct the comment to say so. The setcap wrapper stays the
     path that works without a prompt. Check with
     `grep -rn pkexec modules/ pkgs/` that nothing else changes behaviour
     because pkexec now exists.

   → Verify: `nix eval .#nixosConfigurations.reference.config.security.polkit.enablePkexecWrapper`
   is `true`, and the rule text appears in
   `...security.polkit.extraConfig`.
3. **The two scripts.** In `modules/apps.nix`, `nixarchy-apply`, one line
   before `nh os switch "$flake"` inside the `[yY]*)` branch. In
   `pkgs/omarchy/nix-bin/omarchy-update`, one line before line 225. Each line
   is the export above, with a one-line `# Why:` pointer. In the Nix string,
   `''${` escapes the parameter expansion.
   → Verify: both built scripts contain the export
   (`grep NH_ELEVATION_STRATEGY` on `result/sw/bin/*`).
4. **Checks green.** Rebuild `checks.options`. It must pass, and `modeAInert`
   must stay green.
   → Break each assertion separately, and prove each break landed with
   `git diff` before reading the result:
   - (a) delete the `mkDefault true`, and `pkexecWrapperOn` goes red;
   - (b) delete the rule, and `pkexecKeepRule` goes red;
   - (c) delete the export in `omarchy-update`, and its grep goes red;
   - (d) move the wrapper setting outside `mkIf cfg.enable`, and
     `pkexecWrapperModeA` goes red.

   Restore after each with `git checkout HEAD -- <file>`, from a committed
   baseline (§5: HEAD, not the index). Keep each red log.
5. **The session probe.** *Revised after drafting:* `tests/session.nix` has no
   hyprctl or `HYPRLAND_INSTANCE_SIGNATURE` setup and no `shell.json` fixture.
   The only hyprctl setup is in `tests/plugin.nix:184`, which also already
   writes the user's shell state. So the probe goes in **`tests/plugin.nix`**
   (still no new `checks.<name>`), after its shell-alive wait, reusing that
   setup:
   - Wait until the Omarchy shell's journal says
     `omarchy polkit agent registered`
     (`wait_until_succeeds` on `journalctl -b -t omarchy-shell`).
   - Start pkexec inside the Hyprland session, so the subject is the
     graphical session and not `su`:
     `su omarchy -c 'hyprctl --instance 0 dispatch exec "/run/wrappers/bin/pkexec env touch /tmp/pkexec-ok"'`.
     Use whatever `HYPRLAND_INSTANCE_SIGNATURE` or `XDG_RUNTIME_DIR` setup the
     file already uses for hyprctl calls; find it before writing.
   - `machine.wait_for_text("Authenticat")` to see the agent's dialog, then
     `machine.send_chars("omarchy\n")`.
   - `machine.wait_until_succeeds("test \"$(stat -c %U /tmp/pkexec-ok)\" = root")`.
   - Print "the rebuild's elevation reaches the Omarchy polkit dialog".

   → **Prove it red:** set `disabledPlugins = [ "omarchy.polkit" ]` in the
   test user's `shell.json` fixture. Then no agent registers, the wait on the
   journal line (or on the dialog text) times out, and the check fails.
   Capture that output, then remove the break. A second break: comment out
   `enablePkexecWrapper`. The wrapper path does not exist, the exec fails, and
   the root-owned file never appears.

   *Deviation, made during implementation:* the probe is back in
   **`tests/session.nix`**, not `tests/plugin.nix`. `plugin.nix` starts
   Hyprland with `systemd-run --uid=1000`, a service outside any logind
   session. polkit resolves both the subject (`local`, `active`) and the
   agent's registration through the logind session, so there pkexec could not
   reach the agent even on a correct build: the probe would be red for the
   wrong reason. `session.nix` logs in through the greeter, a real session,
   and already has `enableOCR = true`. It gains the three lines of hyprctl
   environment it lacked, copied from `plugin.nix:179-186`.
   Because it has no `shell.json` fixture, the first break becomes: the
   probe's command runs `true` instead of pkexec, so no dialog is drawn and
   `wait_for_text("Authenticat")` times out. That also proves the OCR match
   does not fire on something else on screen. The second break (the wrapper
   off) is unchanged.

   *Second deviation, made during implementation:* `wait_for_text("Authenticat")`
   timed out on a correct build. The journal showed `Created slice Slice
   /system/polkit-agent-helper` at that moment, so the dialog was up, but OCR
   read only the desktop behind it (this theme OCRs badly; see the greeter
   block). The probe now waits for a `polkit-agent-helper@*` unit instead. Only
   a polkit agent starts that helper, and only once it is asking for the
   password, so it is the same fact, read deterministically. The `true` break
   still proves it: no pkexec, no helper, timeout. The dispatch also changed
   to `hl.dsp.exec_cmd(...)`: this Hyprland takes Lua expressions.
   Run `checks.session` only when `gh run list` shows 0 in flight. It is a
   booted VM.

   The probe does **not** prove the spec's "one dialog per switch" (polkit
   keeping the authorisation across nh's three elevated calls): it runs pkexec
   once. That stays a by-hand check in step 8, and a hole recorded in
   `tests/AGENTS.md` (§3). The dialog text is matched on `Authenticat`, which
   both the agent's default message and pkexec's own action message contain;
   OCR at the VM's resolution is proven only by the red/green pair above.
6. **Docs.**
   - `modules/AGENTS.md`: a section "The rebuild asks through polkit",
     covering why pkexec and not askpass, why `KEEP` and not `YES`, why the
     rule matches on `env`'s basename, the SSH text fallback, and the
     `NH_ELEVATION_STRATEGY=auto` override.
   - `docs/manual/other-packages.md`: one paragraph on the dialog and the
     override.
   - `tests/AGENTS.md`: a named hole (§3). No VM drives a full nh switch, so
     "one password per switch", polkit retention across nh's three elevated
     calls, is checked by hand on real hardware only.
7. **Format and lint:** `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`
   and `nix run nixpkgs#deadnix -- --fail .`, all clean.
8. **By hand, on the owner's machine**, after switching to this branch. The
   switch itself is announced on the bus first, and never runs while CI
   installs are in flight on p620 (§6):
   - one Install > Apply shows exactly one Omarchy dialog and switches;
   - `nixarchy apply` over SSH prompts as text;
   - `NH_ELEVATION_STRATEGY=auto nixarchy apply` uses sudo.

   Record all three in the PR. If more than one dialog appears, retention did
   not hold (the spec's Risk 1). Report it, and do not widen the rule.
9. **Commit and PR.** `git add` every file (a flake sees only tracked files,
   §5). There is one commit whose subject is a full sentence (§8, no `wip:`).
   Fill in the PR template:
   - link `intent/`, `spec/` and `plan/`;
   - the failing outputs from steps 1, 4a-d and 5;
   - the hand results from step 8;
   - "Refs #765", not "Closes", because PRs 2-5 remain.

   Before pushing, check `gh pr view --json mergeable` against a freshly
   rebased `main` (§9).

## Tests

| check | expected green | §1 break, and the expected red |
|---|---|---|
| `nix build .#checks.x86_64-linux.options --print-build-logs` | passes, `modeAInert` included | no `mkDefault true` gives `pkexecWrapperOn`; no rule gives `pkexecKeepRule`; no export gives the script grep; the setting outside `cfg.enable` gives `pkexecWrapperModeA` |
| `nix build .#checks.x86_64-linux.session --print-build-logs` | the dialog appears, the password is accepted, and `/tmp/pkexec-ok` is owned by root | `true` in place of pkexec means no dialog, and a timeout; the wrapper off means no root-owned file |
| `nix eval ...security.polkit.enablePkexecWrapper` on `reference` | `true` | `false` before step 2 |
| hand test on the owner's machine | one dialog per Apply; text over SSH; sudo with `auto` | none (manual; the hole is recorded in `tests/AGENTS.md`) |
| `nix fmt -- --ci`, statix, deadnix | clean | none |

Never pipe a build whose exit status is the result (§1). Run the scripts
under bash (§1).

## PR 2 — approved 2026-09-19

*Revision:* PR 1 (#776) is stepped above and approved. This section steps PR 2
only, which is why the frontmatter is back to `draft`. The branch is
`feat/765-pr2-apply-flags`, stacked on #776. When #776 squash-merges, cherry-pick
this branch's own commits onto `main` (AGENTS.md §8).

**Scope** (the spec's outline, item 2):
- `nixarchy-apply` takes its two answers as flags;
- the failure message stops claiming that nothing changed.

Nothing else changes. The interactive prompts stay for a person at a
terminal, and EOF on stdin still declines.

**Flag semantics:**
- `--no-preview` skips the "Preview in a VM first?" offer.
- `--yes` answers "Build and switch now?" with yes. It does not imply
  `--no-preview`, because a caller that has a terminal may still want the offer.
- Anything else prints a usage line and exits 2. An unknown flag must never
  mean "switch".
- `nixarchy apply` forwards `"$@"` already (`modules/apps.nix`, the dispatcher's
  `apply)` arm), so both spellings work.

**Callers** (from grep):
- 7 menu and enable paths launch it with no arguments. Unchanged.
- `checks.session` (`tests/session.nix:206`) runs `echo n | nixarchy-apply`.
  Unchanged; it keeps proving "EOF/`n` declines".
- `tests/demo/default.nix:402`. Unchanged.
- `tests/apply-staging.nix` and `tests/apply-imports.nix` run the real binary
  with a stub `nh`. These are where the flags get tested.
- nixarchy-pkg's adapter (`bin/nixarchy-pkg:937-955`, issue nixarchy-pkg#19)
  pipes `printf 'n\ny\n'`. Where `nixarchy-preview` is absent, the preview
  question is never asked (`apps.nix:3311`), so its `n` answers the switch and
  declines it. After this PR it should call `nixarchy-apply --yes --no-preview
  </dev/null`. That change is upstream's to make; we file nothing there unless
  the owner asks (§11).

### Steps

1. **Tests first, against today's script (§1).** In `tests/apply-staging.nix`,
   make the stub `nh` record each call (`echo "$@" >> $PWD/nh.calls`) and exit
   with `$NH_STUB_RC` (default 0).
   *Deviation, made during implementation:* the stub is an **exported bash
   function**, not a file on `PATH`. `writeShellApplication` prepends its
   `runtimeInputs`, so the real `nh` shadowed the old stub file. The first
   green attempt at (a) ran the real nh and exited 1. The existing comment
   ("A fake nh") had never been true; it didn't matter while no case answered
   yes. Bash resolves functions before `PATH`. Add three cases after the existing ones:
   - (a) `nixarchy-apply --yes --no-preview </dev/null`: `nh.calls` is non-empty
     and the exit is 0;
   - (b) `nixarchy-apply </dev/null`: `nh.calls` stays empty (EOF still
     declines);
   - (c) `nixarchy-apply --frobnicate`: exit 2, and `nh.calls` stays empty.

   → Verify: build `checks.apply-staging` against unchanged `modules/apps.nix`.
   **(a) and (c) must fail**; today the script ignores arguments, so (a) never
   switches and (c) exits 0. Keep the red log. (b) passes before and after, and
   it guards the EOF rule.
2. **`modules/apps.nix`, `nixarchy-apply`:** a `while [ $# -gt 0 ]; case` at the
   top that sets `yes=1` and `nopreview=1`, and does `*) usage; exit 2`. The
   preview block becomes `if [ -z "$nopreview" ] && command -v
   nixarchy-preview ...`. The switch question is skipped when `yes=1`
   (`reply=y`). Nothing else moves. Carry both flags in the 1-3 line comment
   above the reads that explains EOF, not in a new block (§7).

   → Verify: `checks.apply-staging` is green; (a), (b) and (c) all pass.
3. **The failure message** (`apps.nix:3337`). Replace "Nothing changed on this
   machine." with:
   ```
   The rebuild failed (exit $rc). The log above says where.
     If it stopped while building, the running system is unchanged.
     If it stopped while activating, it may be partly switched --
     'nixarchy rollback' lists the earlier generations to go back to.
   ```
   The two hint lines below it (`nixarchy app remove`, `... | nixarchy
   explain`) stay. Why no claim: nh runs `switch-to-configuration test`, then
   sets the profile, then runs `switch-to-configuration boot`
   (`nh-nixos/src/nixos.rs:383,428,435`, nh 4.4.2). A failure after the first
   of those leaves the live system changed. `nixarchy rollback` is a picker
   (`pkgs/omarchy/nix-bin/nixarchy-rollback`, `--list`) and never rolls back on
   its own, so pointing at it is safe in both cases.

   → Verify: add case (d) to `tests/apply-staging.nix`. With `NH_STUB_RC=3`,
   `--yes --no-preview` exits 3, the output contains `nixarchy rollback`, and it
   does **not** contain `Nothing changed`. **Red first:** run it against
   step 2's tree before step 3 lands; it fails on "Nothing changed".
4. **Docs:** `docs/manual/other-packages.md`, where it describes Apply, gets one
   line on the two flags "for scripts and panels". `modules/AGENTS.md` gets no
   new section: the EOF rationale already lives in the script comment.
5. **Lint:** `nix fmt -- --ci`, statix, deadnix.
6. **Rebase and PR:**
   - Once #776 has merged, cherry-pick onto `main`.
   - Push, and open a PR with the template: link intent, spec and plan, paste
     the red outputs from steps 1 and 3, `Refs #765`.
   - The PR notes, for the owner, the one-line change nixarchy-pkg can then
     make (`--yes --no-preview </dev/null`).

### Tests

| check | what it proves | red first by |
|---|---|---|
| `checks.apply-staging` (a) | `--yes --no-preview` switches with no stdin | running it against today's script |
| `checks.apply-staging` (b) | EOF still declines | none needed; green before and after, it guards a rule |
| `checks.apply-staging` (c) | an unknown flag exits 2 and never switches | running it against today's script (exits 0) |
| `checks.apply-staging` (d) | failure exits with nh's code, points at rollback, makes no "nothing changed" claim | running it before step 3 |
| `checks.session` | `echo n \| nixarchy-apply` still declines in a real session | unchanged; CI runs it |

`checks.apply-staging` is cheap: a `runCommand` with a stub `nh`. It is
already wired (`flake.nix:1819`). No workflow names it; `build.yml`'s `omarchy`
job builds it in its catch-all step, "Build every check no other job claims".
So there is no new `checks.<name>` and no workflow edit (§4). Build it under bash, never piped (§1).

## PR 3 — approved 2026-09-19

*Revision:* PRs 1 (#776) and 2 (#778) are merged. This section steps PR 3 only,
which is why the frontmatter is back to `draft`. Branch:
`feat/765-pr3-supervised-rebuild`, from `main`.

**Scope** (the spec's outline, item 3): the rebuild can run as a supervised
`systemd-run --user` unit named `nixarchy-rebuild`, with its output in the
user journal. The future panel (PR 5) then only has to *view* the unit, and a
shell restart or a closed window can't kill a switch halfway.

Nothing a user runs today changes in this PR. The menu rows still open the
terminal until PR 5 swaps them, and `nixarchy apply` at a terminal behaves
exactly as before.

**Decisions:**
- **`--detach`**, the same word `nixarchy vm run --detach` uses (#762). It
  requires `--yes`, because a unit has no stdin to answer a question with.
  `--detach` alone exits 2.
- **What it does:** `nixarchy-apply --detach --yes` re-runs itself as
  `systemd-run --user --unit=nixarchy-rebuild --collect
  -p RemainAfterExit=yes -p LogRateLimitIntervalSec=0
  --setenv=NIXARCHY_FLAKE=… --setenv=XDG_CONFIG_HOME=… --
  <itself> --yes --no-preview`, prints where to follow it
  (`journalctl --user -fu nixarchy-rebuild`), and exits 0 once the unit
  exists. Rate limiting is off because a nix build log is bursty and
  journald would otherwise drop lines, which is the one log a failure needs.
- **`--no-nom` when stdout is not a terminal.** nom draws with escape codes,
  which are unreadable in a journal. At a terminal nothing changes.
- **State lives in the unit.** `ActiveState`/`SubState`, `Result` and
  `ExecMainStatus` are what a viewer reads, and `RemainAfterExit` keeps the
  result after the process exits.
- **One at a time.** A detached start while the unit is running refuses:
  exit 3, "a rebuild is already running", and the journalctl line. A
  *finished* unit, still present because of `RemainAfterExit`, is cleared
  (`systemctl --user stop`, or `reset-failed`) before the new start.
  Otherwise `systemd-run` refuses with "Unit already exists".
- **No NoNewPrivileges, no sandboxing on the unit.** Elevation goes through
  the setuid pkexec wrapper, which `NoNewPrivileges` would break (Codex's
  review of #765).
- **Cancellation: none in this PR.** Stopping the unit sends SIGTERM to nh,
  which could land mid-activation. No verb here should make that one
  keypress away. PR 5 decides whether a panel offers cancel, and only while
  the log shows the build phase. The docs say not to stop the unit by hand
  once it has passed "Activating".

### Steps

1. **Prove the elevation path first (the gate).** A user unit runs in
   `user@.service`, outside the login session's scope. polkit may then find
   no session for pkexec's subject and never reach the Omarchy agent. If so,
   this whole design is wrong, so it is tested before anything is built on it.
   `tests/session.nix`, next to #776's pkexec probe (same logind session, and
   the same `polkit-agent-helper@*` wait and password entry): start
   `systemd-run --user --wait --collect -- /run/wrappers/bin/pkexec env touch /tmp/unit-pkexec-ok`
   as the session user, wait for the agent's helper unit, type the password,
   and assert that `/tmp/unit-pkexec-ok` is owned by root.
   → Verify: `checks.session` through `heavy-build.sh`.
   **Red first:** the same probe with no password typed times out with no
   root-owned file. **If the green run fails** (polkit refuses the unit's
   subject), stop and revise this plan before step 2. The fallback to weigh
   is `systemd-run --user --scope`, which keeps the caller's session but
   doesn't survive a shell restart. The owner decides.
2. **Tests for the new path, against today's script (§1).**
   `tests/apply-staging.nix` adds `systemd-run` and `systemctl` as exported
   bash functions, the same pattern as the `nh` stub (`:60`), because
   `writeShellApplication` puts real tools first on `PATH`. They record argv
   to files, and `systemctl show` prints what `$UNIT_STATE` says. New cases:
   - (e) `--detach --yes </dev/null`: `systemd-run` was called with
     `--unit=nixarchy-rebuild`, `-p RemainAfterExit=yes` and `--collect`, and
     re-invokes with `--yes --no-preview`. `nh` was not called in-process.
     Exit 0.
   - (f) `UNIT_STATE=running` with `--detach --yes`: exit 3, the output says
     "already running", and `systemd-run` was not called.
   - (g) `UNIT_STATE=exited` (a finished unit): it is cleared, then
     `systemd-run` is called.
   - (h) `--detach` without `--yes`: exit 2, no `systemd-run`.
   - (i) `--yes --no-preview </dev/null` with stdout not a terminal (always
     true in the sandbox): `nh.calls` contains `--no-nom`.
   → Verify: build `checks.apply-staging`. **(e) through (i) all fail** on
   today's script (`--detach` is an unknown flag and exits 2, and there's no
   `--no-nom`). Keep the red log.
3. **`modules/apps.nix`, `nixarchy-apply`:**
   - `--detach` in the existing flag loop (`:3175`).
   - A detach block right after it: the state check, the clear, `systemd-run`
     with `--setenv` for `NIXARCHY_FLAKE`, `XDG_CONFIG_HOME` and
     `NH_ELEVATION_STRATEGY` (a user unit doesn't inherit the caller's
     environment), and the "follow it with" line, then `exit`.
   - `nomflag` set from `[ -t 1 ]` and passed to nh.
   - `pkgs.systemd` added to `runtimeInputs` (pkgs/AGENTS.md: an undeclared
     command is a runtime failure no build catches).
   - Comments stay 1-3 lines at the lines they protect (§7).

   → Verify: `checks.apply-staging` green, (a) through (i). `checks.session`
   is unchanged: `echo n | nixarchy-apply` still declines.
4. **A real detached apply in the session VM** (after step 1 passes):
   `checks.session` runs `nixarchy-apply --detach --yes` against the VM's own
   flake with no change selected. It waits for the unit's `Result=success`,
   asserts `journalctl --user -u nixarchy-rebuild` holds nh's output, then
   asserts a second `--detach` *while* the first is running exits 3. Because
   the switch is a no-op, the time is spent evaluating, not building.
   **Red first:** point the unit at a flake path that doesn't exist, so
   `Result=exit-code` and the assertion on `success` fails with the journal
   excerpt.
5. **Docs:**
   - `docs/manual/other-packages.md`: one paragraph on `--detach`, and how to
     follow the rebuild.
   - `modules/AGENTS.md`: under the existing "the rebuild asks through
     polkit" anchor, add three lines on why it is a unit, why rate limiting
     is off, and why there's no cancel verb.
6. **Lint:** `nix fmt -- --ci`, statix, deadnix.
7. **PR:** rebase onto `main`. Link intent, spec and plan. Paste the red
   outputs from steps 1, 2 and 4. `Refs #765`, not Closes, because PRs 4 and 5
   remain.

### Tests

| check | what it proves | red first by |
|---|---|---|
| `checks.session`, step 1 | pkexec from a user unit reaches the Omarchy agent and authenticates | no password typed: timeout, no root-owned file |
| `checks.apply-staging` (e)-(i) | detach starts the right unit, refuses while one runs, clears a finished one, needs `--yes`; `--no-nom` off a terminal | all fail on today's script |
| `checks.session`, step 4 | a real detached apply completes, logs to the journal, and a concurrent one is refused | nonexistent flake: `Result=exit-code` |
| `checks.apply-staging` (a)-(d), `checks.session` `echo n` | PR 2's behaviour is unchanged | unchanged, green before and after |

No new `checks.<name>`, so no workflow edit (§4). Heavy builds go only through
`/mnt/data/vmtest/heavy-build.sh`, never piped (§1).

### Rollback

Revert the PR. `--detach` goes away, and nothing yet depends on it (PR 5 is
its first user). A unit left over from a run survives until logout, or until
it is stopped by hand. It holds no state beyond its log.

### Deviations found while implementing PR 3

- **No `--collect`.** It was measured on a real systemd user manager before
  shipping. With `--collect`, a unit that fails is unloaded at once and then
  reports `LoadState=not-found … Result=success`. Without it, the unit stays
  `failed`, `Result=exit-code`, and `reset-failed` clears it. A success stays
  loaded either way, because of `RemainAfterExit`. So the unit is started
  without `--collect`, and the "clear a finished unit" step (already `stop`
  plus `reset-failed`) covers both outcomes. Case (e) now asserts that
  `--collect` is **absent**, so bringing it back fails the check.
- **Step 4 runs against real systemd, without a real rebuild.** The session VM
  is offline and cannot evaluate its own flake, so a successful detached
  rebuild can't be staged there. Instead:
  - a detach at a missing flake proves the unit is created, keeps
    `Result=exit-code`, and logs to the journal;
  - a real unit of the same name (a `sleep`) proves a second detach exits 3.
  A successful detached rebuild is the by-hand check on real hardware, and the
  gap is recorded in `tests/AGENTS.md` (§3).
- **Case (h) could not fail on the old script**, since `--detach` was an
  unknown flag and exited 2 anyway. It was proven instead by removing the new
  "needs `--yes`" guard, which it then catches ("exited 0 (want 2)").

## PR 4 — approved 2026-09-19, merged as #873

*Revision:* PRs 1-3 (#776, #778, #805) are merged. This section steps PR 4 only,
which is why the frontmatter is back to `draft`. Branch
`feat/765-spinner-opens-rebuild-log`, cut from `main`.

**Scope** (the spec's outline, item 4): clicking the bar spinner opens the log
of the thing that is actually rebuilding.

### The spec's wording is wrong, and this is the correction

Spec item 4 says `switch-indicator.qml:96` changes to
`journalctl --user -fu nixarchy-rebuild`. Applied literally, that is a
regression for two of the three cases the spinner covers.

The spinner's visibility comes from a process match, and the file states why
that was chosen over a state file:

> Deliberately not a state file written by `nixarchy-apply`: a rebuild the user
> typed themselves is exactly as worth showing as one the menu started, and a
> file only knows about the second.

So it lights for three things, and only one of them has a user unit:

| what is running | has a `nixarchy-rebuild` unit? |
| --- | --- |
| `nixarchy-apply --detach` (#805) | yes |
| Install > Apply in a floating terminal | **no** |
| a rebuild typed by hand | **no** |

Pointing the click unconditionally at the user unit swaps a *wrong* log for an
*empty* one in exactly the cases the process match exists to cover. The spec
wrote item 4 before PR 3 existed, when the unit was the only imagined path.

### What this PR does instead

Choose the log from what is running: if the unit is active, follow its journal;
otherwise keep today's target. The right log when the unit is there, today's
behaviour otherwise, and no case gets a blank window -- which is the failure
this item exists to remove.

`systemctl --user -q is-active` rather than parsing `ActiveState`: it is the
documented predicate, and it exits non-zero for both "inactive" and "no such
unit", which want the same branch.

### Steps

**1. Replace the click handler** in `pkgs/omarchy/switch-indicator.qml`, with
the reason at the line -- two or three lines on why the branch exists, not the
table above (AGENTS.md §7).

→ verify by §1, both directions:

  a. **The unit case.** With the unit active, the command must resolve to the
     user journal. Provable with no desktop: start a transient unit of that
     name, run the branch, and assert which side it takes. Break it by
     inverting the predicate and watch it choose the wrong log.
  b. **The no-unit case.** With no such unit, it must fall back to today's
     target. Break it by dropping the fallback and watch the command exit
     non-zero having opened nothing -- the blank window this PR exists to
     prevent, reproduced on purpose.

**2. Keep the QML parseable.** `tests/qml.nix:68` already parses this file with
`qmllint`; the change must not break it.

→ verify by `nix build .#checks.x86_64-linux.qml`.

### Tests

```
nix build .#checks.x86_64-linux.qml --print-build-logs
# the branch line, by hand, in both states, per §1 above
nix fmt -- --ci, statix, deadnix, over `.`
```

`checks.session` boots a real desktop and already asserts the
`nixarchy-rebuild` unit's journal, so that is where an end-to-end assertion
would live. This PR does **not** add one: the handler runs in the shell's QML
and nothing in the suite drives a bar click today. The gap is named here rather
than papered over, and belongs in `tests/AGENTS.md` if it outlives this PR
(§3).

## PR 5 — draft, awaiting approval

*Revision:* PRs 1-4 (#776, #778, #805, #873) are merged. This section steps PR 5
only, which is why the frontmatter is back to `draft`. Branch
`feat/765-rebuild-panel`, cut from `main`.

**Scope** (the spec's outline, item 5): Install > Apply and the six "queued"
notifications open a Quickshell panel over the supervised unit instead of a
floating terminal.

### The spec's install path is wrong, and this is the correction

Spec item 5 says the panel is "a first-party Quickshell panel in
`pkgs/omarchy/`, installed like `switch-indicator.qml`
(`default.nix:1857`)". `switch-indicator.qml` is not a panel. It is a bar
**indicator**, and `default.nix:1864` says what that means:

> An indicator is a bare .qml in `indicators/` -- no manifest -- picked up by
> name from the list in `Indicators.qml`.

A panel is a plugin: a directory with a `manifest.json` at its root, validated
at build time by `omarchy-plugin-validate` (`modules/home.nix:395`) and
discovered by `PluginRegistry.qml`'s scan. Installed the way the spec says, a
panel would carry no manifest, never be scanned, and never appear — and
`nixarchy-plugin nixarchy.rebuild` would take its "not installed on this
machine" branch. The spec wrote item 5 before any panel shipped; eight have
since, and none of them takes that route.

### Where the source lives — the one open question

Every panel nixarchy installs today comes from an **external flake input**,
copied and adjusted by a `runCommand` in `modules/home.nix:269-300`:

| panel | source |
| --- | --- |
| `nixarchy.pkg` | `inputs.nixarchy-pkg` |
| `nixarchy.podman` | `inputs.nixarchy-podman` |
| `nixarchy.distrobox` | `inputs.nixarchy-distrobox` |
| `olafkfreund.gitlab-pipelines` | `inputs.nixarchy-gltui` |
| `olafkfreund.github-actions` | `inputs.nixarchy-ghtui` |
| `nixarchy.herdr` | `inputs.nixarchy-herdr` |

There is no in-repo panel source in this tree, so PR 5 sets a precedent either
way. **This plan steps option A and needs the owner's word before step 1.**

- **Option A — in this repo**, `pkgs/rebuild-panel/` (`manifest.json` plus its
  QML), added to `defaultPluginSet` with `src = ./../pkgs/rebuild-panel`. The
  panel is inseparable from `nixarchy-apply --detach`, which is this repo's
  script: a version skew between them is a broken panel, and one repo cannot
  skew against itself. It also keeps `checks.qml` and `checks.session` able to
  see the source, which they cannot do for an input.
- **Option B — a `nixarchy-rebuild` repo** as a ninth input, matching every
  existing panel. Consistent, and it lets the panel release on its own; the
  cost is that the unit contract (`nixarchy-rebuild`, `RemainAfterExit`, the
  journal identifier) becomes a cross-repo promise with nothing asserting both
  ends, and creating a repository is a §11 decision.

The rest of this section is written against option A. Under option B, steps 1-3
move to the other repo and step 4 becomes a flake input plus a `defaultPluginSet`
entry; the menu work, the tests and the docs are unchanged.

### Decisions

- **The panel's id is `nixarchy.rebuild`**, and the row opens it with
  `nixarchy-plugin nixarchy.rebuild` (`pkgs/nixarchy-plugin.nix`), never a bare
  `omarchy-shell shell toggle`. That helper already handles the two cases a raw
  toggle gets wrong: not installed, and installed but disabled, both of which
  exit 0 having done nothing.
- **The row only opens the panel.** An earlier draft of this decision had the
  row start the unit *and* open the panel through a wrapper, which contradicts
  the next decision: if the panel asks first, there is nothing to start yet.
  So `install.apply` is exactly `nixarchy-plugin nixarchy.rebuild`, no wrapper,
  and the panel's button is the only thing that runs
  `nixarchy-apply --detach --yes`. A rebuild already running is what the panel
  shows when it opens, which is what the user wanted to see anyway.
- **Apply keeps asking.** Today Install > Apply opens a terminal that offers a
  VM preview and then asks "Build and switch now?". `--detach --yes` answers
  both. Making the menu row a one-click irreversible switch is a behaviour
  change the spec did not ask for, so **the panel asks**: it opens in a
  `confirm` state with what will be built, and starts the unit only on the
  button. `--no-preview` is implied for the detached path; the Preview row
  (`install.preview`) is untouched and still offers the VM.
- **Read-only over the unit.** The panel shells out to nothing but
  `systemctl --user` and `journalctl --user`. No second source of truth: state
  is `ActiveState`/`SubState`/`Result`/`ExecMainStatus`, exactly as PR 3
  decided, and `RemainAfterExit` is what keeps a finished result readable.
- **The log tail is bounded.** `journalctl --user -u nixarchy-rebuild -o cat -f
  -n 200`, with the panel holding at most 2000 lines. A nix build log is
  unbounded and a QML `ListModel` that grows with it will take the shell down
  with it.
- **Closing detaches; reopening reattaches.** The panel holds no state of its
  own, so this falls out of reading the unit rather than being implemented.
  Nothing is written to `shell.json` (see `distroboxPanel`: a manifest default,
  never a settings write).
- **No cancel verb**, carried forward from PR 3: SIGTERM to nh can land
  mid-activation, and a panel button is one keypress. The panel shows how to
  stop it by hand and says not to once the log has passed "Activating".
- **On failure:** Copy log (the full `journalctl --user -u nixarchy-rebuild`,
  not the visible tail) and Open full log in terminal
  (`omarchy-launch-floating-terminal-with-presentation journalctl --user -u
  nixarchy-rebuild`). The terminal does not disappear; it stops being the
  *default*.
- **Mode A:** the panel is a `defaultPluginSet` entry, which already resolves to
  nothing unless `osConfig.programs.nixarchy.enable` (`modules/home.nix:377`).
  No new gating is needed and none is added.

### Territory (§9)

`modules/apps.nix`'s menu rows were named on the bus as a collision-prone file.
Check `gh pr list` and the bus for open work on the `install.*` rows before
step 5, and rebase rather than merge.

### Deviations found while implementing PR 5

- **The manifest is `bar-widget`, not `panel`.** Step 1 below said "a panel
  kind, and no bar widget". `omarchy-shell shell toggle` reaches
  `shell.toggle()` -> `shell.summon()` -> `shell.bar.summonBarWidget(id)`
  (`shell.qml:1169`), and `summonBarWidget` resolves the id with
  `findPanelWidget` against the *instantiated* bar widgets (`Bar.qml:745`).
  What `nixarchy-plugin <id>` opens is a bar widget's panel. The validator does
  carry a `panel` kind, but that is for the shell's own built-ins
  (`shell/plugins/panels/clock`, `weather`). Built as the step first said, the
  plugin would validate, install, enable, and log `summon: no live bar widget
  for:` -- the "installs and does nothing" failure the validator's own comment
  is about. The manifest follows the eight shipping panels:
  `kinds: ["bar-widget"]`, `entryPoints.barWidget = "Panel.qml"`.
- **A default plugin gets a permanent bar icon, and that was not anticipated.**
  `modules/home.nix:1675` enables each default id with
  `omarchy-plugin-enable "$id" right`, so the panel takes a ninth slot in the
  bar -- beside `SystemSwitch.qml`, the rebuild spinner #873 just taught to open
  the rebuild's log. Two bar items about rebuilding. It is forced by the
  mechanism above: a widget that is not in the bar cannot be summoned.
  **Decision taken, after finding the precedent:** the widget is in the bar so
  it can be summoned, and *draws nothing* unless a rebuild is running --
  `visible: RebuildState.active || root.opened` on its `BarIconButton`. This is
  not invented here: `nixarchy.distrobox` ships `hideWhenEmpty`, which hides its
  own icon the same way, and a hidden-but-instantiated widget still answers
  `findPanelWidget`, so `nixarchy-plugin` opens it either way. So there is no
  ninth permanent icon, `SystemSwitch.qml` is untouched, and #873 is not
  reverted. The two do overlap while a rebuild runs -- the indicator's spinner
  beside the panel's icon -- and merging them is a follow-up, in its own PR with
  its own red/green pair, not a change made on the day #873 merged.
- **The log tail is capped at 500 lines, not the 2000 the decisions said.**
  `LogView.qml` in the distrobox panel caps at 400, and matching the house
  number is worth more than the round one I picked before reading it. A failing
  nix build's useful context is its last screenful; the full log is one button
  away and is what Copy log copies.

### Steps

0. **Before anything local:** read the bus, and check nothing is in flight with
   `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
   (§6). Repeat before every build. Work in `/mnt/data/vmtest/nixarchy-765-pr5`.

1. **The manifest, and the assertion that it loads.** `pkgs/rebuild-panel/manifest.json`
   with id `nixarchy.rebuild`, `kinds: ["bar-widget"]` and
   `entryPoints.barWidget = "Panel.qml"` (see the deviation above).
   → **Red first (§1):** add the `defaultPluginSet` entry pointing at the
   directory *before* the manifest is valid — a `manifest.json` missing its
   `id` — and build `nixosConfigurations.reference.config.home-manager...`
   through `checks.options`. `validatedPlugins` must fail with
   `omarchy-plugin-validate`'s message. Keep that log; it proves the build-time
   validation actually covers this new plugin rather than being assumed to.
   Then write the real manifest and watch it pass.

2. **The QML.** `pkgs/rebuild-panel/Panel.qml` (plus whatever the manifest
   names): the `confirm` state, then step, elapsed time, the bounded tail, and
   the two failure buttons.
   → Verify: `nix build .#checks.x86_64-linux.qml`. **That check does not see
   this file yet** — `tests/qml.nix:68` names files explicitly. Add the new
   QML to it in this step, and prove the addition works by introducing a syntax
   error and watching `qmllint` fail. A check that does not name the file is a
   green light (§1, §4).

3. **The unit read, tested without a desktop.** The panel's state mapping
   (which of `ActiveState`/`Result`/`ExecMainStatus` means running, succeeded,
   failed) is shell-level, not QML-level: put it in one place the panel calls
   and `tests/apply-staging.nix` can run with the `systemctl` stub PR 3 already
   added (`--collect`'s absence and the `UNIT_STATE` stub are there).
   Cases: running → running; a `failed` unit with `Result=exit-code` → failed,
   with nh's code; `exited` with `Result=success` → succeeded; no such unit →
   idle.
   → **Red first:** write the four cases against a mapping that returns "idle"
   unconditionally, and watch three of them fail.

4. **Ship it.** `defaultPluginSet.rebuild = { id = "nixarchy.rebuild"; src = ...; }`
   in `modules/home.nix:1555`, beside the others, with the 1-3 line reason at
   the entry (§7).
   → Verify: `checks.options` — assert the id is in the resolved default ids on
   an enabled machine and absent under Mode A, the way the existing plugin
   assertions do. **Red first:** assert before the entry exists.

5. **The seven call sites**, all in `modules/apps.nix`:
   - `install.apply` (`:658`) → the wrapper from the decisions above.
   - the six notification actions (`:1368`, `:1475`, `:1518`, `:1688`, `:1785`,
     `:2437`), each `--exec omarchy-launch-floating-terminal-with-presentation
     nixarchy-apply` → the same wrapper. Their body text ("Click here, or
     Install > Apply changes, to run nixos-rebuild") still reads correctly.
   → Verify: `checks.menu-verbs`. Its `pluginrows` floor is `-ge 8`
   (`tests/menu-verbs.nix:175`) so a ninth row passes, but **its comment names
   the eight (`:173`)** — add Rebuild to that list in the same edit, or the next person
   reads a stale inventory. **Red first:** point the row at
   `nixarchy-plugin nixarchy.rebuil` (a typo) and watch the id scan fail.
   - Also `grep -rn nixarchy-apply tests/demo/` (§4: the demo scenes are
     `packages`, no workflow builds them, and a changed user-facing path
     rots there silently).

6. **The session probe.** `tests/session.nix` already boots a real desktop,
   already drives the `nixarchy-rebuild` unit (PR 3, step 4) and already has
   `enableOCR = true`. Add: with the unit running, `nixarchy-plugin
   nixarchy.rebuild`, then assert the panel is up.
   → **Do not assert it by OCR.** PR 1's deviation recorded that this theme
   OCRs badly and `wait_for_text` timed out on a correct build. Ask the shell
   over IPC instead (`omarchy-shell`, the route `tests/plugin.nix` uses), which
   is the same fact read deterministically.
   → **Red first:** disable the plugin in the test user's `shell.json` — then
   `nixarchy-plugin` takes its "turned off" branch, exits 1, and no panel
   appears.
   → Run `checks.session` only when `gh run list` shows 0 in flight (§6). It is
   a booted VM.

7. **The hole, named (§3).** No check drives a *click* in the panel, so the
   two failure buttons and the confirm button are covered by hand only. Record
   that in `tests/AGENTS.md` beside PR 3's entry, rather than implying the
   session probe covers the panel's behaviour. It covers only that it opens.

8. **Docs.**
   - `docs/manual/other-packages.md`: the Apply row now opens a panel; the
     terminal is still there behind Open full log.
   - `modules/AGENTS.md`, under the existing "the rebuild asks through polkit"
     anchor: why the panel reads the unit rather than keeping state, and why
     there is no cancel button.
   - `pkgs/AGENTS.md`: a first-party panel now lives in this repo — say why
     (option A's reasoning above), so the next panel author knows whether to
     follow it or take an input.
   - If the README or `docs/llms.txt` carry a plugin count, `readme-counts.sh`
     may need its word table taught a new number (§4).

9. **Format and lint:** `nix fmt -- --ci`, statix, deadnix, all clean. Note
   §5: no heredoc inside an indented Nix string.

10. **By hand, on the owner's machine**, announced on the bus first and never
    while CI installs are in flight (§6):
    - Install > Apply opens the panel, asks, and on the button rebuilds with
      exactly one polkit dialog;
    - closing the panel and reopening it reattaches to the running unit;
    - a failed rebuild shows the code, and both buttons work;
    - enabling an app and clicking its notification opens the same panel.

11. **Commit and PR.** `git add` every file (§5). One commit, subject a full
    sentence (§8). Paste the red outputs from steps 1, 2, 3, 4, 5 and 6, and
    the hand results from step 10. **`Closes #765`** — this is the last PR in
    the track, so the issue closes here (§8: one keyword, no qualifier).

### Tests

| check | what it proves | red first by |
|---|---|---|
| `checks.options`, `validatedPlugins` | the manifest is valid and the plugin builds | an `id`-less manifest: `omarchy-plugin-validate` fails |
| `checks.options`, resolved ids | `nixarchy.rebuild` is installed on an enabled machine, absent under Mode A | asserting before the `defaultPluginSet` entry exists |
| `checks.qml` | the panel's QML parses, **and the check names the file** | a syntax error in it |
| `checks.apply-staging` | the unit-state mapping reads running / succeeded / failed / idle correctly | a mapping that always returns idle: three of four fail |
| `checks.menu-verbs` | every row opens an id this machine installs | a typo'd id |
| `checks.session` | the panel opens over a running unit, via IPC not OCR | the plugin disabled in `shell.json` |
| by hand (step 10) | the buttons, the confirm, reattach, one dialog | none — the hole is recorded in `tests/AGENTS.md` (§3) |

Never pipe a build whose exit status is the result, and run scripts under bash
(§1). Heavy builds go through `/mnt/data/vmtest/heavy-build.sh`.

### Rollback

Revert the PR. The seven call sites go back to
`omarchy-launch-floating-terminal-with-presentation nixarchy-apply`, which is
unchanged by this PR and still works; `--detach` stays, unused again as it was
between PRs 3 and 5. The plugin disappears from `defaultPluginSet`, so the next
rebuild removes it from every home. A panel left open at the moment of the
revert is a window over a unit that still exists; it holds no state, and
closing it loses nothing.

## Rollback

Revert the PR's commit. The scripts lose the export, so nh auto-selects sudo
again. The wrapper and the rule go, and the system is back to today's prompt.
Nothing is stored outside the system closure, so there is no state to clean
up. On one machine without a revert, `NH_ELEVATION_STRATEGY=auto` restores
sudo for that rebuild.
