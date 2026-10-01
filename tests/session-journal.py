import shlex


def invocation_journal(machine, command, expected, invocation):
    """Wait for one completed rebuild invocation's program output."""
    probe = "out=$(" + command + "); grep -Fq -- " + shlex.quote(expected) + ' <<<"$out"'
    try:
        machine.wait_until_succeeds(probe, timeout=30)
    except Exception as exc:
        latest = machine.succeed(command)
        raise AssertionError(
            "timed out waiting for " + repr(expected) + " in invocation "
            + invocation + ":\n" + latest
        ) from exc
    log = machine.succeed(command)
    assert log.strip(), "the detached unit's journal for " + invocation + " is empty"
    assert expected in log, (
        "the detached unit's journal for " + invocation
        + " lacks " + repr(expected) + ":\n" + log)
    return log
