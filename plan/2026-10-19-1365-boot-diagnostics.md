---
status: approved
issue: 1365
spec: spec/2026-10-19-1365-boot-diagnostics.md
---

# Plan: an install VM that never reaches multi-user.target says why

Approved decisions, carried from the spec:

- One helper, `wait_for_multi_user(machine, timeout=900, probe_timeout=90)`,
  in the prelude `install` and `free-space` already share. On a console
  timeout it queries the guest (`systemctl list-jobs`, `systemctl --failed`,
  the last 80 warning journal lines) in a daemon thread bounded by
  `join(probe_timeout)` (#1260: `connect()` can block forever). It prints the
  answer, or "no answer from the guest within N s", then **re-raises the
  original exception**.
- Both 900 s waits call it. Passing runs never reach the probe.
- A new cheap `checks.boot-diagnostics` exercises the helper against three
  stub machines (success; timeout with an answer; timeout with a guest that
  never answers). No VM is needed.
- Five files, so the `coder` agent implements steps 1-4 and the lead commits.

**Location:** the shared prelude is `tests/with-vm-cleanup.nix`, which inlines
`tests/vm-cleanup.py` with `builtins.readFile`. The helper goes in
**`tests/vm-cleanup.py`**: it is part of the same prelude, and plain Python
that the new check can `exec` directly, as `tests/install-teardown.py`
already does with `reap_owned_vms`.

## Steps

1. **`tests/vm-cleanup.py`: add the helper** after `reap_owned_vms`, exactly
   as in the spec (comment: `# #1365: say what systemd is stuck on before
   failing. Bounded in a thread, because connect() can block with no timeout
   on a frozen guest (#1260).`). `import threading` goes at the file's top
   with its other imports.
   → verify: `python3 -c 'exec(open("tests/vm-cleanup.py").read())'` runs.
   Traps: the file is inlined into a `''…''` Nix string, so no `''` or `${`
   may appear in it.

2. **`tests/install.nix:371` and `tests/free-space.nix:574`.** Replace
   `machine.wait_for_console_text(r"Reached target Multi-User System", timeout=900)`
   with `wait_for_multi_user(machine)`, and the free-space one
   (`target.…`) with `wait_for_multi_user(target)`. Leave the following
   `wait_for_unit("multi-user.target")` lines and the #1260 comments alone.
   → verify: `grep -n 'Reached target Multi-User System' tests/*.nix` lists no
   call outside `tests/vm-cleanup.py`.

3. **`tests/boot-diagnostics.py` and `tests/boot-diagnostics.nix`, the new
   check**, modelled on `tests/install-teardown.{py,nix}`:
   - The `.py` `exec`s `tests/vm-cleanup.py` into a namespace, defines a stub
     class with `wait_for_console_text(self, pattern, timeout)` and
     `execute(self, cmd, timeout)`, and asserts the three cases from the spec.
     Capture stdout with `contextlib.redirect_stdout`. For case 3, `execute`
     waits on a `threading.Event` that is never set, the call uses
     `probe_timeout=1`, and the case asserts the elapsed time is under 10 s.
     Each failure prints a named message (`"the original failure was
     swallowed"`, `"the probe ran on a successful boot"`, `"the probe was not
     bounded"`) and the script exits 1.
   - The `.nix` is a `pkgs.runCommand "nixarchy-boot-diagnostics"` with
     `python3Minimal`, running `python3 ${./.}/boot-diagnostics.py` and then
     `touch "$out"`.
   → verify: `python3 tests/boot-diagnostics.py` exits 0.

4. **`flake.nix`: register it** beside `install-teardown` (line 2650):
   `boot-diagnostics = import ./tests/boot-diagnostics.nix { pkgs = pkgsFor.${system}; };`
   with a one-line comment. No workflow edit: the generated-checks step builds
   it (CLAUDE.md §4).
   → verify: `nix eval .#checks.x86_64-linux.boot-diagnostics.drvPath`.
   Traps: `git add` new files before evaluating (§5). Run `nix fmt`, then
   `git diff --stat`.

5. **Lead: prove and commit** (cheap tier, under
   `flock /mnt/data/vmtest/codex-build.lock`):
   - `nix build .#checks.x86_64-linux.boot-diagnostics -L` green;
     `checks.install-teardown` green.
   - Break A: delete the helper's `raise`, so case 2 goes red with "the
     original failure was swallowed".
   - Break B: call `probe()` directly instead of in the thread, so case 3
     goes red with "the probe was not bounded" (or times out the check). Use a
     short outer `timeout 120` so the build cannot hang.
   - Restore with `git checkout HEAD --` after committing (§5), and rebuild
     green.
   - Build the install drivers (type check and lint, no VM):
     `.#checks.x86_64-linux.install.driver` and `.free-space.driver`.
   - Commit "Install checks say what systemd is stuck on when the installed
     machine never reaches multi-user.target (#1365)". Open the PR with the
     outputs and `Refs #1365`, which stays open until an occurrence is
     diagnosed.

## Tests

`checks.boot-diagnostics` green, plus red for breaks A and B;
`checks.install-teardown` green; both drivers build; the PR's `install` job is
green.

## Rollback

Revert the commit. The two call sites return to the bare
`wait_for_console_text`.
