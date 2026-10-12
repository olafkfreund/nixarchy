---
status: draft
issue: 1251
spec: spec/2026-10-12-1251-release-push-token.md
---

# Plan: a release moves the release branch even when it carries a workflow change

**Decision.** The release-branch push in `release.yml` uses
`secrets.BUMP_TOKEN` through the URL, with checkout's `GITHUB_TOKEN`
`extraheader` reset for that one command. It falls back to `origin` when the
secret is empty. A refusal prints a precise `::error::` naming the needed
permission. Nothing else in the job changes.

## Steps

1. **`.github/workflows/release.yml`, the "Move the release branch to this
   tag" step (~540-570).**
   - Add `PUSH_TOKEN: ${{ secrets.BUMP_TOKEN }}` to its `env`.
   - Define `push_release` at the top of `run:` and replace both
     `git push origin "$commit:refs/heads/release"` calls with it.
   - Add a two-line comment above the function: `GITHUB_TOKEN` can never
     push commits that touch workflows (#1251), and checkout's extraheader
     would override the URL's token.

   → Verify: `nix run nixpkgs#actionlint -- .github/workflows/release.yml`.
   Traps:
   - Keep `set -e` semantics. The function's failure path must `exit 1`
     after writing the summary.
   - Never echo the token.
2. **Local §1 proof of the header reset.**
   - **Setup:** a `git clone` under `/mnt/data/vmtest/`, with a bogus
     `extraheader` set: `AUTHORIZATION: basic <garbage>`.
   - **Break:** push without the reset → must fail.
   - **Fix:** push with the reset → must succeed, to `test/1251-push-probe`.
   - **Cleanup:** delete the probe branch, then confirm with
     `git ls-remote`.
3. **Docs.** Check whether `docs/internals/workflows.md` describes this
   step. If it does, add a sentence on the token.
4. **Commit and PR.**
   - A full-sentence subject with `Closes #1251`.
   - The PR states it needs a human merge (§11), and that `BUMP_TOKEN` needs
     Contents and Workflows write.

## Tests

| command | expected |
|---|---|
| actionlint on release.yml | clean |
| the probe without the reset | push fails on the bogus header |
| the probe with the reset | push succeeds; the probe branch is then deleted |

## Rollback

Revert the commit. The step goes back to `GITHUB_TOKEN`.
