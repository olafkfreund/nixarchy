---
status: draft
issue: 1251
author: olafkfreund
---

# Intent: a release moves the release branch even when it carries a workflow change

## Problem

`release.yml`'s last step, "Move the release branch to this tag", pushes
`release` with the built-in `GITHUB_TOKEN`. GitHub refuses that push
whenever the new commits change `.github/workflows/`:

```
refusing to allow a GitHub App to create or update workflow `.github/workflows/nightly.yml` without `workflows` permission
```

A `GITHUB_TOKEN` cannot be granted that permission. v4.0.4-3's run
(38218214462) published its assets and then went red on this step, and
`release` was moved by hand. Ten commits between v4.0.4-2 and v4.0.4-3
touched workflows, so most releases will hit this. A red release run also
keeps #1236's `release.yml` row red.

## Proposed outcome

The step pushes with a credential that may update workflows. If the push is
still refused, the error says exactly what the token lacks. A release run
then ends green with `release` at the tag.

## Affected users and systems

- `release.yml`, run on every tag push and on `workflow_dispatch`.
- Users update against `release`, so a branch left behind delays every
  machine's update.

## Constraints

- **CI and secrets need a human (§11).** The PR proposes the change, and
  the owner merges it.
- **Reuse an existing secret.** `BUMP_TOKEN` is the repository's real-
  identity token, already used by `update.yml`, `omarchy.yml` and
  `flake-update.yml`. Whether it holds Workflows write cannot be read from
  here.
- **Keep everything else.** No force push; the not-a-fast-forward branch
  stays as it is; the rest of the job keeps `GITHUB_TOKEN`.

## Open questions

Does `BUMP_TOKEN` have Workflows write? If it does not, the owner adds the
permission. The step's error will say so. Approved in advance by the owner
("approve all and fix all").
