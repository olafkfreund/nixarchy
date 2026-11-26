---
status: approved
issue: 1944
author: x
---

# Intent: A red bump pull request is fixed by Claude instead of Copilot

Approved by the owner's standing pre-approval and "close as many as possible issues" (2026-11-26).

## Problem

copilot-handoff.yml hands a red bump PR to Copilot through a broad PAT (COPILOT_AGENT_TOKEN), and the owner wants Claude (subscription token CLAUDE_CODE_OAUTH_TOKEN, verified 2026-11-26) as the fixer and Codex as the reviewer.

## Proposed outcome

The pipeline does it; a human reviews and merges the workflow change once (§11).

## Affected users and systems

This repository's CI.

## Constraints

CLAUDE.md §4, §6, §11; no secret in a job that runs PR code.

## Open questions

None.
