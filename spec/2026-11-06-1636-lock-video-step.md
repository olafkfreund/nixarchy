---
status: approved
issue: 1636
intent: intent/2026-11-06-1636-lock-video-step.md
---

# Spec: The lock screen must end by holding still for longer than a colour of the video lasts

The owner approved the intent on 2026-11-06.

## Design

The test video is 1 s of red, then 1 s of blue (`tests/session.nix:66-71`). Playing, it cannot stay one colour for more than about 1 s. A handoff ends, and then the still holds.

So in `tests/session.nix`, beside `spread`, a pure function replaces `assert lock_spread <= 60`:

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
```

The same script asserts the function's own cases, once, before the desktop step, where they cost nothing and run in every `session`:

The cases use `B = (1, 1, 251)` and `R = (237, 12, 12)`, which are `#0101FB` and `#ED0C0C` as `spread` reads them:

| readings | expected | why |
|---|---|---|
| `B`, then `R` × 5 | holds | the recorded failure, run 42072346082 |
| `(119, 6, 131)` after `B`, then `R` × 5 | holds | a handoff caught mid-fade (agy) |
| `R` × 6 | holds | the local pass |
| `R` × 2, `B` × 3, `R` × 3 (a 1 s period at 0.4 s) | does not | playback |
| `R` × 3, `B` × 3 (6 readings across one change) | does not | playback seen for only one change, too short to call still |
| `[(237 - 25 * i, 12, 12 + 25 * i) for i in range(6)]` | does not | no change over 60 between neighbours, spread over 60 |

The failure message prints the readings. `lock_readings`' near-black filter and its floor of six are unchanged, so the floor still fails a screen that blanked too early. The comment above the assert, "settle() has already seen the poster", is wrong (agy) and goes.

No wait for the lock surface and no wake key: neither reviewer could find a signal that says the poster has been drawn, and a wait spends the 5 s before the blank that the series needs.

## Coexistence

A test only. Nothing that ships changes, so no fixture applies (§14).

## Alternatives rejected

- **Widen the 60 spread.** Red to blue is far over any usable limit, and it would hide playback.
- **Always drop shot 0.** A handoff across two shots fails again, and it says nothing about why.
- **Wait for a colour.** The video is that colour half the time.
- **A signal from the lock surface.** None is known. `locked` comes from logind and Hyprland, and says nothing about a drawn frame. If one appears, this can move to it.
- **Wake the screen to get more readings.** A keystroke changes the state being measured, and this step already has enough readings.

## Risks

- **Video playing more than 1.6 times too slowly on the lock screen reads as still.** That is the hole. The desktop step uses the same video and interval, but it asserts only a spread, so nothing bounds the speed. It is named in `tests/AGENTS.md`.
- **A handoff late in the series** leaves fewer than five settled readings and still fails, naming the readings. With six readings before the blank, a handoff one shot later fails (agy). That is a smaller flake than today's, and it stays visible.
- **Stalled screenshots can alias with the loop.** `shot_series` sleeps 0.4 s after each screenshot, so a host stall can skip a colour and let real playback read as still, for one run (Codex). The blank at about 5 s limits how far apart the shots can be. Accepted: playback left in would still fail the runs that do not stall.

## Verification

- `checks.session` passes, and prints the function's cases as passing. VM tier (§6).
- §1, each by build: make `holds_still` return `True` and the playback case fails at the top of the script; remove `spread(settled) <= 60` and the drift case fails; give the lock assertion `desktop_readings`, which are real playback measured by the same `shot_series`, and it fails. Nothing here patches upstream's lock surface or owe's pause (Codex, agy): no local patch or setting makes the lock screen play.
- The recorded failure is a case above, because the race cannot be forced.
