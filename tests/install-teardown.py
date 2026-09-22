"""Bounded teardown using real unresponsive children, without booting a VM."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import textwrap
import threading
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parent
TESTS = ("install", "free-space", "install-encrypted", "install-iso",
         "install-iso-net", "reinstall-vm")


def child(mode):
    namespace = {}
    helper = ROOT / "vm-cleanup.py"
    if helper.exists():
        exec(helper.read_text(), namespace)
        cleanup = namespace["reap_owned_vms"]
    else:
        # Exercise the actual previous monitor-based cleanup, not a quotation
        # of the proposed fix. A stuck monitor must not turn failure into hang.
        source = (ROOT / "install-iso.nix").read_text()
        reap = source[source.index("    def reap():"):source.index("    try:\n        # A blank disk")]
        exec(textwrap.dedent(reap), namespace)

        def cleanup(machines):
            namespace["vms"] = machines
            namespace["reap"]()

    process = subprocess.Popen(
        [sys.executable, "-c", "import signal,threading; "
         "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
         "print('ready', flush=True); threading.Event().wait()"],
        stdout=subprocess.PIPE,
    )
    assert process.stdout.readline() == b"ready\n"
    reader = threading.Thread(target=lambda: list(process.stdout))
    if mode == "reader-stuck":
        reader = threading.Thread(target=threading.Event().wait)
    if mode != "partial":
        reader.start()
    if mode == "exited":
        process.kill()
        process.wait(timeout=5)
        reader.join(timeout=5)
    machine = SimpleNamespace(
        process=process, serial_thread=reader if mode != "partial" else None,
        name="unresponsive", send_monitor_command=lambda _: process.wait(),
    )
    if mode == "wrapper":
        def create_machine(command, **kwargs):
            assert command == "exec qemu", command
            assert kwargs["name"] == "fixture", kwargs
            return machine

        exec(Path(os.environ["VM_CLEANUP_WRAPPER"]).read_text(),
             {"create_machine": create_machine})
        raise AssertionError("wrapper swallowed the assertion")
    try:
        if mode not in ("success", "exited"):
            raise AssertionError("ORIGINAL INSTALL ASSERTION")
    finally:
        cleanup([machine, SimpleNamespace(process=None, serial_thread=None)])
    assert process.poll() == -signal.SIGKILL, "guest was not killed/reaped"
    assert not reader.is_alive(), "serial reader survived cleanup"
    print("unresponsive guest reaped")


def main():
    modes = ["failure", "success", "exited", "partial", "reader-stuck"]
    if "VM_CLEANUP_WRAPPER" in os.environ:
        modes.append("wrapper")
    for mode in modes:
        proc = subprocess.Popen(
            [sys.executable, __file__, "--child", mode],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            output, _ = proc.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            output, _ = proc.communicate()
            raise AssertionError(f"{mode}: cleanup exceeded 15s\n{output.decode()}")
        finally:
            # Also reap leaked descendants when a broken helper returns early.
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        output = output.decode()
        assert (proc.returncode == 0) == (mode in ("success", "exited")), output
        if mode not in ("success", "exited"):
            assert "ORIGINAL INSTALL ASSERTION" in output, output
        if mode == "reader-stuck":
            assert "serial reader did not exit" in output, output
        print(f"PASS {mode}: bounded exit, original outcome preserved")

    for name in TESTS:
        source = (ROOT / f"{name}.nix").read_text()
        if "testScript = import ./with-vm-cleanup.nix pkgs.lib ''" in source:
            assert "create_owned_machine(" in source, name
            assert not any("create_machine(" in line and not line.lstrip().startswith("#")
                           for line in source.splitlines()), name
        else:
            assert "testScript = builtins.readFile ./vm-cleanup.py + ''" in source, name
            assert "finally:\n        reap_owned_vms(vms)" in source, name
            assert source.count("vms.append(") == 2, name
            assert source.count('"exec ${') == 2, name
    print("PASS all six install scripts register dynamic machines for cleanup")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        child(sys.argv[2])
    else:
        main()
