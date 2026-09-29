---
status: approved
issue: 1058
intent: intent/2026-09-29-1058-grep-q-pipefail.md
---

# Spec: A check does not fail because grep found what it was looking for

## Design

**The fix: no pipe.** In `tests/manifest-has-kind.nix`, `probe()` tests the
extract with bash's own pattern match:

```sh
[[ $fn == *'function manifestHasKind'* ]] || {
  echo "FAIL: manifestHasKind not found in $1; upstream moved or renamed it"
  exit 1
}
```

This replaces `printf '%s\n' "$fn" | grep -q 'function manifestHasKind'`.
With no second process there is no writer to kill, so the failure mode cannot
exist, rather than merely being made unlikely. The message, the exit code and
the negative control are unchanged. `$fn` is still written into `probe.qml`
the way it is today, which is a redirect to a file, not a pipe.

**The lesson** goes into `tests/AGENTS.md` as a new section, placed before
"The cheap ones, which is where new checks usually belong". The sections there
are unnumbered, so nothing references them by position. Its content:

- The mechanism.
- The measured evidence: 4 `write()`s, `PIPESTATUS=141 0`, and 0 failures in
  8,000 local runs. That last one is why it survives review.
- The safe spellings:
  - `[[ $x == *pat* ]]` or `case`, for a string already in a variable;
  - `grep -q pat <<<"$x"` or `grep -q pat file`, where grep reads input the
    shell has already finished writing;
  - `grep -c`, or grep without `-q`, which reads to EOF.
- **When it applies:** only under `pipefail` (stdenv's `runCommand` and every
  `writeShellApplication` set it), and only where the producer writes again
  after the line that matches.

A `# Why: tests/AGENTS.md#…` pointer sits at the changed line (§7: short note
at the line, reasoning in AGENTS.md).

**A follow-up issue** lists the other roughly 99 `| grep -q` occurrences by
file, for each to be checked. For each one, the questions are:

- is `pipefail` on there?
- can the producer write after the match?

It gets milestone "Keeping the lights on" and labels `ci` and `bug`. It is not
fixed here (the approved scope).

## Alternatives rejected

- **`grep -q … <<<"$fn"`.** It is correct, since the shell writes the here
  string before grep runs. But it still spawns grep for a question bash
  answers alone, and a later edit back to a pipe would look harmless.
- **`grep -c` / drop `-q`.** grep reads to EOF, so there is no SIGPIPE. It is
  correct, but it keeps a pipe and the trap's shape, which invites the `-q` to
  return.
- **`set +o pipefail` around the line.** It hides every other failure in that
  pipeline too, which is exactly what `pipefail` is there to catch.
- **A lint over the whole tree for `| grep -q`.** 99 hits, many not under
  `pipefail` (NixOS test drivers' `machine.succeed`). As a gate it would be
  mostly false positives. The follow-up issue measures first.
- **Retrying the check.** §10.

## Risks

- **The pattern match is bash-only.** The check's builder is stdenv bash, so
  that is fine. It must not be copied into a `/bin/sh` script. The AGENTS.md
  entry names `case` for that.
- **The derivation changes, so the check rebuilds once.** It is cheap
  (seconds).

## Verification

§1, all three directions:

1. **The mechanism** is demonstrated outside the check: a forced delay between
   writes gives `PIPESTATUS=141 0` for the old spelling. The new spelling has
   no pipeline to fail. The PR shows the old spelling failing
   deterministically, which the check itself could never show.
2. **The check still fails when the function really is missing.** Point the
   awk extract at a name that does not exist, confirm the break applied
   (`git diff`), build `checks.manifest-has-kind`, and it fails with "not
   found". Restore it.
3. **The check passes as shipped:** build `checks.manifest-has-kind`. The
   negative control, upstream's function missing "menu" in a Qt sequence,
   still reports bits 1.

Plus `nix fmt -- --ci`, statix and deadnix. Local builds run only when
`gh run list` shows nothing in flight.
