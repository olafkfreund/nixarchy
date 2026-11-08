import datetime
import os
import re
import sys
import threading
import time
import traceback

try:
    from test_driver.errors import RequestedAssertionFailed
except ImportError:  # boot-diagnostics and install-teardown exec this file without the driver
    RequestedAssertionFailed = AssertionError


# Not a RequestedAssertionFailed subclass: the driver's type check rejects a
# base that is one of two classes depending on the import above.
class BootHang(AssertionError):
    monitor_dump = ""


POKE_MAX_LINES = 3000


def reap_owned_vms(vms):
    """No guest/monitor RPC: either can be the reason the test failed."""
    original = sys.exc_info()
    failed = False
    # Kill all first, including a partially started machine whose pid/booted
    # fields the driver has not set yet. Only process owns the child handle.
    for machine in vms:
        process = machine.process
        if process is not None:
            try:
                process.kill()
            except ProcessLookupError:
                pass
            except Exception as error:
                print(f"VM cleanup: {error}", file=sys.stderr)
                failed = True
    for machine in vms:
        try:
            if machine.process is not None:
                machine.process.wait(timeout=5)
            reader = machine.serial_thread
            if reader is not None:
                reader.join(timeout=5)
                if reader.is_alive():
                    raise RuntimeError("serial reader did not exit")
        except Exception as error:
            print(f"VM cleanup: {error}", file=sys.stderr)
            failed = True
    if failed:
        # Python itself joins non-daemon readers at exit. Preserve the original
        # assertion before bypassing that otherwise unbounded final join.
        if original[0] is not None:
            traceback.print_exception(*original)
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(1)


def wait_for_multi_user(machine, timeout=900, probe_timeout=90, silence=120, poke_watch=15,
                        quiet=3, task_max=90):
    console_length = len(machine.full_console_log)
    started = time.monotonic()
    budget_deadline = started + timeout
    silence_deadline = started + silence
    while True:
        now = time.monotonic()
        length = len(machine.full_console_log)
        if length > console_length:
            silence_deadline = now + silence
        console_length = length
        window = min(15, silence_deadline - now, budget_deadline - now)
        if window <= 0:
            reason = (f"console silent for {silence} s" if silence_deadline <= budget_deadline
                      else f"multi-user not reached within {timeout} s")
            dump = _diagnose(machine, probe_timeout, poke_watch, quiet, task_max)
            error = BootHang(f"{reason}\n{dump}")
            error.monitor_dump = dump
            raise error
        # Clamp each wait to both deadlines; only the driver's timeout is a window
        # ending. Anything else is a real failure: diagnose it, re-raise it (#1365).
        try:
            machine.wait_for_console_text(
                r"Reached target Multi-User System", timeout=datetime.timedelta(seconds=window))
            return
        except RequestedAssertionFailed:
            pass
        except Exception:
            _diagnose(machine, probe_timeout)
            raise


def _poke(machine, watch, abandoned, quiet=3, task_max=90):
    entries = []
    blocked = False
    for command in ("nmi", "sendkey alt-sysrq-w", "sendkey alt-sysrq-t"):
        if command == "sendkey alt-sysrq-t" and blocked:
            break
        if abandoned.is_set():
            return entries
        before = len(machine.full_console_log)
        try:
            raw = re.sub(r"\x1b\[[0-9;]*[A-Za-z]|\r", "", machine.send_monitor_command(command))
            # HMP echoes the command (as readline redraws) and its prompt; the rest is an answer.
            reply = "\n".join(line for line in raw.splitlines()
                              if line.strip() not in ("", "(qemu)") and not line.endswith(command))
        except Exception as error:
            entries.append(f"monitor command failed: {error!r}")
            continue
        if command == "sendkey alt-sysrq-t":
            sent = time.monotonic()
            last_line = sent
            console_length = before
            while not abandoned.is_set():
                now = time.monotonic()
                length = len(machine.full_console_log)
                if length > console_length:
                    last_line = now
                console_length = length
                remaining = min(sent + task_max - now, last_line + quiet - now)
                if remaining <= 0:
                    break
                if abandoned.wait(min(0.2, remaining)):
                    break
            waited = time.monotonic() - sent
        else:
            time.sleep(watch)
        new = machine.full_console_log[before:]
        if command == "sendkey alt-sysrq-w":
            blocked = any("state:D" in line for line in new)
        if command == "sendkey alt-sysrq-t":
            entry = (f"poke {command}: {len(new)} console lines within {waited:.0f} s "
                     f"(quiet {quiet} s)")
        else:
            entry = (f"poke {command}: {len(new)} console lines within {watch} s" if new else
                     f"poke {command}: no console output within {watch} s")
        entry += "".join("\n  " + line.replace("\r", "") for line in new[:POKE_MAX_LINES])
        if reply:
            entry += f"\n  monitor replied: {reply}"
        if len(new) > POKE_MAX_LINES:
            entry += "\n  (" + str(len(new) - POKE_MAX_LINES) + " more console lines not shown)"
        entries.append(entry)
    return entries


def _diagnose(machine, probe_timeout, poke_watch=None, quiet=3, task_max=90):
    """Monitor registers first (they answer a frozen guest), then the #1365 probe."""
    monitor_dump = []
    abandoned = threading.Event()

    def sample_monitor():
        for sample in (1, 2):
            def send(command):
                try:
                    response = machine.send_monitor_command(command).replace("\r", "")
                except Exception as error:
                    response = f"monitor command failed: {error!r}"
                entry = f"monitor sample {sample} ({command}):\n{response}"
                monitor_dump.append(entry)
                print(entry)
                return response

            cpus = send("info cpus")
            send("info registers -a")
            for cpu in re.findall(r"CPU #(\d+)", cpus):
                send(f"cpu {cpu}")
                send("info lapic")
            for command in ("info pic", "info irq"):
                send(command)
            reply = send("info virtio")
            # Never `info virtio-status`: it segfaults QEMU 11.1.2 (tests/AGENTS.md#boot-hang-detect).
            # Walk queues until the monitor says the index is past the last one.
            for path in re.findall(r"^(/\S+) \[", reply, re.M):
                for queue in range(64):
                    if "Invalid virtqueue number" in send(f"info virtio-queue-status {path} {queue}"):
                        break
            if sample == 1:
                time.sleep(5)
        if poke_watch is not None:
            for entry in _poke(machine, poke_watch, abandoned, quiet, task_max):
                monitor_dump.append(entry)
                print(entry)
            entry = "a guest that printed after a poke still fails this check"
            monitor_dump.append(entry)
            print(entry)

    monitor_thread = threading.Thread(target=sample_monitor, daemon=True)
    monitor_thread.start()
    budget = 30 if poke_watch is None else 30 + 2 * poke_watch + task_max + 5
    monitor_thread.join(timeout=budget)
    if monitor_thread.is_alive():
        abandoned.set()
        entry = f"monitor did not answer within {budget} s"
        monitor_dump.append(entry)
        print(entry)

    # #1365: say what systemd is stuck on before failing. Bounded in a thread,
    # because connect() can block with no timeout on a frozen guest (#1260).
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
    return "\n".join(monitor_dump)
