---
status: approved
issue: 1359
spec: spec/2026-10-19-1359-owe-handoff-patch.md
---

# Plan: owe 0.2.11 with the handoff fix, instead of holding 0.2.10

Approved decisions, carried from the spec:

- owe is 0.2.11 (hash `sha256-0o+YpXsgz2ibsmzQzOS2wInZcMaZrkUyovoBN6lrk38=`).
- One substitution is added to `pkgs/apps/owe.nix`'s existing `postPatch`
  with `--replace-fail`, which is the repo's patching method:
  `app->handoff_pending = true;` → `app->handoff_pending = true; app->shell_stop_at_ms = 0;`
  The anchor occurs exactly once in v0.2.11's `src/daemon/main.c`.
- A guard before it fails the build if owe already clears the park during a
  handoff, in either shape (beside `handoff_pending = true;`, or inside
  `process_shell_handoff`), so the patch cannot outlive its need.
- #1360 (hold at 0.2.10) merges first, and this then restores 0.2.11 and
  removes #1360's "Held at 0.2.10" comment.
- Deploying to p620 and razer is the owner's `/etc/nixos` step, not this
  change.

One file, so the lead implements it.

## Steps

1. **Rebase onto `main` once #1360 has merged.** Check
   `gh pr view 1360 --json state` reads MERGED, then
   `git rebase origin/main`. Afterwards check `git merge-base origin/main HEAD`
   and that `git show --stat` of the branch lists only artifacts (§5).
   Traps: until #1360 lands, `main` is 0.2.11 already. Step 2's version edit
   is then a no-op, so do not skip the rebase check.

2. **`pkgs/apps/owe.nix`: version, hash, comment.**
   - Remove the line `  # Held at 0.2.10: 0.2.11 parks the renderer mid-handoff (#1359). Bump once owe fixes it.`
   - Set `version = "0.2.11";` and `hash = "sha256-0o+YpXsgz2ibsmzQzOS2wInZcMaZrkUyovoBN6lrk38=";`
   → verify: `git diff` shows exactly those lines.

3. **`pkgs/apps/owe.nix`, `postPatch`** (the block that starts
   `# CARRIED (#1153)`): after the existing `substituteInPlace
   src/daemon/supervisor.c …` command, inside the same `''…''`, append:

   ```sh
   # CARRIED (#1359, omacom/owe#18): switch_to_shell() schedules a park 2 s
   # out, and since 0.2.11 the engine stays "shell" through a handoff, so a
   # video set inside those 2 s had its loading renderer parked and never
   # showed. Clear the pending park when the handoff starts. Drop once owe has it.
   if grep -A1 'app->handoff_pending = true;' src/daemon/main.c | grep -q shell_stop_at_ms \
     || sed -n '/^static void process_shell_handoff/,/^}/p' src/daemon/main.c | grep -q handoff_pending; then
     echo "owe already clears the pending park during a handoff (omacom/owe#18): drop the #1359 substitution" >&2
     exit 1
   fi
   substituteInPlace src/daemon/main.c \
     --replace-fail 'app->handoff_pending = true;' \
                    'app->handoff_pending = true; app->shell_stop_at_ms = 0;'
   ```

   The comment says why, because the existing #1153 block above it is
   commented that way too (pkgs/AGENTS.md).
   → verify: `nix fmt -- --ci`, then `git diff --stat` (§5's reformat hook).
   Traps: the comments sit inside a shell string, so they are shell `#`
   comments, which is fine. Do not put `''` in them.

4. **Build** (package tier: no p620 system build running, load below 12):
   `flock /mnt/data/vmtest/codex-build.lock nix build --no-link -L .#owe`.
   → verify: it succeeds, the meson test summary shows no failures, and
   `nix log` (or the `-L` output) shows the substituted line. Confirm that by
   reading the patched source: `nix build .#owe.src` gives the original, so
   instead check that the build's `postPatch` ran with
   `grep -c 'shell_stop_at_ms = 0' <(nix develop .#owe -c bash -c 'cd $(mktemp -d) && unpackPhase && cd source && patchPhase && cat src/daemon/main.c')`,
   expecting 4 (3 upstream, plus ours).

5. **Guard proof (§1), as a bash script** `/mnt/data/vmtest/wt-1359-guard.sh`
   (`#!/usr/bin/env bash`). It extracts the guard's `if … fi` from
   `owe.nix` and runs it against three copies of v0.2.11's `src/daemon/main.c`
   (from `nix build --print-out-paths .#owe.src`):
   (a) unmodified, expect exit 0;
   (b) with `app->shell_stop_at_ms = 0;` inserted on the line after
   `app->handoff_pending = true;`, expect exit 1 with the message;
   (c) with `if (app->handoff_pending) return;` inserted as the first line of
   `process_shell_handoff`'s body, expect exit 1.
   Confirm with `grep` that each edit landed before running.

6. **Commit** with subject "owe 0.2.11 keeps its first-frame handoff, with a
   carried fix so a video set soon after a still is not parked mid-load
   (#1359)". Then the PR, linking intent, spec and plan, pasting steps 4 and 5,
   and naming the three red runs. Use `Closes #1359`, because the patch is
   the resolution and the upstream issue is linked from it.

7. **After merge:** confirm `main`'s `session` passes on the merged commit,
   with `engine: renderer` after the second `renderer loading behind` in the
   log. Then tell the owner the `/etc/nixos` bump is ready for p620 and razer.

## Tests

- Step 4: build green, meson tests pass, substituted count 4.
- Step 5: (a) 0, (b) 1, (c) 1.
- The PR's `checks.session`: green, with the log pattern above.

## Rollback

Revert the commit. That restores #1360's hold at 0.2.10.
