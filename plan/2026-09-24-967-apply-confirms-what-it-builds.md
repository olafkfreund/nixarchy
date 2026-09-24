---
status: draft
issue: 967
spec: spec/2026-09-24-967-apply-confirms-what-it-builds.md
---

# Plan: apply refuses a source file that changed since you last confirmed it

## The approved decisions, carried over

Self-contained; nothing here needs the intent or spec open.

1. **The hash**, not a shape check and not a diff on every apply. The mechanism
   is already written and persistent -- `applied="${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied"`
   (`modules/apps.nix:3434`) -- and already records a sha256 per copied file. It
   watches the **destination**, so an edit made in the flake is told apart from
   a new pick and preserved. Nothing watches the **source**, which is the side a
   process running as the user writes.

2. **A hash covers `advanced.nix`.** It says nothing about shape, so the
   free-form file -- the one with the widest reach and no shape to check -- is
   covered identically to the others. One mechanism, four files, no exception.

3. **`--yes` confirms**, and `--detach` already requires `--yes`
   (`modules/apps.nix:3371`, *"a unit has no terminal to answer"*). The no-tty
   contract exists; this rides on it. A menu-driven apply is unaffected.

4. **The ordinary apply stays silent.** Unchanged source, no output. A prompt
   people see every time is one they learn to dismiss.

5. **This does not stop a determined attacker**, and nothing written may say it
   does: `$applied` is under `$XDG_STATE_HOME`, so whatever edits the source can
   edit the record. It stops the realistic case -- a tool that writes config
   without knowing nixarchy's state layout, and the accident of a file the user
   forgot they had.

6. **`flatsnap.nix` is recorded but not double-confirmed.** nixarchy-flatsnap#10
   already validates and confirms it. This is the quieter choice and the weaker
   one; the spec's open question, carried forward unchanged.

## Confirmed while writing this, not assumed

**The test harness already exists.** The spec cited `tests/menu-verbs.nix` and
the secret tests as the precedent. The far closer one is
**`tests/apply-imports.nix`**, which drives *this very script*: it lifts
`nixarchy-apply` out of `nixosConfigurations.vm`'s `systemPackages` rather than
from `system.build.toplevel` (a deliberate note there about the hosted runner's
~14 GB disk), stubs `nh` with `printf '#!/bin/sh\nexit 0\n'` so the rebuild
never runs, builds a fake flake, and points `NIXARCHY_FLAKE` at it. The new
check is a sibling of that file, not a new pattern -- the hard part is solved.

## Steps

1. **`modules/apps.nix`, in the copy loop at `:3439`** -- before the copy, hash
   the **source** and compare it with a per-source record beside the existing
   destination one:

   ```sh
   srec="$applied/src.$(printf '%s' "$src" | sha256sum | cut -c1-16)"
   ```

   Three cases, per the table in the spec: unchanged -> silent; no record ->
   ask once, then record; changed -> show the diff against the last confirmed
   content and ask. `--yes` answers yes in all of them.

   The existing destination record and its `edited-in-flake` handling are
   **untouched**. They solve a different problem in the other direction and the
   change must not disturb them.
   → verify by step 4.

2. **`modules/apps.nix`, the `--yes` usage line at `:3356`** -- state the
   widened meaning. It meant "do not ask before rebuilding"; it now also means
   "and accept whatever these files say". Section 4 records that widening
   something silently breaks whoever relied on it being narrow, so the widening
   is written where the flag is described, not only in a commit message.
   → verify by reading it back.

3. **Skip `flatsnap.nix` for the prompt, record it anyway.** One branch in the
   loop, with the reason at it: the plugin confirms that file itself, and
   confirming twice is noise -- but the record keeps the general protection for
   a machine on an older plugin.
   → verify by step 4's fixture.

4. **`tests/apply-confirm.nix`** -- a sibling of `tests/apply-imports.nix`,
   reusing its shape (script from `systemPackages`, stubbed `nh`, fake flake,
   `NIXARCHY_FLAKE`). Cases:

   | | assert |
   |---|---|
   | unchanged source | builds, and says nothing about it |
   | changed source, no `--yes` | **did not build** -- the stub `nh` was not reached |
   | changed source, `--yes` | built, and the record moved to the new hash |
   | no record at all | asked once; a second run with the same content is silent |
   | `$applied` unwritable | asks rather than silently building |

   **Section 1:** each seen failing with step 1's comparison removed, and that
   output in the PR. The trap: asserting apply *printed something*, which any
   message satisfies. Assert that it **did not build** -- `apply-imports.nix`
   already shows how, by watching for the stub's side effect.

5. **`tests/AGENTS.md`** -- record what this cannot reach: whether anyone reads
   the diff, and that the state guarding this is writable by the same user it
   guards against. Both are real limits and neither is a check's to fix.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.apply-confirm` | passes; five cases |
| `nix build .#checks.x86_64-linux.apply-imports` | still passes -- same script, and the new branch must not disturb it |
| `nix build .#checks.x86_64-linux.options` | passes |
| `nix fmt -- --ci`, statix, deadnix | clean |

No workflow edit: `.github/scripts/generated-checks.sh generated` enumerates
every flake check and emits all but its `claimed`/`exempt` lists, so a new entry
is picked up automatically. (Checked -- this is what #968's warning got wrong.)

Queue check before the heavy build, per section 6.

## Rollback

`git revert`. The source records under `$XDG_STATE_HOME/nixarchy/applied` are
left behind and ignored; nothing reads them once the comparison is gone, and
they are a few hex lines. No user file is touched in either direction, and the
destination-side `edited-in-flake` protection is unchanged throughout.
