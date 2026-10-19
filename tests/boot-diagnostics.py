"""wait_for_multi_user against stub machines: no VM needed."""

import contextlib
import io
import sys
import threading
import time
from pathlib import Path

ns = {}
exec((Path(__file__).resolve().parent / "vm-cleanup.py").read_text(), ns)
wait = ns["wait_for_multi_user"]


class Stub:
    def __init__(self, console, execute):
        self._console, self._execute, self.executed = console, execute, False

    def wait_for_console_text(self, pattern, timeout):
        self._console()

    def execute(self, cmd, timeout):
        self.executed = True
        return self._execute()


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def run(machine, **kw):
    buf = io.StringIO()
    raised = None
    with contextlib.redirect_stdout(buf):
        try:
            wait(machine, **kw)
        except Exception as e:
            raised = e
    return raised, buf.getvalue()


def boom():
    raise TimeoutError("ORIGINAL TIMEOUT")


# 1: success never probes
m = Stub(lambda: None, lambda: (0, ""))
raised, out = run(m)
if raised is not None or m.executed:
    fail("the probe ran on a successful boot")
print("PASS 1: success does not probe")

# 2: timeout with an answer prints it and re-raises the original
m = Stub(boom, lambda: (0, "a.service start running"))
raised, out = run(m)
if not isinstance(raised, TimeoutError) or "ORIGINAL TIMEOUT" not in str(raised):
    fail("the original failure was swallowed")
if "a.service start running" not in out:
    fail("the guest's answer was not printed")
print("PASS 2: answer printed, original failure re-raised")

# 3: a guest that never answers must not hang the helper
never = threading.Event()
m = Stub(boom, lambda: never.wait() or (0, ""))
start = time.monotonic()
raised, out = run(m, probe_timeout=1)
elapsed = time.monotonic() - start
if elapsed >= 10:
    fail("the probe was not bounded")
if not isinstance(raised, TimeoutError):
    fail("the original failure was swallowed")
if "no answer from the guest within 1 s" not in out:
    fail("the silent guest was not reported")
print(f"PASS 3: bounded ({elapsed:.1f} s)")
