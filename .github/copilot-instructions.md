# Copilot on nixarchy

You already read `AGENTS.md`, so this does not repeat it. This is the part
that is specific to *your* environment, and most of it is about what you
cannot do here — because the expensive mistake in this repo is a change that
looks verified and is not.

## What your environment has

`.github/workflows/copilot-setup-steps.yml` installs **nix** with this
flake's binary caches before your session starts. So you can run checks, and
you are expected to.

## Checks you can run, and may claim

These finish in seconds to a couple of minutes:

```bash
nix fmt -- --ci
nix run --inputs-from . nixpkgs#statix -- check .
nix run --inputs-from . nixpkgs#deadnix -- .
nix run --inputs-from . nixpkgs#shellcheck -- <script>
nix run --inputs-from . nixpkgs#actionlint -- .github/workflows/<file>.yml

nix build .#checks.x86_64-linux.options       # the broad eval check
nix build .#checks.x86_64-linux.bin-ledger
nix build .#checks.x86_64-linux.doc-options
.github/scripts/readme-counts.sh --check
```

## Checks you cannot run, and must not imply

| | why |
|---|---|
| `checks.session`, `coexist`, `plugin`, `integration` | boot VMs; one attempt can eat your whole 59-minute session |
| `checks.install`, `free-space` | **self-hosted runners you cannot reach** — Copilot supports self-hosted only via ARC, and these are bare NixOS |
| `checks.install-iso` | nightly only, ~3 hours, builds a 5.6 GB image |

If your change touches anything these cover — the installer, the session, the
ISO, the initrd — **say so in the PR, in words**: which check would prove it,
and that you could not run it. A PR that is silent about this reads as
verified, and someone merges it on that reading.

## The rule that most affects you

`AGENTS.md` §1: **a check must be proven able to fail.** If you add or change
a check, break the thing it guards, run it, and paste the red output into the
PR. Then fix it and show it green.

You can honour this for every check in the first list. You cannot for the
second. Do not pretend otherwise — an unverifiable claim is worse than an
admitted gap, because the gap gets covered and the claim does not.

## Never touch these

`AGENTS.md` §11 in full, and these specifically, because they have bitten:

- **`.github/workflows/**`** — CI gates are the repo's immune system. Propose in the PR body; a human wires it.
- **Labels, milestones, the board, repository settings.**
- **The `epic` label.** Opening an epic without a matching row in README's
  Roadmap table turns `main` red and fails **every** subsequent PR until
  somebody notices. It has caught five people. Do not file epics.
- **Anything in another repository.** Upstream is `basecamp/omarchy`; a fix to
  how Omarchy itself behaves belongs there, not patched here.

## What good work looks like here

The shapes that fit your environment, because a cheap check proves them:

- a row in `data/apps.nix`, `data/services.nix`, `data/flatpaks.nix`
- a row in `data/bin-ledger.nix` for a command that shipped without one
- a stale string, a wrong line number in a comment, a derived number
- a test fixture where the fixture check is itself the proof

The shape that does not fit: anything whose proof needs a VM.

## Two more things

- **Commit subjects are full sentences.** No `conventional-commits` prefixes.
  Read `git log --oneline -10` for the register.
- **A local hook reformats `.nix` files.** If `nix fmt -- --ci` disagrees with
  what you just wrote, run it twice before assuming a bug.
