---
status: approved
issue: 1948
author: x
---

# Intent: Agents and scripts stay inside the GitHub API rate limit

Approved by the owner's standing pre-approval and "close as many as possible issues" (2026-11-26).

## Problem

The account's 5,000 requests an hour ran out on 2026-11-24, 25 and 26. Measured on p620: 69 and 145 requests a minute; razer, the factory cluster and hosted CI ruled out; the rest short `gh` calls from agent sessions. `gh run watch` defaults to a 3 s poll.

## Proposed outcome

Nobody has to act on it by hand.

## Affected users and systems

This repository's maintainers and agents.

## Constraints

CLAUDE.md §11, §12.

## Open questions

None.
