---
status: approved
issue: 1604
intent: intent/2026-11-07-1604-boot-hang-sampling.md
---

# Spec: The next install-target hang names the wakeup that never came

## Decisions carried from the approved intent

1. Both pokes, NMI first. Both are always sent. The log records what each
   one printed, and the reading guide says when the key's result is moot.
2. Every virtio queue of every virtio device, in both samples. The paths come
   from `info virtio`, so nothing is guessed (checked below).
3. The idle RIP is symbolised once, here (below), and not in any check.
4. `clocksource=kvm-clock` is not part of this task. It is a separate
   experiment, to run after this probe has captured one hang.
5. The issue corrections are already posted on #1594 and #1604. Nothing is
   left to do for them here.

## The idle RIP, symbolised

Both hangs booted `/nix/store/ajcdl0nncrga4f8wr0crix7pbjdf0gdd-linux-7.3.1`.
The raw logs name this path, and both boot banners read `Linux version 7.3.1
… @1793362192`. Its `System.map` has `_text` at `ffffffff81000000` and
`pv_native_safe_halt` at `ffffffff8227d5c0`, with the next symbol at
`…5e0`. KASLR moves the kernel in 2 MiB steps, so the RIP's offset within a
2 MiB window, `0x7d5cf`, falls into one candidate symbol for each window.
Of the 27 candidates in the text range, `pv_native_safe_halt+0xf` is the
only idle routine. It is the instruction after `sti; hlt`, and that matches
`HLT=1`. It implies KASLR offsets of `0x0b200000` (2026-11-05) and
`0x3b400000` (2026-11-06), and both are 2 MiB-aligned. All four vCPUs are
therefore in the idle loop's halt, as the intent assumed.

The same run also shows that the installer guest booted `6.18.60` and the
target booted `7.3.1`. That matches the intent.

## Design

Everything below is in `tests/vm-cleanup.py`. No module, package or shipped
closure changes.

**Signature.** `wait_for_multi_user` (line 58) gains `poke_watch=15`. The
`BootHang` call at line 73 passes it on as
`_diagnose(machine, probe_timeout, poke_watch)`. The exception-path call at
line 86 stays `_diagnose(machine, probe_timeout)`, so `poke_watch` defaults
to `None` there and nothing is poked. Pokes run only on `BootHang`.

**Samples** (`sample_monitor`, lines 94-105). Each of the two samples keeps
`info cpus` and `info registers -a` first, then runs these commands in order:

- For each `CPU #(\d+)` in that sample's `info cpus` reply: `cpu <n>`, then
  `info lapic`. The command uses the CPU index that `info cpus` printed, not
  an APIC id, so no topology is assumed.
- `info pic`, then `info irq`.
- `info virtio`. For each reply line matching `^(/\S+) \[`, run
  `info virtio-status <path>` and read `num_vqs:\s*(\d+)` from it. Then, for
  each `q` below that number, run `info virtio-queue-status <path> <q>`. If
  `num_vqs` can't be parsed, one line says so and that device is skipped.

Every reply is recorded the same way as today. Each one gets its own entry,
`\r` is stripped, and the entry is printed. A failed command is recorded as
`monitor command failed: …`, and the loop goes on.

The format strings are checked in the `qemu_test` binary this repo's nixpkgs
builds (`qemu-for-vm-tests-11.1.2`). It has `info lapic` (`apic-id:i?`),
`info virtio` (`%s [%s]`), `info virtio-status` (`num_vqs: %ld`) and
`info virtio-queue-status` (`path:s,queue:i`, with `inuse`,
`last_avail_idx` and `used_idx`).

**Pokes.** A module-level `_poke(machine, watch, abandoned)` returns the entries, so
that case C below can call it directly. `sample_monitor` calls it in the
same monitor thread, after sample 2, and only when `poke_watch` is set. For
each of `nmi` and `sendkey alt-sysrq-w`, in that order:

