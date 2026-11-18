---
status: approved
issue: 1855
spec: spec/2026-11-18-1855-keyboard-boot-dead-guest-costs-job.md
coders:
  1: session   # one file, three small edits; below the 3-step/3-file handoff threshold, so no coder
  2: session   # break proof is a temporary line in the same file; builds and commits stay with the session
  3: session   # verification only
reviewers:
  - codex   # read-only second read of the diff against this plan; advice only
---
# Plan: bound keyboard-boot's boots so a dead guest fails in minutes (#1855)

## Approved spec decisions (carried over; no need to open intent or spec)

Problem: on 2026-11-18 (run 44228069452) the nightly `keyboard-boot` job hung and ended `cancelled` at the job cap. The `de` guest died about 333 s in. `first_boot()` waits with `wait_for_unit`, which first waits for the backdoor shell with no limit, so the driver sat silent, and `globalTimeout = 115 * 60` fires after the job's `timeout-minutes: 120` (`.github/workflows/nightly.yml:118`), giving `cancelled` with no failed step.

Decisions (owner approval 2026-11-18):
1. Scope: only a bounded, diagnosed failure of `keyboard-boot` itself. No nightly scheduling or host-free gate change (CI gate, §11); contention is a separate follow-up that I do not file.
2. Use `wait_for_multi_user` from `tests/vm-cleanup.py:62` inline, imported the way `tests/boot-hang-detect.nix:13` does. No local copy of the silence loop, no `with-vm-cleanup.nix` wrapper (nodes are declared, not created).
3. `globalTimeout = 60 * 60` (the 11-17 green run took 19m16s; the driver starts about 12 min into the job, so it fires near minute 72, under the 120 cap). `timeout-minutes` is NOT changed.
4. Use the console line `Reached target Multi-User System` as the helper does. Fallback only if the first real run shows Plymouth swallows it: a bounded `wait_for_console_text` on a line that does appear, as `encrypted_boot` already does.
5. Resolved at approval: guest evidence only. The failure names `keyboard-boot` and carries the helper's guest evidence (registers, lapic, irq via qemu monitor). No `/proc/loadavg` print. Host contention detection goes to the follow-up in decision 1.

Not touched: `wait_for_unit("display-manager.service")` at :124 and the `wait_until_succeeds` calls (the backdoor works once the guest is up); the bounded waits at :89 and :96; the stale "Provisional" comment at `nightly.yml:117` (workflow edit, leave or drop).

Mode A: test-only edit, no module or option change. Coexistence: none (nightly-only test script).

## Resolved risk: console-text matching after `machine.crash()` / `start()`

Read from the nixos test driver source, nixpkgs input `/nix/store/qsy6ddxzv8grxi4i6f65kgszv3jvg3rz-source/nixos/lib/test-driver/src/test_driver/machine/__init__.py`:
- `start()` (:1531) re-creates `self.last_lines = Queue()` and `self.full_console_log = []` (:1600-1602, comment "Re-initialize (if this is not the first start)"). `wait_for_console_text` (:1464-1494) reads only `last_lines`. So after `crash()` (:1636) and `start()` no first-boot console line can match, and `len(machine.full_console_log)` at helper entry (`vm-cleanup.py:64`) starts from the new log. The spec's concern does not apply.
- Residual, handled: `wait_for_console_text("Initrd Root Device")` consumes the queue only up to its match, and a fresh `wait_for_console_text` in the helper drains the rest, so the later `Reached target Multi-User System` line is still seen. A window that times out discards only non-matching lines.
- Not verified: Plymouth swallowing the multi-user line (decision 4); only a real run shows it.

## Steps

All edits are in `tests/keyboard-boot.nix` (line numbers from main at 6cfa2688).

1. Import the helper and bound the waits.
   - `:75-77` (`testScript =` at :75, `{ nodes, ... }:` at :76, opening `''` at :77): change to `{ nodes, ... }: builtins.readFile ./vm-cleanup.py + '' ... ''`, following `tests/boot-hang-detect.nix:13`. Keep the existing `''` body unchanged.
   - `first_boot()` (`:119-121`): insert `wait_for_multi_user(machine)` between `machine.start()` (:120) and `machine.wait_for_unit("multi-user.target")` (:121). Covers `de` (:127) and `ru` (:168).
   - `encrypted_boot()` (`:96-97`): insert `wait_for_multi_user(machine)` between the `Initrd Root Device` wait (:96) and `wait_for_unit("display-manager.service")` (:97). Covers both calls (:159, :173).
   - `:7`: `globalTimeout = 115 * 60;` becomes `globalTimeout = 60 * 60;`.
   - → verify: `git diff` shows exactly those four hunks; `nix eval --raw .#checks.x86_64-linux.keyboard-boot.drvPath` evaluates; `nix fmt -- --ci tests/keyboard-boot.nix`; `nix run nixpkgs#statix -- check tests/keyboard-boot.nix`; `nix run nixpkgs#deadnix -- --fail tests/keyboard-boot.nix` (cheap tier, each under `flock /mnt/data/vmtest/codex-build.lock`, one at a time).
   - Traps: §5 `git add` the file before eval (a flake sees only tracked files); the nixpkgs-fmt hook may reformat `.nix` in the wrong style, so run `nix fmt` and read `git diff --stat` (should stay a few lines); the Python lives in a Nix `''` string, so no `${` and no `\$`; the helper is a file read, so its text is not escaped. Do not use `with-vm-cleanup.nix`.

