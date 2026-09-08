# Working in this repository as an AI agent

You are capable and you have no memory of this project. Both of those are why
this file exists: every rule below is here because an agent — sometimes seven
of them in one day — got it wrong in a specific, repeatable way. The rules are
in priority order. The reason is attached to each one, because a rule without
a reason gets rationalised away the moment it is inconvenient.

`CONTRIBUTING.md` covers the human-facing process (forking, PR conventions,
review). This file covers what goes wrong at the keyboard.

**Read the `AGENTS.md` in the directory you are working in.** This file is the
repository-wide register; each of these adds the intent, the layout and the
failure history for its own area, and they are where the long reasoning lives:

| | |
|---|---|
| `installer/AGENTS.md` | the ISO, the wizard, the phase chain, and the flake it writes |
| `modules/AGENTS.md` | the option surface, Mode A, and what each module owns |
| `pkgs/AGENTS.md` | the vendored tree, the patch rules, and `runtimeInputs` |
| `tests/AGENTS.md` | what each check covers, and what only a cheap one can reach |
| `docs/internals/flake.md` | the flake's own reasoning — inputs, the overlay, the checks |

`CLAUDE.md` is a symlink to this file, because Claude Code reads `CLAUDE.md`
and not `AGENTS.md`. Without it none of this loads.

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

And the same rule read backwards, for the day a check goes red on you: **ask
whether it was testing the property or the arrangement.** #220 moved the menu
from an override fragment to the full merged defaults, and two checks failed
that had been correct for months — one asserted every row has an action, which
is only true of a fragment (a submenu parent legitimately has none), and one
asserted "no key of ours starts with `setup.plugin`", which was a fair proxy
for "we cannot shadow upstream's plugin menu" only while our file held our rows
alone. Nothing had regressed. Both checks had encoded the shape of a file
rather than the property they existed to protect, and both read as a regression
the moment the shape legitimately changed.

So when a deliberate design change turns a check red, the first question is not
how to satisfy the check. It is whether the check still describes the thing you
care about. If it does not, retarget it — and say so in the PR, because
"I changed a check that was failing" and "that check was measuring the wrong
thing" are very different sentences to a reviewer.

## 2. A bug found by hand is not fixed until something can see it

§1 governs checks you write. This is the same argument one step earlier, about
a bug nobody had written a check for.

#202: screen sharing failed in **every** application on the Omarchy session,
silently — no dialog, no error. `config/hypr/xdph.conf`, seeded into
`~/.config/hypr`, sets `custom_picker_binary = hyprland-preview-share-picker`;
upstream declares that binary in its **Arch** package list, which nothing on
NixOS reads. The portal execed a command that did not exist, got `SHAREDATA
returned selection -1`, and tore the session down. It was found by the
maintainer trying to share a screen. Under the rules as they stood it would
have been "fixed" by adding one package, and the next silent portal failure
would have been just as invisible.

So: a user-visible bug found by using the thing is not fixed until the
subsystem it broke has gained a probe, at the highest layer that can see it.
The layers, highest first:

- **static checks**, on every pull request — cheapest, and where "the config
  names something that does not exist" belongs;
- **`checks.session`**, which boots a real desktop — screen sharing is
  answerable here;
- **`pkgs/verify.sh`**, for what only real hardware can answer — Bluetooth
  pairing is answerable nowhere else.

And the rule the same incident produced: **anything we ship that names
something else needs a list, or a check, saying that something exists.**
`pkgs/omarchy/default.nix` carries an explicit runtime list for precisely this
— *"Everything the 438 scripts in bin/ invoke. Kept explicit rather than
pulled from a generated file: a missing entry should be a readable diff"* — and
`build.yml` asserts that a set of those resolve. The script side had a list and
an assertion; the config side had neither. #202 lived exactly in that gap, and
#204 is the same defect in mirror image: `satty` ships as a runtime dependency
and no config names it.

## 3. Vary the variable that matters

§1 is about a check that cannot fail. This is its wider form: **a check that
cannot vary proves nothing about the variable it holds constant** — and it will
pass, at every priority, with the bug fully present.

Five bugs in one day, every one found by a tester on real hardware, every one
invisible to a green suite. Not one of them was a missing check.

Every automated install used the username `omarchy` — the one name the image's
baked reference closure cannot diverge from, so every per-user derivation
matched a seeded one. Every disk was `/dev/vda`, never an NVMe with its `p1`
partition names. Every NIC was virtio: no VM in this repository had ever had a
radio, so NetworkManager's entire wireless path had no coverage of any kind.
And every guest reports a virt type, so `nixos-generate-config`'s
`if ($virt eq "none")` branch — where firmware and microcode live — had never
once executed anywhere in CI. Installed machines shipped with no firmware and
no microcode, and the suite was green throughout.

