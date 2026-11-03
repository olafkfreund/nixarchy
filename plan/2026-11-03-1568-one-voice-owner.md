---
status: approved
issue: 1568
spec: spec/2026-11-03-1568-one-voice-owner.md
coders:
  1: codex   # the Floor class is small, tricky logic (flock, hold count, pending release, the overlap rule)
  2: coder   # wiring into nixarchy-voice's engine touches several call sites, tests beside each
  4: codex   # the same Floor in the companion, same semantics, own tests
  5: coder   # wiring into the companion's Speaker, Wake, HTTP handler and page JS
  7: coder   # nixarchy warning, options case, docs, verify.sh line: small, several files
# Every verify command (pytest, nix builds) is run by the session, not by the
# coder that wrote the step: codex and agy cannot build, and the session owns
# builds, reviews and commits. Steps 3, 6, 8 and 9 are the session's or the owner's.
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
- **`Floor` per process,** one module-level instance `FLOOR = Floor()` in each
  product. The constructor takes `path=None` and `clock=time.monotonic`, both
  injectable for tests.
  - **Holds are a set of keys, not a count.** `hold(key, cancelled=None)` is
    idempotent per key, so Nixi calling `hold("speaker")` on every sentence and
    `release("speaker", tail)` once per reply is balanced (agy). Keys in use:
    Nixi `"speaker"` and `"page"`; Oma `"answer"`, `"announce"` and `"speak"`.
    All state sits under a `threading.Lock`.
  - When the set goes from empty to non-empty, `hold` cancels a pending
    release, or else takes the lock by polling `LOCK_EX | LOCK_NB` every 50 ms.
    Each poll calls `cancelled()` and gives up, returning `False`, when it is
    true. Nixi passes `lambda: g != cls.gen`. Oma uses `async ahold(key)`,
    which polls with `asyncio.sleep(0.05)`, so cancelling the task cancels the
    wait.
  - `release(key, tail)` removes the key. When the set becomes empty, it
    schedules the real release `tail` s later. A `hold` inside that window
    cancels it.
  - `drop()` empties the set and releases now.
  - **Writing the line:** `os.ftruncate(fd, 0)` then `os.pwrite(fd, line, 0)`
    on the held descriptor, each line ending in `\n`. A reader ignores a line
    without its newline, a partial write (agy).

  There is no timeout on waiting.
- **Overlap rule for listeners:** `floor_overlaps(capture_start)` is true if
  any of these holds:
  - another process holds the lock now (a fresh-descriptor `LOCK_SH | LOCK_NB`
    fails while our own count is 0);
  - the file's line has another pid with `released_at >= capture_start`;
  - the file's line has another pid with no `released_at` and the lock is free.
    That holder crashed. The listener completes the record: it takes
    `LOCK_EX | LOCK_NB` and, if it gets the lock, appends
    `released_at = now`, then releases. It rejects the current capture,
    which began before `now`. Later captures start after `released_at` and
    are accepted. Without this step every later capture would be rejected
    (codex).

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
   - the child `SIGKILL`ed mid-hold: the floor is free, the capture spanning
     the crash is rejected, the file gains a `released_at`, and a capture
     starting after it is accepted;
   - `release(key, tail)` then `hold(key)` within the tail: one hold, and the
     lock is never dropped;
   - `hold("a")` three times then `release("a", 0)` once: the floor is free (the
     key-set fix);
   - `hold(key, cancelled=...)` returns `False` once the predicate turns true
     while another process holds the lock;
   - a 3-field line overwritten by a 2-field line reads back as the 2-field
     line (the truncate);
   - a `Popen` while holding: the descriptor is not in `/proc/<pid>/fd`.

   → verify: `python -m pytest tests/test_floor.py`. §1, with each hook removed
   in turn:
   - the overlap check stubbed to `return False`: the spanning test goes red;
   - the crash-completion write removed: the "accepted after" test goes red;
   - holds as a counter instead of a set: the triple-hold test goes red;
   - `ftruncate` removed: the overwrite test goes red.

   Quote each red run in the PR.
   Traps: `flock` belongs to the open file description, so read our own count
   before probing. Write the line with `os.pwrite` on the held descriptor, not
   through a second open. Run under bash, not zsh (CLAUDE.md §1).

