---
status: approved
issue: 967
intent: intent/2026-09-24-967-apply-confirms-what-it-builds.md
---

# Spec: apply refuses a file that changed since you last saw it

## The direction, decided

**The hash**, of the three the issue offered. Taking it because the mechanism is
already written, already persistent, and already aimed one file over -- and
because it is the only one of the three that covers `advanced.nix`.

`modules/apps.nix:3434` keeps per-file state in a user-owned directory that
survives reboots:

```sh
applied="${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied"
```

and the loop below it records `sha256sum` of each **destination** after copying,
so an edit made in the flake itself is told apart from a new pick and is
*preserved* rather than clobbered. That is careful work about exactly this class
of problem. It watches the wrong side: nothing hashes the **source**, which is
what a process running as the user writes.

## Design

**Apply refuses to build a source file whose content changed since the user last
confirmed it, unless they confirm the change.**

Alongside each existing destination record, apply keeps a **source** record:
the sha256 of `~/.config/nixarchy/<part>.nix` as it stood when the user last
agreed to build it. On each apply, per file:

| source vs its record | apply |
|---|---|
| unchanged | copies and builds, silently. The ordinary case, and it must stay silent. |
| no record yet | shows the file is new and asks once. First run after this ships records everything, so it is a one-time cost, not a per-apply prompt. |
| changed | **shows what changed** and asks. Confirming records the new hash. |

**`--yes` confirms.** `--detach` already requires `--yes` (`:3371`, *"a unit has
no terminal to answer"*), so the no-tty contract exists and this rides on it
rather than inventing one. A menu-driven apply is `--detach --yes` and is
unaffected; the protection is for the interactive path, which is where a person
is present to be protected.

**What "shows what changed" is:** a unified diff of the source against its last
confirmed content, truncated. Not a diff of the flake copy, and not an
evaluation of what the module would produce -- the second is the honest thing to
want and needs a build, which is what we are deciding whether to do.

### `advanced.nix`, answered

The intent asked what `advanced.nix` means here, since it is free-form and no
shape check can constrain it. **A hash does not care about shape**, so it covers
`advanced.nix` identically to the others. That is the decisive argument for this
direction over the shape-check one: one mechanism, four files, no exception that
needs its own reasoning.

### `flatsnap.nix`, left alone

nixarchy-flatsnap#10 already validates its file against its own grammars,
regenerates it from parsed state, and builds only what the user confirmed via
`apply --expect <hash>`. This spec does **not** add a second confirmation on top
of that -- a file that arrives already confirmed should not be confirmed twice.
The source record is kept for it anyway, so a machine without the plugin's newer
version still gets the general protection.

## Alternatives rejected

| | why not |
|---|---|
| Constrain `apps.nix`/`services.nix` to their generated shape | Real, and does not cover `advanced.nix`, which is the file with no shape and the widest reach. Two mechanisms, one of them with an exception. |
| A diff on every apply | A prompt people see every time is a prompt they learn to dismiss. The intent named this; the hash means the ordinary apply stays silent. |
| Evaluate and diff the resulting NixOS config | The honest version of "show what it will do", and it needs a build to answer. Expensive on every apply and a much larger change. Worth revisiting if the hash proves too blunt. |
| Make the polkit prompt informative | A different mechanism and a different issue; the intent puts it out of scope. |

## Risks

- **The one-time prompt on first run.** Every machine that upgrades past this
  has no source records and will be asked once per existing file. That is
  defensible but it must be *obviously* a one-time thing in the wording, or it
  reads as a new nag.
- **`--yes` now means more than it did.** It meant "do not ask before
  rebuilding"; it will also mean "and accept whatever these files say". That is
  a widening of an existing flag's meaning, which section 4 records as breaking
  readers silently. It must be stated where `--yes` is documented.
- **State the protection depends on is user-writable too.** `$applied` is under
  `$XDG_STATE_HOME`, so the same process that edits the source can edit the
  record. **This does not stop a determined attacker and must not be described
  as if it does.** What it stops is the realistic case: something that writes a
  config file without knowing nixarchy's state layout, and the accident where a
  tool rewrites a file the user forgot they had. Claiming more than that would
  be worse than claiming nothing.
- **Mode A.** A machine that never runs `nixarchy-apply` is untouched.

## Verification

- **`checks.options`** cannot reach this: the logic is in generated shell, not
  in the option surface. The real check is a **`runCommand` driving the script
  against fixture files**, the way `tests/menu-verbs.nix` and `pkgs/secret.nix`'s
  tests already drive real commands against fixtures.
  Cases: unchanged source is silent and builds; changed source refuses without
  `--yes`; changed source with `--yes` builds and re-records; a missing record
  asks once and then does not; `$applied` unwritable degrades to asking rather
  than to silently building.
- **Section 1:** each case seen failing with the comparison removed, and that
  output in the PR. The trap: asserting that apply *printed something*, which
  any message satisfies. Assert that it **did not build** when it should refuse.
- **What no check here reaches:** whether a user reads the diff. Recorded in
  `tests/AGENTS.md` rather than implied.

## Open question

Should a changed `flatsnap.nix` be refused here as well, given the plugin
already confirms it separately? Refusing twice is noise; not refusing means a
machine running an **older** flatsnap plugin has no protection on that file at
all. I have specified "record but do not double-confirm", which is the quieter
choice and the weaker one. Say if you want it refused unconditionally.
