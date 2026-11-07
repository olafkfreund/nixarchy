---
status: draft
issue: 1604
spec: spec/2026-11-07-1604-boot-hang-sampling.md
coders:
  1: codex   # small, tricky logic: thread budget, abandoned Event, console-index ordering
  2: coder   # stub extension that follows step 1's exact strings; needs the break table run
  3: coder   # nixosTest script edit inside a Nix '' string, plus nix fmt
  4: agy     # prose only, from a fully specified outline; no logic to get wrong
reviewers:
  - codex    # reads the diff against this plan and the pinned QEMU/driver source read-only
  - agy      # independent read of the reading guide and the break table for checks that cannot fail
---

# Plan: The next install-target hang names the wakeup that never came

## Decisions carried over (approved intent and spec, plus owner decisions)

- Scope: `tests/vm-cleanup.py`, `tests/boot-diagnostics.py`,
  `tests/boot-hang-detect.nix`, `tests/AGENTS.md#boot-hang-detect`. No module,
  package or shipped closure changes. No CI workflow change (none needed:
  `checks.boot-diagnostics` is built by the generated step, `boot-hang-detect`
  by its `build.yml` job, and `install-gate.nix:45` already routes a
  `tests/vm-cleanup.py` change to the install job).
- Both pokes, always both, NMI first, then `sendkey alt-sysrq-w`. The code never
  skips the key; the reading guide says when its result is moot.
- Pokes run only on `BootHang`. The exception path (`vm-cleanup.py:86`) passes
  no `poke_watch` and pokes nothing.
- A guest that prints after a poke still fails: `BootHang` is raised regardless.
  No retry.
- Every virtio queue of every virtio device, in both samples; paths come from
  `info virtio`, never guessed.
- `cpu <n>` then `info lapic`, with `n` from that sample's `info cpus`
  (`CPU #(\d+)`), not an APIC id.
- The idle RIP was symbolised in the spec (`pv_native_safe_halt+0xf`, kernel
  `/nix/store/ajcdl0nncrga4f8wr0crix7pbjdf0gdd-linux-7.3.1`, `System.map`
  `_text ffffffff81000000`, symbol `ffffffff8227d5c0`, window offset `0x7d5cf`,
  KASLR offsets `0x0b200000` (2026-11-05) and `0x3b400000` (2026-11-06)). It goes
  in AGENTS.md as the worked example, not in any check.
- `clocksource=kvm-clock` and a kernel-version experiment are out of scope
  (separate, later, one at a time). `microvm-boot` is out of scope. Issue
  corrections are already posted.
- Budget: monitor join `30 + 2 * poke_watch` (60 s default, 30 s exception
  path); a timed-out join sets an `abandoned` `threading.Event` that `_poke`
  checks before each send.
- Log size: about 2,000 lines per hang. Owner: acceptable (only on a hang).
- Owner: if a healthy guest prints nothing after an NMI (case C), drop that one
  assertion and record in `tests/AGENTS.md` that NMI silence cannot be read.
- Facts checked for this plan: the pinned nixpkgs' `test-instrumentation.nix`
  sets `boot.consoleLogLevel = 7` (line 252) and no `kernel.sysrq`, so both
  the healthy test guest and the install target run systemd's
  `kernel.sysrq=16`, under which `w` prints `This sysrq operation is disabled`
  at `pr_info`, visible at loglevel 7. The driver's `full_console_log` is a
  `list[str]` (`test_driver/machine/__init__.py:1523`), and none of the
  consuming nixosTests sets `skipLint`/`skipTypeCheck`, so the new Python must
  pass the driver's pyflakes and mypy.

## Steps

