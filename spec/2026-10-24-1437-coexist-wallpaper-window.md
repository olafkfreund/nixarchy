---
status: draft
issue: 1437
intent: intent/2026-10-24-1437-coexist-wallpaper-window.md
---

# Spec: coexist waits as long as the desktop needs to draw, and owe stops killing a renderer that is about to start

The intent was approved with all three recommendations.

## Design

### 1. `tests/coexist.nix`: a 120 s window, with a stated reason

- At line 180, change `for attempt in range(12):` to `range(24)`.
- At line 193, change `after 60s` to `after 120s`.
- Extend the comment above the loop (lines 175–178) by two lines. In this
  VM, the first paint waits for the shell to take owe's hand-off. Across
  12 runs it showed on try 10 or 11, which is 50–55 s, so 120 s is about
  twice the slowest pass (#1437).

The pixel assertion (`delta < 120`) is unchanged. The loop still breaks
at the first match, so a passing run takes no longer than it does today.

### 2. `pkgs/apps/owe.nix:92-97`: the carried renderer wait goes from 10 s to 30 s

- In the existing #1153 substitution, change the replacement
  `'while (waited < 10000) {'` to `'while (waited < 30000) {'`.
- Rewrite the comment to give the new measurement. In CI's coexist VM,
  start-up under llvmpipe was 8.9 s and 10.6 s (#1437). The second hit the
  10 s limit 70 ms before the renderer was ready, and was killed. The wait
  counts its own sleeps, not elapsed time.
- Keep the "Drop once owe has it" rule.

On a machine with a GPU, the renderer is ready within about a second and
returns at once, so nothing changes there. The only effect is that a slow
start is waited for rather than killed.

What 30 s blocks: `owed` waits in this loop synchronously, at most 30 s
instead of 10 s, and only while a renderer is starting. That only happens
when a renderer is slow enough to need the time.

### 3. An upstream report, filed after the merge, on your go-ahead (given)

One `omacom/owe` issue. It is drafted in the PR body and filed with
`gh issue create -R omacom/owe` once this merges. It describes:

- the supervisor wait counts `usleep` sleeps, not wall time, and 1 s is
  short for a slow first start (the CI timeline above);
- under llvmpipe the renderer logs `ready` but the screen stays black until
  the shell takes over.

It carries no nixarchy-internal paths beyond the public repo.

## Alternatives rejected

- **Wait for owed's `engine: shell` or `renderer parked` journal line.**
  That couples the check to upstream's log wording. The passing run still
  needed about 11 s after that line before pixels showed, so it would not
  remove the pixel wait either. Codex and agy both rejected it.
- **Raise only the check's window.** The failing run's kill-and-respawn is
  our own patch's limit, and its stated reason ("about 1.3 s") is now false.
  A rule whose reason no longer holds gets discarded (`AGENTS.md` §6).
- **Rewrite owe's supervisor to use a wall-clock deadline.** That is a
  larger carried patch to upstream code. It belongs in the upstream report.
- **Move the wallpaper check later in coexist, as session's is.** That hides
  how long first paint takes instead of bounding it.

## Risks

- **owe's own tests.** The owe build runs its meson tests (`doCheck`). The
  test that exercises the supervisor (`daemon`) is not in the allowlist,
  because the sandbox has no Wayland. So nothing in the owe build asserts
  the timeout, and nothing breaks either. The `owe` build is in
  `system-build` and `apps`.
- **The cache.** owe's output hash changes, so `main` pushes the new owe the
  next time it builds. That is the normal path for a package change, and no
  allowlist edit is needed.
- **Workflows.** No workflow, trigger, timeout or required check changes.
  `system-checks` runs coexist as it does now. A failing coexist run is
  slower to fail: 120 s instead of 60 s, inside the job's timeout.
- **The patch anchor.** `--replace-fail` still matches upstream's
  `while (waited < 1000) {`, because only our replacement text changes. A
  later owe bump that changes the line fails the build loudly, as it does
  today.
- **Not covered by any check:** the 30 s value on a real machine. No CI
  layer boots owe on real hardware. The coexist VM is the measured case,
  and the PR says so (§3).

## Verification

All builds follow §6's tiers. The VM run happens only with nothing in
flight (`gh run list` prints `0`). Otherwise CI does it.

1. **Old-code red** is already on record. Run 40081835769 shows 12 tries
   black and then the `after 60s` assertion.
2. **§1 negative control for the wider loop.** Commit a temporary break
   that sets the reference colour to white (`w_r, w_g, w_b = 255, 255, 255`)
   after `avg(local_paper)`. `checks.coexist` must then go through all 24
   tries and fail with `after 120s`. This proves the longer loop still
   asserts and the message matches. Prove the break landed with
   `git diff`. Restore it with `git checkout HEAD --` before the real run.
3. **Green.** `checks.coexist` passes with the fix, and its log shows the try
   it passed on.
4. **owe.** `nix build .#owe`, the package tier, is green, and its meson tests
   pass. `grep 'waited < 30000'` on the built `supervisor.c`, or the patched
   source, matches.
5. **Static.** `nix fmt -- --ci`, statix and deadnix all exit 0.
6. **The PR's CI is all green,** including `system-checks`, with coexist
   in it. Before merging, check `mergeable`.
7. **Review.** A fresh read-only review of the diff against the plan, on
   Fable, as you asked, plus Codex `review --base origin/main`.
