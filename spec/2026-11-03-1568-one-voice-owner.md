---
status: draft
issue: 1568
intent: intent/2026-11-03-1568-one-voice-owner.md
---

# Spec: one voice owner, one speaker at a time

Line numbers below refer to the pinned commits: nixoarchy-snowflake at
`/nix/store/i8fqg72s…-source` (`app/server.py`, `app/static/index.html`) and
nixarchy-voice at `0231774e` (`src/omarchy_voice/`). The plan re-reads them at
each product's head before editing.

Revised after the codex and agy review of the first draft. They found that a
point-in-time check cannot reject a recording made during the other product's
turn, and that the hold's start and end points were wrong in both products.
The `## Review` table at the end lists every finding.

## Design

### The floor

Both products use one file, `$XDG_RUNTIME_DIR/nixarchy-voice-floor.lock`.
Whoever holds `flock(LOCK_EX)` on it **has the floor**. The kernel drops the
lock when the holder's descriptor closes, crash included, so nothing expires
and nothing goes stale.

While it holds the lock, the holder also **writes one line into the file**:
`<pid> <taken_at>` when it takes the floor, and `<pid> <taken_at> <released_at>`
just before it releases. The times are `time.monotonic()`. That clock is
`CLOCK_MONOTONIC`, which every process on the machine shares, so the two
products can compare them.

**Speaking.** Each product keeps one `Floor` object per process, with a hold
count and a pending release:

- `hold()` raises the count. On 0 → 1 it cancels any pending release, or, if
  none is pending, takes `LOCK_EX`. The take **polls** `LOCK_EX | LOCK_NB`
  every 50 ms rather than blocking, so a waiting speaker can still be cancelled
  (a cut-off in Nixi, `stop`/`quit` in Oma). Oma polls with `asyncio.sleep`, so
  its event loop and control socket keep working while it waits.
- `release(tail)` lowers the count. On 1 → 0 it schedules the real release
  `tail` seconds later. A `hold()` inside that window cancels it, so one reply's
  sentences, and a reply that follows straight on, keep one hold. The
  `released_at` it writes includes the tail.
- `drop()` releases at once and is used on a cut-off.

Waiting has no timeout (intent decision 3).

**Hearing: reject any capture that overlapped someone else's turn.** A listener
records `capture_start = time.monotonic()` when a capture begins. Before it
transcribes, it calls `floor_overlaps(capture_start)`. That returns true when:

- the lock is held now by another process (a fresh descriptor, `LOCK_SH |
  LOCK_NB` fails, and this process's own count is 0); or
- the file's line names another pid whose `released_at` is at or after
  `capture_start`, meaning the other turn ended during this capture; or
- the file's line names another pid with no `released_at` and the lock is
  free. That holder crashed mid-turn, so the capture is rejected to be safe:
  one dropped capture, never a stuck listener.

A rejected capture is thrown away before any learning or transcription. This
replaces the first draft's "probe when the capture is processed", which both
reviewers showed misses a capture that began before the other's turn or ended
after it.

**Players die with their parent.** Each player process (`paplay`/`aplay` in
Nixi, `pw-cat` in Oma) gets `PR_SET_PDEATHSIG = SIGKILL` through `preexec_fn`.
Then a crashed speaker cannot leave buffered audio sounding after the kernel
has handed the floor on. `pdeathsig` fires when the spawning *thread* exits.
Both spawn from a long-lived worker (Nixi's `_player_loop` thread, Oma's
thread for `_speak_now`), and the plan checks this at each product's head.
Descriptor leakage is a separate trap. Python opens descriptors
non-inheritable and `Popen` defaults to `close_fds=True`, so a long-lived
player cannot keep the lock. A test asserts it.

Each product carries its own ~60-line `Floor` with the same file and the same
line format. Both `doctor` commands print the path and the current line.

### Nixi companion (nixoarchy-snowflake)

- **Server path, hold.** In `Speaker._player_loop` (`server.py:2277`), call
  `Floor.hold()` after popping a line and **before** `_player(prate)` and
  `now = time.monotonic()` (lines 2295-2300). That way the clock is read after
  any wait, not before (agy). Holding again mid-reply, after an underrun or
  during the previous reply's tail, does nothing, because the count is already
  one. After the hold, re-check `g != cls.gen`. If the line was cut off while
  waiting, take the cut-off path below.
- **Server path, release.** At the end-of-reply branch that already exists
  (`not cls.ready and not cls.todo and not cls.making`, where `spk_done` is
  published, lines 2281-2287), call `Floor.release(tail = follow_up)`. So Nixi
  keeps the floor through its follow-up window, the 4 seconds in which it
  takes speech without its wake word (`server.py:177`). Per-sentence calls to
  `talking_until` set no release timer.
- **Cut-off.** `Speaker.stop()` (line 2177) calls `Floor.drop()`, and the
  `g != cls.gen` paths in the player loop do the same once nothing is queued.
  The invariant the tests assert: after a cut-off at any point, the floor is
  free within one player-loop iteration.
- **Page path.** When `voice_out` is `"page"`, the page plays clips itself
  (`index.html:1276-1281`), and it fetches them concurrently, sentence by
  sentence, ahead of playback (agy). The server cannot time that, so the page
  reports it. `pump()` (`index.html:1397`) posts `/api/floor {"hold": true}`
  before its first clip plays, and `{"hold": false}` when its queue drains.
  The server maps these to `hold()`/`release(follow_up)`. If the page goes
  away mid-turn, the server releases anyway, at the sum of the durations of
  the clips it served for that turn plus `follow_up`. It knows those durations
  because it made the clips. `/api/tts` itself takes no lock.
- **Hearing.** `Wake.session` records `capture_start` where a segment starts
  (`started = now`, `server.py:1649`). `Wake.check` (line 1658) returns early
  when `floor_overlaps(started)` is true: before `MicAuto.learn` and before
  transcribing. `Wake.should_run` (line 1571) also returns `False` while
  another process holds the lock, so an idle recorder closes. The loop's
  "finish what you started saying" clause (line 1602) no longer matters,
  because whatever it finishes is rejected by the overlap rule. And because
  Nixi's own turn is not "someone else's", the overlap rule never blocks
  Nixi's own barge-in.
- **Push-to-talk (`Listen`) stays exempt.** That is open question 1 below.

### Oma (nixarchy-voice)

- **Hold per answer, not per queue.** The queue empties between streamed
  sentences (agy), so the queue is the wrong place for the hold. Hold in
  `_answer` (`local_engine.py:709`) from its start until the answer's speech
  has drained. That is `await self._speech.join()`, already used by `_say` at
  line 503. Then `release(tail = echo_tail)`. `_announce` (line 1020) does the
  same, so scheduled `announce` messages are covered. `_speech_loop` itself
  takes no hold.
- **One-shot processes.** `Feedback._speak_now` (`feedback.py:288`) also calls
  `hold()`/`release(echo_tail)`. In the daemon the count is already one, so
  this does nothing. In `omarchy-voice ask` and `say` it is the hold.
- **Shutdown.** The daemon's stop path calls `Floor.drop()`. Even without it,
  the descriptor closes on exit and the kernel releases the lock.
- **The echo tail is new.** Line 474 sets `_voice_until` the moment playback
  returns. #114's tail runs only before Oma's own next capture opens
  (`local_engine.py:686-687`), so it does not protect the other product. The
  release tail starts at 0.5 s. The real-hardware step measures it on p620 and
  records the value in the plan.
- **Hearing.** `_record` stamps `capture_start` when the microphone opens.
  `_hear` (`local_engine.py:679`) returns `("", None)`, the 2-tuple both
  callers unpack (line 650 and the active turn), when `floor_overlaps(...)` is
  true. `_wake_turn` (line 631) skips recording while another process holds the
  lock, and sleeps 0.2 s when it does. Returning straight away would make
  `_listen_loop` (line 887) spin (agy).
- **Control timeouts.** Control commands wait on `future.result(timeout=10)`
  (`local_engine.py:982`). A `say`/`announce` that has to wait out Nixi's reply
  plus 4 s could time out client-side while still speaking later. The plan
  checks what those commands wait for, and makes them return once the line is
  queued if they currently wait for playback.

### nixarchy

- **A warning, in `modules/home.nix`** beside the nixi/voice wiring: when
  `services.nixi.companion.enable` is on and
  `programs.omarchy-voice.settings.ears.wake_word` is non-empty. It says two
  idle microphones then run, each with a speech-to-text model, and that Nixi
  listens for its word by default from its own `config.json` (intent
  decision 1).
- **A short section in `docs/manual/ai.md`:** the two options together, and
  what the floor does (intent decision 2).
- **Pin bumps,** after both products merge: `nixarchy-voice` (a commit URL in
  `flake.nix`) and `nixi-companion` (`flake.lock`).

## Coexistence

nixarchy adds no option and sets nothing a user also sets. The warning reads
two options and writes none. The lock file sits in the user's runtime
directory, which no NixOS option manages. `checks.coexistence` has nothing to
collide.

## Alternatives rejected

- **`programs.nixarchy.voiceOwner`:** rejected in the intent (decision 1).
- **Each product commanding the other** (`listen stop/start`): not a pause,
  not restored afterwards, and stuck if the caller crashes (intent premise 2).
- **A shared speech daemon, or a D-Bus name:** ruled out by the intent's
  constraints.
- **PipeWire ducking or one exclusive sink:** it stops the overlap, not the
  hearing.
- **A point-in-time probe when the capture is processed** (the first draft):
  it misses captures that began before, or ended after, the other's turn.
- **Holding per sentence, or per queue-empty in Oma:** it releases between
  sentences.
- **Blocking `flock`:** it cannot be cancelled, and in Oma it freezes the event
  loop.
- **Server-timed page playback:** the server cannot see when the page plays.
- **A timestamp file without a lock:** it needs expiry, and a crash leaves it
  stale. Here the lock carries ownership and the line carries history.
- **A shared Python package:** a dependency between two repos for ~60 lines.
  The file and its line format are the contract.

## Risks

- **Oma waits for Nixi's follow-up window** after Nixi stops: up to
  `follow_up` seconds, 4 by default. That is intended, and `follow_up` is
  already a Nixi setting.
- **Polling is not fair.** A product that keeps starting new replies can, in
  principle, starve the other. A new reply needs a new request from the user,
  and every release carries a tail, so the plan judges this acceptable and
  does not build a queue.
- **A holder that hangs without crashing** (a wedged `pw-cat` or `paplay`)
  keeps the floor, and neither product bounds playback today. The first draft
  said they did; it was wrong (codex). This stays a documented risk: a
  playback timeout would be the expiry logic the intent rules out. `doctor`
  shows the holder's pid, so it can be found and killed.
- **`pdeathsig` and threads.** If a player is ever spawned from a short-lived
  thread, the signal fires when that thread exits and kills the player
  mid-sentence. A test spawns from the real worker to catch this.
- **One capture is dropped after a crash.** That is the safe direction.
- **Version skew is harmless.** A product without the change neither takes the
  floor nor reads the file, so behaviour is today's, never a deadlock. Merge
  order does not matter.
- **nixoarchy-snowflake has no CI,** so its tests are run by hand and quoted
  in its PR.

## Verification

- **Unit tests in each product**, with a temporary `XDG_RUNTIME_DIR` and a
  child process playing the other product:
  - a child holding the floor: the speaker under test waits, and can be
    cancelled while waiting;
  - a capture that began before the child's hold and ended after its release:
    rejected (the case the first draft missed);
  - a capture entirely after the child's `released_at`: accepted;
  - the child killed with `SIGKILL` mid-hold: the floor is free, and the next
    capture is rejected once and then accepted;
  - a multi-sentence reply with a gap between sentences longer than the queue
    drain: one hold (Oma `_answer`; Nixi `_player_loop`);
  - a cut-off while waiting, and while playing: the floor is free afterwards
    (Nixi);
  - a player spawned while holding does not inherit the descriptor
    (`/proc/<pid>/fd`), and dies when its parent is killed.

  §1: each is shown failing with its hook removed, then passing.
  nixarchy-voice's run under its CI. nixoarchy-snowflake's are run by hand.
- **nixarchy:** a `tests/options.nix` case for the warning in both states,
  shown failing first.
- **Real hardware (§2, the owner on p620):** both products on, Oma's wake word
  on, speakers rather than headphones.
  - Ask Nixi something, then say "Oma, what time is it" during Nixi's answer.
    Nixi finishes, Oma ignores Nixi's speech, then Oma answers after the
    follow-up window.
  - Ask Oma something, and check Nixi takes nothing from Oma's reply.
  - Kill the companion mid-reply: sound stops, and Oma can speak within a
    second.
  - Measure the echo tail, and record it in the plan.
- **`pkgs/verify.sh`:** under the voice section, when both are on, print the
  floor file's path and its current line. That is readable state, not a
  pass/fail.

## Open questions

1. **Push-to-talk.** Should Nixi's push-to-talk (`Listen`, `/api/listen`) also
   drop speech that overlapped Oma's turn? The intent says neither product
   takes the other's speech as a request. But push-to-talk is the user
   deliberately speaking, and if the user talks over Oma, the overlap rule
   would drop *their* words too. I recommend **exempting push-to-talk**, as
   this spec does, and narrowing the intent's outcome to the hands-free
   listeners (wake word, follow-up, and Oma's active session).

## Review

First draft, codex (gpt-6-sol) and agy (model not reported):

| Finding | Who | Verdict | Where it went |
|---|---|---|---|
| A point-in-time probe misses captures spanning the other's turn | both | confirmed (`server.py:1602-1649`, the `in_speech` clause) | the overlap rule |
| The page plays clips itself, concurrently fetched; server timing cannot work | both | confirmed (`index.html:1276-1281`) | the page reports hold/release |
| A crash can leave the child player sounding | codex | confirmed (Nixi keeps 0.8 s buffered; Oma's `pw-cat` plays a whole clip) | `PR_SET_PDEATHSIG` |
| A one-shot release timer can drop a later reply's hold; a stale clock after waiting | both | confirmed (`server.py:2295-2306`) | hold count, hold before `now`, release at the end-of-reply branch |
| Lock leak on a cut-off race | agy | confirmed | `drop()`, and a re-check after the hold |
| Oma's queue empties between sentences | agy | confirmed (`_say` joins at 503) | hold per `_answer`/`_announce` |
| No echo tail at `local_engine.py:474` | both | confirmed (`686-687`) | a new release tail, measured |
| A blocking `flock` freezes Oma's event loop; control times out at 10 s | both | confirmed (`982`) | polling with `asyncio.sleep`; plan checks control waits |
| A per-process flag is unsafe across threads | codex | confirmed | per-process hold count under a thread lock |
| `_wake_turn` early return spins `_listen_loop`; `_hear` must return a tuple | agy | confirmed (`650`, `887-912`) | sleep 0.2 s; `("", None)` |
| "Both products already bound playback" is false | codex | confirmed | moved to Risks, as unbounded |
| `Speaker.idle()` is `True` while a one-sentence reply waits | agy | confirmed | moot: the overlap rule does not depend on it |
| PTT is exempt against the intent | codex | confirmed | open question 1 |
| Wrong line refs (`3461-3488`, `652`) | both | confirmed | fixed |
| The `LOCK_SH` probe cannot see a waiting `LOCK_EX` | codex | true, harmless | a waiter is not speaking, so nothing to reject |