1. Take `before = len(machine.full_console_log)` *before* sending.
2. Send the command.
3. `time.sleep(poke_watch)`.
4. Record one line: `poke <command>: <k> console lines within <w> s` or
   `poke <command>: no console output within <w> s`. Below it go the first
   20 new console lines, indented.

After the pokes, one more line: `a guest that printed after a poke still
fails this check`. `BootHang` is raised regardless (intent constraint).

**Budget.** The join at line 109 becomes `30 + 2 * poke_watch` (60 s by
default, 30 s on the exception path), and so does its message. A monitor
that stops answering still ends the probe at the join. The thread is a
daemon, as it is today. The thread outlives a timed-out join, so a monitor
that answers late could otherwise inject a poke after diagnosis has
returned. To stop that, `_diagnose` sets a `threading.Event` (`abandoned`)
when the join times out, and `_poke(machine, watch, abandoned)` checks it
before each send, then returns without poking. The only thing left is a
command already in flight when the join expired. The #1365 systemd probe runs after this, unchanged,
and at worst a hang now costs 150 s instead of 120 s.

**Size.** The NixOS test backdoor is a virtconsole on a default
`virtio-serial` device, which has 64 queues. On top of that come the
root disk's 4 queues and a few on net and rng. That is about 75 queues of
about 12 lines each, twice, so roughly 2,000 lines per hang. This only ever
appears in a failed run. It is the price of decision 2.

**Reading guide.** `tests/AGENTS.md#boot-hang-detect` gains:

- What the new samples mean: an IRR or ISR bit set in both samples, an
  IOAPIC entry with remote-IRR set, and a virtio queue with `inuse > 0`
  whose `used_idx` doesn't move between the samples (a request the device
  never completed). The two limits from the intent also go here: a
  TSC-deadline timer doesn't show in the LAPIC count, and MSI-X bypasses the
  IOAPIC.
- How to read the pokes:
  - Only `Uhhuh. NMI received for unknown reason` after the NMI: the vCPUs
    can be woken, and the guest went back to idle.
  - Any other boot output (systemd lines) after the NMI: the guest resumed,
    and the key's result is moot.
  - `This sysrq operation is disabled` after the key: the legacy
    i8042 → IOAPIC → LAPIC path delivered.
  - Silence: weak evidence, for the reasons the intent gives.
- The symbolisation above, as the worked example. The paragraph that starts
  "There is no sysrq dump" is updated, because the key is now sent as a
  poke. It still dumps nothing.

## Coexistence

None. This changes test helpers only. No option, package or merged
environment that a user's configuration could share is touched.

## Alternatives rejected

- **`info lapic <apic-id>`, which saves the `cpu` command.** It assumes
  APIC id equals CPU index. That holds for the default topology, but it is
  a guess, and `cpu <n>` avoids it.
- **Only the root disk's queues.** That would mean picking the disk out of
  `info virtio` by type or position, which is a guess the intent ruled out.
  Every queue is what the owner chose.
- **Skip the key when the NMI printed.** The unknown-NMI message is expected
  even when the guest stays hung, so an NMI that printed doesn't make the key
  moot. The reading guide makes that call, and the code doesn't.
- **Pokes on the exception path too.** That path fires on driver failures
  that aren't hangs, and the intent limits pokes to `BootHang`.
- **A module-level constant for the watch.** A keyword matches `silence`
  and `probe_timeout`, and it lets each check shorten the watch without
  touching globals.

## Risks

- **An NMI claimed silently.** If the guest runs the perf NMI watchdog, an
  external NMI should still reach `unknown_nmi_error`. That is unverified.
  Case C below measures it on a real guest. If it stays silent there, the
  plan drops that one assertion, and AGENTS.md records that NMI silence
  can't be read on this guest.
- **Log volume.** Covered under Size above. It only appears on failure.
- **Wall time on the install job.** A hang takes about 30 s longer to fail.
  `globalTimeout` is 85 min in `tests/install.nix:166` and
  `tests/free-space.nix:166`, so 150 s doesn't approach it.
