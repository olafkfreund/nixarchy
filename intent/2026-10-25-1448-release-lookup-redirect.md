---
status: approved
issue: 1448
author: x
---

# Intent: the nightly app bump does not depend on GitHub's unauthenticated API

## Problem

`update.yml` runs `nix run .#update` every morning. Two of the update
scripts it chains, `hey-cli` (`pkgs/apps/hey-cli.nix:81`) and `once`
(`pkgs/apps/once.nix:94`), ask `api.github.com/.../releases/latest` for the
newest tag, with no token. A hosted runner shares its IP with other tenants,
and that endpoint allows 60 unauthenticated requests an hour per IP. On
2026-10-25 both calls got a 403 (run 40164387271), `nixarchy-update` exited 1,
and the job went red. Nothing in nixarchy had changed. Every nix-update script
in the same run read `github.com/<repo>/releases.atom` and none of them failed.

## Proposed outcome

Both scripts find the newest release without a REST API call, so the nightly
bump no longer fails because of whoever else shares the runner's IP. A
genuinely unreadable tag still fails loudly, with the scripts' own "could not
read a release tag" message.

## Affected users and systems

`pkgs/apps/hey-cli.nix` and `pkgs/apps/once.nix` (their `updateScript`s only;
the packages are unchanged), and the `update` workflow, which runs them. Users
are not affected.

## Constraints

- No workflow edit: passing a token would mean changing `update.yml` (§11).
- No new dependency; `curl` is already in both scripts' `runtimeInputs`.
- No change to what ships, so the package derivations must be unchanged.

## Open questions

None.
