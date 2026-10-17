---
status: draft
issue: 1313
spec: spec/2026-10-17-1313-nixarchy-menu-connections-crash.md
---

# Plan: Enabling nixarchy-menu must not crash the shell

Branch `fix/1313-nixarchy-menu-connections-crash`, worktree
`/mnt/data/vmtest/wt-1313`, cut from `main` at `9c42160c`.

## Approved decisions (spec revision 2)

- **D1.** Only nixarchy-menu's panel loads synchronously.
  - In the vendored `shell/shell.qml` `panelLoader` (4.0.4, lines 1404–1405),
    `asynchronous: true` becomes `asynchronous: panelEntry.pluginId !== "nixarchy.menu"`.
  - The anchor is two lines: the `active: … openPanelIds …` line plus the
    `asynchronous: true` under it. It is applied with `--replace-fail` from
    `pkgs/omarchy/default.nix`, beside the other carried shell edits.
  - Every other plugin keeps its asynchronous load. That keeps the Mode A
    constraint, by the owner's decision of 2026-10-17.
- **D2.** `checks.session` fails with `#1313: Quickshell crashed during the
  session` when either of these holds:
  - the boot journal has a `(.quickshell-wra) … terminated abnormally` line
    (note the leading dot) or a `Quickshell has crashed` line;
  - `/home/omarchy/.cache/quickshell/crashes` is not empty.

  It is checked right after the #1283 probe enables nixarchy-menu, and again
  at the end of the test script.
  - A `journalctl` that errors fails the check; it never reads as "no crash".
  - No `coredumpctl`.
  - The existing #1283 assertion and its 60 s retry are unchanged.
- **D3.** The probe prints `#1313 timing: row Xs, plugin-list answered Ys
  after it`. It is not asserted anywhere.
- **Follow-ups, not code in this PR:**
  - An issue in `olafkfreund/nixarchy-menu` for its fragile `Connections`,
    with fix (a)'s diff and the backtrace.
  - The PR asks the owner whether omacom/omarchy should hear about it. The
    default is no, because the defect is nixarchy-menu's.

Evidence lives in `/mnt/data/vmtest/scratch-1313/`:
- `loop-results.txt`: unpatched 3/3 SEGV; fix (a) 1/3.
- `b-results.txt`: fix (b) 2/2 clean, plus D1's own runs n-1..n-6 once team-1305
  reports them.
- `vm-run2.clean.log:3234,3238`: the two journal lines D2 matches.

## Steps

Steps 1–3 edit files. The coder does them, one step per message. Steps 4–7
are the lead's.

