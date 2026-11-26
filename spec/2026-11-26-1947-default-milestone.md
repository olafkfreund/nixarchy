---
status: approved
issue: 1947
intent: intent/2026-11-26-1947-default-milestone.md
---

# Spec: An issue filed without a milestone is given one

Approved by the owner's standing pre-approval (2026-11-26).

## Design

A new workflow, `.github/workflows/milestone.yml`, on `issues: opened, reopened, labeled`: no milestone and not `epic` gets *Keeping the lights on*; an `epic` label arriving on an issue still holding that default has it removed, because the epic filing order adds the label after the issue exists and epics carry no milestone (§12). Bot-filed issues already pass `--milestone` (review.sh, nightly.yml, weekly.yml, edge-report.sh) and could not trigger it anyway. The backstop check is the review's existing board row, which flagged #1937.

## Alternatives rejected

A paragraph alone: §1 asks for something mechanical where it can be.

## Risks

None beyond the design.

## Verification

Every run of the review's board row; actionlint.
