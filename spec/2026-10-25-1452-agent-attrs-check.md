---
status: approved
issue: 1452
intent: intent/2026-10-25-1452-agent-attrs-check.md
---

# Spec: checks.agent-attrs

## Design

`tests/agent-attrs.nix` reads `omarchy-default-agent` at evaluation time:
- It takes the text between `attr_for() {` and the next line that is `}`.
- It matches each line against `^ +([a-z0-9-]+)\) +echo ([a-z0-9-]+) ;;$`.

For each `(id, attr)`, the problem is one of:
- `"no pkgs.<attr>"`, when `pkgs ? <attr>` is false;
- `"mainProgram is <x>, not <id>"`, when `builtins.tryEval
  (pkgs.<attr>.meta.mainProgram or null)` disagrees. A thrown alias counts
  as a failure.

The problems become a `runCommand` that prints them and exits 1. So a wrong
mapping is a failed build that names the arm, never an evaluation error.
Fewer than 5 parsed arms is itself a failure, because the parse must have
moved.

It is registered as `checks.agent-attrs` in `flake.nix` beside
`stale-scripts`, and the generated step builds it on pull requests (§4).
`pkgs` is `pkgsFor.${system}`, the nixpkgs `nixarchy-pkg-add` builds from.

## Alternatives rejected

- **A Python parse at build time.** It would need the attribute values at
  evaluation anyway.
- **Asserting in `flake.nix`.** That throws at evaluation and kills the
  batch.

## Risks

An unfree attribute's `meta` evaluates without allowing unfree, so
`claude-code` and the other unfree agents are fine.

## Verification

§1: map `codex` to `amp` (the editor). The check fails, naming `codex`.
Restore it, and the check passes.
