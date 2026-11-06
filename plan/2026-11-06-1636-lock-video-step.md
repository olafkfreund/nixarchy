---
status: approved
issue: 1636
spec: spec/2026-11-06-1636-lock-video-step.md
coders:
  1: codex  # one small predicate and its cases, in a Nix '' string, where a wrong case reads as coverage
reviewers:
  - codex  # reads the diff itself, independent of the session
  - agy    # independent read of the diff against this plan
---

# Plan: The lock screen must end by holding still for longer than a colour of the video lasts

Worktree `/mnt/data/vmtest/wt-1636`, branch `fix/1636-lock-video`.

## Decisions carried from the approved spec

1. The video is 1 s red, 1 s blue. Five readings at least 0.4 s apart cannot be one colour while it plays, so a handoff of any length ends and five steady readings then follow.
2. No lock-surface signal, no colour wait, no wake key, no wider spread, no dropped shot 0.
3. The near-black filter and the floor of six stay.
4. Accepted holes, named in `tests/AGENTS.md`: playback more than 1.6 times too slow, and a screenshot stall aliasing with the loop for one run. A handoff one shot later still fails, and prints the readings.
5. Tests only, so no coexistence fixture and no release note.

## Steps

### 1. `tests/session.nix`, `tests/AGENTS.md` (codex)

**`tests/session.nix`,** straight after `def spread` (`:2649-2654`), before `# 1. owed is a user unit`:

```python
    # A handoff, fade included, ends. The video changes every 1 s, so five
    # readings at least 0.4 s apart (1.6 s) cannot be one colour while it plays.
    def holds_still(readings):
        changes = [
            i for i in range(1, len(readings))
            if spread(readings[i - 1:i + 1]) > 60
        ]
        settled = readings[changes[-1]:] if changes else readings
        return len(settled) >= 5 and spread(settled) <= 60

    R, B = (237, 12, 12), (1, 1, 251)
    for readings, expected in [
        ([B] + [R] * 5, True),  # the recorded failure, run 42072346082
        ([B, (119, 6, 131)] + [R] * 5, True),  # a handoff caught mid-fade
        ([R] * 6, True),
        ([R] * 2 + [B] * 3 + [R] * 3, False),  # playback
        ([R] * 3 + [B] * 3, False),  # one change, then too short to call still
        ([(237 - 25 * i, 12, 12 + 25 * i) for i in range(6)], False),  # a slow drift
    ]:
        assert holds_still(readings) == expected, f"holds_still({readings}) is not {expected}"
    print("owe: holds_still's own cases pass")
```

**At `:2836-2843`,** replace `lock_spread = ...`, its `print`, the comment "settle() has already seen the poster..." and the `assert lock_spread <= 60` with:

```python
    print(f"owe: lock screen readings {lock_readings}")
    # The outcome a user sees: it holds still rather than playing (#15289).
    assert holds_still(lock_readings), (
        f"the locked screen plays the video over 2.8s ({lock_readings}); "
        f"since quattro 1381fa0 it shows the still")
```

Keep every other line of the step. `R` and `B` must not shadow a name the script uses later: grep the test script first, and rename them if one does.

**`tests/AGENTS.md`,** in "The owe one" (`:467-500`): one or two sentences naming the two accepted holes from decision 4. `:471-472` says "the desktop and the lock screen's feed both visibly move", which has been false since quattro 1381fa0: correct it to say the lock screen holds still.

→ verify (Opus): `checks.session`, `nix fmt -- --ci`, statix, deadnix.

Traps: §5 no `''` inside the `''` string, and `f"..."` with `{` is fine since only `${` interpolates. §5 `nix fmt` after the edit. The driver's type check rejects shadowing a driver name (`log`, found on #1620), so `session` must at least evaluate and start.

### 2. Prove and run (Opus; only the temporary breaks below edit a file)

From a committed baseline, one at a time, restoring with `git checkout HEAD -- tests/session.nix`. All are VM tier (§6), so `gh run list` must print `0`. The first two fail near the top of the script.

| Break | Must go red |
|---|---|
| `holds_still` returns `True` | the playback case |
| remove `and spread(settled) <= 60` | the drift case |
| `assert holds_still(desktop_readings)` in place of `lock_readings` | the real step, on real playback measured by the same `shot_series` |

### 3. Pull request (Opus)

Subject: "checks.session's lock-screen step no longer reads the handoff as playback". `Closes #1636`. It links all three artifacts, says Codex did step 1, and carries each break's failing output. "@codex review". Merge with `--auto --squash --delete-branch`. It names `install` as not run locally.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.session` | passes; red on each break above |

## Rollback

Revert the squash commit. Nothing ships.

## Deviation: the floor is five, not six

Decision 3 kept the floor of six. On the combined tree `session` failed that floor with five readings of `#ED0C0C`: the lock screen held still and blanked before a sixth, on a host at load 15. Six existed to span a whole loop for the old spread test. `holds_still` needs five, which outlast one colour of the video, so the floor follows it. A screen that blanks sooner still fails.
