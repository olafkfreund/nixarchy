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
   with `$NH_STUB_RC` (default 0). Add three cases after the existing ones:
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

## Later PRs (outline; each is stepped when reached)

3. The rebuild runs as a `systemd-run --user` unit, `nixarchy-rebuild`, with
   `--no-nom`, and its output goes to the journal.
4. The spinner opens `journalctl --user -fu nixarchy-rebuild`.
5. The Quickshell panel replaces the floating terminal for Install > Apply and
   the per-app rows.

## Rollback

Revert the PR's commit. The scripts lose the export, so nh auto-selects sudo
again. The wrapper and the rule go, and the system is back to today's prompt.
Nothing is stored outside the system closure, so there is no state to clean
up. On one machine without a revert, `NH_ELEVATION_STRATEGY=auto` restores
sudo for that rebuild.
