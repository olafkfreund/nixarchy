---
title: The workflows, and what each is for
---

# The workflows

Nine of them. Four run on your pull request, five run on a clock. Knowing
which is which saves the most common confusion here — *"CI is green, why did
the nightly fail?"* — because they check different things on different
machines.

This page is mirrored to the [wiki](https://github.com/olafkfreund/nixarchy/wiki)
from `docs/internals/`. Edit it here; the wiki copy is generated.

## The daily clock

They are staggered on purpose, and the order is the point: each one reports on
the state the previous one left.

| UTC | workflow | what it does |
|---|---|---|
| 03:00 | `nightly.yml` | the expensive VM checks — installs, the offline ISO, MicroVM boot |
| 04:00 | `omarchy.yml` | is there a new Omarchy release? If so, open the bump PR |
| 05:00 | `update.yml` | are the small vendored tools (hey-cli, ttfx, once…) behind? |
| 06:00 | `review.yml` | read all of the above and write the answer into #195 |
| 07:00 | `flake-update.yml` | bump the flake inputs |

**`review.yml` is the one to read first thing.** It edits a single issue in
place with a table of everything pinned, everything vendored, and every
workflow's last result — and **closes that issue automatically when the table
is all green**. So an open #195 means something needs attention, and a closed
one means nothing does. Run it yourself with `nix run .#review`.

## On a pull request

| workflow | runs | notes |
|---|---|---|
| `build.yml` | every push and PR | 9 jobs. The bulk of the checks |
| `install-check.yml` | every push and PR | 3 jobs. Installs into a VM — the expensive one |
| `release.yml` | a `v*` tag only | builds and publishes the images |
| `copilot-setup-steps.yml` | Copilot agents | environment setup |

### Why the install check is slow, and why that is deliberate

`install-check.yml` boots a real VM and installs nixarchy into it. It runs on
**self-hosted runners** (p620), and it is capped so only one install runs at a
time.

That cap was not caution. The VM's own install has a 30-minute timeout
*inside the guest*, and a guest-side timeout is a **hidden concurrency
limit**: host-side timeouts scale with the machine, guest-side ones do not.
Running four of these at once on one box turned "slower" into "failed", and
the failure named the test rather than the contention. Two concurrent jobs is
what demonstrably passes.

If your install check sits queued for twenty minutes, that is the cap working.

## The checks that exist to stop prose from lying

Three guards enforce things a reviewer would otherwise have to remember:

- **The roadmap** — an issue with the `epic` label and no row in README's
  Roadmap table turns `main` red, and then fails **every** subsequent PR until
  someone notices. It has caught five people. File the row in the same change
  as the epic.
- **The README's numbers** — `readme-counts.sh --check` derives every count in
  the README (commands, apps, skills) from the built package. Prose edited by
  hand must not drift.
- **The bin ledger** — every command in `pkgs/omarchy/nix-bin/` needs a row in
  `data/bin-ledger.nix` with a reason, and the check fails in both directions:
  a new file with no row, and a row for a file that no longer exists.

## Reading a failure

**`cancelled` means three different things**, and they are distinguishable
only by timings:

| what you see | how to tell | what it is |
|---|---|---|
| ran 75–92 min | long duration | a `timeout-minutes` kill — GitHub does not say `timed_out` |
| started, then died | has a `runner_name` | the per-ref cancel; on a PR this fires when `main` moves |
| ~90 s, no runner | `runner_name` empty | concurrency-group eviction — re-run it |

A **cancelled required check silently disables auto-merge**: it never turns
green and never will, so the PR sits open with no failure to investigate.

**A green branch is a claim about the `main` it was tested against.** Two PRs,
each green against a `main` that lacked the other, broke `main` (#137 + #141).
Rebase before merging.

## Where the work is tracked

- The [board](https://github.com/users/olafkfreund/projects/9) — public, one
  view per question
- Milestones — one per feature, showing how far each has got
- README's Roadmap — the shape, CI-enforced

`AGENTS.md` §12 has the filing rules and what the board does by itself.