2. **nixarchy-voice: wire it in.**
   - `_answer` (`local_engine.py:709`): `await FLOOR.ahold("answer")` once it
     is known there is something to say, and `release("answer", echo_tail)`
     after `await self._speech.join()`, in a `finally`.
   - `_announce` (`1020`) only spawns `self._say(text)` and returns
     `"announced"` at once (agy). So the hold goes **inside the spawned
     coroutine**, after the `not text` / `not self.active` guards:
     `self._spawn(self._announce_spoken(text))`. That new coroutine does
     `ahold("announce")`, `await self._say(text)`, `await self._speech.join()`,
     and `release("announce", echo_tail)` in a `finally`. The control socket
     still gets its answer immediately, so the 10 s `future.result` cannot
     fire.
   - `_set_active(False)` and `_drop_queued_speech` (`505`, called at `807` and
     `996`): `FLOOR.drop()`. When the user toggles Oma off, any floor she held
     is released.
   - `Feedback._speak_now` (`feedback.py:288`): `hold()`/`release(echo_tail)`
     around playback. This does nothing in the daemon and is the hold for
     `ask`/`say`.
   - Every `pw-cat` `Popen` in `feedback.py` (`PLAYER`, the per-sentence path,
     `PiperWorker`): add `preexec_fn=pdeathsig_preexec`. In `feedback.py`, make
     the player command an attribute the tests can replace with `sleep 30`.
   - `_record`: stamp `capture_start`. `_hear` (`local_engine.py:679`): return
     `("", None)` when `floor_overlaps(capture_start)` is true.
   - `_wake_turn` (`631`): if another process holds the floor,
     `await asyncio.sleep(0.2)` and return.
   - The daemon's stop path: `floor.drop()`.
   - `doctor`: print the floor path and its current line.
   - Control commands: read what `say`/`announce` wait on behind
     `future.result(timeout=10)` (`local_engine.py:982`). If they wait for
     playback, make them return once the line is queued.

   Tests go in `tests/test_local_engine.py`, each with the hook its §1 run
   removes:
   - a multi-sentence `_answer` with a stalled second sentence holds the floor
     throughout (red with the `_answer` hold removed);
   - `_announce` returns at once while another process holds the floor, and the
     line is spoken after it releases (red with the hold moved back into
     `_announce`);
   - `_hear` drops an overlapping capture and returns `("", None)` (red with
     the `_hear` check removed);
   - `_wake_turn` returns at most about 5 times in 1 s while the floor is held
     elsewhere (red without the sleep);
   - the real `_speak_now` path, with the player swapped for `sleep 30` and
     run in a subprocess that is then `SIGKILL`ed: the `sleep` dies (red with
     `preexec_fn` removed from that call site).

   → verify: the full suite, run by the session in the repo's dev shell
   (`nix develop -c python -m pytest`, or whatever `check.yml` runs; read it
   first).
   Traps: `_speak_now` runs in a worker thread (`asyncio.to_thread`), so all
   `Floor` state is under its lock. `pdeathsig` fires when the spawning
   *thread* exits. `asyncio.to_thread` uses a pool whose threads outlive one
   call, but a pool can retire idle threads, so the subprocess test spawns
   through the real `to_thread` path, not a hand-made thread.

3. **nixarchy-voice: open the PR.** Link this plan. Comment `@codex review` on
   the PR, run the `reviewers:` reviews on the diff, wait for green CI, and
   merge with `--auto --squash`. Say in the PR which steps the coders did.

4. **nixoarchy-snowflake: `app/floor.py`** (new). The same `Floor` (instance,
   `FLOOR`, keys, `cancelled=`, injectable `path`/`clock`), the same line
   format, and the same `tests/test_floor.py` cases with the same §1 breaks.
   It is thread-only, with no `ahold`. The two files may be near-copies; that
   is deliberate (the spec rejects a shared package).
   → verify: `python -m pytest tests/test_floor.py`, run by the session (the
   repo has no CI). Quote the output and the §1 red runs in the PR.

