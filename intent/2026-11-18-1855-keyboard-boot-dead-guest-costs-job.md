---
status: draft
issue: 1855
author: x
---

# Intent: a dead keyboard-boot guest costs the whole nightly job budget

Issue: #1855 (label `ci`, milestone "Keeping the lights on").

## Problem

The nightly `keyboard-boot` job ("type through LUKS, greeter and lock screen") on 2026-11-18 (run 44228069452) did not fail. It hung, and ended `cancelled` at the job cap.

What the issue records:

- The `de` guest booted to `Finished Save Transient machine-id to Disk` at 03:19:44 (7.99 s guest time).
- Its next and last line was `clocksource: Watchdog remote CPU 3 read timed out` at 03:25:09, with 333 s of guest time gone. That is the host-starvation signature from #1365.
- The job was then silent until the cap cancelled it at 05:06:59.
- Meanwhile other VM jobs shared p620: `install from the network ISO` (03:09:26 to 03:22:04), `commit-independent` (until 04:12:19), `cache` (until 03:26:14), and `install with encryption` (ended 03:19:10).
- The nightly runs all its self-hosted VM jobs in parallel on one host, with no host-free gate.

What the repository shows:

- The test has no bound on the first boot. `first_boot()` in `tests/keyboard-boot.nix` (defined at line 119, called for `de` and again for `ru` at line 168) calls `machine.start()` and then `wait_for_unit("multi-user.target")`. A guest that freezes after the backdoor shell appears blocks in the driver with no timeout of its own. The later `wait_for_unit("display-manager.service")` in the same helper is unbounded too, so bounding only the multi-user wait would not close the hole.
- The same test does bound later waits: `wait_for_console_text(..., timeout=240)` and `timeout=300` in `encrypted_boot`, plus a few `wait_until_succeeds(..., timeout=60/120)`. The first-boot wait on `de` has none.
- The repository already solved this for other VM tests. `tests/install.nix:371-375` and `tests/free-space.nix:576-577` call `wait_for_multi_user(machine)`, which reports a frozen guest within minutes with register evidence (#1260, #1365, #1594, #1604, checked by `checks.boot-hang-detect`). `keyboard-boot` does not use it.
- The driver does not win the race against the job cap. `globalTimeout = 115 * 60` (`tests/keyboard-boot.nix:7`) and the job's `timeout-minutes: 120` (`nightly.yml:118`) differ by 5 minutes, and the build and eval before the driver starts take part of that. The job started 03:06:47 and the guest's first line was 03:19:44, so the driver started about 12 minutes in and its 115-minute cap would have fired about 05:14, after the job cap at 05:06:47. The result is `cancelled` with no failed step, not a reported failure. Compare `install-encrypted`'s comment at `nightly.yml:~84-90`, which sets its globalTimeout under the job cap so "the driver loses the race to the job and a hang is a reported failure".
- The `nightly.yml` comment on this job says "Provisional until the supervisor's first measured run sets this margin." The 11-17 green run is a measurement nobody has used: about 19 minutes, against the 115-120-minute budget.

Consequences:

- About 2 hours of a self-hosted runner were burned by a guest that was dead after 6 minutes.
- The `digest` job then ran from 05:07 to 09:26. The `report` job then failed to file the issue because the digest body exceeded GitHub's limit (#1856). That is a separate defect, but it is why a human had to file #1855 by hand.
- A `cancelled` conclusion reads like an eviction or a timeout (CLAUDE.md §6). It does not point at a test hang.

First occurrence: 11-17's nightly passed this job. 11-16's failure was the nix-init job, not this one. A single data point does not separate "p620 overload tonight" from "this check has no margin".

## Proposed outcome

When a keyboard-boot guest freezes, the check fails within minutes. The failure carries guest evidence (what systemd was waiting on, or the console state) and names `keyboard-boot` as the cause. It does not consume the whole job budget, and it is not reported as `cancelled`.

Separately, a nightly that starves its own VM guests should be recognisable as host contention, not as a regression in the keyboard path.

## Affected users and systems

- The owner and agents reading the nightly report: a hang looks like a timeout or an eviction.
- Self-hosted p620 runners (four runners, one shared nix store and one host). A 2-hour hang blocks the `nightly` concurrency group, so the next nightly queues behind it.
- `tests/keyboard-boot.nix` (the `de` and `ru` nodes), the `keyboard-boot` job in `.github/workflows/nightly.yml:114-122`, and `.github/scripts/vm-host-free.sh`, which today knows only the install and edge pair.
- The `digest` and `report` jobs, which depend on this job finishing.

## Constraints

- A new or changed check must be shown to fail (CLAUDE.md §1): reproduce a frozen first boot and capture the failing output. A stubbed machine in the style of `tests/boot-hang-detect.nix` would be the cheap layer.
- A CI-gate change (job timeouts, workflow triggers, concurrency) needs a human to merge (§11). The PR may propose it.
- Local VM builds are gated by tier (§6): no VM check while a self-hosted runner is busy, and at most two VMs at once.
- Do not retry until green (§10). The investigation must account for the starvation, not hide it.
- Mode A must not change. `keyboard-boot` has no per-PR coverage to preserve: `build.yml:423` lists it among the checks deliberately left nightly-only, and `generated-checks.sh` has it in `nightly_only`.

## Open questions

1. Should `keyboard-boot` reuse `wait_for_multi_user`, or should the driver's `wait_for_unit` be wrapped some other way? That helper lives in `vm-cleanup.py`, and it is not known whether `runNixOSTest` can see it. Owner decision on the shape.
2. Should the nightly's VM jobs be serialised or gated against each other, so p620 is not asked to run `install-iso-net`, `install-encrypted` and `keyboard-boot` together? Or should `vm-host-free.sh` gain a nightly participant? It knows only the install and edge pair today, so that means a new participant and its check. The `nightly.yml` comment on `install-encrypted` says its runner pool serialises jobs, and the 11-18 timings show the jobs overlapping, so that comment is wrong or stale either way. This is a CI-gate change, so it is the owner's call.
3. What should the job cap and `globalTimeout` be? The 5-minute gap currently lets the job cap win. Is the target "driver wins" like `install-encrypted`, and what measured duration (the 11-17 green run, and the nightly's own timing step) sets the figure?
4. Is one occurrence enough to act on, or should a second hang be required first? The owner's standing rule (never park a found problem as flaky) argues for acting now.
5. None for the digest: its 4h20m runtime and the report's failure are #1856, which PR #1857 fixes. They are out of scope here.

## Predecessor

Issue #1855, with the guest log lines it quotes. No earlier intent exists for this task.