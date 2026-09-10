<!-- The subject-line rule: a single-commit branch is squashed using the
     COMMIT subject, not the PR title. If your branch has one commit, its
     subject is what lands on main — amend away any `wip:` before marking
     this ready. -->

## What this changes, and why

<!-- One paragraph. If it fixes a bug: what broke, and would it also break on
     Arch? If yes, it belongs at basecamp/omarchy, not here — see
     CONTRIBUTING.md. -->

## How I proved the check fails

<!-- The verification contract (AGENTS.md §1): break the thing, run the
     check, paste the RED output here, then show it green with the fix.
     A check that has never been seen failing has never been seen working.

     If this PR genuinely needs no check (docs, comments), say so instead. -->

```
(failing output here)
```

## Checks run locally

<!-- Which `nix build .#checks.x86_64-linux.<name>` you ran, by name.
     `checks.install` costs ~25 min and only ONE install job runs at a time —
     p620 has four runners, but install-check.yml caps this job because the
     in-VM timeout is a guest-side one and contention turns "slower" into
     "failed". You don't need to have run it locally; say what you did run. -->

- [ ] `nix fmt` / statix / deadnix are clean
- [ ] New files are `git add`ed (a flake cannot see untracked files)
- [ ] If this adds an option: `tests/options.nix` covers both states
- [ ] If this adds a `checks.*` entry: a PR-triggered workflow builds it
      (CI enforces this; the workflow edit needs maintainer sign-off)

## What this cost, and where it is written down

<!-- If something here cost you an hour and the cause was GENERAL — a nix
     mechanic, a way a check can silently stop checking, a trap in the test
     harness — add it to AGENTS.md in THIS pull request. See "Write back what
     cost you an hour" at the top of that file.

     Same PR, because the follow-up commit for documentation is the one that
     never gets written. Specific facts ("this attribute was misspelled")
     belong in the commit message instead.

     Nothing surprising happened? Say "nothing general" and move on. -->

- [ ] A general lesson is recorded in `AGENTS.md`, or nothing general came up