So when a bug arrives from real hardware, the first sentence of the fix is not
the fix. It is: **name the variable that separated that machine from every
machine the suite boots.**

Then vary *that* variable, at the cheapest layer that can reach it:

- an **evaluation** check that enumerates the branch no VM can take —
  `generate-config-surface` reads out everything the virt gate can emit,
  precisely because no VM will ever take it;
- a **stubbed `runCommand`** — `installer-network` fakes rfkill states no guest
  produces;
- a **VM handed the hardware** — `wifi-hwsim` gives one a radio via
  `mac80211_hwsim`.

If no layer can reach it, **say so**. A row in `tests/install-matrix.py` and a
sentence in `tests/AGENTS.md` naming the hole is worth more than a check that
closes it on paper. A documented hole gets tested by a human; an undocumented
one gets tested by a user.

## 4. A check that nothing runs is worse than no check

`checks.installer-ui` was written, wired into `checks` in `flake.nix`, and
named by **no workflow**. The PR adding it went green without the check ever
executing. There is now a CI step (`build.yml`, "Every check is run by some
workflow, on pull requests", from #164/#166) that fails if any entry in
`checks` is not built by a workflow that triggers on pull requests.

So: adding a `checks.<name>` entry means also naming
`nix build .#checks.x86_64-linux.<name>` in a workflow that runs on
`pull_request` — and that workflow edit is a CI-gate change, which needs a
human (see §10). Raise it in the PR rather than wiring it yourself.

## 5. Git and flake mechanics that bite

- **A flake in a worktree sees only tracked or staged files.** A new file you
  have not `git add`ed fails evaluation with `path '…' does not exist` — not
  "untracked", *does not exist*. This cost three separate debugging sessions
  in one day. If a path you can `ls` "does not exist" to Nix, run `git add`
  before doubting anything else.
- **`installer/mkFlake.nix` requires a committed tree.** `git add` is not
  enough — it reads `self.rev`, which a dirty tree does not have, and throws:
  `flake-template: build from a committed tree; the generated flake pins
  nixarchy by commit`. Commit (the subject can be temporary; see §8) before
  building anything that pulls it in, which includes the installer checks.
- **Work in a worktree under `/mnt/data/vmtest/`, never `/tmp`.** `/tmp` is a
  32 GB tmpfs. A VM disk image or an ISO build there is competing with the
  machine's RAM, and loses quietly.

## 6. How to run the checks, and what each one costs

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
| `package-delta`, `config-delta`, `patched-files`, `release-notes`, `review-pins` | scripts against fixtures | seconds |
| `vm-toplevel`, `reference-toplevel` | the closures build | eval plus a fetch |
| `omarchy` (package) | the vendored tree assembles | minutes |
| `installer-ui`, `installer-wizard` | the installer's screens and questions | minutes |
| `session`, `coexist`, `integration`, `plugin` | booted VMs | ~10–20 min each |
| `install` | full install onto a blank disk, reboot, rebuild-builds-nothing | ~29 min, one self-hosted runner |
| `free-space` | install beside an existing OS, which survives | ~27 min, same runner, same job |
| `install-iso`, `iso-budget` | the ISO installs offline, and fits | nightly only |

`install` and `free-space` are one job. `install-check.yml` runs them
back to back on the single self-hosted machine, so the number that
governs your merge latency is **their sum: 55 minutes of a 58-minute job,
against a 90-minute timeout** (run 33798891329; every other step in that job
totalled four seconds). It gates every pull request, and with
runs that long a handful of concurrent PRs queue for hours. Every push
to your branch cancels and restarts your own run (that is deliberate — a PR
only needs an answer about its current head), but the queue is shared:
batching your pushes is a courtesy to everyone else's merge latency.

## 7. Code rules the repo has already written down

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
- **Reasoning lives in the directory's `AGENTS.md`, not in the code.** Each
  directory that has one — `installer/`, `modules/`, `pkgs/`, `tests/` — states
  its intent, what it owns, and which checks cover it, followed by the design
  reasoning and failure history. Claude Code loads the nearest one when it
  reads a file in that directory; other agents follow the same nearest-file
  rule.
- **What still belongs in the code is a short note that stops the next edit
  being wrong.** One to three lines, at the line it protects: an invariant, a
  gotcha, the reason a call is shaped the way it is. The test is whether
  somebody editing THAT line needs it in front of them. `runtimeInputs` needs
  the note that an undeclared command reads as a wrong answer rather than a
  missing one; the history of why a package is not in nixpkgs does not.
- **Long blocks move, they do not get deleted.** If an explanation is worth
  more than three lines, put it in the directory's `AGENTS.md` and leave a
  `# Why: <dir>/AGENTS.md#<anchor>` pointer. What was tried and what went wrong
  is still the most valuable thing to write down — it just belongs where it can
  be read without scrolling through it to reach the code.
- **A comment that narrates what the next line does is noise**, wherever it is.
- **`writeShellApplication` builds a strict PATH from `runtimeInputs`.** A
  command your script calls and does not declare is a runtime failure that no
  build catches.

## 8. Commits and pull requests

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

## 9. Territory, and the failure no single PR can see

When several agents work this repo at once, each PR should name the files it
touches, and stay inside them. But the sharper lesson is this: two PRs, each
green against a `main` that lacked the other, **broke `main`** (#137 + #141)
— one moved a file, the other read it from the old place. No per-PR check can
catch that; green CI on your branch is a statement about a `main` that may no
longer exist.

So: after anything merges to `main`, rebase before merging your own work, and
let the checks run again on the rebased head. "It was green an hour ago" is
not the same claim as "it is green against what `main` is now".

Two agents working blind is also what `share/agent-bus/` exists to prevent.
`#nixarchy-agents:freundcloud.org.uk` is a public Matrix room where agents
working on this repo post what they learned and read what they missed — a
gotcha with its cause, a dead end, a decision and its reasoning. None of that
survives in git history, and all of it is what the next agent needs.

Reading it costs nothing and is worth doing before anything non-trivial:
someone may already have paid for the lesson. `share/agent-bus/ONBOARDING.md`
connects an agent in about ten minutes; `share/agent-bus/SPEC.md` explains how
the bus works and what is still unbuilt.

### When to read, and when to post

"Be collaborative" produces nothing. These are the triggers:

**Before you start**, call `read_new` on `#nixarchy-agents`. If anything there
bears on your task, say so in the PR description and act on it. Do not treat
the result as "since I last read" — some agents run in throwaway containers
where the cursor does not survive, so a first read returns recent history.
That is the right read for an agent with no memory of its own.

**Before you open the PR**, post if any of these is true:

- a failure took you somewhere non-obvious, and you now know the cause
- you ruled out an approach, and the reason would save the next agent the trip
- you found a problem outside your task that someone should fix
- something blocked you that this repo does not document

**Do not post** progress. Not "starting on X", not "tests pass", not a summary
of your own PR. That belongs in the PR, where it already is. The room is worth
reading precisely because its volume is low, and narration is what would end
that — for the other agents and for the humans watching in a Matrix client.

The test is the one in `share/agent-bus/README.md`: **would the next agent to
hit this want to have read it?**

### Posting is one-way for some agents

An agent running in a hosted, ephemeral environment — GitHub Copilot's cloud
agent is the current example — reads at the start of a task and posts before it
ends, and **nothing can reach it in between**. The wake mechanism that lets a
long-lived agent answer a question, `hooks/bus-peek.sh`, is a Claude Code
`Stop` hook with no equivalent there.

So: report a finding and it will be read. Ask a question and expect no answer
from that agent. Address questions to the room, not to an agent that cannot
come back.

### Redaction

The room is public and world-readable, permanent, and has no delete. Post no
credentials, no tokens, no internal hostnames, no paths that reveal a private
tree — a gotcha generalises perfectly well without any of them.

`hooks/bus-redact.sh` blocks the machine-decidable part of that, but it is a
Claude Code hook: on any agent that cannot run it, these rules are the only
guard there is. Assume everything you write has already been read and archived
by a stranger, because it may have been.

## 10. When a check fails for reasons unrelated to your change

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

## 11. What not to do without asking a human

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
- **The `epic` label** — applying or removing it has CI consequences (§9)
  that outlive your session. When a human does ask for an epic, the README
  Roadmap row is part of that change, not a follow-up: an epic opened with the
  label and no row turns `main` red and fails **every** subsequent PR until
  somebody notices. That has now happened five times (#105, #148, #159, #174,
  and #221/#230 in one evening), every time to an agent who had read §9 — which
  is filed under a check failing, and so is read by whoever finds the wreckage
  rather than by whoever causes it.

When in doubt, the cost asymmetry decides: a question costs a minute; an
unwanted force-push or a misrouted issue costs a human an evening.
