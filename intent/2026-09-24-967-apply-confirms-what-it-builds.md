---
status: approved
issue: 967
author: olafkfreund
---

# Intent: apply should not build, as root, a file it never showed you

## Problem

`nixarchy-apply` copies `~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix`
into the flake and imports each as a **full NixOS module**
(`modules/apps.nix:3439`, the copy at `:3456`, the generated `imports` at
`:3489`).

Those files are writable by any process running as the user. So whatever such a
process writes -- a `systemd.services` unit, a `users.users` entry, an
`environment.etc` file, a `security.sudo` rule -- becomes **root system
configuration at the next apply**. The only confirmation is a polkit prompt that
does not say what will be built, or no prompt at all where sudo is passwordless.
`advanced.nix` is free-form by design, so there is no shape anyone could check.

This is a privilege boundary, not an inconvenience: the gap between "can write
files as you" and "can configure the system as root" is supposed to be the sudo
prompt, and here the prompt carries no information about what it is authorising.

**It matters where the flake itself is NOT user-writable.** On the hosts here
`/etc/nixos` points into `$HOME`, so the user can edit the flake directly anyway
and nothing is gained by a process going through these files. That is a property
of this setup, not of nixarchy, and it is the reason this has never bitten
anyone here.

## What reading the code adds

**The machinery for the fix already exists and points the other way.** The loop
already keeps a hash per copied file:

```sh
record="$applied/$(printf '%s' "$dst" | sha256sum | cut -c1-16)"
...
if [ -f "$dst" ] && [ -f "$record" ] && ! sha256sum <"$dst" | cmp -s - "$record"; then
  kept="$applied/$part.nix.edited-in-flake.$(date +%Y%m%d%H%M%S)"
```

That detects **the flake copy being edited behind apply**, and preserves the
user's version rather than clobbering it. It is careful work about exactly this
class of problem -- and it watches the destination. Nothing watches the
**source**, which is the side a hostile or careless process writes.

So the third direction the issue proposes ("record a hash of each file at the
time the user last saw it, and refuse to copy one that changed behind them") is
not a new mechanism. It is the existing one, aimed at the other file.

**And one of the four is already solved, upstream of us.** nixarchy-flatsnap#10
(PR #20, merged) checks `flatsnap.nix`'s shape and every entry against the
grammars its `add` command uses, regenerates the file from parsed state before
apply copies it, and builds only the state the user confirmed
(`apply --expect <hash>`). So `flatsnap.nix` has a model that works; `apps.nix`,
`services.nix` and `advanced.nix` do not.

## Proposed outcome

- Applying shows what it is about to build from these files, or refuses to build
  a file that changed without the user seeing it. Which of those, and for which
  files, is the decision below.
- `advanced.nix` stays an escape hatch -- it exists to let people write
  arbitrary NixOS config -- but being an escape hatch is stated and confirmed
  rather than implicit.
- A machine where the flake is user-writable anyway loses nothing and gains no
  new prompts for a boundary that is not there.

## Affected users and systems

- Any machine where the flake is **not** user-writable -- which is the
  configuration this protects, and not the one used here.
- `modules/apps.nix` (the generated `nixarchy-apply`), and whatever confirms.
- Not the installer: it writes the flake, not these files.

## Constraints

- **Must not break the no-tty path.** Menu actions run detached; `nixarchy-apply
  --detach --yes` is a supervised unit with nowhere to ask. A confirmation that
  only works with a terminal turns a working path into a broken one, and #949's
  bug 3 is the same mistake already made once here.
- **Must not clobber a user's file.** The existing `edited-in-flake` handling is
  careful about this and must keep working.
- **Must not make an ordinary apply annoying.** A prompt on every apply is a
  prompt people learn to dismiss, which is worse than none.
- `flatsnap.nix` already has a stricter mechanism upstream; whatever is done
  here should not fight it or duplicate it.

## Open questions

1. **Which of the three directions, and is it one issue or three files?** The
   issue offers a diff before switch, a constrained shape for
   `apps.nix`/`services.nix`, and a hash the user last saw. They are not
   exclusive, and they differ a lot in cost. My inclination is the **hash**,
   because the mechanism is already written and aimed at the other file, and
   because a diff nobody reads is the prompt problem again -- but a hash needs
   somewhere honest to record "the user saw this", and I do not yet know where
   that is for a file edited by hand in `$EDITOR`.

2. **What does `advanced.nix` mean here?** It is free-form on purpose. A hash
   works for it; a shape check cannot. If the answer for the other two is a
   shape check, `advanced.nix` needs a different answer in the same change.

3. **Is this worth doing given the flake is user-writable on every machine we
   run?** An honest question rather than a rhetorical one. The answer is
   probably yes -- nixarchy is shipped to people whose setups we do not know --
   but it decides how much machinery is proportionate, and I would rather ask
   than build for a threat model nobody here has.

## Not in scope

- `flatsnap.nix`'s own validation, which is nixarchy-flatsnap's and is done.
- Making the polkit prompt itself informative; that is a different mechanism
  and probably a different issue.
- Anything about who may run `nixarchy-apply`.
