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

## Write back what cost you an hour

Every numbered section below exists because something broke, and most name the
issue. That is not decoration — it is the only reason this file is worth
reading rather than skimming. **Keeping it that way is part of doing the
work**, not a chore afterwards.

So: when something costs you an hour, and the cause was *general* rather than
a fact about the one thing you were fixing, add it here in the same pull
request as the fix. Same PR, because a follow-up commit for documentation is
the one that never gets written.

The test is whether it would bite somebody else:

- **General** — `find` does not follow the `result` symlink; a module argument
  cannot have a `?` default; a check that cannot run reads as one that passes.
  Those belong here.
- **Specific** — this attribute was misspelled, that path moved. Those belong
  in the commit message, where `git log -S` will find them.

Put it in the section it belongs to rather than opening a new one: the numbers
are cross-referenced from `build.yml`, `omarchy.yml`, `tests/bus-mcp.nix` and
the PR template, so **inserting a section renumbers the ones below it and
breaks those references silently.** Append a new section only when nothing
existing fits, and never insert one in the middle.

Area-specific lessons go in that directory's own `AGENTS.md`. A trap in how
checks are written belongs in `tests/AGENTS.md`, where somebody writing a
check is already looking.

And prefer a check to a paragraph. If the mistake can be caught mechanically,
the paragraph is a consolation prize — `checks.iso-source`, the roadmap gate,
the board rows in the nightly review and `readme-counts.sh` all began as
things somebody would otherwise have had to remember.

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

Two other ways a check stops checking, both found in one week:

- **A check that cannot RUN reads as a check that passes.** The install job
  pushed to cachix and then asked the cache whether it had taken it — and died
  on `curl: command not found`, because the runner is self-hosted NixOS where a
  step's shell carries only what the environment provides. `continue-on-error`
  was on it (correctly: #235, a cache upload must not fail a build that
  succeeded), so nothing was red and nobody looked. **The verification had
  never checked anything, for any commit.** If a step is
  `continue-on-error`, its failure has to be *loud somewhere else* — the
  nightly, the summary — or it is decoration.
- **After the model changes, the checks that encode the old model fail for the
  reason the work succeeded.** Stage 3 of #436 made the installer copy a
  prebuilt closure instead of evaluating one. Three checks then failed in
  sequence: one greped the drvPath for the hostname that stage 1 had removed
  *on purpose*; one used `unable to download` as a proxy for "something was
  fetched", when it means a fetch was **attempted and failed** — evidence the
  machine is offline; one rebuilt the system to add a serial console, which
  under stage 3 is a different closure and therefore a build. Each looked like
  a regression and was a stale assertion. **When a check fails immediately
  after a deliberate change to how something works, ask what the check is
  asserting before asking what broke.**
- **A hand-maintained list fails OPEN.** Found three times in one day, in
  three unrelated places: four manual pages published and reachable from no
  sidebar; a third page index (`docs/manual/index.md`) that nothing compared,
  already missing Boxes and Sandboxes; and `nightly.yml`'s `report` job
  missing `reinstall-vm` from `needs`, so a 200-minute check could fail every
  night and file nothing. In each case the thing still worked — the page
  published, the job ran — so nothing went red and the only detector was a
  human happening to look. The same shape sat in `docs/llms.txt` saying *ten*
  skills while `ai.md` said *twelve* and the README said *thirteen*; the
  README was right because it was the only one with a check.
  **Any list naming things that exist elsewhere wants a comparison, not
  discipline** — and the comparison should name the missing item, because a
  count only says a number moved.
- **A guard can also fail CLOSED, and then it looks like your change.**
  `readme-counts.sh` spells its counts as words from a hand-written `word_for`
  table and matches them with a fixed alternation (`twelve|thirteen|…`). The
  sixteenth skill is not a drift the script reports — it is a number the script
  cannot *say*, so it refuses with "computed as empty" or "nothing matches its
  pattern", which reads as a broken script rather than a missing vocabulary
  entry. That refusal is the design (§4's rule: an auto-fixer that cannot refuse
  is worse than a check). **Teach it the new word in the same PR** — the case
  table and every alternation that carries the old range.

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
- **You cannot compare closures across commits.** `installer/cd.nix` collects
  `flake.outPath` into `inputSources`, so the source tree's own store path is
  in the closure and **every commit changes every derivation**. To prove a
  refactor changes nothing that ships, evaluate the old and new code **in the
  same tree** — check the old file out beside the new one (`git show
  <rev>:path > path-old.nix`), instantiate both, compare `drvPath`. Baselining
  before and comparing after looks obvious, produces a difference every time,
  and the difference means nothing. #479 lost an hour to reading that noise as
  a real change.