1. **`tests/vm-cleanup.py`** (lines 1-7, 58-131). Coder: codex.
   - Add `import re` to the imports (lines 1-6). It must be used, or pyflakes
     fails every nixosTest that prepends this file.
   - Line 58: `def wait_for_multi_user(machine, timeout=900, probe_timeout=90, silence=120, poke_watch=15):`.
   - Line 73: `dump = _diagnose(machine, probe_timeout, poke_watch)`. Line 86
     stays `_diagnose(machine, probe_timeout)`.
   - New module-level `_poke(machine, watch, abandoned)` returning a list of
     entries. For `command` in `("nmi", "sendkey alt-sysrq-w")`: if
     `abandoned.is_set()`, return what it has; `before = len(machine.full_console_log)`
     **before** the send; send via `machine.send_monitor_command(command)`
     (exceptions recorded as `monitor command failed: …`, loop continues);
     `time.sleep(watch)`; `new = machine.full_console_log[before:]`; entry is
     `poke <command>: <len(new)> console lines within <watch> s` or
     `poke <command>: no console output within <watch> s`, followed by
     `new[:20]` each indented by two spaces, `\r` stripped. If the monitor's
     own reply to the poke is non-empty after `\r` stripping and `.strip()`,
     add a line `  monitor replied: <reply>` under it, so an HMP rejection
     (`unknown command:`, a bad key name) is visible rather than reading as
     "no console output", and case A's `unknown command:` assertion sees it.
   - `_diagnose(machine, probe_timeout, poke_watch=None)`: create
     `abandoned = threading.Event()`. `sample_monitor`, per sample, keeps
     `info cpus` then `info registers -a`, then: for each `CPU #(\d+)` in this
     sample's `info cpus` reply, `cpu <n>` then `info lapic`; then `info pic`,
     `info irq`, `info virtio`; for each `re.findall(r"^(/\S+) \[", reply, re.M)`,
     `info virtio-status <path>`, parse `num_vqs:\s*(\d+)`; if absent, one entry
     `num_vqs not found for <path>; its queues are skipped` and continue; else
     `info virtio-queue-status <path> <q>` for `q in range(num_vqs)`. Every
     command goes through one local helper that does what lines 97-103 do today
     (send, strip `\r`, record `monitor command failed: {error!r}`, append
     `monitor sample {sample} ({command}):\n{response}`, print). Keep the 5 s
     sleep after sample 1 only. After sample 2, if `poke_watch` is not None:
     extend and print `_poke(machine, poke_watch, abandoned)`, then append and
     print `a guest that printed after a poke still fails this check`.
   - Join: `budget = 30 + 2 * (poke_watch or 0)`; `join(timeout=budget)`; if
     alive, `abandoned.set()` and record/print `monitor did not answer within {budget} s`.
   - The #1365 probe (lines 114-131) is unchanged.
   - Verify: step 2's `checks.boot-diagnostics`, then the driver lint and type
     check: `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.boot-hang-detect.driver --print-build-logs`.
   - Traps: §5 a flake sees only tracked files, `git add` before evaluating.
     The file is prepended to install, free-space, install-encrypted,
     install-iso-net and `with-vm-cleanup.nix`, so a pyflakes error breaks all
     of them at driver build; the `.driver` build above is the cheap catch.
     codex cannot build (no nix daemon in its sandbox): the session runs every
     check. No shell edits, so `grep-q-pipefail` does not apply.

