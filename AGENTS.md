# Working in this repository as an AI agent

You are capable and you have no memory of this project. Both of those are why
this file exists: every rule below is here because an agent — sometimes seven
of them in one day — got it wrong in a specific, repeatable way. The rules are
in priority order. The reason is attached to each one, because a rule without
a reason gets rationalised away the moment it is inconvenient.

`CONTRIBUTING.md` covers the human-facing process (forking, PR conventions,
review). This file covers what goes wrong at the keyboard.

## 1. Prove your check fails

This is the most important rule in the file.

A check was written for #133, added to the test suite, and passed. Later the
bug it existed to catch was fully reintroduced — and the check **passed
again**. It was measuring something that could not vary with the bug. Every
minute spent on it had bought negative value: it read like coverage and
covered nothing.

The contract, for any check, assertion, or verification loop you write:

1. Break the thing the check is about — revert the fix, reintroduce the bug.
2. Run the check. Watch it fail. Capture that output.
3. Restore the fix. Watch it pass.
4. Put the failing output in the PR.

If you cannot make the check fail, you have not written a check; you have
written a green light. `installer/vm.nix` describes a harness that reported
success on failure as "worse than no harness", and that judgement generalises.

Two mechanical traps that produced fake green results here, live:

- **Pipelines report the last command's status.** `nix build ... | tail -20`
  exits with *tail's* status. A "0" after that pipe means tail worked. Use
  `set -o pipefail`, or don't pipe the command whose status you need.
- **Verify under bash, because CI runs bash.** A verification loop here
  reported PASS for both the working and the broken case because it ran in
  zsh, and zsh does not word-split unquoted expansions — `for c in $names`
  iterated once, over the whole string. Interactive shells on the machines
  this repo is developed on are zsh. Put `#!/usr/bin/env bash` on the script
  and run it as a script, not by pasting into your shell.

## 2. A check that nothing runs is worse than no check

