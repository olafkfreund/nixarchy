---
status: approved
issue: 1000
intent: intent/2026-09-25-1000-test-registration-guard.md
---

# Spec: a test no checks entry imports fails the build

## The intent's questions, decided

**1. It is a `checks.<name>` entry, not a `build.yml` step.** Self-covering:
`generated-checks.sh` enumerates every flake check and emits all but its
hand-written exempt lists, so this one is picked up with **no workflow edit** --
and therefore no CI-gate change needing a human (section 11). A `build.yml`
step would sit beside the existing coverage guard and read as one thing, but it
would need somebody to touch CI to add a guard about forgetting things.

**2. "Imported" means `import ./tests/<name>.nix` appears in `flake.nix`.** The
honest test is asking Nix which files `checks` actually read, and it will not
say. This misses a check that built a path dynamically; nothing does that, and
a comment saying so costs less than handling it.

## Design

A `runCommand` reading `flake.nix` and the `tests/` directory:

1. Collect `tests/*.nix` filenames.
2. Collect every `import ./tests/<name>.nix` in `flake.nix`.
3. **Refuse** if fewer than 50 imports were found -- that is a broken parse, not
   38 unregistered tests. #949's agent-id comparison is the precedent: a regex
   matching nothing would have accepted everything and passed having checked
   nothing.
4. Fail, naming each file, for anything in (1) that is in neither (2) nor the
   exempt list.

**The exempt list has one entry**, with its reason beside it, in the shape
`cache-allowlist.sh` uses:

```
with-vm-cleanup.nix   a helper, imported by install, install-encrypted,
                      free-space and install-teardown rather than registered
```

**Measured before designing:** 88 `tests/*.nix`, 87 named in `flake.nix`, 87
imports that resolve to a real file, 1 unregistered. Both directions are clean
today, so this guards recurrence rather than fixing a backlog.

## Alternatives rejected

| | why not |
|---|---|
| A `build.yml` step | Needs a CI-gate change for a guard about forgetting; the check needs nothing. |
| `grep -q "tests/$f" flake.nix` | Passes if the filename appears in a **comment**. Whether it is *imported* is the property. |
| Ask Nix which files were read | It does not expose that. |
| Also guard `tests/*.py` | Those are fixtures (`install-matrix.py`, `install-teardown.py`), not checks. Guarding them would need a second exempt list for no benefit. |

## Risks

- **The parse is the whole guard**, so it is also the whole failure mode. It can
  fail open (match nothing, accept everything) -- closed by the floor in step 3,
  and that floor must be seen refusing.
- **A file added to `tests/` that is genuinely not a check** now needs an exempt
  entry. That is the intended friction, and one line.
- **`flake.nix` is read as text**, so a reformat that splits an import across
  lines would break the parse. The floor catches that too, loudly.

## Verification

- The check passes on the tree as it stands (87 registered, 1 exempt).
- **Section 1, two breaks, both required in the PR:**
  - add an unregistered `tests/*.nix` -> the build fails naming it;
  - break the import regex so it matches nothing -> the check **refuses** on
    the floor rather than flagging 88 files or passing.

  The second is the one that matters. A comparison that silently accepts
  everything is the green light section 1 exists for.
- **What it cannot reach:** a check whose test file is registered but which no
  workflow builds. That is the existing gate's direction, and it already holds.
