---
status: approved
issue: 1948
intent: intent/2026-11-26-1948-gh-polling-budget.md
---

# Spec: Agents and scripts stay inside the GitHub API rate limit

Approved by the owner's standing pre-approval (2026-11-26).

## Design

fleet-guard (nixos_config #3227, merged) refuses `gh run watch` and `gh pr checks --watch` in command position without `--interval` of 30 or more; its deny test fails with the rule off. Here: `docs/internals/workflows.md` stops recommending a bare `gh run watch`, and AGENTS.md §6 records the budget and the rule. A low-budget row in the review is left for later: the hook removes the measured cause.

## Alternatives rejected

A paragraph alone: §1 asks for something mechanical where it can be.

## Risks

None beyond the design.

## Verification

fleet-guard's `claude plugin test`; the generated checks.
