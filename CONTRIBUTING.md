# Contributing to nixarchy

Two documents come before this one:

- **Reporting a bug** is routed, not just filed — there are two projects here
  and sending a report to the wrong one wastes everybody's time. The routing
  rules live in
  [`pkgs/omarchy/skills/nixarchy/contributing.md`](pkgs/omarchy/skills/nixarchy/contributing.md),
  which is also what the AI agents on an installed machine follow. The short
  version: *would this happen on Arch?* Yes → Omarchy's. No → nixarchy's.
  Unsure → file it here.
- **If you bring an AI coding agent** — most contributors do — point it at
  [`AGENTS.md`](AGENTS.md) before it touches anything. It is a list of the
  ways agents have actually broken things in this repo, with the reasons
  attached. Most of it is worth a human's read too.

What follows is the code-contribution process itself.

## The one rule that outranks the others

A change to how *Omarchy* behaves belongs upstream at
[basecamp/omarchy](https://github.com/basecamp/omarchy), not here. Nixarchy
tracks Omarchy releases as a source bump; a fix landed upstream arrives here
for free, while a patch carried here has to be re-applied at every bump. If
your fix would also fix Arch, it is not a nixarchy PR.

## Setting up

```sh
gh repo fork olafkfreund/nixarchy --clone
cd nixarchy
nix develop            # nixd, statix, deadnix, qemu, gh
```

Two mechanics worth knowing before your first confusing error:

- A flake sees only **tracked or staged** files. A new file you have not
  `git add`ed fails evaluation with `path '…' does not exist`.
- The installer checks require a **committed** tree — `installer/mkFlake.nix`
  pins the generated flake by commit and throws otherwise. The commit can be
  temporary; the final subject is what matters (see below).

## Before pushing

```sh
nix fmt                                          # CI runs `nix fmt -- --ci`
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
nix build .#omarchy                              # the vendored tree assembles
```

Then build the check nearest your change, by name — `nix flake check` is not
how this repo runs its suite:

```sh
nix build .#checks.x86_64-linux.<name> --print-build-logs
```

`AGENTS.md` §5 has the full table of checks and what each costs. The one
number to know: **`checks.install` gates every PR, takes ~25 minutes, and
runs on a single self-hosted machine.** Concurrent PRs queue behind each
other, so batch your pushes — every push restarts your own run and lengthens
everyone else's wait.

## What a change needs to bring with it

**A check that provably fails without the change.** This repo has shipped
checks that passed with the bug they were written for fully reintroduced, and
the README's "What running it on real hardware found" section records three
more that were structurally incapable of failing. So the standard is: break
the thing, show the check going red, fix it, show it going green, and put the
red output in the PR. A check that cannot fail is worse than no check,
because it reads like coverage.

**Comments that explain why**, including what was tried and did not work.
`installer/cd.nix` and `modules/flatpaks.nix` are the register. And read the
header of `modules/services/default.nix` before setting any NixOS option from
a module — the priority rules there (`mkDefault` on scalars, plain assignment
on lists and attrsets, `mkForce` never) exist because getting them wrong
silently discards user configuration.

**Both states, if it adds an option.** `tests/options.nix` asserts every
option on and off, because the off state is the half nobody exercises and
exactly what a refactor breaks quietly. Someone importing this module into a
machine they already run must be untouched by anything they did not opt into.

## Commits and PRs

- The subject is a full sentence describing the change — `git log --oneline`
  shows the register. No conventional-commit prefixes.
- A single-commit branch is squashed using the **commit** subject, so do not
  leave `wip:` on it; amend before marking the PR ready.
- Fill in the PR template. Its questions are this document in form shape.
- After something else merges to `main`, rebase and let CI run again. Two
  PRs, each green against a `main` that lacked the other, have broken `main`
  here; green-an-hour-ago is not green-against-now.

## Issues, epics, and the roadmap

Bug reports follow the routing doc linked at the top. One label carries
machinery: an issue labelled `epic` must have a row in README's Roadmap
table, and CI fails **every** PR until the two agree — in both directions,
opening and closing. Leave that label to the maintainer.

## Scope of the project

Read "What is deliberately not planned" at the bottom of the README before
proposing something in that territory. The reasoning there is the answer to
the proposal, and it was expensive to earn.
