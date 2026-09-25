---
status: approved
issue: 1000
spec: spec/2026-09-25-1000-test-registration-guard.md
---

# Plan: a test no checks entry imports fails the build

## The approved decisions, carried over

1. **A `checks.<name>` entry**, not a `build.yml` step: `generated-checks.sh`
   picks it up with no workflow edit, so no CI-gate change needs a human.
2. **"Imported" = `import ./tests/<name>.nix` in `flake.nix`.** Misses a
   dynamically built path; nothing does that, and a comment is cheaper.
3. **A floor that refuses**: fewer than 50 imports found means the parse broke,
   not that 38 tests are unregistered. #949's precedent.
4. **One exempt entry**, `with-vm-cleanup.nix`, with its reason beside it.
5. Measured first: 88 files, 87 registered, 1 exempt, both directions clean.

## Steps

1. **`tests/test-registration.nix`** -- a `runCommand` over `flake.nix` and
   `tests/`. Collect filenames, collect imports, refuse under the floor, then
   fail naming anything registered nowhere and not exempt.
   → verify by step 3.
2. **`flake.nix`** -- register it, beside the other `tests/` entries.
   → verify by the build.
3. **The two breaks**, both in the PR:
   - an unregistered `tests/*.nix` -> fails, naming it;
   - the import regex broken to match nothing -> **refuses on the floor**.
4. **`tests/AGENTS.md`** -- replace the note #999 left saying a comparison
   *would* close this with one saying it does, and what it cannot reach.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.test-registration` | passes |
| `nix fmt -- --ci`, statix, deadnix | clean |

No workflow edit, by design.

## Rollback

`git revert`. One check and one test file disappear; nothing else reads them.
