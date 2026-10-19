---
status: draft
issue: 1365
intent: intent/2026-10-19-1365-boot-diagnostics.md
---

# Spec: an install VM that never reaches multi-user.target says why

## Design

**One helper, in the prelude both tests already share.** `tests/install.nix`
(`boot()`, line 371) and `tests/free-space.nix` (line 574) wrap their test
scripts in `tests/with-vm-cleanup.nix`, which already defines
`create_owned_machine`. The intent's open question is resolved that way: the
helper goes there, beside it, so the two copies cannot drift.

```python
def wait_for_multi_user(machine, timeout=900, probe_timeout=90):
    try:
        machine.wait_for_console_text(r"Reached target Multi-User System", timeout=timeout)
    except Exception:
        # #1365: say what systemd is stuck on before failing. Bounded in a thread,
        # because connect() can block with no timeout on a frozen guest (#1260).
        import threading
        answer = {}
        def probe():
            try:
                answer["out"] = machine.execute(
                    "systemctl list-jobs --no-pager; systemctl --failed --no-pager; "
                    "journalctl -b -p warning --no-pager | tail -n 80", timeout=60)[1]
            except Exception as e:
                answer["out"] = f"the probe itself failed: {e!r}"
        t = threading.Thread(target=probe, daemon=True)
        t.start()
        t.join(probe_timeout)
        print("multi-user.target was not reached. What systemd reports:\n"
              + answer.get("out", f"no answer from the guest within {probe_timeout} s"))
        raise
```

- Both call sites become `wait_for_multi_user(machine)` /
  `wait_for_multi_user(target)`. Their existing comments about #1260 stay.
- **The original failure is re-raised unchanged**, so the check fails exactly
  as before, with the same message.
- **Bounded:** a daemon thread plus `join(probe_timeout)`. If the backdoor
  never answers, the test prints "no answer from the guest" and fails at most
  90 s later than today, never at `globalTimeout`. A thread left blocked dies
  with the driver, and `reap_owned_vms` in the wrapper's `finally` kills the
  VM it is waiting on.
- Passing runs never enter the `except`, so nothing changes for them.

**A cheap check proves the helper, with no VM.** `checks.install-teardown`
already runs the wrapper as plain Python against a stub (`tests/install-teardown.py`).
A new `checks.boot-diagnostics` does the same, with three stub machines:

1. `wait_for_console_text` returns. The helper returns, and `execute` is never
   called.
2. `wait_for_console_text` raises, and `execute` returns `(0, "a.service start running")`.
   The helper prints that text, and the original exception propagates.
3. `wait_for_console_text` raises, and `execute` blocks forever, with
   `probe_timeout=1`. The helper prints "no answer from the guest within 1 s"
   and re-raises within a few seconds.

It is picked up by `build.yml`'s generated-checks step on its own (CLAUDE.md
§4), with no workflow edit.

## Alternatives rejected

- **Dump on the host side** (the console log is already there): it shows
  only what reached the console, which is exactly what stopped at 4.8 s.
- **`machine.execute` without the thread:** #1260's blocked `connect()` would
  turn a 15-minute failure into a `globalTimeout` one.
- **Raising the 900 s timeout:** guesses at slowness, and the guest was alive
  and stuck, not slow.

## Risks

- **The probe's `journalctl … | tail`** runs in the guest's shell. A failed
  pipe only shortens the dump, and cannot fail the test.
- **`install-encrypted.nix`** also uses the wrapper. It gains the helper but
  does not call it, so its derivation changes and its behaviour does not.

## Verification

- `checks.boot-diagnostics` green. §1: break the helper by deleting the
  `raise`, and case 2 must fail ("the original failure was swallowed"). Then
  make `probe()` call `execute` without the thread bound, and case 3 must
  time out instead of passing.
- `checks.install-teardown` still green, since it shares the wrapper.
- `nix fmt -- --ci`; the install test drivers build (their type check and
  lint), with no VM.
- The PR's own `install` job green (a real install through the helper's
  success path).

This is more than three files (the wrapper, two tests, a new check, and
`flake.nix` to register it), so the `coder` agent implements the plan
(managed instructions).
