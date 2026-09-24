---
status: approved
issue: 959
intent: intent/2026-09-24-959-shadowed-plugins.md
---

# Spec: nixarchy doctor names a plugin directory that shadows a shipped one

## The two open questions, decided

The intent left both to you and you approved without picking, so these are **my
calls**, stated as such rather than presented as yours.

**1. Where it surfaces: `nixarchy doctor`, and not a desktop notification.**

Doctor is the right home and this is checked rather than assumed:

- It is already **testable at the cheapest layer**. `tests/doctor-graphics.nix`
  runs `nixarchy-doctor` inside a `runCommand` against a faked environment and
  asserts on its transcript. A plugin finding is provable the same way, with no
  VM and no hardware -- which matters, because section 1 says a check that
  cannot fail is worse than none, and this one can be made to fail cheaply.
- It is **structured in sections** already (Compositor, Display manager,
  library resolution), so a Plugins section is an existing shape, not a new one.

A notification is deliberately **not** in this spec. It would be seen by more
people and resented by more people, it has no test layer as cheap as the above,
and once it is wrong about somebody's working copy it is wrong at them on every
login. If doctor proves insufficient, a notification is a second, smaller change
with evidence behind it.

**The honest weakness of this choice, stated rather than glossed:** nothing runs
doctor automatically. It is a command someone types when they already suspect
something. So this makes the problem *diagnosable* rather than *announced* --
which is a real improvement over a journal line nobody reads, and is not the
same as solving it. If you want it announced, say so and the notification goes
in the plan.

**2. The discriminator: report, do not decide.**

Same `origin` is necessary and not sufficient -- p620's `github-actions` clone
is same-origin, 28 commits ahead, entirely deliberate. So doctor reports the
facts and lets the reader judge:

- the directory,
- the commit it is on, and whether that commit is **ahead of, behind, equal to,
  or unrelated to** the one nixarchy ships,
- the commit nixarchy ships,
- the one-line fix, shown only when the clone is **behind or unrelated**.

"Behind" is the case that cost a day; "ahead" is somebody working; "equal" is
harmless today and latent tomorrow. Naming which one it is costs nothing and a
discriminator that decides will eventually be wrong about someone's work.

## Design

A **Plugins** section in `pkgs/doctor.sh`, its first. For each declared plugin
whose path in `~/.config/omarchy/plugins` is a real directory rather than a
symlink:

| what doctor finds | what it says |
|---|---|
| not a git clone | one line: this is yours, nixarchy is not managing it. No advice. |
| clone, different origin | same. It is their own plugin at that id. |
| clone, same origin, **equal** to the shipped commit | says so, and that it will silently stop tracking at the next pin bump |
| clone, same origin, **ahead** | says so, and that nixarchy's copy is older. No advice to move it. |
| clone, same origin, **behind or unrelated** | the finding: names both commits and the two-line fix (`mv` aside, restart `home-manager-<user>`) |

Comparison is `git merge-base --is-ancestor` in both directions, which answers
ahead/behind/equal/unrelated in two calls and needs no network. A shallow clone
that cannot answer reports **unrelated**, which is the safe direction: it asks a
human to look rather than staying quiet.

### The manifest gap -- corrected after approval, and it is now a dependency

**This section said doctor "already knows the declared set from the
configuration it is reading". That is wrong**, and reading `pkgs/doctor.sh`
rather than assuming is what found it. Its header states the opposite as a
design decision:

> Deliberately inspects the live system rather than evaluating a flake: this
> has to be useful *before* nixarchy is an input, and `nix run` on a flake that
> is not yet imported anywhere is the only entry point a new user has.

Doctor reads `/run/current-system/sw` and `$XDG_CONFIG_HOME`. It never
evaluates module config, and it must not start: being useful before nixarchy is
an input is the reason it exists.

So it has to learn the declared set **from disk**, and the only candidate is
`~/.config/omarchy/plugins/.nixarchy-managed` (`modules/home.nix:1094`) -- which
today lists what activation **linked**, and therefore omits exactly the
shadowed ids this issue is about. Doctor reading it would see no trace of the
problem.

**So the intent's third open question is answered: the manifest change is a
dependency, not a separate issue.** The reconcile step records the declared id
in both cases, distinguishing linked from shadowed:

```
nixarchy.herdr
!nixarchy.distrobox      # declared, not linked -- a real directory is there
```

A leading marker rather than a second file, so the "a plugin dropped from the
configuration goes away" loop directly above keeps working on the same list --
it greps for exact lines, so a marked id is simply not matched and not removed,
which is already the behaviour that branch wants.

This also makes the finding possible **without git at all** for the first
question ("is something shadowing a declared plugin?"), leaving git needed only
to say ahead/behind. That is a better failure mode than the risks section
assumed.

## Alternatives rejected

| | why not |
|---|---|
| Desktop notification at first login | See above. No cheap test layer, and it is wrong at the user repeatedly once it is wrong once. |
| Move the clone aside automatically | p620's 28-commits-ahead clone. The issue reaches the same conclusion. |
| Flag on `origin` match alone | Would flag two deliberate working copies on two hosts today. A warning that is wrong twice on the first machine is a warning that gets ignored. |
| Compare file content instead of commits | Cheaper, no git, and flags razer's identical clone the moment any file differs for any reason -- a dirty working tree, a build artefact. |
| Make activation fail | It is the user's directory. Refusing to activate over it is a worse outcome than a stale plugin. |

## Risks

- **Doctor grows a git dependency, for part of the answer only.** With the
  manifest change above, "something is shadowing a declared plugin" needs no
  git. Only ahead/behind does, and doctor must degrade to naming the directory
  and both paths rather than erroring when `git` is absent.
- **Doctor must not start evaluating config.** The manifest is a file on disk,
  which keeps its pre-install contract intact. Any future temptation to read
  module options here breaks the reason it exists.
- **`~/.config/omarchy/plugins` may hold directories for plugins we do not
  declare.** Those are not our business and must not be reported at all -- the
  section walks the *declared* set, not the directory.
- **Mode A.** A machine with nixarchy's plugins off declares none, so the
  section finds nothing and prints nothing. Asserted both ways.
- **Wording.** Every line here is read by someone who did something reasonable.
  It should not imply they were wrong.

## Verification

- **A new `tests/doctor-plugins.nix`**, modelled on `tests/doctor-graphics.nix`:
  a fake plugin directory in each of the five states above, doctor run against
  it, and the transcript asserted. Section 1: each case must be seen failing
  with the finding removed, and that output goes in the PR.
- Adding a `checks.<name>` entry means a workflow must name it, and that
  workflow edit is a CI-gate change needing a human (section 4, section 11). The
  plan raises it rather than wiring it.
- **`checks.options`**, Mode A both ways: the section exists and finds nothing
  where no plugins are declared.
- **By hand on p620 and razer**, which between them have four of the five states
  live today -- including the ahead case, which no fixture would have thought to
  invent.

## Open question

Should the "equal today, latent tomorrow" case be a finding at all, or only a
note? It is not wrong yet. Reporting it is how razer's clone gets caught before
the next bump rather than after -- but it is also a line about something that is
working, on a machine where nothing is broken. I have specified it as a note
rather than a finding; say if you want it louder.
