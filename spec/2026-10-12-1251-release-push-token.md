---
status: draft
issue: 1251
intent: intent/2026-10-12-1251-release-push-token.md
---

# Spec: a release moves the release branch even when it carries a workflow change

## Design

In `.github/workflows/release.yml`, the "Move the release branch to this
tag" step gets `PUSH_TOKEN: ${{ secrets.BUMP_TOKEN }}` and one shell
function, `push_release`, used by both of the step's pushes:

- **With `PUSH_TOKEN` set,** it runs `git -c http.https://github.com/.extraheader=
  push "https://x-access-token:$PUSH_TOKEN@github.com/$GITHUB_REPOSITORY.git"
  "$commit:refs/heads/release"`. The empty `extraheader` matters:
  `actions/checkout` stores `GITHUB_TOKEN` as an `Authorization` extra
  header, which wins over the credentials in a URL. git documents that an
  empty value resets the header list.
- **Unset** (a fork, or a missing secret), it falls back to
  `git push origin …`, exactly as today.
- **On failure,** it prints `::error::`. The error says the release
  published, that a refusal naming workflows means `BUMP_TOKEN` needs
  Contents and Workflows write on this repository (#1251), and how to move
  the branch by hand. It writes the same to the step summary.

The fast-forward logic and the not-a-descendant branch are unchanged.

## Alternatives rejected

- **A new GitHub App:** it needs an App created and installed, and two
  secrets, when a working real-identity token already exists. If the owner
  prefers an App later, only the env line changes.
- **Pass `token:` to `actions/checkout`:** every step in a long job would
  then hold the stronger token, when one push needs it.
- **Stop maintaining `release` and point users at tags:** that changes the
  update contract for every installed machine.

## Risks

- **`BUMP_TOKEN` may lack Workflows write.** The push is then refused, as
  today, and the error names the fix. That is no worse than now.
- **A token in the push URL** is masked in the logs as a secret, and it
  never lands in `.git/config` because it is passed on the command line.

## Verification

- **`actionlint`** on `release.yml`, since `lint` runs it in CI.
- **The extraheader reset, proven locally.** In a scratch clone, set a bogus
  `http.https://github.com/.extraheader` that makes a plain `git push` fail.
  The function's push, with a valid token in the URL, must succeed to a
  throwaway branch, which is deleted afterwards. A run without the reset
  must fail, which proves the reset is load-bearing (§1).
- **The real proof is the next release:** the step reports "release branch
  moved", and #1236's row goes green. Stated as pending in the PR.
