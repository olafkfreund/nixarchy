# Starting work on nixarchy

For a developer — human or agent — with commit access and no history here.
Half an hour, and you will know where things are and which mistakes are
expensive.

This page is mirrored to the [wiki](https://github.com/olafkfreund/nixarchy/wiki)
from `docs/internals/`. Edit it here; the wiki copy is generated.

## What this repository is

A NixOS port of [Omarchy](https://omarchy.org), which is an Arch desktop.
Upstream is vendored, not forked: `flake.nix` pins a released tag, and
`pkgs/omarchy/default.nix` patches what cannot work on NixOS — mostly
`pacman`, and paths under `/usr`.

That shapes almost every decision. **A fix to how Omarchy itself behaves
belongs upstream**, not patched here: a patch carried here is re-applied at
every bump; a fix landed upstream arrives for free.

## The one rule to absorb first

**Nothing imperative survives a rebuild.** A package the user picks is
*declared* in a file they own and applied by `nixarchy-apply`. Nothing
installs anything at the moment of clicking. If a change you are making would
install, download or mutate state at pick time, it is the wrong shape.

## Read these, in this order

| | |
|---|---|
| `AGENTS.md` | how to work here. 12 sections, each written after something went wrong |
| `docs/internals/workflows.md` | the nine workflows and how to read a failure |
| `docs/internals/flake.md` | what every flake output is and why |
| `modules/AGENTS.md` | the module layer, in depth |
| `tests/AGENTS.md` | how checks are written here |

`AGENTS.md` is not a style guide. Every numbered section exists because
something broke, and most cite the issue number. §1 — *prove your check
fails* — is the one that gets skipped and the one that matters most.

## Setting up

```bash
git clone https://github.com/olafkfreund/nixarchy
cd nixarchy
nix develop            # or direnv allow
```

Then, before touching anything:

```bash
nix flake check                                # everything (slow)
nix build .#checks.x86_64-linux.options        # the fast, broad one
nix run .#review                               # what is stale right now
nix run .#vm                                   # boot the desktop in a VM
```

`checks.options` is the one to run while iterating — it evaluates the whole
module surface and catches most mistakes in a minute or two.

## The four linters, and why all four

```bash
nix fmt -- --ci
nix run --inputs-from . nixpkgs#statix -- check .
nix run --inputs-from . nixpkgs#deadnix -- --fail .
nix run --inputs-from . nixpkgs#shellcheck -- <script>
nix run --inputs-from . nixpkgs#actionlint -- .github/workflows/<file>.yml
```

**Copy those invocations exactly, flags included.** `deadnix` without
`--fail` prints the same warning and exits **0** -- so the obvious form says
clean while CI says otherwise. `build.yml:132-138` is the authority, and this
list was missing `deadnix` altogether until it cost a red pipeline.

They catch different things and CI runs all of them. `statix` in particular
finds repeated keys and useless parens that `nix fmt` is happy with — it has
caught the same class of mistake three times in one session.

**A local hook reformats `.nix` files after an edit.** If `nix fmt --ci`
disagrees with what you just wrote, run it twice before assuming a bug.

## Committing

- The subject is a **full sentence** describing the change. No
  `conventional-commits` prefixes. Read `git log --oneline -10` for the
  register.
- **Never leave `wip:` on a single-commit branch** — the squash uses that
  subject, and two `wip:` commits are on `main` because of it.
- The PR template asks for your check's *failing* output. That is §1 in
  form-field shape, and it is not decoration: a check nobody has seen fail is
  a check that may not be able to.

## Filing work

Every issue gets a **milestone** and an **area label** when it is filed. The
nightly review names anything missing one, and its issue does not close until
that is dealt with.

An **epic** is three things in one change: the issue with the `epic` label,
the row in README's Roadmap, and the milestone with its children. Forgetting
the row turns `main` red and fails every subsequent PR until somebody notices
— it has happened five times.

`AGENTS.md` §12 has the detail.

## The expensive mistakes

Each of these cost someone an evening:

- **Skipping §1.** A check that cannot fail passes forever and proves
  nothing. Break the thing, watch it go red, then fix it.
- **Assuming a green branch is green against `main`.** Two PRs each green
  against a `main` lacking the other broke `main` (#137 + #141). Rebase.
- **Reading `cancelled` as "someone stopped it".** It also means a timeout
  and a concurrency eviction. See `workflows.md`.
- **Adding runners to make VM tests faster.** It makes them fail — the
  timeout is inside the guest. See `workflows.md`.
- **Fixing the symptom the ticket names.** Grep every caller of the function
  first; one guard in the shared path is a smaller diff than a guard in each
  caller, and patching one path leaves the siblings broken.

## Talking to the other agents

`#nixarchy-agents:freundcloud.org.uk` is a public Matrix room where agents
working here post what they learned — a gotcha with its cause, a dead end, a
decision and its reasoning. None of that survives in git history.

Read it before anything non-trivial; somebody may already have paid for the
lesson. `share/agent-bus/ONBOARDING.md` connects you in about ten minutes.

## What not to do without asking

Destructive git, changes to CI gates, repository settings, and posting to
anyone else's repository. `AGENTS.md` §11 is the list, and the reasoning is a
cost asymmetry: a question costs a minute, an unwanted force-push costs
somebody an evening.
