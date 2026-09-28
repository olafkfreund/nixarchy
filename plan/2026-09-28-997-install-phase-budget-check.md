---
status: approved
issue: 997
spec: spec/2026-09-28-997-install-phase-budget-check.md
---

# Plan: the install phase says it is getting full before it is

## Approved decisions, carried from the spec

- **Fail when `omarchy`'s `installPhase` exceeds 123,000 bytes.** The value's
  hard ceiling is 131,058 (`MAX_ARG_STRLEN` 131,072 − `installPhase=` 13 − NUL
  1), so red leaves 8,058 bytes of room. Today it is 113,966, so 9,034 bytes
  before red. There is no warning band.
- **Only this phase.** The message says so.
- **The check fails if `omarchy` switches to `__structuredAttrs`**, saying the
  budget is obsolete, because then the phase isn't an environment string and
  the limit doesn't apply.
- **A `runCommand` given values, not store paths:** `bytes` (the phase's
  `builtins.stringLength`), `budget` and `structured`. Evaluation only.
- **Registered like its neighbours; no workflow edit** (the `omarchy` job
  builds every unclaimed check).
- The message names the fix: move prose to `pkgs/AGENTS.md` behind a
  `# Why:` pointer (AGENTS.md §7), and mentions structured attrs as the way
  to retire the limit.

## Steps

**0. Before any local build:** `gh run list … | length` must print 0 (§6),
**checked in its own command and read before the build starts.** That wasn't
done twice on #1037.

1. **`tests/install-phase-budget.nix`** as in the spec. `printf`, not
   heredocs, inside the Nix string (§5). No variable named `out`
   (tests/AGENTS.md).
   → verify: `nix eval` of its `bytes` attribute prints the phase size
   measured today (113,966 on `c9e1a86`).
2. **`flake.nix`:** register `install-phase-budget` with
   `omarchy = self.packages.${system}.omarchy`, next to `branch-guard`. Then
   `nix fmt`, and read `git diff --stat`.
   → verify: `nix build .#checks.x86_64-linux.install-phase-budget` is green,
   and the log prints the size, budget, ceiling and headroom.
3. **Red (§1), with a committed baseline first:**
   - pad `installPhase` in `pkgs/omarchy/default.nix` with about 10 KB of
     comment (a temporary commit, proven with `git diff`): the check must go
     red, naming the size and the fix;
   - set `__structuredAttrs = true` on the package (a temporary commit): the
     check must go red with the "obsolete" message.
   Each break is dropped with `git reset --hard` to the baseline after the
   tree is shown clean. Both outputs are captured for the PR.
4. **Docs:** in `pkgs/AGENTS.md`'s "Why the install phase says so little", one
   paragraph naming the check, the budget and where to change it.
   → verify: `grep -n install-phase-budget pkgs/AGENTS.md`.
5. **Lint and PR:** `nix fmt -- --ci`, statix, deadnix. Squash the
   implementation into one commit with a full-sentence subject, keeping the
   artifact commits. Link all three artifacts and include both red outputs.
   **`Closes #997`**: this is the piece its first plan deferred, and nothing
   else is left in scope (further prose moves were "follow-up if anyone
   wants it"). Before opening: `read_new` on the bus.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.install-phase-budget` | green; log shows 113,966 / 123,000 / 131,058 |
| the same with the phase padded by about 10 KB | red, with the size and the fix |
| the same with `__structuredAttrs = true` | red, "obsolete" |
| `nix fmt -- --ci`, statix, deadnix | exit 0 |

## Rollback

Revert the commit. The check and its registration go; no machine changes.
