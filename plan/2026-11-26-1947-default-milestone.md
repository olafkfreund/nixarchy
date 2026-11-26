---
status: approved
issue: 1947
spec: spec/2026-11-26-1947-default-milestone.md
---

# Plan: An issue filed without a milestone is given one

Approved by the owner's standing pre-approval (2026-11-26). Decisions: the spec's design.

## Steps

1. The files the spec names, as it describes. → Every run of the review's board row; actionlint.

## Tests

Every generated check; statix, deadnix, \`nix fmt -- --ci\`.

## Rollback

Revert the commit.
