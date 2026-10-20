---
status: approved
issue: 1383
author: olafkfreund
---

# Intent: a failed Omarchy bump is visible, and edge carries main without waiting on quattro

## Problem

The Omarchy workflows fail in three ways that cost hours this week, and
none of them is a code bug.

1. **A failed release bump is silent.** `omarchy.yml` builds the new
   release (`nix build .#omarchy`, line ~115) before it opens its PR (line
   441). When the build fails, the only report is a step summary
   ("Report what needs a human", line 571) that nobody opens. Omarchy
   4.0.6 stalled this way on 2026-10-20 (#1374): no PR, no issue, found
   only when the owner pasted the log.
2. **Carrying `main` to edge also moves quattro.** `omarchy-edge.yml`'s
   "Find the newest quattro commit" (line 165) runs on every dispatch,
   including `from_candidate`. On 2026-10-20, a run meant only to carry
   4.0.6's fixes to edge also took quattro's new notification engine and
   failed (#1380). Edge then stayed behind `main` until that unrelated
   upstream change was ported, and a scheduled run whose new quattro
   fails always leaves edge without `main`'s fixes.
3. **Edge verify runs a hand-kept list of checks** (line 239: seven
   names). `etc-overlay` was missing, so 13 unclassified `/etc` files
   shipped on edge with verify green (#1377). §4 already says a
   hand-maintained list fails open; PR CI solved this with
   `.github/scripts/generated-checks.sh`.

## Proposed outcome

- **A failed Omarchy bump leaves something a person sees**: an issue, or
  a draft PR on a pushed branch, naming the failing step and its first
  error lines. A later night's success closes or updates it.
- **Edge can carry `main` without moving quattro.** A `from_candidate`
  dispatch keeps the candidate's quattro pin. When a scheduled run's new
  quattro fails, edge still gets `main` on the last good quattro, so
  `main`'s fixes never wait on an upstream port.
- **Edge verify builds the same generated check list PR CI uses**, so a
  new check (`etc-overlay` and the rest) runs on edge without anyone
  editing the workflow. This carries #1377's workflow half.

## Affected users and systems

- Edge-channel users, who get `main`'s fixes sooner and no unverified
  `/etc` drift.
- The owner, who sees bump failures instead of hearing about them.
- `.github/workflows/omarchy.yml`, `.github/workflows/omarchy-edge.yml`,
  and possibly a small script under `.github/scripts/`.

## Constraints

- **Workflow changes are CI-gate changes (CLAUDE.md §11).** The PR
  proposes them, and the owner merges.
- **Never weaken a gate.** Edge still promotes only a candidate whose
  checks passed. The fallback (`main` on the last good quattro) is
  verified like any other candidate.
- **No new noise.** One rolling issue or PR per failure kind, updated in
  place, not a new one each night. The edge report job's rolling-issue
  pattern already does this (`omarchy-edge` label), and an issue it
  closes on promotion must not swallow unrelated tracked issues (that
  happened to #1377).
- **§1:** each behaviour is proved by a run that fails without it. For
  example, a deliberately broken bump on a throwaway branch must produce
  the issue or PR, and `from_candidate` on a pinned candidate must not
  move the pin.
- Measure runtime: edge verify's cheap stage must still fit its job
  timeout once it builds the generated list.

## Open questions

- **Issue or draft PR for a failed bump?** I propose a draft PR: the bump
  branch is already made, a PR shows the diff and its CI, and it is where
  the fix gets pushed anyway. An issue would duplicate it.
- **The fallback on a failing quattro:** automatic, in the same run, or a
  second run? I propose the same run: try new quattro first, and on
  failure retry with the old pin plus `main`. One run, two candidates,
  only a verified one promoted.

## Decisions (owner, 2026-10-20)

- A failed bump opens a **draft PR** on the pushed bump branch, updated in place.
- The quattro fallback runs **in the same edge run**: new quattro first; on failure, the last good quattro with `main`.
