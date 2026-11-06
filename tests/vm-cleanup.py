import datetime
import os
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


def wait_for_multi_user(machine, timeout=900, probe_timeout=90, silence=120):
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
            dump = _diagnose(machine, probe_timeout)
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


def _diagnose(machine, probe_timeout):
    """Monitor registers first (they answer a frozen guest), then the #1365 probe."""
    monitor_dump = []

    def sample_monitor():
        for sample in (1, 2):
            for command in ("info cpus", "info registers -a"):
                try:
                    response = machine.send_monitor_command(command).replace("\r", "")
                except Exception as error:
                    response = f"monitor command failed: {error!r}"
                entry = f"monitor sample {sample} ({command}):\n{response}"
                monitor_dump.append(entry)
                print(entry)
            if sample == 1:
                time.sleep(5)

    monitor_thread = threading.Thread(target=sample_monitor, daemon=True)
    monitor_thread.start()
    monitor_thread.join(timeout=30)
    if monitor_thread.is_alive():
        monitor_dump.append("monitor did not answer within 30 s")
        print("monitor did not answer within 30 s")

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
