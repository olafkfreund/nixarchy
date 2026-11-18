---
status: draft
issue: 1855
intent: intent/2026-11-18-1855-keyboard-boot-dead-guest-costs-job.md
---
# Spec: bound keyboard-boot's boots so a dead guest fails in minutes

## Design

Two edits, both in `tests/keyboard-boot.nix`. No workflow file changes.

1. **Bound every boot wait with `wait_for_multi_user`.** It lives in `tests/vm-cleanup.py:62`. It waits for the console line `Reached target Multi-User System` in windows of at most 15 s. It fails with `BootHang` on 120 s of console silence or a 900 s budget, and the message carries two qemu-monitor samples (registers, lapic, irq). That is exactly the evidence #1855 lacks. `install.nix:371-375` and `free-space.nix:576-577` already call it before `wait_for_unit`, because `wait_for_unit` first waits for the backdoor shell with no limit (`tests/AGENTS.md:2295`, `install.nix:368-370`).
   - `first_boot()` (`keyboard-boot.nix:119-121`, called for `de` at :127 and `ru` at :168): add `wait_for_multi_user(machine)` between `machine.start()` and `wait_for_unit("multi-user.target")`. This is the call the 11-18 log was stuck in.
   - `encrypted_boot()` (`:97`): after the bounded `wait_for_console_text("Reached target Initrd Root Device", timeout=300)`, the next `wait_for_unit("display-manager.service")` is again an unbounded backdoor wait on a freshly booted second-stage guest. Add `wait_for_multi_user(machine)` before it. The earlier waits at :89 and :96 are already bounded and stay.
   - `wait_for_unit("display-manager.service")` at :124 and the `wait_until_succeeds` calls: after the guest is known to be up, the backdoor works, so they keep their own (default 900 s) timeouts. Not touched.
2. **Make the driver lose to nothing but its own bound.** Change `globalTimeout = 115 * 60` (`:7`) to `60 * 60`. The 11-17 green run took 19m16s, so this is about 3x. The driver starts about 12 minutes into the job (03:06:47 start, 03:19:44 first guest line), so 115 min fires at about minute 127, past `timeout-minutes: 120` (`nightly.yml:118`), and the job ends `cancelled`. At 60 min it fires at about minute 72 even after a cold 12-minute build, and `nix build` fails as a reported failure. The same "driver loses the race" pattern is in `nightly.yml:~84-90` (`install-encrypted`).

The job cap (`nightly.yml:118`) is **not** changed. The "Provisional until the supervisor's first measured run" comment at `nightly.yml:117` is now stale (19m measured) but editing it is a workflow edit; leave it for the human who merges any CI-gate change, or drop it from this PR.

To import the helper, follow `tests/boot-hang-detect.nix:13`: `testScript = { nodes, ... }: builtins.readFile ./vm-cleanup.py + '' ... ''`. `keyboard-boot` does not need `with-vm-cleanup.nix`'s `reap_owned_vms` wrapper: that exists for tests that create their own machines (`create_owned_machine`), and these are declared nodes. Not verified: whether a `BootHang` raised mid-test leaves qemu children behind under `runNixOSTest`'s own teardown; `boot-hang-detect.nix:41-42` terminates its frozen guest by hand, so check the failing run leaves no `qemu` behind.

## Decisions for approval

1. **Scope (intent open question 1).** Recommendation: a bounded, diagnosed failure of `keyboard-boot` itself. That stands on the evidence (guest dead at 333 s, job silent for 1h41m). Alternative: also change how the nightly schedules self-hosted VM jobs. Rejected for this issue because contention is only a hypothesis here (p620 load at 03:19-03:25 was never measured), and it is a CI-gate change (§11). A separate follow-up issue would be "nightly: put `keyboard-boot` (and other self-hosted VM jobs) behind the same host-free sequencing as the install chain (`needs:` or `vm-host-free.sh`)". I do not file it.
2. **Helper placement.** Recommendation: call `wait_for_multi_user` inline in `first_boot` and `encrypted_boot`. Alternative: copy the 120 s silence loop locally. Rejected: duplicates a helper with its own check (`boot-hang-detect`).
3. **`globalTimeout` value.** Recommendation: `60 * 60` (about 3x the measured 19 min, and under the job cap even after a slow build). Alternative: 90 min (safer for a starved host, but a hang then burns 90 min against a job whose real work is 19). Alternative: lower `timeout-minutes` instead: rejected, it is a CI gate and the test-side bound suffices.
4. **Console-text risk and fallback.** Recommendation: use `Reached target Multi-User System` as the helper does. If the first real run shows Plymouth swallows that line on the console (see Risks), fall back to a bounded `wait_for_console_text` on a line that does appear, as `encrypted_boot` already does at :89/:96.
5. **Host-contention outcome (intent line 43).** The intent also asks that starvation be recognisable as host contention. The helper collects guest state only, not host load, so this spec does not deliver it by itself. Recommendation: narrow that outcome for this issue to "the failure names `keyboard-boot` and carries guest evidence", and leave contention detection to the follow-up in decision 1. Smallest optional addition if you want host evidence now: print the driver host's `/proc/loadavg` when `BootHang` is caught (test-side, no workflow edit). Needs your explicit approval either way; I will not drop the outcome silently.