1. **D1, the carry.**
   - New `pkgs/omarchy/1313-panel-loader.old.qml`: exactly these two lines,
     with their 8-space indent, copied from the built
     `share/omarchy/shell/shell.qml:1404-1405`:
     ```
             active: panelEntry.sourceUrl !== "" && (panelEntry.keepLoaded || shell.openPanelIds[panelEntry.pluginId] === true)
             asynchronous: true
     ```
   - New `pkgs/omarchy/1313-panel-loader.new.qml`: the same first line, then
     `        asynchronous: panelEntry.pluginId !== "nixarchy.menu"`.
   - `pkgs/omarchy/default.nix`: after the `902-notification-sender-close.patch`
     line (~2110) and its blank line, add:
     ```
                         # Why: pkgs/AGENTS.md#nixarchy-menu-loads-synchronously-1313
                         substituteInPlace $out/share/omarchy/shell/shell.qml \
                           --replace-fail "$(cat ${./1313-panel-loader.old.qml})" "$(cat ${./1313-panel-loader.new.qml})"
                     ```
     One comment line only: the install phase has about 1,450 bytes left of its
     123,000 budget, and #1311 adds to it too. The `# Why:` pointer carries the
     reasoning (§7). The `$(cat …)` form is the one `1301-pkg-has.{old,new}.js` already uses.
     It keeps the install phase small (`checks.install-phase-budget`) and
     needs no quoting of the QML.
   - `pkgs/AGENTS.md`: a new section after the #1301 one, with anchor
     `<a id="nixarchy-menu-loads-synchronously-1313"></a>` and heading `## nixarchy-menu loads
     synchronously (#1313)`. About 20 lines, covering:
     - the backtrace (`QQmlConnections::setTarget` ← `connectSignalsToMethods`,
       inside `QsIncubationController::incubate`);
     - `providers/Applications.qml:32`;
     - the two routes;
     - fix (a) at 1/3 against D1's result;
     - why only nixarchy-menu (Mode A, owner's decision);
     - that a future keepLoaded plugin with the same pattern is unprotected;
     - the drop condition: nixarchy-menu survives an asynchronous load,
       proven with the same runs;
     - the follow-up issue's number, filled in at step 7.
   - Verify:
     ```
     out=$(nix build --no-link --print-out-paths .#omarchy) && grep -c 'asynchronous: panelEntry.pluginId !== "nixarchy.menu"' $out/share/omarchy/shell/shell.qml
     ```
     It prints `1`. `grep -c '^        asynchronous: true' $out/share/omarchy/shell/shell.qml`
     prints `0`, and `grep -c '^    asynchronous: true'` still prints `1`
     (line 266's bar loader is untouched).
   - Traps:
     - New files need `git add` before any `nix build` (§5).
     - An editor hook may run nixpkgs-fmt: run `nix fmt` and read
       `git diff --stat` (§5).
     - Non-cheap tier (§6): no p620 system build. The lead runs the
       `pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` gate; the
       owner waived the load<12 gate today.

2. **D2 and D3, the probe.** `tests/session.nix`.
   - Above `marker = "/home/omarchy/.local/state/nixarchy/enabled-once/nixarchy.menu"`
     (~line 868), define:
     ```python
         def quickshell_crashed(where):
             # #1313: a shell that crashed and restarted still fails. The journal
             # line is written at the crash; a stored core may never be.
             status, journal = machine.execute("journalctl -b -o cat --no-pager")
             assert status == 0, f"#1313: journalctl exited {status} {where}"
             hits = [l for l in journal.splitlines()
                     if ("(.quickshell-wra)" in l and "terminated abnormally" in l)
                     or "Quickshell has crashed" in l]
             crash_dir = "/home/omarchy/.cache/quickshell/crashes"
             found = machine.succeed(f"find {crash_dir} -mindepth 1 -maxdepth 1 2>/dev/null || true").strip()
             report = machine.succeed(f"find {crash_dir} -name report.txt -exec head -30 {{}} + 2>/dev/null || true") if found else ""
             assert not hits and not found, (
                 f"#1313: Quickshell crashed during the session ({where}):\n"
                 + "\n".join(hits[:10]) + "\n" + found + "\n" + report)
     ```
   - Replace
     ```python
         click("setup.default.menu.nixarchy")
         stock, nix = menus()
     ```
     (the first pair, ~line 877) with:
     ```python
         t_row = time.time()
         click("setup.default.menu.nixarchy")
         t_done = time.time()
         stock, nix = menus()
         print(f"#1313 timing: row {t_done - t_row:.2f}s, plugin-list answered {time.time() - t_done:.2f}s after it")
         quickshell_crashed("after enabling nixarchy-menu")
     ```
     The `assert nix and not stock` that follows is unchanged.
   - At the very end of the test script, after the `qml_errors` assertion and
     before the closing `''`, add `quickshell_crashed("at the end of the session")`
     at the script's 4-space indent.
   - Verify:
     - `nix fmt -- --ci`;
     - `nix eval --raw .#checks.x86_64-linux.session.drvPath` evaluates;
     - `nix eval --raw .#checks.x86_64-linux.session.driver.testScript | grep -c quickshell_crashed`
       prints `3` (one definition, two calls). The script lives in the driver
       derivation, not the vm-test-run one.
     - `nix build --no-link .#checks.x86_64-linux.session.driver` succeeds.
       It is cheap, and nixpkgs runs `ty check` and `ruff check --select F` on
       the script, so a Python error shows here rather than six minutes into a VM.

     Do not build `session` here: it is a VM check (§6), and the lead runs it
     in step 4.
   - Traps:
     - This is a Nix `''` string. No `${` may appear, and the f-string braces
       above have none. `{{}}` is Python's literal `{}` for `find -exec`.
     - No heredoc (§5).
     - `time` is already imported (`tests/session.nix:281`).

3. **Docs.** `tests/AGENTS.md`: under the existing session-check material,
   add a short `#1313` paragraph, 3–6 lines. It says the probe now fails on
   any Quickshell crash in the boot, both at the switch and at the end. It
   says why the journal is used and not `coredumpctl`, citing the "No
   coredumps found" while 798 MB were being written, and the
   `.quickshell-wra` leading dot. Verify: `git diff --stat` shows one file.

4. **§1 proofs (lead, VM tier: only with `gh run list` showing 0 in flight).**
   Commit steps 1–3 first. Then build the proof tree from #1307's head, the
   same tree `loop-unpatched-1` crashed on, with steps 1–3 on top:
   ```
   git worktree add --detach /mnt/data/vmtest/wt-1313-proof 193c7d13
   git -C /mnt/data/vmtest/wt-1313-proof cherry-pick <step 1–3 commits>
   ```
   Merging HEAD instead conflicts in `tests/AGENTS.md` (#1307 against #1310).
   #1307 does not touch `tests/session.nix`. The cherry-picks are the
   committed baseline that the restores return to, and the tree `mkFlake`
   needs (§5). Evaluate each drv once and check it with
   `nix derivation show` before building `<drv>^*` (§5, the stale-evaluation
   trap). For Break A, `nix derivation show -r <drv> | grep -c 1313-panel-loader`
   prints `0`. For Break B, the driver's `testScript` contains the planted
   `mkdir` line. Use `git checkout HEAD --` to restore, never `git checkout --`.
   Confirm each break landed with `git diff` (§1).
   - **Break A:** delete the D1 `substituteInPlace` (both lines). Run 3
     times. Expected red each time:
     `#1313: Quickshell crashed during the session (after enabling nixarchy-menu)`.
     `loop-unpatched-1` is the recorded case where the old #1283 assertion
     alone passed over the crash (segv=1, switch_ok=1). Record whether any of
     the three is that case too. Each failure text must show both detectors,
     the journal lines and the crash-directory entry. If one is missing, that
     detector is blind (§1).
   - **Break B:** keep D1. Directly before the final
     `quickshell_crashed("at the end of the session")`, plant
     `machine.succeed("mkdir -p /home/omarchy/.cache/quickshell/crashes/proof-1313")`.
     Run once. Expected red: `#1313: Quickshell crashed during the session (at the end of the session)`.
     A real crash with the switch-time check removed does not work for this:
     the crash run that got past the switch (`loop-unpatched-1`) then failed
     on an unrelated `#1284` assertion and never reached the end.
   - **Restore** with `git checkout HEAD -- pkgs tests` and confirm
     `git status` is clean. Run twice, expecting green both times. The second
     run uses `nix build --rebuild '<drv>^*'`, because a successful build is
     cached and would otherwise run no VM. Each log
     has a `#1313 timing:` line, and neither has a
     `.quickshell-wra … terminated abnormally` line.
   - D1's six measurement runs (n-1..n-6, team-1305, same tree) must all be
     clean. They carry D2's checks as a scratch `check1313` at three points:
     after the enable, after the switch back, and at the end. Any crash rejects D1, and the plan goes back to the spec.
   - Save each log to `/mnt/data/vmtest/1313-proof-*.txt`.

5. **Startup cost (team-1305, VM tier, scratch only, not committed).**
   Method: a scratch `testScript` edit on the proof tree, placed right after the
   enable. It runs `omarchy-restart-shell` three times, as `on_desktop(...)`.
   Each sample is the time from the restart's return to the first successful
   `omarchy-plugin-list --json`, polled every 0.1 s. Run it with D1, and with
   Break A. Record the medians in the PR. On Break A a restart may itself
   crash: count a sample with a new `.quickshell-wra` journal line as a crash,
   not as a time. A slower start well inside the 60 s retry is accepted.

6. **Cheap checks (lead, under `flock`):** `install-phase-budget`, `omarchy`,
   `qml` (it lints the built, substituted `shell.qml`, `tests/qml.nix:83`),
   `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`,
   and `nix fmt -- --ci`. Before pushing, `git merge origin/main` and re-run
   `install-phase-budget`: #1312 and #1311 also add to the install phase.

7. **Follow-up and PR (lead).**
   - File `olafkfreund/nixarchy-menu` "Connections on `root.library` is
     retargeted during async incubation and can segfault Quickshell
     (nixarchy#1313)". The body carries the backtrace, the two routes and fix
     (a)'s diff, read from `scratch-1313`. Put its number in the
     `pkgs/AGENTS.md` section.
   - PR title: "Enabling nixarchy-menu no longer crashes the shell, and the
     session check fails on any Quickshell crash".
   - Body: closes #1313; links intent/spec/plan; says which steps the coder
     did; gives step 4's red and green outputs, step 5's numbers and the
     n-1..n-6 table; asks the omacom/omarchy question.
   - No `wip:` subject, no skip-CI marker (§8).
   - Push only when no install job is queued (§6). `merge-when-green.sh`
     applies; no override, because this is the PR that makes the session
     check mean something.
   - **Then:** merge `main` into #1307, #1311 and #1312 (if it is still open),
     and let their `checks.session` run green with no override (spec
     Verification 6).

8. **Edge carry (after merge, approved):** in a fresh worktree off
   `edge-candidate`, merge `main`, then check that edge's `shell.qml`
   contains the two anchor lines. If `omarchy` builds on edge, nothing more
   is needed. If quattro reworded them, add an edge-only carry commit with
   its own `.old/.new.qml` pair. Push to `edge-candidate` and dispatch
   `omarchy-edge.yml` with `from_candidate=true`.

## Tests

| check | expected |
|---|---|
| `omarchy` build and the step 1 greps | 1 / 0 / 1 |
| `install-phase-budget` | green, after merging main |
| `session`, Break A ×3 | red, `#1313: … (after enabling nixarchy-menu)` |
| `session.driver` build | green (ty, ruff) |
| `qml` | green |
| `session`, Break B ×1 (planted dir) | red, `#1313: … (at the end of the session)` |
| `session`, restored ×2 (second `--rebuild`) | green, timing line printed |
| D1 runs n-1..n-6 | no SEGV, no crash dir, no binding loop |
| statix, deadnix, fmt | clean |

## Rollback

Revert the PR's squash commit. That removes the carry, its two `.qml`
files, the probe and the docs together. The shell goes back to loading
nixarchy-menu asynchronously, which brings back the crash for anyone who
enables it, and the session check goes back to its #1283-only assertion.
