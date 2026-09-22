---
status: approved
issue: 834
spec: spec/2026-09-21-834-luks-prompt-race.md
---

# Plan: tolerate the kernel talking over the LUKS prompt

Branch `fix/834-luks-prompt-race`, already carrying the intent and spec. One
commit; the change is one file. A deviation updates this file in the same
commit as the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **Keep waiting for the prompt.** Send the passphrase once, after seeing it.
  A retry loop needs a guard, and that guard is prompt detection again.
- **Tolerate a run of kernel timestamped lines between the characters**, and
  nothing else:

  ```python
  KMSG = r"(?:\[ *\d+\.\d+\][^\n]*\n?)*"
  prompt = "(?i:" + KMSG.join(re.escape(c) for c in "assphrase for") + ")"
  ```

- **Not a character budget.** `.{0,2048}?` between letters matches a decoy boot
  log containing no prompt, because `wait_for_console_text` searches a buffer
  holding the whole boot. That would send the passphrase with nothing asking.
- **`loglevel` stays**, the second serial device is rejected, and a shared
  helper for other call sites is out of scope until a second one needs it.
- **The fixture is the recorded transcript**, asserted both ways.

## Measured before planning

- The real interruption is **92 characters**: one kernel line plus its newline.
- `import re` is already in the test script (`tests/install-encrypted.nix:362`),
  so no import is added.
- The wait is at `:642`, inside `testScript = import ./with-vm-cleanup.nix
  pkgs.lib ''…''` — a Nix **indented string**. Backslashes pass through
  literally, which is what makes the regex writable; `${` would interpolate,
  and the pattern contains none.

## Steps

**1. Replace the matcher, and put its fixture beside it.** In
`tests/install-encrypted.nix`, immediately above the existing wait at `:642`:

- build `KMSG` and `prompt` as above;
- assert the pattern against the recorded split, and assert the **old** pattern
  does not match it;
- assert a decoy — kernel lines carrying the letters of the phrase in order,
  with no prompt — does **not** match;
- assert both clean spellings still match;
- pass `prompt` to `wait_for_console_text`, leaving the 600 s timeout and the
  `send_console` line as they are.

The comment above the wait keeps its existing explanation of the two stage-1
spellings and gains the reason the separator is shaped rather than budgeted —
three lines, not the spec's argument (§7: long reasoning lives in the
directory's `AGENTS.md`, short notes live at the line they protect).

→ verify by §1, three assertions that run in milliseconds and need no VM:

  a. **It fixes the failure.** Revert `prompt` to `[Pp]assphrase for`; the
     split-transcript assertion must fail, naming the transcript. That is the
     break this issue exists for, and today it "passes" only by timing out in a
     nightly.
  b. **It is not too loose.** Replace the separator with `.{0,2048}?`; the
     decoy assertion must fail. This is the one that matters most — a matcher
     that is too permissive types a passphrase at no prompt.
  c. **Both spellings still match**, clean.

Confirm each break landed by reading the **file**, not `git diff` against
`HEAD` — a change inside a block that is not yet committed produces no `-` line
to match, which cost a cycle on #831.

Run the assertions under `python3` directly first, against the extracted
pattern, before spending a VM build: the fixture is plain Python and does not
need the driver to be exercised.

**2. Evaluate, and build the check if the slots are free.** The assertions run
inside the test script, so a full `checks.install-encrypted` is the only way to
see them execute in place.

→ verify by `nix eval --raw .#checks.x86_64-linux.install-encrypted.drvPath`
first — the pattern lives in a Nix string and an escaping mistake is an
evaluation error, not a test failure. Then, **only if `gh run list` shows no
install job in flight** (§6, and three 90-minute timeouts today make this
sharper than usual), build the check by its pinned `drvPath`, not by attribute
path (AGENTS.md §5: building by attribute lets a stale evaluation back in).

The check is a nightly one and takes tens of minutes. If the box is busy, the
Python assertions plus a clean evaluation are enough to open the pull request,
and the nightly is the end-to-end proof — said plainly in the PR rather than
implied.

## Tests

```
python3 - <<'PY'   # the three assertions, standalone, before any build
PY
nix eval --raw .#checks.x86_64-linux.install-encrypted.drvPath
nix build '<that drv>^*' --print-build-logs      # only if nothing is in flight
nix fmt -- --ci && nix run --inputs-from . nixpkgs#statix -- check . \
  && nix run --inputs-from . nixpkgs#deadnix -- --fail .
```

The lint trio runs over **`.`, not the changed file** — #829 was `main` going
red because the new line was fine and its neighbours were not.

`.humanize/` is untracked and not ignored; Codex writes its transcript there.
Stage explicit paths, never `git add -A` — that reflex committed a gcroot and a
74-file, 19 MB scratch directory earlier today.

## Rollback

`git revert` the commit. The matcher returns to `[Pp]assphrase for` and the
check returns to failing intermittently, which is where it was. Nothing outside
the test changes, no state lives outside the repository, and the installed
system is untouched.
