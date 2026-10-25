---
status: approved
issue: 1448
spec: spec/2026-10-25-1448-release-lookup-redirect.md
---

# Plan: read the newest release from the redirect, not the REST API

Approved decisions:
- Use the `github.com/<repo>/releases/latest` redirect. No token, and no
  `update.yml` edit.
- An empty result falls into the existing "could not read a release tag"
  error.
- `jq` leaves both files.

## Steps

1. `pkgs/apps/hey-cli.nix:81-85`: replace the API+jq lookup with
   `curl -fsSLI -o /dev/null -w '%{url_effective}' …/releases/latest | sed -n 's|.*/releases/tag/v\{0,1\}||p'`.
   Make the guard `[ -z "$latest" ]` only. Drop `jq` from lines 7 and 70.
   Check: `nix run .#hey-cli.updateScript` from the repo root prints
   `already at 1.10.1`.
2. `pkgs/apps/once.nix:94-98`: the same change. Drop `jq` from lines 10 and 83.
   Check: prints `already at 0.3.4`.
3. §1 break: point step 1's URL at a repository with no releases. Check: exit
   1 with "could not read a release tag". Restore with `git checkout HEAD --`.

Traps:
- Run `nix fmt` and read `git diff --stat` afterwards (§5: the agent hook
  reformats).
- Inside `''…''`, `${` would need escaping; the sed has none.

## Tests

- `nix fmt -- --ci`, statix, deadnix
- `nix eval .#hey-cli.drvPath .#once.drvPath`: identical before and after

## Rollback

Revert the commit.
