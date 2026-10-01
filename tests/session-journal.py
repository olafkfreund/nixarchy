def invocation_journal(machine, command, expected, invocation):
    """Read one completed rebuild invocation's journal."""
    log = machine.succeed(command)
    assert log.strip(), "the detached unit's journal for " + invocation + " is empty"
    assert expected in log, (
        "the detached unit's journal for " + invocation
        + " lacks " + repr(expected) + ":\n" + log)
    return log
