---
status: draft
issue: 747
spec: spec/2026-09-23-747-split-options-check.md
---

# Plan: checks.options stops evaluating every machine at once

This plan is self-contained: it carries every approved spec decision.

## Decisions

- **Scope the fixtures. Do not split the check.** `checks.options` keeps its
  name, its coverage and its single derivation. No new `checks.*` entry, so
  **nothing here needs a workflow edit** — which was the earlier design's
  worst property, since a `checks.options-home` nobody wired would run nowhere.
- **Measured, not reasoned.** 21 NixOS configurations producing the same 21
  booleans: **rooted in a top-level `let`, 4.73 GB and 36.9 s; scoped where
  consumed, 1.62 GB and 32.7 s.** Both exited 0 and both returned `true`.
  66% less memory and 11% *faster* — the speed is what rules out the objection
  that scoping re-evaluates what sharing computed once.
- **Group, never per case.** Scoping a shared fixture to a single case would
  re-evaluate it for each consumer and undo #745. The scope is a feature group.
- **All 21 NixOS fixtures must exist.** Each varies one option that cannot be
  varied on a shared machine — `rdpOff`/`rdpOn`/`rdpFirewall`/`rdpNoSecret` is
  four states of one feature. There is no win in having fewer.
- **Target: under 8 GB**, not "under 16". A ceiling the check merely fits
  inside is how this arrived here from 11.5 GB.
- **The split stays documented and unused** as the next lever, with its counts
  already gathered (32 NixOS-only cases, 38 Home-Manager-only, 8 both).

## The shape the file already has

`tests/options.nix` is 5,502 lines: `let` at 13, `cases = { … }` spanning
**464–1638**, the fixtures defined *after* it at **1640–2553**, `in` at 2554,
and the builder below. Nix's `let` is order-independent, which is why fixtures
defined below `cases` are in scope above it — and why they are all rooted for
the whole evaluation.

So the mechanism is: each group becomes a `let … in { … }` whose bindings are
its fixtures and whose attrset is its cases, merged into `cases`. Once a
group's attrset is forced, its machines are unreachable and collectable.

```nix
cases =
  { …ungrouped cases… }
  // (let rdpOff = …; rdpOn = …; rdpFirewall = …; rdpNoSecret = …;
      in { rdpOffIsOff = …; rdpOnOpensNothing = …; … })
  // (let sopsOn = …; in { … })
```

## Steps

**1. Count the cases, before anything moves.** `nix eval` the length of
`cases`'s attribute names and record it. This number must be identical at the
end; a move that loses a case is otherwise invisible, because both the before
and after runs are green.

→ verify: the number is written into the PR, twice.

**2. Re-measure `main` on this host, in this session.** The 13.06 GB baseline
was taken earlier today; before/after from different days on a machine that is
also a desktop is not a comparison.

→ verify: `env -u NIXPKGS_ALLOW_UNFREE /usr/bin/time -v nix eval --option
eval-cache false --raw .#checks.x86_64-linux.options.drvPath`, peak RSS
recorded.

**3. Map each fixture to its consumers.** Mechanical, and the output is the
group list: for each of the 32 bound fixtures, which case names reference it.
A fixture with consumers in two would-be groups either joins the larger group
or stays at the top level — and **every fixture that stays rooted is named in
the PR with its reason**, rather than quietly left behind.

→ verify: the map is committed as a comment block in the file, so the next
person regrouping does not redo it.

**4–9. Move one group at a time**, in ascending order of size: `sops`, `rdp`,
`nvidia`, `docker`, `ai`, `devenv`. Each step is one commit: wrap the group's
fixtures in a `let`, merge its cases with `//`, run the check.

→ verify each: `checks.options` green, and the case count from step 1 unchanged.
A group that changes the count has lost or duplicated a case.

**10. Measure again.** Same command, same host, same session as step 2.

→ verify: **under 8 GB.** If it is not, the work has not succeeded, and the PR
says so rather than shipping a large mechanical refactor for its own sake.
The split remains available as the next lever.

**11. Wall clock must not regress.** The experiment's scoped variant was
*faster*; a slower result here means a shared fixture was scoped too narrowly
and is being re-evaluated.

→ verify: wall clock from the same runs as step 10.

## Tests

| Command | Expected |
|---|---|
| `nix eval … --apply 'c: builtins.length (builtins.attrNames c)'` on `cases` | identical before and after |
| `nix build .#checks.x86_64-linux.options` | green after every group, not just at the end |
| `/usr/bin/time -v` peak RSS | 13.06 GB before → **under 8 GB** after |
| wall clock | not worse than before |
| `nix fmt -- --ci`, statix, deadnix | clean |

**There is no break to prove here, and that is worth stating.** This is a
refactor: the check's job is unchanged, so §1's contract does not apply to it.
What replaces it is the case count — the only thing that can silently go wrong
is a case disappearing, and step 1 is what catches that.

## Rollback

Each group is its own commit, so a group that misbehaves is reverted alone.
Nothing outside `tests/options.nix` changes: no option, no module, no workflow,
nothing in a closure. If the whole thing is reverted, the check returns to
13 GB and nobody's machine notices.
