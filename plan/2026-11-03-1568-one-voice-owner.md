---
status: draft
issue: 1568
spec: spec/2026-11-03-1568-one-voice-owner.md
coders:
  1: codex   # the Floor class is small, tricky logic (flock, hold count, pending release, the overlap rule)
  2: coder   # wiring into nixarchy-voice's engine touches several call sites, tests beside each
  4: codex   # the same Floor in the companion, same semantics, own tests
  5: coder   # wiring into the companion's Speaker, Wake, HTTP handler and page JS
  7: coder   # nixarchy warning, options case, docs, verify.sh line: small, several files
reviewers:
  - codex    # independent read of each product diff against this plan
  - agy      # found the timing flaws in the spec; reads the wiring for the same class of bug
---

# Plan: one voice owner, one speaker at a time

This plan is self-contained. It implements the approved spec without needing
the spec or intent open.

## Decisions carried from the approved intent and spec

- **No new nixarchy option.** No `voiceOwner`, no presets. Instead, a warning
  when both wake words are on, plus a docs section.
- **One lock file:** `$XDG_RUNTIME_DIR/nixarchy-voice-floor.lock`. The holder
  of `flock(LOCK_EX)` has the floor. While holding, it writes one line:
  `<pid> <taken_at>`, then `<pid> <taken_at> <released_at>` just before
  releasing. The times are `time.monotonic()` (`CLOCK_MONOTONIC`, shared by
  every process).
- **`Floor` per process:**
  - a hold count, guarded by a `threading.Lock`;
  - `hold()`: on 0 → 1, cancel a pending release, or else take the lock by
    polling `LOCK_EX | LOCK_NB` every 50 ms. The poll is cancellable;
  - `release(tail)`: on 1 → 0, schedule the real release `tail` s later; a
    `hold()` inside that window cancels it;
  - `drop()`: release now.

  There is no timeout on waiting.
- **Overlap rule for listeners:** `floor_overlaps(capture_start)` is true if
  any of these holds:
  - another process holds the lock now (a fresh-descriptor `LOCK_SH | LOCK_NB`
    fails while our own count is 0);
  - the file's line has another pid with `released_at >= capture_start`;
  - the file's line has another pid with no `released_at` and the lock is free
    (a crashed holder: reject, to be safe).

  A rejected capture is dropped before any learning or speech-to-text.
- **Players get `PR_SET_PDEATHSIG = SIGKILL`.** Descriptors stay
  non-inheritable (a test asserts it).
- **Push-to-talk is exempt.** The rule covers the hands-free listeners only.
- **Nixi holds** from its first sentence until its end-of-reply branch, plus
  a `follow_up` tail (4 s). **Oma holds** per `_answer`/`_announce` until its
  speech has drained, plus an echo tail (0.5 s, measured in step 9).
- **Version skew is harmless.** The two product PRs can merge in either order.

## Steps

The product repos come first. nixarchy only bumps pins and adds the warning.
Clone each product into `/mnt/data/vmtest/` and branch
`feat/one-voice-floor` from its **current head**, not from nixarchy's pin:
nixarchy-voice is at `1ccbc238` against the pin `0231774e`, and
nixoarchy-snowflake at `2e361233`. Line numbers below are from the pins, so
re-locate each by the named function before editing.

1. **nixarchy-voice: `src/omarchy_voice/floor.py`** (new) with the `Floor`
   class, `floor_overlaps()`, and `pdeathsig_preexec()` (`ctypes` `prctl(1, 9)`).
   It also gets an async `ahold()` that polls with `asyncio.sleep(0.05)`.
   Write `tests/test_floor.py`; each test uses a temporary `XDG_RUNTIME_DIR`
   and a child Python process standing in for the other product:
   - the child holds: `hold()` waits, and the wait can be cancelled;
   - a capture that spans the child's hold: rejected;
   - a capture that starts after `released_at`: accepted;
   - the child `SIGKILL`ed mid-hold: the floor is free, the next overlapping
     capture is rejected, and a later one is accepted;
   - `release(tail)` then `hold()` within the tail: one hold, the lock is never
     dropped;
   - a `Popen` while holding: the descriptor is not in `/proc/<pid>/fd`, and
     the child dies with its parent under `pdeathsig_preexec`.

   → verify: `python -m pytest tests/test_floor.py`. §1: show it failing with
   the overlap check stubbed to `return False`.
   Traps: `flock` belongs to the open file description, so read our own count
   before probing. Write the line with `os.pwrite` on the held descriptor, not
   through a second open. Run under bash, not zsh (CLAUDE.md §1).