2. **`tests/boot-diagnostics.py`** (lines 15-28, 51-99). Coder: coder.
   - `Stub.__init__` gains `self.commands = []`. `send_monitor_command` appends
     the command, then answers: `info cpus` → `* CPU #0: thread_id=1\r\n`;
     `info virtio` → two devices,
     `/machine/peripheral-anon/device[0]/virtio-backend [virtio-blk]\r\n/machine/peripheral-anon/device[1]/virtio-backend [virtio-serial]\r\n`;
     `info virtio-status …device[0]…` → `  num_vqs:                 2\r\n`,
     `info virtio-status …device[1]…` → `  num_vqs:                 3\r\n`
     (two devices with different counts, so "first device only" and "a fixed
     number of queues" both go red);
     `nmi` → append `Uhhuh. NMI received for unknown reason 00 on CPU 0.` to
     `self.full_console_log`, return `""`; `sendkey …` → `""`; else today's
     `CPU#0\r\nEIP=000ebd8b\r\n`.
   - Case 4 passes `poke_watch=0.1` and asserts, each with a `fail(...)`:
     `info lapic`, `info pic`, `info irq` each sent exactly twice; each
     `info lapic` immediately preceded by `cpu 0`;
     the set of `info virtio-queue-status` commands sent equals exactly
     `{device[0] path} 0..1` and `{device[1] path} 0..2`, each sent twice (ten
     commands); index of `nmi` < index of `sendkey alt-sysrq-w`;
     `poke nmi: 1 console lines` and `NMI received for unknown reason` in
     `raised.monitor_dump`; `poke sendkey alt-sysrq-w: no console output` in it;
     existing `elapsed < 15` kept.
   - New case 5: `ev = threading.Event(); ev.set()`; `ns["_poke"](Stub(...), 0.1, ev)`
     sends nothing (`stub.commands == []`).
   - New case 6: a stub subclass whose `sendkey …` reply is
     `unknown key: 'x'\r\n`; `ns["_poke"](stub, 0.1, threading.Event())` must
     contain `monitor replied: unknown key`. Case 4's dump must not contain
     `monitor replied:` (the normal stub replies are empty).
   - Cases 2 and 3: assert `"nmi" not in m.commands`.
   - Verify: `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.boot-diagnostics --print-build-logs`
     (no pipe on it; §1 pipelines). Then run the spec's break table, one break
     at a time, each confirmed with `git diff` before running, restored with
     `git checkout HEAD -- tests/vm-cleanup.py` (not `git checkout --`, §5) from
     a committed baseline:

     | break in `vm-cleanup.py` | case that must go red |
     |---|---|
     | drop `info pic` | 4 (`info pic` count) |
     | `info lapic` without `cpu` | 4 (`cpu 0` order) |
     | `range(2)` instead of `num_vqs` | 4 (device[1] queue 2) |
     | only the first `info virtio` path (`[:1]`) | 4 (device[1] queues) |
     | drop the `monitor replied:` line from `_poke` | 6 |
     | swap poke order | 4 (order) |
     | take `before` after sending | 4 (`poke nmi: 1 console lines`) |
     | drop the sendkey poke | 4 (sendkey line) |
     | remove the `abandoned` check | 5 |
     | pass `poke_watch` at line 86 | 2 and 3 |

     Capture each failing output for the PR.
   - Traps: §1 (a break that stays green may never have applied; prove it with
     `git diff`), §5 `git checkout HEAD --`, cheap tier, one at a time under the
     lock.

3. **`tests/boot-hang-detect.nix`** (lines 17, 23-24, after 33). Coder: coder.
   - Line 17: add `poke_watch=2`.
   - After line 24, assert on replies (a rejected command still writes its
     header): `raised.monitor_dump` contains `dumping local APIC state for CPU`,
     `ioapic0: ver=`, `used_idx:`, `poke nmi:`, `poke sendkey alt-sysrq-w:`, and
     contains neither `unknown command:` nor `monitor command failed`. Keep
     `elapsed < 60` (expected about 35 s; the join cap is 34 s).
   - Case C after line 33:
     `poked = "\n".join(_poke(healthy, 15, threading.Event()))`, then split it
     at the `poke sendkey` line and assert the NMI part contains
     `NMI received for unknown reason` and the key part contains
     `This sysrq operation is disabled`.
   - Verify: `.driver` build (lint and mypy), then the VM check (VM tier, below).
     Breaks: misspell `info lapic` (case A shows `unknown command:`), delete the
     poke block (case A loses `poke nmi:`), replace `nmi` with `info status`
     (case C's NMI assert fails).
   - Owner decision applies here: if on the passing tree case C's NMI part is
     empty on the healthy guest, delete only that assertion and do step 4's
     NMI-silence note. Record the observed output in the PR.
   - Traps: Python inside a Nix `''` string: no `${` (escape `''${`), `\$` is
     literal (§5). Run `nix fmt` after the edit and read `git diff --stat`
     (a hook may rewrite with nixpkgs-fmt, §5). §5 stale background evaluation:
     `nix eval --raw .#checks.x86_64-linux.boot-hang-detect.drvPath`, check it is
     the derivation you mean, then `nix build '<drv>^*'`.

4. **`tests/AGENTS.md`** (lines 708-741, `## Boot hang detect`). Coder: agy.
   - Extend the "Both print…" paragraph: the samples now also hold `cpu <n>` +
     `info lapic` per vCPU, `info pic`, `info irq`, `info virtio` and every
     queue's `info virtio-queue-status`, and on `BootHang` only, two pokes.
   - Reading the samples: an IRR or ISR bit set in both samples (stuck vector);
     an IOAPIC entry with remote-IRR set (level line waiting on an EOI); a
     virtio queue with `inuse > 0` whose `used_idx` does not move between
     samples (a request the device never completed). Limits: a TSC-deadline
     timer does not show in the LAPIC count; MSI-X bypasses the IOAPIC.
   - Reading the pokes: only `Uhhuh. NMI received for unknown reason` after
     the NMI: vCPUs can be woken and went back to idle. Other boot output
     after the NMI: the guest resumed, and the key's result is moot.
     `This sysrq operation is disabled` after the key: the legacy
     i8042 → IOAPIC → LAPIC path delivered. Silence: weak evidence (a quietly
     handled NMI or a key that never reached sysrq look the same). A guest that
     prints after a poke still fails the check.
   - Worked example: the symbolisation from the decisions above, replacing the
     generic grep advice's example.
   - Rewrite the "There is no sysrq dump" paragraph: the key is now sent as a
     poke under the shipped `kernel.sysrq=16`, which still dumps nothing but
     prints the disabled line; enabling more would change the shipped closure.
   - What no check proves: case A's stopped guest cannot print, so nothing
     shows a poke waking a halted-and-hung guest; case C runs the test VM's
     default kernel, not the target's 7.3.1. The first real answer is the next
     CI hang. Raw logs, not job logs, hold hangs before #1643:
     `bzcat <log> | tr '\r' '\n'`.
   - Update the check paragraph: case A also asserts the replies and poke
     lines (breaks named in step 3); case C pokes the healthy guest.
   - If step 3's owner decision fired: one sentence that NMI silence cannot be
     read on this guest, with what case C showed.
   - Verify: `git diff tests/AGENTS.md` reads as prose; no section inserted or
     renumbered (the root CLAUDE.md's numbered sections are untouched).
   - Traps: agy cannot run commands headless; the session checks the diff.

## Tests (by §6 tier)

- Cheap, any time, one at a time under `flock /mnt/data/vmtest/codex-build.lock`:
  `checks.boot-diagnostics` (plus its ten breaks), `checks.install-teardown`
  (execs `vm-cleanup.py` without the driver), `checks.install-gate`,
  `checks.test-registration`, `boot-hang-detect.driver` and
  `install.driver` (pyflakes and mypy on the prepended script),
  `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
  `nix run nixpkgs#deadnix -- --fail .`. Expected: all green.
- VM tier: `checks.boot-hang-detect`, only when
  `gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'`
  prints `0` and no p620 system build runs; at most two local VMs. Expected:
  case A ~35 s and green, case B green, case C green (or the owner decision).
  Its three breaks run in the same tier.
- Plus every target `.github/scripts/generated-checks.sh` prints, by tier,
  before pushing (cache hits for what this does not touch).
- Not run locally: the `install` job (and free-space, install-encrypted,
  install-iso-net), where a real hang would appear; it hangs about 1 run in
  25-30 and needs an install slot. Their drivers are linted locally above; CI's
  install job is the run.

## Rollback

Revert the PR's commit. Only test helpers and `tests/AGENTS.md` change, so a
revert restores the previous two-sample probe with nothing to migrate.
