---
status: approved
issue: 1448
intent: intent/2026-10-25-1448-release-lookup-redirect.md
---

# Spec: read the newest release from the redirect, not the REST API

## Design

In both `updateScript`s, replace the `api.github.com/.../releases/latest | jq`
lookup with the web redirect GitHub serves for every repository:

    curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/basecamp/<repo>/releases/latest \
      | sed -n 's|.*/releases/tag/v\{0,1\}||p'

`github.com/<repo>/releases/latest` 302s to `/releases/tag/<tag>`. It is not
the REST API, so the 60-an-hour unauthenticated limit does not apply. It is
the same host nix-update already reads `releases.atom` from in the same run.
`sed -n …p` prints nothing unless the URL is a tag page, so a repository with
no release falls into the existing `-z "$latest"` error. The `"null"` test
only existed for jq's output, so it goes.

Files: `pkgs/apps/hey-cli.nix:81-82`, `pkgs/apps/once.nix:94-95`, and the
`[ -z … ] || [ … = "null" ]` line after each.

## Alternatives rejected

- **Pass `GITHUB_TOKEN` from `update.yml`.** That is a workflow edit (§11),
  and it would still leave the scripts failing for anyone running
  `nix run .#update` without a token.
- **Retry on 403.** A rate limit lasts up to an hour, longer than any retry
  worth writing.

## Risks

- If GitHub changed the redirect, the lookup would come back empty. The
  scripts would then fail with "could not read a release tag", loudly, the
  same way they do now.
- `jq` has no other use in either file, so it leaves both the argument list
  and `runtimeInputs` (hey-cli.nix:7,70; once.nix:10,83). Nothing else reads
  it there.

## Verification

- Run both scripts from the repo root: each prints `already at <version>`,
  exit 0.
- §1 break: point one URL at a repository with no releases. The script must
  fail with "could not read a release tag".
- The package `drvPath`s are unchanged: only `passthru.updateScript` changes.