2. **nixarchy-voice: wire it in.**
   - `_answer` and `_announce` (`local_engine.py:709`, `1020`):
     `await floor.ahold()` at the start, and `release(echo_tail)` after
     `await self._speech.join()`, in a `finally`.
   - `Feedback._speak_now` (`feedback.py:288`): `hold()`/`release(echo_tail)`
     around playback. This does nothing in the daemon and is the hold for
     `ask`/`say`.
   - Every `pw-cat` `Popen` in `feedback.py` (`PLAYER`, the per-sentence path,
     `PiperWorker`): add `preexec_fn=pdeathsig_preexec`.
   - `_record`: stamp `capture_start`. `_hear` (`local_engine.py:679`): return
     `("", None)` when `floor_overlaps(capture_start)` is true.
   - `_wake_turn` (`631`): if another process holds the floor,
     `await asyncio.sleep(0.2)` and return.
   - The daemon's stop path: `floor.drop()`.
   - `doctor`: print the floor path and its current line.
   - Control commands: read what `say`/`announce` wait on behind
     `future.result(timeout=10)` (`local_engine.py:982`). If they wait for
     playback, make them return once the line is queued.

   Tests go in `tests/test_local_engine.py`:
   - a multi-sentence `_answer` with a stalled second sentence holds the floor
     once;
   - `_hear` drops an overlapping capture and returns a 2-tuple;
   - `_wake_turn` does not spin (it is called at most about 5 times in 1 s
     while the floor is held elsewhere).

   → verify: the full suite `python -m pytest`, and `nix flake check` in that
   repo if its CI runs it (read `check.yml`). §1 for each new test.
   Traps: `_speak_now` runs in a worker thread (`asyncio.to_thread`), so the
   hold count must be thread-safe. Confirm that `pdeathsig` fires on thread
   exit with a test that spawns from a short-lived thread and expects the
   player to die; that proves the spawning thread must be long-lived.

3. **nixarchy-voice: open the PR.** Link this plan. Comment `@codex review` on
   the PR, run the `reviewers:` reviews on the diff, wait for green CI, and
   merge with `--auto --squash`. Say in the PR which steps the coders did.

4. **nixoarchy-snowflake: `app/floor.py`** (new), the same `Floor` with the
   same file, line format and tests (`tests/test_floor.py`, the same six
   cases). Thread-only; no async variant. The two files may be near-copies;
   that is deliberate (the spec rejects a shared package).
   → verify: `python -m pytest tests/test_floor.py`, run by hand (the repo has
   no CI), and quote the output plus the §1 failing run in the PR.

5. **nixoarchy-snowflake: wire it in** (`app/server.py`, `app/static/index.html`):
   - `Speaker._player_loop` (`2277`): `Floor.hold()` after `ready.pop` and
     before `_player(prate)` and `now = time.monotonic()`. After it, if
     `g != cls.gen`, go to the cut-off path. At the end-of-reply branch (where
     `spk_done` is published): `Floor.release(tail=CFG.follow_up)`.
   - `Speaker.stop()` (`2177`) and the player loop's `g != cls.gen` paths, once
     nothing is queued: `Floor.drop()`.
   - `make_player` (`2111-2114`, and the override at `2344`):
     `preexec_fn=pdeathsig_preexec`.
   - `Wake.check` (`1658`): return before `MicAuto.learn` when
     `floor_overlaps(started)` is true. `Wake.should_run` (`1571`): `False`
     while another process holds the floor.
   - New `POST /api/floor {"hold": bool}`, mapped to `hold()` /
     `release(follow_up)`. The server keeps the sum of clip durations served
     by `/api/tts` since the last page hold, and releases at that sum plus
     `follow_up` if the page never sends `false`.
   - `index.html` `pump()` (`1397`): post `hold: true` before the first clip
     plays and `hold: false` when the queue drains or is cut off.
   - `doctor()`: print the floor path and line.

   Tests in `tests/`:
   - a cut-off while waiting, and while playing, leaves the floor free;
   - a multi-sentence reply with an underrun holds once;
   - `Wake.check` drops a capture that spans another's hold;
   - `/api/floor` hold-then-vanish releases at the computed time (with the
     clock injected).

   → verify: `python -m pytest tests/` by hand, with §1 failing output.
   Traps: `ThreadingHTTPServer` handlers are concurrent, so all `Floor` state
   is under its lock. Push-to-talk (`Listen`, `/api/listen`) stays untouched.

