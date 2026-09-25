---
status: approved
issue: 1000
author: olafkfreund
---

# Intent: a test file nothing imports should fail the build

## Problem

`tests/shell-ipc-resolve.nix` shipped with #963 and `flake.nix` named it
**nowhere**. It had never run -- not in CI, not locally, not once -- from the
moment it was written until #982 happened to try registering a sibling beside it
and found the anchor missing.

That is `CLAUDE.md` section 4's headline failure, *"a check that nothing runs is
worse than no check"*, arriving through the one door the existing guard does not
watch.

## Why the existing guard misses it

`build.yml` asserts that **every entry in `checks` is built by some workflow**
that triggers on pull requests. That closes one direction, and it was written
after the failure it exists for (#164/#166).

It cannot close the other. **A file in `tests/` that no `checks` entry imports
is invisible to it**: there is nothing to name, so nothing is missing, so
nothing fails. A test written, reviewed and merged without a `flake.nix` entry
passes every gate this repository has -- including the one about checks nothing
runs.

## Measured, and it makes this cheaper than I said when filing

The issue as filed implies a design problem: helpers, fixtures and
differently-named imports all needing exemptions. **Counted rather than
assumed:**

    tests/*.nix files                              88
    named in flake.nix                             87
    imports in flake.nix that resolve to a file    87
    unregistered                                    1  (with-vm-cleanup.nix)

`with-vm-cleanup.nix` is a helper imported by `install.nix`,
`install-encrypted.nix`, `free-space.nix` and `install-teardown.nix`. That is
the whole exemption list.

Both directions are clean today: no stray test, and no import naming a file that
does not exist. So this is **purely a guard against recurrence**, not a cleanup
-- and the mechanism is a three-line comparison with one documented exception,
rather than the classification problem the issue describes. I overstated the
cost when I filed it, on the assumption that 88 files would hold more mess than
they do.

## Proposed outcome

- A `tests/*.nix` that no `checks` entry imports, and that is not on a short
  exempt list carrying its reason, **fails the build** and is named.
- The exempt list holds one entry today and its reason, in the shape
  `cache-allowlist.sh` already uses -- each exemption says why, so the next
  reader can judge whether it still holds.
- Adding a test without registering it stops being possible to merge.

## Affected users and systems

- Nobody's machine. This is a CI guard over the repository's own structure.
- Whoever adds the next check, which is the point.

## Constraints

- **A workflow edit is a CI-gate change** (section 11), so where this runs is a
  human's call. It can live beside the existing coverage step in `build.yml`, or
  as a `checks.<name>` entry that is itself covered by the generated list --
  the second needs no workflow edit at all and is worth preferring for that
  reason alone.
- **The comparison must not be a grep for a filename.** A check that greps
  `flake.nix` for `tests/foo.nix` passes if the string appears in a comment.
  Whether the file is *imported* is the property.
- **It must refuse rather than pass on an implausible parse** -- the lesson from
  #949's agent-id comparison, where a regex that matched nothing would have
  accepted everything. Fewer than, say, 50 registered tests means the parse
  broke, not that 38 tests were unregistered.

## Open questions

1. **Where does it live?** A `checks.<name>` entry is self-covering: the
   generated check list picks it up with no workflow edit, so it needs no
   CI-gate change and no human sign-off beyond this. A `build.yml` step sits
   beside the existing guard and reads as one thing. I lean to the **check**,
   because it needs nothing from anybody and runs in the same place as the rest.

2. **What counts as "imported"?** The honest test is evaluating
   `self.checks.<system>` and asking which files it read, which Nix will not
   tell you directly. The practical one is parsing `import ./tests/<name>.nix`
   out of `flake.nix`, which is what the 87 above came from, and which would
   miss a check that built a path dynamically. Nothing does that today; a
   comment saying so is cheaper than handling it.

## Not in scope

- Registering anything. #999 registered the one stray and it passes.
- The existing coverage gate, which is correct for its direction.
- `tests/*.py` and other non-Nix files, which are fixtures rather than checks.
