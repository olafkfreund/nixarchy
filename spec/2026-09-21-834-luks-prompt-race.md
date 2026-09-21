---
status: approved
issue: 834
intent: intent/2026-09-21-834-luks-prompt-race.md
---

# Spec: tolerate the kernel talking over the LUKS prompt

Refs #834.

## Decision

Keep waiting for the prompt, and make the pattern tolerate a **kernel message
landing inside it**. Send the passphrase once, as now.

That is option 3 of the three the intent listed. The argument that settled it
came from the independent review (Codex, consulted at the maintainer's
request), and it is the one I had missed:

> Option 1 violates your "don't type into a shell" constraint unless you add a
> guard, and that guard is just prompt detection again.

A retry loop does not escape the matcher. It keeps the same detection problem
and drops the assertion that we typed at a prompt. Option 2 — quieting the
console — lowers the probability without removing the race, and throws away the
stage-1 output this test most needs on the day it genuinely fails.

## How the matcher tolerates it, and why not the way that was proposed

The review's implementation was to join the escaped characters of the phrase
with `.{0,2048}?`. **Rejected, on measurement.**

`wait_for_console_text` is not a line matcher. From the driver
(`nixos/lib/test-driver/src/test_driver/machine/__init__.py:1291`):

```python
console = io.StringIO()          # accumulates everything since the wait began
...
matches = re.search(regex, console.read())
```

It searches a buffer that **grows to hold the whole boot**. With thirteen gaps
of up to 2048 characters each, the pattern can span roughly 26 KB — and the
letters of `assphrase for`, in order, with arbitrary text between them, occur
readily in a boot log. Verified with a decoy containing no prompt at all:

| pattern | the real split | a clean prompt | **decoy, no prompt** |
| --- | --- | --- | --- |
| `[Pp]assphrase for` (today) | **no match** | match | safe |
| `.{0,2048}?` joined | match | match | **MATCHES** |
| kernel-line bounded | match | match | safe |

A false positive here is not a flaky test. It sends the passphrase to whatever
is listening, with nothing having asked for it — the exact outcome the intent
forbids under "only types after seeing the prompt".

**So the tolerance is shaped, not budgeted.** What interrupts the prompt is a
`printk`, and a `printk` on this console has a form: `[ <seconds>.<micros>]`
followed by the rest of its line. The separator permits a run of those and
nothing else:

```python
KMSG = r"(?:\[ *\d+\.\d+\][^\n]*\n?)*"
prompt = "(?i:" + KMSG.join(re.escape(c) for c in "assphrase for") + ")"
```

This is **tighter** than any character budget — arbitrary prose between the
letters does not match — and **more general**, because it tolerates any number
of interleaved kernel lines rather than a guessed length. The observed failure
was one line of 92 characters; a budget derived from it would have been a guess
about the next one.

`assphrase for` rather than `passphrase for` keeps the existing tolerance of
both stage-1 spellings (`Passphrase for …` and `Please enter passphrase for
disk …`) without an alternation, and `(?i:)` replaces the `[Pp]`.

## The fixture is the transcript

The bug is a race. A VM run that passes proves nothing, and the race cannot be
provoked on demand — so the check on the check runs in Python, in the test
script, against the bytes the failure actually produced:

```python
SPLIT = ("Please enter pas[    2.948528] scsi 1:0:0:0: CD-ROM            QEMU"
         "     QEMU DVD-ROM     2.5+ PQ: 0 ANSI: 5\n"
         "sphrase for disk disk-main-root (cryptroot): (press TAB for no echo) ")

assert re.search(prompt, SPLIT), "the matcher no longer tolerates a split prompt"
assert not re.search(r"[Pp]assphrase for", SPLIT), "the transcript is no longer a split"
```

The first line is the regression test. The second pins *why* it exists: it
fails if someone "simplifies" the fixture into a normal prompt, which would
leave the first assertion passing for the wrong reason — a check that cannot
fail (§1).

Intent open question 4 asked whether to assert the old pattern fails. Yes, and
that is the reason: it is not nostalgia for a dead pattern, it is what keeps
the fixture honest.

## Alternatives rejected

- **A character budget between letters** (`.{0,N}?`). See above: it admits
  matches across unrelated output, and the safe value of N is a guess about
  the length of the next kernel message.
- **Send the passphrase on a retry loop.** Escapes the matcher by giving up the
  guarantee it exists to provide.
- **Lower `loglevel`.** A smaller target, not a fix, and it costs the stage-1
  output that makes a real failure diagnosable.
- **A second serial device**, so the prompt and `printk` do not share a
  console. Attractive and rejected: making it honest means separating kernel
  console routing from stage 1's password agent tty — initrd plumbing for a bug
  that is "console bytes are not atomic".
- **A shared helper for every `wait_for_console_text` in the suite** (intent
  open question 3). Out of scope here: this change is one file and provable
  today. If a second call site needs it, the helper is a later change with its
  own evidence, and this spec is deliberately not pre-building for it.

## Risks

- **`wait_for_console_text` still uses the growing buffer.** The shaped
  separator makes a false positive implausible rather than impossible; the
  decoy test is the guard, and it lives beside the pattern.
- **A `printk` format change** would defeat `\[ *\d+\.\d+\]`. The fixture would
  still pass, because it pins the recorded bytes — so this risk is not covered
  by the fixture and is stated here instead. It is the same trade the rest of
  the suite makes against console formats.
- **The end-to-end proof is unchanged.** Reaching `multi-user.target` and
  mounting `/` from the mapped device still carry the real assertion. If the
  matcher ever became wrong in the *other* direction — matching when there is
  no prompt — those two would fail, loudly, which is the backstop.

## Verification

Per §1, both directions, in milliseconds and with no VM:

1. **The fix works on the failure.** The fixture asserts the new pattern
   matches the recorded split. Revert the pattern to `[Pp]assphrase for` and
   that assertion fails immediately, with the split in the message — instead of
   a 600-second timeout in a nightly.
2. **The fix is not too loose.** A decoy built from kernel lines carrying the
   letters of the phrase in order, with no prompt present, must **not** match.
   Replace the separator with `.{0,2048}?` and this assertion fails.
3. **Both spellings still match**, clean: `Passphrase for …` and `Please enter
   passphrase for disk …`.

The VM check continues to run nightly and remains the end-to-end proof. What
changes is that its matcher now has a unit test, which is the part a passing
nightly could never give.
