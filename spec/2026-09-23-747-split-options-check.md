---
status: draft
issue: 747
intent: intent/2026-09-23-747-split-options-check.md
---

# Spec: checks.options stops evaluating every machine at once

## The intent's open questions, answered before designing anything

**Question 3 first, because a "no" would have cancelled the work.** *Do 21
distinct NixOS machines need to exist, or would fewer carry the same coverage?*

**They are needed.** Reading all 21: `sopsOn`, `rdpOff`, `rdpOn`,
`rdpFirewall`, `rdpNoSecret`, `devenvOn`, `devenvNoCache`, `nvidiaHost`,
`nvidiaDeclined`, `cachesDeclined`, `dockerDefault`, `dockerRooted`, `mvOn`,
`mvOff`, `aiModels`, `aiPlain`, `aiModelsBeside`, `webuiOn`, `syncthingBeside`,
`ollamaBeside`, `defaultMachine`. Each varies **one option that cannot be
varied on a shared machine** — the four `rdp` fixtures are off, on, on with
`openFirewall`, and on with no secret named, which is four configurations
because it is four states of one feature. That is what "asserted in both
states" means, and it is exactly the coverage `modules/AGENTS.md` says protects
Mode A.

So there is no free win in having fewer machines, and the structural change is
the right one. This question was worth asking — it would have saved the whole
job if the answer had gone the other way — and the answer is no.

**Question 2: how much do the two halves share?** Counted across the 109 cases
the `cases` attrset defines:

| | cases |
|---|---|
| read NixOS fixtures only | 32 |
| read Home Manager fixtures only | 38 |
| **read both** | **8** |
| read neither directly (helpers, literals, package lists) | 31 |

**Eight.** The overlap is small enough that the split does not force a choice
between duplicating fixtures and losing cases — it forces a decision about
eight named cases, which is a reviewable list rather than a structural problem.

**Question 1: does the split reduce the peak or move it?** The Home Manager
half becomes cheap: 11 fixtures, and Home Manager configurations are a fraction
of a NixOS `config`. The NixOS half is still 21 machines and still the great
majority of the 13.2 GB live heap. **So the split alone does not fix this**,
and the spec has to say so rather than assume a halving.

**Question 4: what is the target?** Half the runner — **under 8 GB per
derivation** — rather than "under 16". A ceiling the check merely fits inside
re-opens this issue at the next growth spurt, which is how it arrived here from
11.5 GB.

## Design

**Two derivations, split by fixture family, and the NixOS half split again by
feature group.**

The owner chose a NixOS/Home-Manager split (2026-09-23). Taken alone it leaves
the expensive half unchanged, so it is the first of two cuts rather than the
whole design:

1. **`checks.options-home`** — the 38 Home Manager cases and the 11 HM
   fixtures. Cheap, and it stops paying for 21 NixOS machines to assert a
   `home.activation` script.

2. **`checks.options`** keeps its name and the 32 NixOS cases, **grouped so the
   fixtures a group needs are evaluated within it** rather than all 21 at the
   top level. The grouping follows the features the fixtures already name —
   rdp, docker, ai, devenv, nvidia, sops — which is how they were written.

3. **The 8 both-reading cases go with the NixOS half**, because that is where
   the expensive fixture already is; the Home Manager fixture they also read is
   the cheap one to duplicate. Each of the eight is named in the plan, so the
   decision is reviewed rather than inferred.

**The top-level `let` is what retains them.** #745 made the fixtures shared so
they would be evaluated once rather than per case, and that is still right
*within* a group. What it did not intend is that a case about `sops` keeps
`nvidiaHost` alive. Moving each fixture into the narrowest scope that uses it
keeps #745's win and drops the peak, because the garbage collector can reclaim
a group's machines once that group's cases are forced.

## Alternatives rejected

- **Fewer fixtures.** Answered above: each of the 21 varies a different option,
  and merging any two loses a state. This was the cheapest possible fix and it
  is not available.
- **The NixOS/HM split alone.** Rejected as insufficient rather than wrong: it
  is change 1 of the design, and on its own it leaves 21 machines in one
  derivation and the peak roughly where it is.
- **Splitting by case count** (two halves of ~55 cases each). Rejected: the
  cost is the fixtures, not the cases, and a split that cuts through a feature
  group duplicates the machine both halves need — the double-evaluation the
  intent forbids.
- **`nix eval` with a smaller heap and more GC cycles.** Rejected: it trades a
  memory failure for a time failure, and 18 cycles at 2:37 says the collector
  is already working.
- **Dropping `--option eval-cache false` in CI.** Rejected: that measures the
  cache, not the check, and the first run after any change pays the full cost
  anyway.

## Risks

- **A split that loses a case is invisible.** Two derivations that each pass
  say nothing about a case that ended up in neither. The plan's first step is
  therefore a count that must match before and after, and the PR carries it.
- **A new `checks.*` entry needs a workflow line, which is a human's** (§4,
  §11). `checks.options-home` is exactly that. It is raised in the PR, not
  wired — and until it is wired, that half runs nowhere, which is worse than
  not splitting. **This is the risk that decides whether the work ships**, so
  the plan's last step is the request rather than an afterthought.
- **Regrouping is a large mechanical diff** in a 5,400-line file, and a
  mechanical diff is where a case quietly changes meaning. Mitigated by the
  count above and by `git diff --stat` being dominated by moves rather than
  edits.
- **The measurement may not improve as predicted.** The peak is driven by what
  is live simultaneously, and Nix's collector decides when to reclaim. If the
  after-measurement does not beat 8 GB, the work has not succeeded and the PR
  says so rather than shipping a structural change for its own sake.

## Verification

| | how |
|---|---|
| no case is lost | count the `cases` keys in both files before and after; the totals must be equal, and the PR carries both numbers |
| no case is evaluated twice | no fixture name appears in both derivations except the eight named, which are listed explicitly |
| coverage is unchanged | `checks.options` and `checks.options-home` both green, and each option still asserted in both states |
| **the peak actually drops** | `env -u NIXPKGS_ALLOW_UNFREE /usr/bin/time -v nix eval --option eval-cache false` on each half, same host, same way as the 13.06 GB before-measurement. Target: **under 8 GB each** |
| the before-number is reproducible | re-measure `main` on the same host in the same session, so before and after are not from different days |

The fourth row is the only one that says whether this worked. Everything else
says it did no harm.