5. **nixoarchy-snowflake: wire it in** (`app/server.py`, `app/static/index.html`):
   - `Speaker._player_loop` (`2277`): after `ready.pop`, and before
     `_player(prate)` and `now = time.monotonic()`, call
     `FLOOR.hold("speaker", cancelled=lambda: g != cls.gen)`. If it returns
     `False`, or `g != cls.gen` afterwards, `continue` (the cut-off path). At
     the end-of-reply branch (where `spk_done` is published):
     `FLOOR.release("speaker", float(CFG.get("follow_up") or 0))`.
   - **Every early `continue` after the hold** also releases when nothing is
     left (`not cls.ready and not cls.todo and not cls.making`) with
     `FLOOR.release("speaker", 0)`. That covers `g != cls.gen`, the
     `_player(prate)` exception that publishes `spk_skip` (agy), and a failed
     `_write`.
   - `Speaker.stop()` (`2177`): `FLOOR.drop()`.
   - `make_player` (`2111-2114`, and the override at `2344`):
     `preexec_fn=pdeathsig_preexec`.
   - `Wake.check` (`1658`): return before `MicAuto.learn` when
     `floor_overlaps(started)` is true. `Wake.should_run` (`1571`): `False`
     while another process holds the floor.
   - New `POST /api/floor {"hold": bool}`, mapped to `hold("page")` /
     `release("page", follow_up)`. **Fallback:** the server sums the durations
     of every clip `/api/tts` has served since the `"page"` key was last
     released. That covers clips the page prefetched before its first `hold`
     (codex, agy). If no `hold: false` arrives, it releases at the time of the
     first `hold: true` plus that sum plus `follow_up`, re-computed as more
     clips are served.
   - `index.html` `pump()` (`1397`): post `hold: true` before the first clip
     plays, and `hold: false` when the queue drains or is cut off.
   - `doctor()`: print the floor path and line.

   Tests in `tests/`:
   - a cut-off while waiting, and while playing, leaves the floor free;
   - a multi-sentence reply with an underrun holds once;
   - `Wake.check` drops a capture that spans another's hold;
   - `/api/floor` hold-then-vanish releases at the computed time, including a
     clip served *before* the hold (with the clock injected; red with the sum
     restricted to clips after the hold);
   - the page hook: a test reads `app/static/index.html` and asserts `pump()`
     posts `/api/floor` with `hold: true` and `hold: false`. This is a source
     check, not a behaviour test, and is labelled so in the PR, because the
     repo runs no browser. The behaviour is covered by step 9, which includes
     `voice_out = "page"`;
   - `make_player` with `audio_player_cmd` swapped for `sleep 30`, spawned from
     the real player thread in a subprocess that is then `SIGKILL`ed: the
     `sleep` dies (red with `preexec_fn` removed).

   → verify: `python -m pytest tests/` by hand, with §1 failing output.
   Traps: `ThreadingHTTPServer` handlers are concurrent, so all `Floor` state
   is under its lock. Push-to-talk (`Listen`, `/api/listen`) stays untouched.

6. **nixoarchy-snowflake: open the PR.** Same as step 3, with the hand-run test
   output in the body, since there is no CI.

7. **nixarchy: the warning, docs and probe** (this branch):
   - `modules/home.nix`: append to the **existing top-level `warnings`**
     (`modules/home.nix:1016`, currently one `lib.optional`). Make it
     `lib.optional … ++ lib.optional bothWake ''…''`. `warnings` is a top-level
     Home Manager option and cannot go inside the `services = { … }` block
     (agy). `bothWake` is defined in the existing `let`:
     `config.services.nixi.companion.enable && (let w = config.programs.omarchy-voice.settings.ears.wake_word or null; in w != null && w != "")`.
     `or` does not catch a `null` value (agy).
     It names the cost: two idle microphones, two speech-to-text models, and
     Nixi listening for its word by default from its own `config.json`.
   - `tests/options.nix`: one case asserting the warning appears with both set,
     and does not appear with either off.
   - `docs/manual/ai.md`: a short "Both voices on one desktop" section with the
     two options and what the floor does.
   - `pkgs/verify.sh`: under the voice section, gated on both being enabled,
     print the floor path and its line. This is readable state, not pass/fail.

   → verify (the session runs these; the coder only edits):
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
   - with the companion's `voice_out = "page"`, repeat the first check;
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

