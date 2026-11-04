---
status: draft
issue: 1594
spec: spec/2026-11-04-1594-boot-hang-diagnostics.md
coders:
  1: codex   # small, tricky timing logic in one Python function: windows, clamps, threads
  2: coder   # a new nixosTest file plus one flake entry, following hibernate-resume
  3: coder   # two list or step edits mirroring wifi-hwsim/hibernate-resume
  4: coder   # one prose paragraph in tests/AGENTS.md
reviewers:
  - codex    # independent read of the timing loop against the driver
  - agy      # independent read of the check's ability to fail, and CI placement
---

# Plan: Fail fast with evidence when an install target's boot hangs

## Decisions carried over from the approved spec

- Only `tests/vm-cleanup.py` changes behaviour. The two callers
  (`tests/install.nix:371`, `tests/free-space.nix:574`) are not edited.
- `wait_for_multi_user(machine, timeout=900, probe_timeout=90, silence=120)`
  works like this:
  - It reads `n = len(machine.full_console_log)` on entry.
  - It loops over `machine.wait_for_console_text(regex, timeout=timedelta(seconds=w))`
    with `w = max(1, min(15, silence_left, budget_left))`.
  - It catches only `RequestedAssertionFailed`, imported from
    `test_driver.errors`.
  - If the log grew, the silence clock resets. If there has been no growth
    for `silence` s, it fails with reason "console silent for N s". If the
    budget runs out, it fails with "multi-user not reached within N s".
- On either failure, in order:
  1. A daemon thread joined at most 30 s runs `info cpus` and
     `info registers -a`, sleeps 5 s, then runs both again.
  2. The helper **prints each response** and keeps it, labelled with the
     sample number. A join that expires prints "monitor did not answer
     within 30 s".
  3. The existing #1365 systemd probe runs, unchanged, bounded by
     `probe_timeout`.
  4. The helper raises with the reason and the captured monitor text, as an
     `AssertionError` subclass or by attaching `.monitor_dump`, so a test
     can assert on it without scraping the log.
- 120 s is about 19× the longest healthy gap measured (6.4 s over 65 waits).
- No sysrq, no retry, no change to the shipped closure.
- `checks.boot-hang-detect` has two nodes:
  - **`frozen`:** started, then `stop`ped on the monitor at once. It calls
    `wait_for_multi_user(frozen, timeout=120, silence=20, probe_timeout=5)`
    and must raise with "console silent" in under 60 s, with the dump
    holding register output (`RIP=` or `RIP `).
  - **`healthy`:** a separate fresh node, never the stopped one resumed. It
    must return from the same helper.
- CI placement: claimed in `generated-checks.sh` and built in `build.yml`'s
  KVM job, beside `hibernate-resume`. Both are CI-gate edits, and a human
  merges (§11).
- RIPs are printed raw. `tests/AGENTS.md` names the lookup against the
  reference kernel's `System.map`, and nothing symbolises inline (YAGNI).

## Steps

1. **`tests/vm-cleanup.py:45-66`:** rewrite `wait_for_multi_user` per the
   decisions above. Keep the #1365 probe body and its comments. Add
   `import datetime` and `from test_driver.errors import
   RequestedAssertionFailed` at the top. One short comment at the loop: why
   the windows are clamped, and why only that exception is caught.
   → verify: `python3 -c 'import ast,sys;ast.parse(open("tests/vm-cleanup.py").read())'`;
   `nix build .#checks.x86_64-linux.grep-q-pipefail` (cheap). Step 2's check
   is the behavioural proof.
   Traps:
   - Don't keep a `StringIO` across windows (the spec rejected scanning the
     log ourselves, because of the `last_lines` queue).
   - The monitor thread must not be joined without a timeout.
   - §5: the file is prepended verbatim into Nix `''` strings by
     `with-vm-cleanup.nix` and `install-iso*.nix`. So no `${`, and no line
     that starts with `''`.

2. **`tests/boot-hang-detect.nix` (new), `flake.nix` checks:**
   - A `runNixOSTest` named `nixarchy-boot-hang-detect`, nodes `frozen` and
     `healthy` (memorySize 1024).
   - `testScript = builtins.readFile ./vm-cleanup.py + ''…''`, with
     cases A then B as decided.
   - Assert the elapsed time with `time.monotonic()`.
   - Header comment: two lines, pointing at `tests/AGENTS.md`.
   - Register it in `flake.nix` next to `hibernate-resume`'s entry, in both
     the attribute and the name list at line ~1886.
   → verify: `git add`, `nix eval .#checks.x86_64-linux.boot-hang-detect.drvPath`.
   Traps:
   - §5: `git add` before eval.
   - Check that the nixosTest console actually prints "Reached target
     Multi-User System" for `healthy`. If it doesn't, case B can't pass, so
     stop and report rather than change the regex.

3. **`.github/scripts/generated-checks.sh:41` and `.github/workflows/build.yml:~2034`:**
   - Add `boot-hang-detect` to `claimed`.
   - Add a step after the `hibernate-resume` one: `if:
     needs.gate.outputs.relevant == 'true'`, running
     `build-unless-proven.sh .#checks.x86_64-linux.boot-hang-detect`, with a
     one-line comment (a nixosTest that needs this job's /dev/kvm).
   → verify: the claim-consistency checks that `build.yml` runs on the lists,
   locally (`bash .github/scripts/generated-checks.sh generated` must not
   list it), plus `actionlint`.
   Traps:
   - §4: claimed and built must agree in both directions.
   - Relevance is already right: `pr-touches-build.sh` is a denylist
     (header, lines 23–32), so `tests/vm-cleanup.py` and the new test make
     `relevant=true`. Confirm with
     `printf 'tests/vm-cleanup.py\n' | .github/scripts/pr-touches-build.sh -`
     → `true`, and the same with `--install` (`install-gate.nix:45`).

4. **`tests/AGENTS.md`:** one paragraph, placed where install checks and
   `vm-cleanup.py` are discussed (grep `vm-cleanup` there first, §12). It
   covers:
   - the silence detector and its 120 s threshold, with the measurement
     behind it;
   - what each detector's failure line means;
   - how to read the dump: halted vs same-RIP vs moving RIP;
   - the `System.map` lookup command against the reference kernel;
   - why there's no sysrq.
   → verify: the generated cheap checks in step 5, which include any check
   that reads `tests/AGENTS.md`.

5. **Mine: the proofs and the builds (§1, the local-checks rule).**
   - All cheap tier at any time: the 161 generated checks plus
     `grep-q-pipefail`, under `flock`, then `nix fmt -- --ci`, `statix`,
     `deadnix`.
   - VM tier only when `gh run list` shows nothing in flight:
     `boot-hang-detect` must be green.
   - **Break:** comment out the silence branch, commit as temporary, build
     `boot-hang-detect` and capture the red (elapsed ≥ 60 s or wrong
     reason). Restore with `git checkout HEAD~ -- tests/vm-cleanup.py` (§5:
     not `git checkout --`), then green again.
   - Build `checks.install` locally only if CI is idle and the load gate
     passes, or leave it to the PR's install job and say so.
   - Squash to a real subject (§8), open the PR linking all three artifacts,
     post "@codex review", and arm `--auto --squash`. The PR body says it is
     a CI-gate change for a human to merge.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.boot-hang-detect` | green; red with the silence branch removed |
| PR install job (install + free-space) | green: healthy boots pass the windowed wait |
| generated checks + `grep-q-pipefail` + fmt/statix/deadnix | green |

## Rollback

Revert the squash commit. The helper goes back to one 900 s wait, and the
new check and its claim and step go with it.