- **A NixOS module argument cannot have a `?` default.** `{ source ? {...} }`
  in a module reads as correct and fails with `error: attribute 'source'
  missing`, because an argument absent from `specialArgs` is resolved through
  `_module.args` rather than by the function default — the trace says so, two
  frames down. Pass it from the call site instead.
- **Two processes cannot share one worktree.** A background driver doing
  `git checkout` while you do the same in the same directory is a race, and
  git's refusal to check out a branch already held by another worktree turns
  a failed `checkout` into a `reset --hard` landing on whatever branch was
  there. That happened here twice: once discarding pushed work (recoverable
  from the remote), once rebasing the wrong branch. If something else may be
  driving the tree, `git worktree add` and work there.
- **`find` does not follow the `result` symlink.** `find "$out" -name X`
  where `$out` is `./result` returns nothing, silently. Use `find -L`.
  `readme-counts.sh` counted zero skills this way, and only failed loudly
  because it refuses on an implausible count.
- **`builtins.tryEval` does not catch a missing attribute.** It catches
  `throw` and `assert`, and nothing else — so `tryEval (v.${n})` around an
  attribute access reads as a guard and is not one. A walk over
  `config.programs.nixarchy` aborted with `attribute 'allowUnfreePredicate'
  missing`, thrown from an *option default*
  (`{ inherit (pkgs.config) allowUnfree allowUnfreePredicate; }`), with every
  access already wrapped. If you are walking evaluated configuration, bound
  the root to a subtree you know rather than trusting `tryEval` to make an
  unbounded walk safe.

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
| `install` | full install onto a blank disk, reboot, rebuild-builds-nothing | self-hosted, shares the one VM slot |
| `free-space` | install beside an existing OS, which survives | same job, same nix invocation |
| `installer-refusal` | a dark substituter is refused, disk left intact | ~2–3 min, same job — a VM too |
| `install-iso`, `iso-budget` | the ISO installs offline, and fits | nightly only |