## Deviations

- Step 7, `pkgs/verify.sh`: the script sees runtime state, not Nix options, so
  "both enabled" is read as `omarchy-voice.service` active and
  `nixi-companion` on PATH.
- Step 7, `modules/home.nix`: the coder's `++` followed the dictation
  warning's closing `'';`, which failed to parse. Fixed by moving the `;` to
  the end of the list.
- Step 1 (codex): `floor_overlaps` returned true during our own release tail,
  because it checked the key set rather than the held lock. Codex's test
  asserted that behaviour. Fixed, and the assertion flipped; it fails on
  codex's version. Also fixed a `KeyError` at import with `XDG_RUNTIME_DIR`
  unset. The suite runs as `nix develop -c bash -c 'cd tests && python -m
  pytest'`: 1394 passed.
- Step 4 (codex): `hold()` polled while holding the object lock, so a waiting
  Nixi blocked its own wake thread's `floor_overlaps` and `Speaker.stop()`'s
  `drop()`. The poll now runs outside the lock. A new test,
  `test_waiting_speaker_does_not_block_listener`, hangs on codex's version (a
  deadlock: drop waits behind the poll) and passes on the fix. Codex ran the
  tests with `unittest`, because pytest was not on its PATH.

- Step 2 (coder, finished by the session after the agent was lost in a
  restart). Holds: `_say` takes `say` and, inside an answer, `answer` at the
  first sentence, not during thinking. `answer` is released when the turn
  ends. Announcements and one-shot `say` are covered by `say`, which the
  speech loop releases when its queue drains, so `_announce` needed no key of
  its own and still returns at once. The coder's `_answer` released `answer`
  without ever taking it; the stalled-sentence test caught this.
- Step 2 review (the Codex PR bot, local codex, agy), fixed in nixarchy-voice
  `2ba211f`:
  - muting mid-sentence no longer drops the floor while a line plays;
  - taking the floor records the other holder's release time
    (`foreign_release`), so a capture that spanned its turn is still dropped;
  - a `_say` cancelled before queueing releases `say`;
  - the daemon's stop path drops the floor.

  The same `foreign_release` fix goes into the companion's `app/floor.py`.
## Review

Draft plan, codex (gpt-6-sol) and agy (model not reported). Every finding was
checked against the code and accepted:

| Finding | Who | Change |
|---|---|---|
| The crash rule never recovers: every later capture is rejected | codex | a listener completes the dead holder's line; test "accepted after" |
| A counting `hold` paired with one release per reply leaks the floor on every multi-sentence Nixi reply | agy | holds are a set of keys |
| `_announce` spawns `_say` and returns; holding there releases early or trips the 10 s control timeout | agy (checked at `local_engine.py:1020-1031`) | hold inside a spawned `_announce_spoken` |
| `pwrite` without truncate leaves a corrupt line | agy | `ftruncate` + newline-terminated line, a reader ignores a partial |
| The page fallback misses clips prefetched before the hold | both | sum since the key's last release |
| `_player` raising after the hold leaks the floor | agy | release on every early `continue` with nothing left |
| The pdeathsig test proves the failure mode, not the call sites | both | a test per real player path |
| §1 breaks named only for the overlap test | codex | a named break per test |
| No capable owner for the nix and pytest runs | both | the session runs every verify |
| The cancel contract, instance vs class, and clock injection were unspecified | agy | `FLOOR`, `cancelled=`, injectable `path`/`clock` |
| `_set_active(False)` / `_drop_queued_speech` did not drop the floor | agy | `FLOOR.drop()` there |
| `warnings` can't go inside `services = {}`; `or ""` misses `null` | agy (checked at `home.nix:1016`) | append to the existing list, null-safe test |
| No test can fail when the page posts are removed | codex | a labelled source check, plus step 9 with `voice_out = "page"` |