- **A monitor that answers slowly.** About 150 monitor commands per sample
  share the 30 s of the old join, now 30 + 2 × watch. A monitor that
  answers each command in tens of ms fits easily. One that stalls is cut
  off at the join, which is the intent's bound.
- **Hosts.** Only CI's install job and the `boot-hang-detect` VM check on
  p620 run this. Nothing ships.

## Verification

Each new assertion is shown failing under the named break (CLAUDE.md §1),
with the break confirmed by `git diff` before running.

**`checks.boot-diagnostics`** (cheap `runCommand`, `tests/boot-diagnostics.py`).
The `Stub` records every monitor command and answers per command:

- `info cpus` → `* CPU #0: thread_id=1`
- `info virtio` → `/machine/peripheral-anon/device[0]/virtio-backend [virtio-blk]`
- `info virtio-status …` → `  num_vqs:                 2`
- `nmi` appends `Uhhuh. NMI received for unknown reason 00 on CPU 0.` to
  `full_console_log`
- anything else → today's `CPU#0\r\nEIP=000ebd8b\r\n`

Case 4 passes `poke_watch=0.1` and asserts the following, each with the
break that must turn it red:

| assertion | break |
|---|---|
| `info lapic`, `info pic`, `info irq` each sent twice | drop `info pic` from the sample |
| `cpu 0` sent before each `info lapic` | send `info lapic` without `cpu` |
| `info virtio-queue-status …/virtio-backend 0` and `… 1` each sent twice | loop `range(1)` instead of `num_vqs` |
| `nmi` sent before `sendkey alt-sysrq-w` | swap the poke order |
| dump has `poke nmi: 1 console lines` and the NMI line | take `before` after sending |
| dump has `poke sendkey alt-sysrq-w: no console output` | drop the sendkey poke |
| with `abandoned` already set, `_poke` sends nothing | remove the `abandoned` check |
| `elapsed < 15` still holds | none needed: the watch is 0.2 s |

Cases 2 and 3 (exception path) assert that `nmi` was **not** sent. Break:
pass `poke_watch` at line 86.

**`checks.boot-hang-detect`** (VM, tier per §6: no self-hosted runner busy).

- **Case A** passes `poke_watch=2`. Here is the expected time: about 20 s
  of silence, then about 10 s for the samples (the 5 s sleep and the
  pokes), then 5 s for the systemd probe on a stopped guest. That is about
  35 s, so the existing `elapsed < 60` bound and its documented break
  (`took 130 s to notice`) still hold. The 34 s join cap is only reached if
  the monitor stalls, and failing then is correct.
- Case A adds asserts on the *replies*, not on the command headers, because
  a rejected command still writes its header. `raised.monitor_dump` must
  contain:
  - `dumping local APIC state for CPU` (from `info lapic`)
  - `ioapic0: ver=` (from `info pic`)
  - `used_idx:` (from `info virtio-queue-status`)
  - both `poke nmi:` and `poke sendkey alt-sysrq-w:`

  It must not contain `unknown command:` or `monitor command failed`. These
  reply strings come from the pinned QEMU 11.1.2 binary. Breaks: misspell
  `info lapic` (`unknown command:` appears and the marker goes missing), or
  delete the poke block (`poke nmi:` goes missing).
- **Case C (new)**, on the healthy guest after case B reaches multi-user:
  run `_poke(healthy, 15, threading.Event())` directly and assert that the NMI's
  new console lines contain `NMI received for unknown reason` and the key's
  contain `This sysrq operation is disabled`. That proves, on a real QEMU
  and kernel, that each poke prints from a live guest and that the watch
  captures it. Break: replace `nmi` with `info status`, and the NMI
  assertion fails.

**What no check proves**, which goes in the reading guide as well:

- The stopped guest in case A can't print, so nothing shows that a poke
  wakes a *halted-and-hung* guest.
- Case C's guest runs the test VM's default kernel, not the target's 7.3.1.

The first real answer is the next hang in CI.

**Not run locally:** the `install` job, where a real hang would appear. It
only fails at a rate of about 1 in 25-30.
