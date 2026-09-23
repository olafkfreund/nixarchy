---
status: draft
issue: 747
author: olafkfreund
---

# Intent: checks.options stops evaluating every machine at once

## Problem

`checks.options` peaks at **13.06 GB of resident memory**, on a runner with 16.

That is **82% of `ubuntu-latest`**, measured on `5fd866c` with
`/usr/bin/time -v` around `nix eval --option eval-cache false`. The issue was
filed at 11.5 GB and 72%. Nothing was done to make it worse; the option surface
grew, which is the drift the issue exists to watch, and the headroom has
narrowed by ten points in the meantime.

**It is not failing today.** This is a report about how close it runs, and about
what that failure would look like when it arrives.

The reason it is worth acting on before it fails is the shape of the failure.
A job that runs out of memory on a hosted runner reports `cancelled`, with no
failed step — and `cancelled` already means three different things here
(eviction, `timeout-minutes`, a deploy to p620), each documented because each
cost somebody an afternoon. A fourth cause that looks identical to the other
three, and that arrives gradually rather than on a particular commit, is the
kind of thing that gets misdiagnosed twice before anyone measures it.

**Where the memory goes is now known rather than guessed.** `NIX_SHOW_STATS=1`:

| | bytes | count |
|---|---|---|
| **attribute sets** | **15.28 GB** | 68.2 M sets, 852.7 M elements |
| values | 8.15 GB | 509.3 M |
| envs | 3.81 GB | 190.1 M |
| lists | 0.55 GB | 69.2 M elements |
| live heap | **13.22 GB** | 18 GC cycles |

Attribute sets are half of everything allocated. That is the module system:
`tests/options.nix` binds **21 NixOS configurations and 11 Home Manager ones**
at its top-level `let`, so all 32 are retained for the whole evaluation by
construction — 13.2 GB across 21 system evaluations is about 630 MB each, which
is the right order for a `config` with `system.build.toplevel` reachable.

They are retained **on purpose**. #745 made the fixtures shared precisely so
they would be evaluated once rather than per case, and that bought 17.6% of
wall clock. The cost of that decision is that the peak is now the sum of every
machine the file needs, and the file needs more machines every time an option
is added.

## Proposed outcome

`checks.options` evaluates comfortably inside a hosted runner's memory, with
headroom that does not shrink every time an option is added.

Observable:

- peak RSS well below the 16 GB ceiling — with enough margin that adding the
  next ten options does not re-open this issue;
- **every option is still asserted in both states.** This is the check that
  protects Mode A, and the off state is the one a refactor breaks quietly.
  Nothing here may reduce what is covered;
- no case is evaluated twice to achieve it — the thing #742 and #745 were both
  about;
- the number is measured after the change, not predicted.

## Affected users and systems

- **`tests/options.nix`** — 5,400 lines, ~205 cases, 32 bound fixtures.
- **`flake.nix`**, which exposes `checks.options`.
- **`.github/workflows/build.yml`**, which builds it — and any change to what
  that workflow names is a CI change a human merges, not something this work
  does on its own.
- **Every contributor**, indirectly: this is the check that tells you an option
  you added works in both states, and it is already the slowest thing most
  people wait for.
- **Nobody's machine.** No shipped behaviour changes. If this work alters a
  single thing a user can observe, it has gone wrong.

## Constraints

- **Coverage must not shrink.** Not one case may be dropped, weakened, or
  moved to a check nothing runs. `modules/AGENTS.md` is explicit that the off
  state is what protects Mode A.
- **Nothing may be evaluated twice.** A split that re-evaluates shared
  fixtures in both halves trades memory for wall clock and re-creates the
  problem #745 fixed.
- **Adding a `checks.*` entry means a workflow names it**, and that workflow
  edit is a human's (§4, §11). Any shape that produces a new check has to be
  raised rather than wired.
- **The measurement must be reproducible.** One sample on one workstation is
  what the issue already has, and it says so about itself. Before and after
  have to be measured the same way, on the same host, with the environment
  stripped (`env -u NIXPKGS_ALLOW_UNFREE`, `--option eval-cache false`).
- **Do not start local runs while installs are in flight.** §6 names an 11.5 GB
  evaluation as the same load as a build, and this work is a loop of them.

## Open questions

1. **Does the split actually reduce the peak, or move it?** The owner has
   chosen a NixOS/Home-Manager split (2026-09-23). The NixOS side is 21 of the
   32 fixtures and the great majority of the heap, so the Home Manager half
   should become cheap — but the NixOS half is then *still* 21 machines, and
   whether that alone fits comfortably is the question the spec has to answer
   with a number before any code is written.

2. **How much do the two halves actually share?** If a meaningful number of
   cases read both a NixOS config and a Home Manager one, they cannot be split
   without either duplicating a fixture or losing the case. I have not counted
   this yet, and the spec cannot be honest without it.

3. **Is there something cheaper that was not on the issue's list?** The 21
   NixOS fixtures are retained because they are top-level bindings. Whether
   the same coverage needs 21 *distinct machines* — rather than the same
   machines asserted about more — is a question about the fixtures, not the
   check's shape, and it would need no split and no new workflow entry at all.
   Worth an hour before committing to the structural change.

4. **What is the target?** "Under 16 GB" is what the runner enforces and is not
   a goal worth having, since the issue would re-open at the next growth spurt.
   A number with headroom — half the runner, say — makes the outcome testable
   and says when to stop.
