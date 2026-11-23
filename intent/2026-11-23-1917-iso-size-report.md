---
status: draft
issue: 1917
author: x
---

# Intent: the nightly ISO size report fails after the ISO built

## Problem

Nightly 45104089805 built `iso-net`, then failed in "Report the ISO size": `nix path-info -Sh` on the reference toplevel errored `path ... is not valid` because the toplevel was not in the store, and `nix path-info` does not build. The `< <(...)` hid that failure, `read` got nothing, and `bash -e` killed the step, skipping the budget and network-install checks.

## Proposed outcome

The size report builds (substitutes) what it measures, and a failure in it names its own cause.

## Affected users and systems

`nightly.yml` `iso-net` job on the p620 runners.

## Constraints

Workflow edit: a human merges (CLAUDE.md §11).

## Open questions

None.
