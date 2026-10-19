---
status: approved
issue: 1352
spec: spec/2026-10-19-1352-owe-handoff-checks.md
---

# Plan: two checks that fail #1349 for reasons in the checks themselves

Approved decisions, carried from the spec:

- One PR, two test-only fixes. Nothing that ships changes.
- **owe 0.2.11** sets `engine` to `renderer` only once the first video frame
  is drawn. If no frame arrives within `MEDIA_READY_TIMEOUT_MS` (5000 ms), it
  cancels the handoff and the shell keeps its still. The session check's
  existing 60 s poll is enough, so **no budget changes**.
- **Fix 1:** the session video poll also waits for `engine == "renderer"`.
  The three asserts after it stay word for word. It must pass on owe 0.2.10
  and on 0.2.11.
- **Fix 2:** the mimeapps-hold section writes the activation script to a
  file and runs awk on the file, the file's own idiom. The awk program,
  `exit` included, is unchanged.
- If llvmpipe misses owe's 5 s deadline in CI, that is a separate finding
  about owe, not something to make the check tolerate.

Two files and two editing steps, so the lead implements it (model split:
below the coder threshold).

## Steps

1. **`tests/session.nix:2353–2358`: the poll waits for the handoff.**
   - Replace the two-line comment above the loop with:
     `# owe >= 0.2.11 keeps the shell's still until the video's first frame,`
     `# then sets engine (omacom/owe#17), so the poll waits for that too.`
   - Make the `if` inside `for _ in range(30):` read:
     ```python
     if (status.get("source_kind") in ("video", "gif") and status.get("render_alive")
             and status.get("engine") == "renderer"):
     ```
   - Leave the three asserts below unchanged.
   → verify: `git diff tests/session.nix` shows only the comment and the
   condition; `nix fmt -- --ci` is clean (the Python sits in a Nix string;
   check that nixfmt left the indentation alone).
   Traps: §5's reformat hook. Read `git diff --stat` after `nix fmt`.

2. **`tests/home-activation-writes.nix:95–100`: no pipe.**
   `rehome ${act "nixarchySeed"} | awk '` becomes two lines:
   ```sh
   rehome ${act "nixarchySeed"} > seed.sh
   awk '
   ```
   and `' > hold.sh` becomes `' seed.sh > hold.sh`. The program in between
   is unchanged.
   → verify: `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.home-activation-writes --print-build-logs`
   is green, and its log still prints the four mimeapps-hold `ok` lines.
   Traps: `git add` before building (§5).

3. **Commit steps 1–2** with subject "The owe session check waits for the
   first-frame handoff, and the mimeapps hold check reads a file, not a
   pipe (#1352)".

4. **SIGPIPE proof (cheap, bash script).** `/mnt/data/vmtest/wt-1352-sigpipe.sh`,
   starting `#!/usr/bin/env bash` and `set -o pipefail`:
   - `seq 1 200000 | awk 'NR==1{print; exit}' > /dev/null; echo "pipe=$?"`
     must print `pipe=141`;
   - `seq 1 200000 > big; awk 'NR==1{print; exit}' big > /dev/null; echo "file=$?"`
     must print `file=0`.
   Then the hold control: `sed -i 's/mimeapps_absent=1/mimeapps_absent=/' modules/home.nix`
   (the #1342 break), `git diff` to confirm the break landed, `git add -A`,
   build `home-activation-writes`: it must fail on the hold assertion.
   Restore with `git checkout HEAD -- modules/home.nix` and `git add -A`
   (§5: checkout restores the index otherwise), then confirm
   `git status --short` is empty.

5. **Session proofs (VM, §6 tier 3).** Each one runs only when
   `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
   prints 0. Each evaluates the drvPath first and builds `'<drv>^*'` (§5's
   stale-evaluation trap).
   a. **0.2.10, green:** `checks.session` on the step-3 commit.
   b. **0.2.11, green:** a throwaway commit applying #1349's `pkgs/apps/owe.nix`
      change (version `0.2.11`, hash
      `sha256-0o+YpXsgz2ibsmzQzOS2wInZcMaZrkUyovoBN6lrk38=`), then
      `checks.session`.
   c. **0.2.11, red:** on top of (b), `owe_video_path` (`tests/session.nix:2291`)
      points at `${pkgs.writeText "broken.mp4" ""}`. It must fail on one of
      the three asserts after the poll. owe stops the renderer when it
      cancels, so `render_alive` is likelier than the `engine` assert. The
      spec said "the engine assert"; the plan accepts any of the three and
      records which.
   Drop the throwaway commits (`git reset --hard <step-3 commit>`; they are
   never pushed). If CI never goes idle long enough, push (b) as a draft PR
   whose only purpose is the `system-checks` run, then close it. That PR
   must not evict a queued install: check `gh run list` for queued
   install-check runs first.

6. **PR.** Link intent, spec and plan, paste the outputs of 4 and 5, and use
   `Closes #1352`. Then re-run #1349 (`gh run rerun <id> --failed`) after
   this merges, so it is judged on the bump alone.

## Tests

- Step 2's build green. Step 4: `pipe=141`, `file=0`, the hold control red
  then green.
- Step 5: a green, b green, c red.
- `nix fmt -- --ci`, statix and deadnix clean.

## Rollback

Revert the squash commit. Both files return to their earlier form, and nothing
outside `tests/` is touched.

## Deviation

Step 2: the same `rehome ${act "nixarchySeed"} | awk '…exit…'` shape was
also in the dry-plugin-reconcile section (line 73, from #1277), with the same
SIGPIPE exposure. The activation script is now written to `seed.sh` once,
before that section, and both awk programs read it. Neither program changed.

## Deviation (after merge)

Step 1 covered the first video poll only. `tests/session.nix` has a second:
the re-arm before locking (step 4 of the owe block), which also waited only
for `render_alive`. On `main` c335cad7 (owe 0.2.11), the test locked about
one second after setting the video. The lock paused the renderer before its
first frame, owed logged `renderer handoff cancelled (media did not start)`,
and the lock screen kept the still: `the locked screen does not move over
2.8s (spread 0)`. The same failure appeared on edge's verify. It passed on
#1349's own run only because that handoff finished before the lock. The
re-arm poll now waits for `engine == "renderer"` too. A grep for
`render_alive` finds no other poll that waits for the video.
