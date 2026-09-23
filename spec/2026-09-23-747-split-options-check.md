---
status: draft
issue: 747
intent: intent/2026-09-23-747-split-options-check.md
---

# Spec: checks.options stops evaluating every machine at once

> The slug says `split-options-check` because that was the approved direction
> when the branch was cut. The measurement below changed it to scoping, and the
> files keep their name so the intent, spec and plan still point at each other.
> The intent's title — "stops evaluating every machine at once" — is what both
> designs were ever for, and is still exactly right.

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

**Question 1: does the split reduce the peak or move it?** **Measured, and the
answer changes the design.**

Twenty-one NixOS configurations, producing the same twenty-one booleans, built
two ways. The only difference is where each configuration is bound. Separate
processes, `env -u NIXPKGS_ALLOW_UNFREE`, `--option eval-cache false`, the same
way the 13.06 GB baseline was taken:

| | peak RSS | wall clock |
|---|---|---|
| **`rooted`** — all 21 in a top-level `let`, the shape `tests/options.nix` has | **4.73 GB** | 36.9 s |
| **`scoped`** — each bound inside the expression that consumes it | **1.62 GB** | 32.7 s |

Both exited 0 and both returned `true`, so both really did evaluate all 21 —
checked before the numbers were read, because an earlier run of this same
experiment returned two *identical* figures that looked like a clean null
result and were two evaluation failures.

**Scoping cuts the peak by 66%, and is 11% faster.** The speed is the part that
settles the argument: the obvious objection to scoping is that it re-evaluates
what sharing had computed once, and a re-evaluating variant would be slower,
not faster. It is faster because there is less to collect.

So the peak is caused by the fixtures being **reachable**, not by their being
in one derivation. The collector was always willing to reclaim them; the
top-level `let` was what forbade it.

## Design

**Scope the fixtures. Do not split the check.**

The owner chose a NixOS/Home-Manager split (2026-09-23) on the evidence then
available, which was a count of fixtures and no measurement. The measurement
says a split would move the expensive half intact into its own derivation and
leave the peak roughly where it is, while scoping removes two thirds of it.

1. **Each fixture moves from the top-level `let` into the narrowest scope that
   uses it.** Where several cases share one — and many do, which is #745's
   whole point — that scope is a feature group (`rdp`, `docker`, `ai`,
   `devenv`, `nvidia`, `sops`), not a single case. Scoping per *case* would
   re-evaluate a shared machine and undo #745; scoping per *group* keeps
   #745's sharing exactly where it pays and drops it where it never did.

2. **`cases` is assembled from the groups**, so the file still presents one
   attrset of ~205 named cases and the check's output is unchanged.

3. **Nothing is split, so nothing new needs a workflow entry.** `checks.options`
   keeps its name, its coverage and its single derivation. This removes the
   risk the earlier design carried — a `checks.options-home` that runs nowhere
   until somebody wires it — and removes the need for the owner to merge a CI
   change at all.

**The split stays available and unused.** If scoping lands and the number is
still too high, splitting by fixture family is the next lever, and the counts
for it are already in this spec (32 NixOS-only cases, 38 Home-Manager-only, 8
reading both). It is not needed to start.

## Alternatives rejected

- **The NixOS/HM split**, which this spec previously proposed. Rejected on the
  measurement above: it relocates the expensive set rather than shrinking it,
  and it costs a new `checks.*` entry, a workflow edit the owner must merge, a
  boundary decision about eight cases, and a way to lose a case between two
  files. Scoping costs none of those and measured better.
- **Fewer fixtures.** Answered under question 3: each of the 21 varies a
  different option, and merging any two loses a state. The cheapest possible
  fix is not available.
- **Scoping per case rather than per group.** Rejected: it would re-evaluate
  every shared machine, which is exactly what #745 fixed and what the intent
  forbids.
- **`nix eval` with a smaller heap and more GC cycles.** Rejected: it trades a
  memory failure for a time failure, and 18 cycles at 2:37 says the collector
  is already working — as this experiment confirms, it was willing all along.
- **Dropping `--option eval-cache false` in CI.** Rejected: that measures the
  cache, not the check.

## Risks

- **A split that loses a case is invisible.** Two derivations that each pass
  say nothing about a case that ended up in neither. The plan's first step is
  therefore a count that must match before and after, and the PR carries it.
- **Regrouping is a large mechanical diff** in a 5,400-line file, and a
  mechanical diff is where a case quietly changes meaning. Mitigated by the
  case count above and by `git diff --stat` being dominated by moves rather
  than edits.
- **The 66% is from a proxy, not from the real file.** The experiment used
  plain NixOS configurations, which are smaller than nixarchy's fixtures
  (~225 MB each there against ~630 MB here), and it scoped every fixture to a
  single consumer where the real file must scope to groups. The *direction* is
  not in doubt; the *magnitude* is, and only the after-measurement settles it.
- **A fixture that turns out to be shared across groups** cannot be scoped
  without either duplicating it or keeping it at the top level. Any that
  remain rooted are named in the PR with their reason, rather than quietly
  left behind.
- **The measurement may not improve as predicted.** The peak is driven by what
  is live simultaneously, and Nix's collector decides when to reclaim. If the
  after-measurement does not beat 8 GB, the work has not succeeded and the PR
  says so rather than shipping a structural change for its own sake.

## Verification

| | how |
|---|---|
| no case is lost | count the `cases` keys in both files before and after; the totals must be equal, and the PR carries both numbers |
| no case is evaluated twice | wall clock must not regress; the experiment's scoped variant was *faster*, and a slower result means a shared fixture was scoped too narrowly |
| coverage is unchanged | `checks.options` green, and each option still asserted in both states |
| **the peak actually drops** | `env -u NIXPKGS_ALLOW_UNFREE /usr/bin/time -v nix eval --option eval-cache false`, same host, same way as the 13.06 GB before-measurement. Target: **under 8 GB**, and the experiment suggests materially better |
| the before-number is reproducible | re-measure `main` on the same host in the same session, so before and after are not from different days |

The fourth row is the only one that says whether this worked. Everything else
says it did no harm.
