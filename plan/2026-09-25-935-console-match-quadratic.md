---
status: draft
issue: 935
spec: spec/2026-09-25-935-console-match-quadratic.md
---

# Plan: match the LUKS prompt in a bounded window

## The approved decisions, carried over

1. **Bound the input, not the pattern.** `luks_prompt`, `SPLIT` and `DECOY`
   are untouched: #834 measured the loose-quantifier alternative and found it
   matches a decoy containing no prompt, which sends the passphrase to whatever
   is listening.
2. **Poll a bounded tail of `get_console_log()`**, not `wait_for_console_text`.
   The driver rescans its whole buffer per arriving line; the cost is the
   pattern's backtracking over a growing input, and a window bounds it.
3. **64 KiB**, because the `SPLIT` fixture is ~200 characters and the entire
   failing run produced ~45 KB -- so it bounds the worst case without changing
   the normal one.
4. **No staged marker.** It would have to be guessed: no surviving log shows
   what precedes the prompt.
5. `console=ttyS0` stays (#834: it is the output this test most needs when it
   genuinely fails).

## Steps

1. **`tests/install-encrypted.nix:671`** -- replace
   `target.wait_for_console_text(luks_prompt, timeout=600)` with a poll over
   `target.get_console_log()[-65536:]`, with the window and the reason at the
   line.
   → verify by step 3.
2. **Check the test script's imports.** It already uses `re` (the SPLIT/DECOY
   assertions). `time` may not be imported; if not, add it.
   → verify by the build not raising NameError.
3. **Build the check, and TIME it.**
   `nix build .#checks.x86_64-linux.install-encrypted`. It has never finished,
   so completion is the headline -- but the duration is the claim that matters,
   and it goes in the PR.
4. **The bounded proof** the spec asks for, since the natural break takes 90
   minutes to observe: assert in the test that the slice is bounded, so
   removing it fails immediately rather than hanging.
   → verify by removing the slice and watching that assertion fail.
5. **`tests/AGENTS.md`** -- the mechanism, so the next person meeting a slow
   console wait finds it: the driver's per-line full-buffer rescan, why the
   pattern cannot be cheapened, and that 45 KB of console was enough to hang a
   90-minute job.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.install-encrypted` | **finishes**, and in minutes not hours |
| `nix build .#checks.x86_64-linux.install` | still passes -- shares nothing, but it is the control |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

`git revert`. The test returns to `wait_for_console_text` and to hanging. No
shipped behaviour is involved -- this is test-harness code only.