6. **nixoarchy-snowflake: open the PR.** Same as step 3, with the hand-run test
   output in the body, since there is no CI.

7. **nixarchy: the warning, docs and probe** (this branch):
   - `modules/home.nix`, beside the `services.nixi` block (`~872-885`): add a
     `warnings` entry when `config.services.nixi.companion.enable` and
     `(config.programs.omarchy-voice.settings.ears.wake_word or "") != ""`.
     It names the cost: two idle microphones, two speech-to-text models, and
     Nixi listening for its word by default from its own `config.json`.
   - `tests/options.nix`: one case asserting the warning appears with both set,
     and does not appear with either off.
   - `docs/manual/ai.md`: a short "Both voices on one desktop" section with the
     two options and what the floor does.
   - `pkgs/verify.sh`: under the voice section, gated on both being enabled,
     print the floor path and its line. This is readable state, not pass/fail.

   → verify:
   - build `options-home` (the shard holding Home Manager cases; check
     `tests/options-shards.nix`) and `options-shards`, both at the VM tier per
     §6 (CI idle) or left to CI;
   - `nix fmt -- --ci`, statix, deadnix;
   - build `checks.grep-q-pipefail` after the `verify.sh` edit;
   - `checks.docs-lists`.

   §1: show the options case red with the warning removed.
   Traps:
   - `warnings` is a list, so assign it plainly, never with `mkDefault`
     (CLAUDE.md §7);
   - the `settings` attribute path may be absent, so read it with `or`;
   - a nixpkgs-fmt hook may reformat `.nix` files, so run `nix fmt` and read
     `git diff --stat` (§5);
   - the options cases build home configs: check `configBeside` fixtures for
     how other HM cases set `programs.omarchy-voice`.

8. **nixarchy: bump the pins,** once steps 3 and 6 have merged:
   - `flake.nix`: the `nixarchy-voice` URL commit;
   - `nix flake update nixi-companion nixarchy-voice`.

   → verify: `vm-toplevel`, `reference-toplevel` (eval and fetch), and
   `options-home` via CI. Open one nixarchy PR linking all three artifacts and
   both product PRs, comment `@codex review`, and merge with `--auto --squash`.
   It closes #1568 (`Closes #1568`, alone on its line).

9. **Real hardware (the owner, on p620),** after the deploy. Both products on,
   Oma's wake word on, speakers:
   - ask Nixi something, and say "Oma, what time is it" mid-answer. Expected:
     Nixi finishes, Oma ignores Nixi, then Oma answers after about 4 s;
   - ask Oma, and confirm Nixi takes nothing from Oma's reply;
   - kill the companion mid-reply. Expected: silence, and Oma can speak within
     1 s.

   Measure the echo tail (raise it from 0.5 s if Nixi still hears Oma's last
   word) and record the value here under Deviations, along with any product
   change it needs.

## Tests

| where | command | expected |
|---|---|---|
| nixarchy-voice | `python -m pytest` | all pass. New tests shown red first (§1) |
| nixoarchy-snowflake | `python -m pytest tests/` | all pass, run by hand. Red first |
| nixarchy | `options-home`, `options-shards`, `docs-lists`, `grep-q-pipefail`, fmt/statix/deadnix | green. The warning case is red without the warning |
| p620 | step 9 | as listed |

## Rollback

- **A product:** revert its PR. With only one side changed, behaviour is
  today's (no deadlock), so the other product needs nothing.
- **nixarchy:**
  - revert the pin bump commit, or move the two inputs back with
    `nix flake lock --override-input`;
  - the warning and docs revert as one commit;
  - nothing persists on a machine except the lock file in
    `$XDG_RUNTIME_DIR`, which disappears at logout.
