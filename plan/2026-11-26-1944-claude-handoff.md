---
status: approved
issue: 1944
spec: spec/2026-11-26-1944-claude-handoff.md
coders:
  1: codex # the design is its own
reviewers:
  - codex
---

# Plan: A red bump pull request is fixed by Claude instead of Copilot

Approved by the owner's standing pre-approval (2026-11-26). Decisions: the spec's design, numbered points 1 to 6, Lead's change to the design: the publisher authenticates with the existing BUMP_TOKEN (it already opens bump PRs and starts their CI), not a new GitHub App installation, so the owner has nothing new to set up.

## Steps

1. Implement points 1-6 of the spec in the files it names, fixture first: the check must fail under the named mutations before the change is complete, and pass intact. → `nix build .#checks.x86_64-linux.<the check>`, actionlint on the workflow.

## Tests

Every generated check; actionlint; statix; deadnix; `nix fmt -- --ci`.

## Rollback

Revert the commit.