`install`, `free-space` and `installer-refusal` are one job.
`install-check.yml` builds all three in a single `nix build --max-jobs 3`,
so they **overlap** rather than run in sequence — the old serial model, and
its "55 minutes of a 58-minute job" sum, no longer exists. What governs your
merge latency now: the build step took **16–19 minutes on a warm store**
(runs 34573539340, 34509257501, 2026-09-10/11) against a 90-minute timeout,
and a cold store can push it toward that limit (#434 timed out at the cap
three times). There are **four self-hosted runners** — p510-nixarchy,
p510-nixarchy-2, p620-nixarchy, p620-nixarchy-2 — with identical labels and
separate stores, but the `nixarchy-install-vm-{1,2}` concurrency groups admit
**two relevant install jobs at a time, machine-wide** (#555, #587). Two is the
measurement, not a guess: 2 concurrent installs both succeed, 3–4 all fail at
the in-guest timeout (2026-09-09). A ref is assigned its slot by
`cksum(GITHUB_REF) % 2`, so a pull request's re-runs queue behind themselves
rather than migrating. Every push to your branch cancels and restarts your own
run (deliberate — a PR only needs an answer about its current head), but
batching your pushes is a courtesy to everyone else's merge latency.

**The mechanism, because getting it wrong costs hours.** GitHub retains
**one PENDING job per concurrency group**, and `cancel-in-progress: false`
means a newcomer cancels the *queued* job, not the *running* one. So:

- a **running** job blocks nothing — `main` building plus one PR pending is
  fine;
- eviction begins at the **second pending** job in the same group;
- the evicted job reports `cancelled`, which renders as a failure and
  **silently disables auto-merge**, and a re-run reaps itself — the only
  escape is a new head commit (#548).

Three separate supervisor designs were written here on the assumption that a
*running* job was the blocker. All three waited for a condition that never
came, and achieved nothing across about ninety minutes. The rule that works:
re-trigger when nothing is **queued**, not when nothing is running.

And read the JOB's conclusion, never the column: `gh pr checks` prints
`cancelled` as `fail`, so an eviction and a real failure look identical in the
summary. `gh run view <id> --json jobs` tells them apart, and the difference
decides whether you re-trigger or read a log.

**Do not build a VM check locally while CI has an install job in flight.**
The concurrency group in `install-check.yml` serialises GitHub *jobs*; it
knows nothing about a `nix build .#checks.x86_64-linux.session` you start by
hand on the same machine. Two of the four runners are on p620, and so is
your shell.

What it looks like when you do is not "your build was slow" — it is somebody
else's check failing, on a line that has nothing to do with their change:

    installer # Startup finished in ... 6min 34.738s (userspace)
    installer # systemd-udevd: Worker [441] ... is taking a long time
    installer # systemd-udevd: Worker [441] ... killed
    installer # dhcpcd.service: start operation timed out
    RequestedAssertionFailed: command `udevadm settle` failed (exit code 1)

Six and a half minutes for a userspace boot that normally takes seconds.
`udevadm settle` did not break; it was starved. This is §6's own lesson from
the other side — **a guest-side timeout is a hidden concurrency limit**, and
host-side timeouts scale with the box while guest-side ones do not.

Check first: `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`.

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

### Closing keywords do exactly what they say, and nothing you add to them

Both of these were written here in one day, and both lost tracking silently:

- **`Closes #555 in part`** closes #555. GitHub parses the keyword and the
  number and ignores every qualifier around it. There is no "closes in part".
  A partial fix uses `Refs #N`, and says in the body what is left — the
  residue of #555 went untracked the moment that merged, on a pull request
  whose own description explained why it must stay open.
- **`Closes #575, #576, #578`** closes only **#575**. The keyword has to be
  repeated per issue: `closes #575, closes #576, closes #578`. The other two
  sat open for hours with their work already on `main`.

Neither produces an error. Check the issues actually closed rather than
assuming the body did it.

### `auto=on` is not "will merge"

Auto-merge waits for required checks — and it waits **just as quietly** on a
`CONFLICTING` merge state, with nothing in `gh pr checks` to say so. Two pull
requests sat armed and unmergeable here while every check read green.

`gh pr view <n> --json mergeable` is the only answer. Check it before
reporting that something is on its way.

### A stacked PR conflicts the moment its base squash-merges

The branch still carries the commits that just landed as one squashed commit,
so git sees the same content twice. The fix is not to merge `main` into it:
**cherry-pick the branch's OWN commit onto the new `main`** and force-push.
That happened to four pull requests in one afternoon; the replay is
mechanical and takes a minute, but only if you recognise it rather than
fighting the conflict.

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
Roadmap table breaks the roadmap guard, the "roadmap still matches the open
epics" step in `build.yml` (four times in one day: #105, #148, #159, #174).
It fails **both** ways: an open epic with no row, and a row whose epic has
since closed.

**Where it fails changed, and this paragraph used to say otherwise.** The step
carries `if: github.event_name != 'pull_request'`, so it runs on pushes to
`main` and weekly — never on a pull request. The sentence here used to say it
failed "on every subsequent PR", which sends a reader through PR runs looking
for a failure that only ever appears in main's push build.

It reads the **live issue list**, not the diff, so a red clears on a re-run once
the state is consistent — no new commit needed. `docs/internals/workflows.md`
has the filing and retirement orders and why each one avoids the red.

The same shape now guards milestones: "A milestone whose work is done is
closed" names any milestone with no open issues left. `Keeping the lights on`
is exempt by design (§12) — it sits at zero open issues whenever the queue is
briefly clear.

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
- **The `epic` label** — applying or removing it has CI consequences (§10,
  and the whole filing process is §12)
  that outlive your session. When a human does ask for an epic, the README
  Roadmap row is part of that change, not a follow-up: an epic opened with the
  label and no row turns `main` red and fails **every** subsequent PR until
  somebody notices. That has now happened five times (#105, #148, #159, #174,
  and #221/#230 in one evening), every time to an agent who had read §9 — which
  is filed under a check failing, and so is read by whoever finds the wreckage
  rather than by whoever causes it.

When in doubt, the cost asymmetry decides: a question costs a minute; an
unwanted force-push or a misrouted issue costs a human an evening.

## 12. Issues, milestones and the board

The work is visible in three places and they answer different questions. Keep
all three true or none of them is worth reading.

| | answers |
|---|---|
| README **Roadmap** | what the shape is. CI-enforced: see §11 |
| **Milestones** | how far each feature has got. One per feature, not per release |
| The [**board**](https://github.com/users/olafkfreund/projects/9) | where each individual piece is right now. **Public** |

**Milestones are per feature, not per release.** Releases here are driven by
Omarchy bumps and can be cut any day, so a release milestone would be a bucket
with an arbitrary line through it. `Keeping the lights on` is where CI, docs
and small fixes go — it has no end and is not a failure to plan.

**Check the premise before filing.** An issue filed on something already true
is worse than no issue: it looks like work, it gets picked up, and the person
who picks it up learns not to trust the queue. One was filed this way — "the
bin ledger has no row for nixarchy-android", where the row had landed with the
command itself — and closing it cost less than leaving it. Read the tree
first; it is thirty seconds.

**And search for the BEHAVIOUR, not for the implementation you expect.** An
issue was filed here saying nixarchy had no garbage-collection policy, on the
strength of grepping `nix.gc.automatic`, `nix.gc.options` and
`configurationLimit` and finding nothing. All three were genuinely absent, and
the conclusion was still wrong: `programs.nh.clean` had been collecting
generations for a long time, with a comment making the same argument the issue
made. The fix that followed added a duplicate, nixpkgs warned the two
conflict, and `checks.config-warnings` failed.

The question that would have worked is "does anything collect generations",
not "is `nix.gc.automatic` set". A grep for one spelling answers whether that
spelling is present, which is not the same claim. The same mistake closed
#484 as outstanding work when the check it asked for was already on `main`,
scheduled nightly, and green — the agent that picked it up checked and said
so rather than building a second one.

**Every issue gets a milestone and an area label when it is filed.** Not
later. An issue with no milestone is invisible in every view that groups by
one, which makes it work nobody can see and nobody schedules. The nightly
review has a `board` row that names any issue missing one, and #195 does not
close while it is red — so this is checked rather than hoped, and the pressure
lands on whoever filed it rather than on someone's unrelated PR.

Epics are deliberately exempt: an epic in its own milestone reads as a child
of itself.

**Filing an epic is three things, not one** (§11 has the cost of forgetting):
the issue with the `epic` label, the README Roadmap row, and the milestone
with its children. Do all three in the same change.

### What the board does on its own

- **"Auto-add sub-issues" is on.** Adding a tracked epic pulls in its
  children, and new sub-issues join by themselves. The board grows without
  anyone touching it — expect that rather than discover it.
- Items stay when they close, which is what makes the *Shipped* view mean
  anything.

### What the API cannot do, so a human must

`createProjectV2View` takes a name, a layout and a filter. Its `configuration`
accepts **only** `visibleFieldIds` — there is no group-by, no sort. So an
agent can create and filter a view and **cannot** group it. If a view should
be grouped by Milestone, say so and let a human click it once; do not leave an
ungrouped table looking like the intended result.

Changing the board's **visibility** is a repository setting under §11: it is
outward-facing, and public means every issue title and every piece of
half-finished work is readable by anyone. Ask.

### Where a thing belongs

Anything a check can verify goes **in the repo**, where CI enforces it: the
Roadmap row, the derived numbers in the README, the board row above. The
[wiki](https://github.com/olafkfreund/nixarchy/wiki) is a separate git
repository that **no check in this repo can see**, so nothing load-bearing
lives there. It carries orientation and reasoning — the parts that do not
drift on their own. If you find yourself wanting to put a rule in the wiki,
that is the signal it belongs in a check instead.
