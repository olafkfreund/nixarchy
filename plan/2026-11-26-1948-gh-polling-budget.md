---
status: approved
issue: 1948
spec: spec/2026-11-26-1948-gh-polling-budget.md
---

# Plan: Agents and scripts stay inside the GitHub API rate limit

Approved by the owner's standing pre-approval (2026-11-26). Decisions: the spec's design.

## Steps

1. The files the spec names, as it describes. → fleet-guard's `claude plugin test`; the generated checks.

## Tests

Every generated check; statix, deadnix, \`nix fmt -- --ci\`.

## Rollback

Revert the commit.
