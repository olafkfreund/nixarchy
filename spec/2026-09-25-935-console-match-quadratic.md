---
status: approved
issue: 935
intent: intent/2026-09-25-935-console-match-quadratic.md
---

# Spec: match the prompt in a bounded window, and leave the pattern alone

## The intent's open question, and why the answer changed the design

The intent leaned to **staged waits**: a cheap `wait_for_console_text` on a
marker just before the prompt, then the expensive pattern over the short window
after it. That needs a marker, and the marker has to come from a log.

**No surviving log shows what precedes the prompt.** The 2026-09-25 nightly's
serial output stops at 452 lines, at `systemd[1]: Hostname set to <nixos>`,
guest uptime 1.89 s -- it never reached the prompt. The 2026-09-23 and
2026-09-24 nightlies did fail the same way, and **I deleted their runs during a
workflow cleanup earlier in this session**, so their logs are gone too.

Choosing a marker now would mean writing it from what an initrd *plausibly*
prints. This repository has been bitten by exactly that before -- expectations
written from what a panel plausibly says rather than read off the frames -- so
the staged shape is rejected on the grounds that its one input is unavailable.

**The driver offers what the other shape needs.** `get_console_log()`
(`nixos/lib/test-driver/src/test_driver/machine/__init__.py:1313`) returns the
accumulated console as a string. A bounded-tail poll needs no marker.

## Design

Replace the single `wait_for_console_text(luks_prompt, timeout=600)` at
`tests/install-encrypted.nix:671` with a poll over a **bounded tail** of
`get_console_log()`:

```python
def wait_for_luks_prompt(m, timeout=600, window=65536):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if re.search(luks_prompt, m.get_console_log()[-window:]):
            return
        time.sleep(1)
    raise Exception("no LUKS passphrase prompt within %ds" % timeout)
```

**The pattern is unchanged.** `luks_prompt`, `SPLIT` and `DECOY` stay exactly as
they are. `spec/2026-09-21-834-luks-prompt-race.md` measured the loose-quantifier
alternative and rejected it: it matches a decoy containing no prompt, and a
false positive sends the passphrase to whatever is listening. The thirteen
kernel-line-bounded groups **are** the safety property.

**Why a window fixes it.** The cost is not the O(n^2) line count -- 452 lines is
about 45 KB, and a plain quadratic over that is trivial. It is the pattern's
backtracking over a buffer that keeps growing, repeated on every arriving line.
Bounding the input bounds the backtracking, so the per-poll cost stops growing
and the feedback loop that starves the qemu never starts.

**Why 64 KiB.** The `SPLIT` fixture in the file is roughly 200 characters, so
the window has about three orders of magnitude of margin over the longest split
this test has ever seen. It is also larger than the entire 45 KB the failing run
produced, so on today's evidence the window never truncates anything --
it bounds the *worst* case rather than changing the normal one.

**Why polling once a second.** `wait_for_console_text` blocks on the line queue
and matches per line; polling decouples match cost from line rate entirely. A
prompt sitting unmatched for up to a second is irrelevant against a 600-second
timeout.

## Alternatives rejected

| | why not |
|---|---|
| Cheapen the regex | #834 measured it: matches a decoy with no prompt, sends the passphrase unprompted. The file's own `DECOY` assertion exists to catch this. |
| Staged waits on a pre-prompt marker | Needs a marker no surviving log can supply. Would be guessed. |
| Drop `console=ttyS0` | #834: "throws away the stage-1 output this test most needs on the day it genuinely fails". |
| Fix `wait_for_console_text` upstream | The quadratic is real and everyone with a chatty console pays it -- but it is nixpkgs', not ours to file unprompted (section 11), and far too slow to unblock this check. Worth raising separately. |
| Raise the 90-minute cap | The job needs about 35 years at the observed rate. |

## Risks

- **A prompt older than the window would be missed.** Only if more than 64 KiB
  arrives between the prompt appearing and the next poll -- a second of serial
  output at 115200 baud is at most ~11 KB, so it cannot happen at this baud.
  Worth stating because the window is the one number that could be wrong.
- **`get_console_log()` joins a list on every call.** That is O(n) per poll
  rather than per line, once a second -- not the quadratic, but not free
  either. Acceptable at 45 KB; worth a comment so nobody reads the window as
  the only bound.
- **This is test-harness code**, so a mistake here is a check that passes when
  it should not. The `DECOY` assertion is the guard, and it stays.

## Verification

- **The check itself.** `nix build .#checks.x86_64-linux.install-encrypted`
  must finish. It has never finished, so a completing run *is* the headline
  result -- and it must be timed, because "it finished" and "it finished in a
  normal time" are different claims.
- **Section 1** is awkward here and the spec says so rather than pretending:
  the natural break is to restore the unbounded match and watch it hang, which
  takes 90 minutes to observe. A bounded proof instead: assert in the test that
  the matched window is bounded, which fails immediately if the slice is
  removed.
- **The existing assertions** -- `SPLIT` matches, `DECOY` does not -- run
  unchanged at import time and are what keep #834's property honest.
- **What no check reaches:** whether the window is large enough for a split
  this test has never seen. The margin is the argument, not a proof.

## Open question

Should the upstream quadratic be raised with nixpkgs? It affects every VM test
that waits on a chatty console, and our fix is a local workaround. Filing there
is not done unprompted (section 11), so this is the maintainer's call.
