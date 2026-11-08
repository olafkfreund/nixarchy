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
DEV0 = "/machine/peripheral-anon/device[0]/virtio-backend"
DEV1 = "/machine/peripheral-anon/device[1]/virtio-backend"


class Stub:
    def __init__(self, console, execute):
        self._console, self._execute, self.executed = console, execute, False
        self.full_console_log = []
        self.commands = []

    def send_monitor_command(self, command):
        self.commands.append(command)
        if command == "info cpus":
            return "* CPU #0: thread_id=1\r\n"
        if command == "info virtio":
            return f"{DEV0} [virtio-blk]\r\n{DEV1} [virtio-serial]\r\n"
        for dev, count in ((DEV0, 2), (DEV1, 3)):
            if command.startswith(f"info virtio-queue-status {dev} "):
                q = int(command.rsplit(" ", 1)[1])
                return f"Error: Invalid virtqueue number {q}\r\n" if q >= count else "  used_idx: 0\r\n"
        if command == "nmi":
            self.full_console_log.append("Uhhuh. NMI received for unknown reason 00 on CPU 0.")
        if command == "nmi" or command.startswith("sendkey "):
            # A real HMP reply: readline redraws of the command, then the prompt.
            redraw = "".join(f"{command[:i]}\x1b[K" + "\x1b[D" * i for i in range(1, len(command) + 1))
            return f"{redraw}\r\n(qemu) "
        return "CPU#0\r\nEIP=000ebd8b\r\n"

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
if "nmi" in m.commands:
    fail("the exception path poked the guest")
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
if "nmi" in m.commands:
    fail("the exception path poked the guest")
print(f"PASS 3: bounded ({elapsed:.1f} s)")

# 4: no console growth across windows fails on silence, with the monitor dump
def window_ends():
    time.sleep(0.2)
    raise ns["RequestedAssertionFailed"]("window")


m = Stub(window_ends, lambda: (0, ""))
start = time.monotonic()
raised, out = run(m, silence=1, probe_timeout=1, poke_watch=0.1)
elapsed = time.monotonic() - start
if not isinstance(raised, ns["BootHang"]) or "console silent" not in str(raised):
    fail(f"silence was not detected: {raised!r}")
if "EIP=" not in raised.monitor_dump:
    fail("the monitor dump was not attached")
if "\r" in raised.monitor_dump or "\r" in out:
    fail("the monitor dump contains carriage returns")
if elapsed >= 15:
    fail(f"silence took {elapsed:.1f} s to fire")
c = m.commands
for command in ("info lapic", "info pic", "info irq"):
    if c.count(command) != 2:
        fail(f"{command} sent {c.count(command)} times, not once per sample")
if any(c[i - 1] != "cpu 0" for i, x in enumerate(c) if x == "info lapic"):
    fail("info lapic was not preceded by cpu 0")
queues = [x for x in c if x.startswith("info virtio-queue-status ")]
# Every queue of every device, then the one index past the last, in each sample.
want = [f"info virtio-queue-status {DEV0} {q}" for q in range(3)] + [
    f"info virtio-queue-status {DEV1} {q}" for q in range(4)]
if queues != want * 2:
    fail(f"wrong virtio queues sampled: {queues}")
if any(x.startswith("info virtio-status") for x in c):
    fail("info virtio-status was sent; it segfaults QEMU 11.1.2")
if "nmi" not in c or "sendkey alt-sysrq-w" not in c or c.index("nmi") > c.index("sendkey alt-sysrq-w"):
    fail(f"pokes missing or out of order: {c[-3:]}")
for text in ("poke nmi: 1 console lines", "NMI received for unknown reason",
             "poke sendkey alt-sysrq-w: no console output"):
    if text not in raised.monitor_dump:
        fail(f"{text!r} not in the monitor dump")
if "monitor replied:" in raised.monitor_dump:
    fail("the monitor's echo of a poke was reported as a reply")
print(f"PASS 4: silence detected with registers ({elapsed:.1f} s)")

# 5: an abandoned diagnosis sends no poke
ev = threading.Event()
ev.set()
m = Stub(lambda: None, lambda: (0, ""))
ns["_poke"](m, 0.1, ev)
if m.commands != []:
    fail(f"an abandoned diagnosis still poked: {m.commands}")
print("PASS 5: abandoned diagnosis sends nothing")


# 6: an HMP rejection of a poke is shown, not read as silence
class Rejecting(Stub):
    def send_monitor_command(self, command):
        if command.startswith("sendkey "):
            return "unknown key: 'x'\r\n"
        return super().send_monitor_command(command)


entries = ns["_poke"](Rejecting(lambda: None, lambda: (0, "")), 0.1, threading.Event())
if "monitor replied: unknown key" not in "\n".join(entries):
    fail(f"the monitor's rejection was not shown: {entries}")
print("PASS 6: monitor rejection shown")
