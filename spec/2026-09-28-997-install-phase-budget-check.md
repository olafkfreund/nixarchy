---
status: approved
issue: 997
intent: intent/2026-09-28-997-install-phase-budget-check.md
---

# Spec: the install phase says it is getting full before it is

## The open questions, settled

1. **One fixed line: fail when `installPhase` exceeds 123,000 bytes.** There
   is no warning band: a warning in a green job is §4's "decoration". Why this
   number:
   - the hard ceiling for the value is **131,058** (below);
   - 123,000 leaves **8,058 bytes** between red and a failed build, room for
     two of the largest paragraphs the first pass moved (2-4 KB each), so a
     red check is a request to tidy up, never an emergency;
   - today the phase is **113,966**, so there are **9,034 bytes** before red:
     the check is green now, and it takes a real change to trip it.
2. **Only `omarchy`'s `installPhase`.** It's the only phase in the repo that
   has ever come near the limit, and the check's message says that is all it
   measures. A sweep over every package would make a claim the first pass
   never measured.

## What the kernel counts, verified

- `pkgs/omarchy/default.nix` has `__structuredAttrs = false` (evaluated), so
  the phase reaches the builder as an **environment string**, not a file.
  That is why the limit applies at all. A future switch to structured attrs
  would retire this whole problem, and the check says so.
- `execve` refuses any single argument or environment string whose length
  with its NUL exceeds `MAX_ARG_STRLEN` = 32 pages = **131,072** bytes. The
  string is `installPhase=<value>`, so the ceiling for the value is
  131,072 − 13 (`installPhase=`) − 1 (NUL) = **131,058**.
- `ARG_MAX` (2 MB on p620) caps the whole environment, and is not the one
  that bites.

## Design

`tests/install-phase-budget.nix` → `checks.install-phase-budget`, a
`runCommand` that gets the phase's length **as a value** (tests/AGENTS.md: a
store path in a derivation's environment is a build input):

```nix
{ omarchy, pkgs }:
pkgs.runCommand "nixarchy-install-phase-budget" {
  bytes = toString (builtins.stringLength omarchy.installPhase);
  budget = "123000";
  structured = if omarchy.__structuredAttrs or false then "yes" else "no";
} '' … ''
```

The script:

- fails if `structured` is `yes`, with a message saying the budget no longer
  means anything and the check should be retired, so it can't go on passing
  against a limit that stopped applying;
- fails if `bytes` > `budget`, printing the size, the budget, the hard ceiling
  and the headroom, and naming the fix: *move prose to `pkgs/AGENTS.md`
  behind a `# Why:` pointer (AGENTS.md §7)*;
- on success, prints the same numbers, so the job log shows how close it is.

It is registered in `flake.nix` like its neighbours, with `omarchy =
self.packages.${system}.omarchy`. It needs no workflow edit: the `omarchy`
job builds every unclaimed check (§4). It costs one evaluation of the
package, which that job already does, and a shell comparison.

## Alternatives rejected

- **A warning band before the red line:** read by nobody (§4).
- **Measuring the `.nix` source's size:** it isn't what `execve` counts. The
  source carries indentation Nix strips and lacks what interpolation adds.
- **Budgeting every phase of every package:** a claim nothing measured
  (question 2).
- **Switching `omarchy` to `__structuredAttrs`:** that removes the limit
  outright, but it changes how every phase and variable reaches the builder
  in a 2,000-line derivation. It's a real option and a separate, riskier
  change. It is named in the check's message rather than done here.
- **Lowering headroom with more prose moves instead:** the first pass already
  did that. This is the thing that says when to do it again.

## Risks

- **The number is a judgement.** 123,000 could trip on a legitimate large
  patch. The message says the fix is ordinary (move prose), and the budget is
  one line to change with a reason in the PR.
- **`builtins.stringLength` counts bytes, and so does the kernel**, so UTF-8
  box characters in the phase are counted correctly (`pkgs/AGENTS.md` notes
  that `awk length()` in a C locale disagrees; that doesn't apply here).

## Verification

| what | how | break it by |
|---|---|---|
| green today | `nix build .#checks.x86_64-linux.install-phase-budget` | — |
| it fails for the right reason | add about 10 KB of comment to `installPhase` | must go red, naming the size and the fix |
| the structured-attrs guard | set `__structuredAttrs = true` on the package in a scratch commit | must go red, saying the check is obsolete |
| the ceiling arithmetic | print `bytes`, `budget` and `131058` in the log | read, not asserted |
| it runs on PRs | the `omarchy` job's generated list names it | read in the PR's run log |