`checks.installer-ui` was written, wired into `checks` in `flake.nix`, and
named by **no workflow**. The PR adding it went green without the check ever
executing. There is now a CI step (`build.yml`, "Every check is run by some
workflow, on pull requests", from #164/#166) that fails if any entry in
`checks` is not built by a workflow that triggers on pull requests.

So: adding a `checks.<name>` entry means also naming
`nix build .#checks.x86_64-linux.<name>` in a workflow that runs on
`pull_request` — and that workflow edit is a CI-gate change, which needs a
human (see §9). Raise it in the PR rather than wiring it yourself.

## 3. Git and flake mechanics that bite

- **A flake in a worktree sees only tracked or staged files.** A new file you
  have not `git add`ed fails evaluation with `path '…' does not exist` — not
  "untracked", *does not exist*. This cost three separate debugging sessions
  in one day. If a path you can `ls` "does not exist" to Nix, run `git add`
  before doubting anything else.
- **`installer/mkFlake.nix` requires a committed tree.** `git add` is not
  enough — it reads `self.rev`, which a dirty tree does not have, and throws:
  `flake-template: build from a committed tree; the generated flake pins
  nixarchy by commit`. Commit (the subject can be temporary; see §6) before
  building anything that pulls it in, which includes the installer checks.
- **Work in a worktree under `/mnt/data/vmtest/`, never `/tmp`.** `/tmp` is a
  32 GB tmpfs. A VM disk image or an ISO build there is competing with the
  machine's RAM, and loses quietly.

## 4. How to run the checks, and what each one costs

Checks are built one at a time by name — `nix flake check` is not how this
repo works:

```sh
nix develop                                     # nixd, statix, deadnix, qemu, gh
nix fmt                                         # CI runs `nix fmt -- --ci`
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
nix build .#checks.x86_64-linux.<name> --print-build-logs
```

Know the price before you pay it, and pick the cheapest check that can answer
your question:

| check | what it proves | cost |
|---|---|---|
| `options` | every option asserted in both states | cheap — evaluation only |
| `omarchy` (package) | the vendored tree assembles | minutes |
| `installer-ui`, `installer-wizard` | the installer's screens and questions | minutes |
| `session`, `coexist`, `integration`, `plugin` | booted VMs | ~10–20 min each |
| `install` | full install onto a blank disk, reboot, rebuild-builds-nothing | **~25 min, one self-hosted runner** |

`checks.install` gates every pull request and there is exactly one machine
that can run it. Seven concurrent PRs queue for about three hours. Every push
to your branch cancels and restarts your own run (that is deliberate — a PR
only needs an answer about its current head), but the queue is shared:
batching your pushes is a courtesy to everyone else's merge latency.

## 5. Code rules the repo has already written down

Do not restate these in new comments; read them where they live, because the
files carry the full reasoning and the failure history.

- **Module priorities:** the header of `modules/services/default.nix`.
  `lib.mkDefault` on scalars; **plain assignment** on lists and attrsets
  (mkDefault on a merging type silently drops the whole contribution the
  moment the user adds an element — reproduced live, not hypothetical);
  `mkForce` never.
- **Mode A is real.** Someone importing `nixosModules.nixarchy` into a
  configuration they already run must be untouched by anything opt-in.
  `tests/options.nix` asserts every option in both states for this reason —
  the off state is the one a refactor breaks quietly. (#180, open at the time
  of writing, adds `programs.nixarchy.installerManaged` to mark the other
  mode; check whether it has merged before referring to it.)
- **Comments explain WHY, and record what was tried and what went wrong.**
  `installer/cd.nix`, `modules/flatpaks.nix` and `installer/vm.nix` are the
  register. A comment that narrates what the next line does is noise; a
  comment that says which approach failed and why saves the next agent from
  re-failing it.
- **`writeShellApplication` builds a strict PATH from `runtimeInputs`.** A
  command your script calls and does not declare is a runtime failure that no
  build catches.

## 6. Commits and pull requests

- The final commit subject is a full sentence describing the change — read
  `git log --oneline -10` for the register. No `conventional-commits`
  prefixes.
- **Do not leave `wip:` on the last commit of a single-commit branch.** The
  repository squashes using the commit subject when the branch has one
  commit, and two `wip:` subjects are on `main` today because of it. Before
  marking a PR ready: `git commit --amend` (or squash locally) so the subject
  is the real one.
- Fill in the PR template, including the section that asks for your check's
  failing output. That section is §1 in form-field shape.

## 7. Territory, and the failure no single PR can see

When several agents work this repo at once, each PR should name the files it
touches, and stay inside them. But the sharper lesson is this: two PRs, each
green against a `main` that lacked the other, **broke `main`** (#137 + #141)
— one moved a file, the other read it from the old place. No per-PR check can
catch that; green CI on your branch is a statement about a `main` that may no
longer exist.

So: after anything merges to `main`, rebase before merging your own work, and
let the checks run again on the rebased head. "It was green an hour ago" is
not the same claim as "it is green against what `main` is now".

## 8. When a check fails for reasons unrelated to your change

First establish that it *is* unrelated: is `main` red too? One standing trap —
opening an issue with the `epic` label without adding a row to README's
Roadmap table fails CI **on every subsequent PR**, related or not (four times
in one day: #105, #148, #159, #174; the guard is the "roadmap still matches
the open epics" step in `build.yml`, and it fails the other way when an epic
closes and the row remains).

If the failure is unrelated: do not "fix" it inside your PR — that is scope
the reviewer did not ask for and a second thing to review. Say in the PR what
failed and why you believe it is unrelated, link the run, and if the cause is
a repo-wide state (like a roadmap row), flag it to a human rather than
editing README from a PR about something else.

Do not retry-until-green. A flaky pass is a bug report you deleted.

## 9. What not to do without asking a human

- **Destructive git**: `push --force` to any shared branch, deleting branches
  you did not create, rewriting published history, `git reset --hard` on work
  that is not yours.
- **Changing CI gates**: workflow triggers, required checks, the check
  coverage guard, timeouts on the install job. These are the repo's immune
  system; a PR may *propose* a change with reasoning, a human merges it.
- **Repository settings**: anything under `gh api` that mutates the repo —
  labels, protection, merge settings.
- **Posting to other people's repositories.** Upstream is
  `basecamp/omarchy`, and the routing rules in
  `pkgs/omarchy/skills/nixarchy/contributing.md` apply to you exactly as to a
  human: never file anywhere unprompted, and a fix to how Omarchy itself
  behaves belongs upstream, not patched here — a patch carried here is
  re-applied at every source bump; a fix landed upstream arrives for free.
- **The `epic` label** — applying or removing it has CI consequences (§8)
  that outlive your session.

When in doubt, the cost asymmetry decides: a question costs a minute; an
unwanted force-push or a misrouted issue costs a human an evening.
