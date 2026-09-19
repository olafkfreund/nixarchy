---
status: approved
issue: 714
spec: spec/2026-09-16-714-install-fail-fast.md
---

# Plan: bounded dynamic-VM cleanup

Owner approved the revised stages on 2026-09-19. The original branch remains
untouched. Pinned nixpkgs is e554fab72f81915600f3f449b786fd9af40439a5:
create_machine does not register machines, shutdown waits without a deadline,
release joins a non-daemon serial reader without a deadline, and StartCommand
uses shell=True. The old approved fallback cannot handle the reported failure.

## Decisions

Use a shared script wrapper and factory registering machines before start.
Prefix direct qemu commands with exec so the driver's Popen owns qemu.
Finally kill all owned processes, bounded wait and serial join, no guest RPC.
If cleanup cannot complete, print the original exception and fail with os._exit
rather than hanging in interpreter thread shutdown. Keep restart shutdowns.
Three tests use the wrapper; the three ISO tests retain their existing lists
and finally blocks, calling the same helper instead of monitor reapers.
No driver/job timeout, deployment, or installed-system behavior changes.

## Steps

1. Add an executable cheap subprocess regression and prove the old cleanup
   fails. Include source wiring checks for all six tests.
2. Add tests/vm-cleanup.py and tests/with-vm-cleanup.nix. Update the six
   install/free-space/encrypted/ISO/ISO-net/reinstall test scripts, keeping all
   assertions and intentional restart operations.
3. Add checks.install-teardown and name it in the PR-triggered build workflow.
   Maintainer reviews this check addition; no existing gates are weakened.
4. Prove regression red with kill removed, restore, run green. Check syntax,
   Nix formatting/lint, and rendered wrapper type checks when resources permit.
5. Document actual pinned-driver contracts and limitations in tests/AGENTS.md.
6. Commit, coordinate root before pushing/opening PR, include evidence and
   Closes #714. Do not merge or deploy. Full VM integration is left to CI unless
   the shared build slot is explicitly granted.

## Tests

python3 tests/install-teardown.py
nix build .#checks.x86_64-linux.install-teardown --print-build-logs
nix fmt -- --ci; statix check; deadnix --fail

The subprocess checks fail on leaked/unresponsive children, lost assertion text,
unbounded reader cleanup, omitted factory registration and missing test wiring.
A real install remains unrun locally until coordinated; report that limit.

## Rollback

Revert the implementation commit. Failed dynamic VM tests may again occupy a
slot until the job timeout. No persistent host configuration changed.