## Alternatives rejected

- **Only lower `globalTimeout`.** Turns `cancelled` into a failure, but still after up to about 1 hour and with no guest evidence. Doesn't meet "fails within minutes".
- **Raise or change `timeout-minutes`.** CI gate (§11); unnecessary.
- **Retry the job on hang.** Hides starvation (§10 do not retry until green).
- **Add a host-free gate for `keyboard-boot` now.** Out of scope per decision 1; hypothesis unproven.
- **Wrap in `with-vm-cleanup.nix`.** Not needed for declared nodes.

## Risks

- **Plymouth may keep `Reached target Multi-User System` off the console.** `boot.plymouth.enable` is set (`keyboard-boot.nix:53`). `install.nix` and `free-space.nix` have no Plymouth, so the helper has not been proven with it. Initrd lines do reach the console (:89, :96 match), which is mild evidence the second stage does too. Not verified. If wrong, the symptom is `multi-user not reached within 900 s` on a healthy guest, or 120 s silence, in the first run, so the nightly shows it immediately.
- **The 120 s silence limit on a loaded host.** Healthy boots have a longest gap of 6.4 s (`tests/AGENTS.md` boot-hang-detect), but a starved-but-alive guest can trip it. That is the intended report: a failure with evidence, not a retry.
- **`encrypted_boot` after `machine.crash()`/`start()`:** `full_console_log` is the guest's cumulative log; the helper samples its length at entry (`vm-cleanup.py:64`) and looks for the target text in new output only via `wait_for_console_text`. Whether `wait_for_console_text` matches old lines from the first boot's console was not checked; if it does, the helper returns early and bounds nothing there. Check before relying on it.
- Edit is test-only; no module or option change, so Mode A is untouched.

## Coexistence

Not user-facing config: a nightly-only test script edit, nothing a user's configuration can set.

## Verification

- **§1 break proof (the only honest proof the new bound works).** The guest is started by `machine.start()` inside `first_boot` (`keyboard-boot.nix:120`), not by a call at the call site (`first_boot(de)` is :127). Add a temporary `machine.send_monitor_command("stop")` right after `machine.start()` at :120 and before the new `wait_for_multi_user(machine)` (as `tests/boot-hang-detect.nix:16-17` does), then build `checks.x86_64-linux.keyboard-boot`. Also copy the existing proof's guard (`boot-hang-detect.nix:36`): assert `"Reached target Multi-User System" not in "\n".join(machine.full_console_log)` after the failure is caught or in the break, so a stop that landed late cannot leave the marker available and prove nothing. Expected: the build exits nonzero with `BootHang: console silent for 120 s` plus a dump containing `IP=` and `dumping local APIC state`. Timing is measured from the injected stop to the build's nonzero exit, teardown included: 120 s of silence, then diagnostics (monitor pokes up to `30 + 2*15 + 90 + 5` = 155 s per `vm-cleanup.py:191`, typically less on a responsive monitor), then the guest probe (up to 90 s, `vm-cleanup.py:213`). Expect roughly 4 minutes, and up to about 6 minutes at the configured allowances; both are far below the 60-minute driver bound. Before the fix, the same break runs on `wait_for_unit` with no output until the driver's `globalTimeout`. Capture that output for the PR (evaluate the drvPath first and confirm the break landed with `git diff`, per §1 and §5). Then remove the line and watch the unbroken test pass. Because the build takes about 19 minutes warm, the before-state may instead be shown by running the pre-fix test with the same stop and killing it at 10 minutes with the driver still silent; state which was done.
- **Green run:** the unbroken `keyboard-boot` passes, and its duration stays near 19 min (confirms the helper is not tripped by Plymouth, and the globalTimeout of 60 min is not too tight).
- **`checks.boot-hang-detect`** (VM tier, ~minutes): unchanged helper, run once to confirm nothing regressed.
- **Tiers (§6):** `keyboard-boot` and `boot-hang-detect` are VM checks: at most two at once, only when `gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'` prints 0, and with no p620 system build running. `nix fmt -- --ci` and `statix`/`deadnix` on the edited file are cheap tier, under `flock /mnt/data/vmtest/codex-build.lock`.
- **Not run locally, by nature:** the nightly job itself (cap, concurrency, `cancelled` vs failed rendering). It only shows on the next nightly. No workflow file is edited, so no CI-gate change is in the PR; if decision 3 or the stale comment at `nightly.yml:117` is changed, that edit is a CI-gate change a human merges (§11).
