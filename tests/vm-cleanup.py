import os
import sys
import traceback


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
