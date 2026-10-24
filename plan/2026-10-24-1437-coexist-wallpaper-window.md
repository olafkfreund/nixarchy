---
status: approved
issue: 1437
spec: spec/2026-10-24-1437-coexist-wallpaper-window.md
---

# Plan: coexist waits as long as the desktop needs to draw, and owe stops killing a renderer that is about to start

## Approved decisions

- **`tests/coexist.nix`:** the wallpaper loop goes from 12 to 24 tries
  (120 s), and the message says `after 120s`. The comment gives the
  measurement. The pixel assertion `delta < 120` is unchanged.
- **`pkgs/apps/owe.nix`:** the carried #1153 renderer wait goes from 10 s to
  30 s, in sleep-counted units: `waited < 30000`. The comment gives the new
  measurement and keeps the drop rule.
- **Upstream `omacom/owe` report:** drafted in the PR body, and filed after
  the merge (approved).
- **No workflow, trigger, timeout or required-check change.**

Work on `fix/1437-coexist-wallpaper-window` in `/mnt/data/vmtest/wt-1437`,
cut from `main` 6d4b111b. It edits two files, below the coder hand-off
threshold, so the lead implements it. Review is by a fresh Fable agent and
Codex `review`, as asked.

## Steps

1. **owe** (`pkgs/apps/owe.nix:93-98`). Replace the three comment lines and
   the replacement text:
   ```nix
     # CARRIED (#1153): owed gives owe-render a sleep-counted wait to open its
     # socket, then kills it and retries. Upstream's is 1 s. Under software GL
     # (llvmpipe) in CI's coexist VM, start-up took 8.9 s and 10.6 s, and the
     # second was killed 70 ms before it was ready (#1437), so 30 s. A GPU start
     # is ready in about a second and returns at once.
     postPatch = ''
       substituteInPlace src/daemon/supervisor.c \
         --replace-fail 'while (waited < 1000) {' 'while (waited < 30000) {'
   ```
   → verify:
     - `grep -c "waited < 30000" pkgs/apps/owe.nix` prints `1`;
     - `grep -c "waited < 10000" pkgs/apps/owe.nix` prints `0`;
     - `nix build "$(nix eval --raw .#owe.drvPath)^*" --no-link -L` is green,
       and its meson tests pass.
   Traps:
   - **Package tier (§6):** both `vm-host-free.sh` sides print `free`, the
     1-minute load is below 12, and the build runs under
     `flock /mnt/data/vmtest/codex-build.lock`.
   - **§5:** run `nix fmt` and read `git diff --stat`; commit before
     evaluating.
   - **The anchor stays upstream's line.** Do not touch the first argument
     of `--replace-fail`.

2. **coexist** (`tests/coexist.nix:175-194`).
   - Add two lines to the end of the comment above the loop:
     ```
         # Here first paint waits for the shell to take owe's hand-off: across 12
         # CI runs it came on try 10 or 11, so 24 tries is ~2x the slowest (#1437).
     ```
   - Change `for attempt in range(12):` to `for attempt in range(24):`.
   - Change `after 60s` to `after 120s`.

   Commit it as `wip: coexist window`.

   → verify that `grep -c "range(24)" tests/coexist.nix` prints `1`,
     `grep -c "after 120s" tests/coexist.nix` prints `1`, and
     `nix eval --raw .#checks.x86_64-linux.coexist.drvPath` evaluates.
   Traps:
   - **§5:** a heredoc inside an indented Nix string reindents the file, so
     edit in place with the Edit tool, never a heredoc.
   - Run `nix fmt -- --ci` afterwards.

3. **§1 negative control** (`tests/coexist.nix:173`).
   - Insert one line after `w_r, w_g, w_b = avg(local_paper)`, at the same
     indent:
     `    w_r, w_g, w_b = 255, 255, 255  # NEGATIVE CONTROL, do not commit`
   - Prove it landed with `git diff`, then `git add` it but do not commit.
   - Only when `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
     prints `0`:
     - evaluate the `drvPath` once;
     - build `"$drv^*"` under the lock, with `pipefail`, logging to
       `/mnt/data/vmtest/1437-control.log`.

   → verify that the build is red, the log has `attempt 23:`, and it ends with
     `delta … after 120s`.
   Then restore with `git checkout HEAD -- tests/coexist.nix` (not
   `git checkout --`, §5), and check that `git status` is clean.
   Traps:
   - If CI is busy, wait for it to finish. Do not build a VM check beside an
     install (§6).
   - If the wait runs long, push the PR first, and run the control after CI
     finishes.

4. **Green** (`checks.coexist`). Run it under the same rule as step 3, with
   a clean tree, logging to `/mnt/data/vmtest/1437-green.log`.
   → verify that it is green, and record the try it passed on.

5. **Static checks.** Run `nix fmt -- --ci`,
   `nix run nixpkgs#statix -- check .` and
   `nix run nixpkgs#deadnix -- --fail .`.
   → verify that all three exit 0.

6. **Review** (lead).
   - Squash the `wip` commits into one, with the subject: "coexist waits as
     long as the desktop needs to draw, and owe no longer kills a renderer
     that is about to start (#1437)".
   - Check that `git show --stat HEAD` lists `pkgs/apps/owe.nix` and
     `tests/coexist.nix`, plus `plan/` if a deviation was recorded.
   - Run a fresh read-only `Agent` review on `model: "fable"`, given only
     this plan's path and `git diff origin/main...HEAD`.
   - Run Codex `review --base origin/main`, read-only.
   - Act on any finding that holds up when checked; record a deviation in
     `plan/` in the same commit as the change.

7. **PR and merge** (lead).
   - Push, a fast-forward only, and open the PR from the template:
     - link the intent, spec and plan;
     - paste the red outputs (run 40081835769, plus step 3) and step 4's
       green;
     - name the hole: there is no real-hardware check of the 30 s value;
     - include the draft upstream report;
     - use `Closes #1437`.
   - Wait for CI to go green, with `system-checks` including coexist, and
     check that `mergeable` is `MERGEABLE`. Then squash-merge, and confirm
     that #1437 closed.

8. **Upstream report** (lead, approved). Run
   `gh issue create -R omacom/owe` with the PR's draft. It must carry no
   internal hostnames or paths, only the public repo's file names.

9. **Clean up.** Remove the worktree, delete the local branch, and delete
   `/mnt/data/vmtest/1437-*`.

## Tests

| step | check | expected |
|---|---|---|
| 1 | `nix build .#owe` | green, meson tests pass |
| 3 | `checks.coexist` with the reference colour set to white | red after 24 tries, `after 120s` |
| 4 | `checks.coexist` | green |
| 5 | fmt, statix and deadnix | clean |
| 7 | the PR's CI | all green |

## Rollback

Revert the squash commit. The owe wait returns to 10 s and the coexist
window to 60 s. Nothing else depends on either change.