2. Break proof (§1), temporary, never committed.
   - After step 1 is committed as a known-good baseline (`git checkout HEAD -- <path>` later, not `git checkout --`), add `machine.send_monitor_command("stop")` right after `machine.start()` at `:120`, before `wait_for_multi_user(machine)`, plus after it is caught nothing else: let the build fail. Also add the boot-hang-detect guard `assert "Reached target Multi-User System" not in "\n".join(machine.full_console_log)` immediately after the stop, with a `time.sleep(1)` as `boot-hang-detect.nix:18` does, so a late stop cannot leave the marker available.
   - Prove the break landed: `git diff` shows the `stop` line; `nix eval --raw .#checks.x86_64-linux.keyboard-boot.drvPath`, then `nix derivation show <drv>`, locate the testScript it names (`vm-cleanup.py` also contains `send_monitor_command`, so that bare word proves nothing) and require the exact injected statement `machine.send_monitor_command("stop")` plus the guard assert in it; then `nix build '<drv>^*' --print-build-logs` (not by attribute path, §5 stale evaluation).
   - Expected: build exits nonzero with `BootHang: console silent for 120 s` followed by a dump containing `IP=` and `dumping local APIC state`; about 4 minutes, up to about 6 (`vm-cleanup.py:191,213` allowances), well under 60.
   - Before-state (required, spec:54; the only choice is how long it runs, not whether): step 1 is already committed, so `git stash` cannot remove it. Create a separate worktree at the pre-fix commit (`git worktree add --detach /mnt/data/vmtest/wt-1855-prefix <parent-of-step-1-commit>`, own index, §5), add the same injected `stop` + guard after `machine.start()` in `first_boot`, `git add`, evaluate and inspect the drv as above, then `nix build '<drv>^*'` and kill the `nix build` at 10 minutes if the driver is still silent (full wait only if it ends sooner). Kill by pid only, reap the nixbld qemu by pid (§6). State in the PR that it was killed at 10 minutes, and capture the silent output. Remove that worktree afterwards.
   - Restore: `git checkout HEAD -- tests/keyboard-boot.nix`, then `git diff` must be empty.
   - Traps: §1 (prove the break applied); §5 `git checkout -- path` restores the index, use `HEAD`; check no `qemu` is left behind after the failing run (spec's unverified teardown question).

3. Green run and regression check.
   - After the restore, evaluate the unbroken test afresh (§5 stale evaluation): `nix eval --raw .#checks.x86_64-linux.keyboard-boot.drvPath`, `nix derivation show <drv>` and confirm no injected `stop` and no guard assert appear, then build `'<drv>^*'` (not the attribute path). Expect pass in about 19 min (Plymouth does not trip the helper; 60 min not too tight). Then `checks.x86_64-linux.boot-hang-detect` once, evaluated and built the same way.
   - → verify: both exit 0, `--print-build-logs` shows `Reached target Multi-User System` matched in `first_boot` for `de` and `ru` and in both `encrypted_boot` calls. If it instead reports `multi-user not reached within 900 s` or 120 s silence on a healthy guest, that is the Plymouth risk: apply decision 4's fallback and update this plan in the same commit.
   - Traps: §6 VM tier.

## Tests (by §6 tier)

- Cheap, one at a time under `flock /mnt/data/vmtest/codex-build.lock`: `nix fmt -- --ci`, statix, deadnix on the file; `nix eval --raw .#checks.x86_64-linux.keyboard-boot.drvPath`; the generated checks list (`.github/scripts/generated-checks.sh`) needs no edit because `keyboard-boot` stays in `nightly_only`, but AGENTS.md:799 still requires building every target it prints (plus claimed checks whose files are touched) before the push, by §6 tier (cache hits where CI already built them); list them in the PR and name any not run; also build `checks.grep-q-pipefail` only if a shell edit appears (none planned).
- VM tier (`keyboard-boot`, `boot-hang-detect`): at most two at once, only when `gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'` prints `0` and no p620 system build runs (`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'`); an API failure counts as busy. Before starting run `for a in install edge; do GITHUB_REPOSITORY=olafkfreund/nixarchy .github/scripts/vm-host-free.sh $a; done` (the script aborts without `GITHUB_REPOSITORY`, `vm-host-free.sh:12`); each must print `free` and exit 0, exit 2 means not known free.
- Break proof: expected failing output in step 2; capture it for the PR's §1 section.
- Not run locally: the nightly job itself (cap, concurrency, `cancelled` vs failed rendering); name it in the PR. No workflow file is edited, so no CI-gate change.

## Rollback

Revert the single commit touching `tests/keyboard-boot.nix` (`git revert`); nothing else depends on it. The test returns to the unbounded `wait_for_unit` and the 115-minute driver.
