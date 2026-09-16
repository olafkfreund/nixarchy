---
status: approved
issue: 727
author: olafkfreund
---

# Intent: the proof push neither ratchets nor reports

Closes #727, #728, #729 — three failures of one mechanism, taken together
because fixing any one of them leaves 2026-09-16 able to happen again.

## Problem

On 2026-09-15 the Cachix free tier evicted 31 of 34 check proofs. On
2026-09-16 that turned into a day-long outage: `omarchy` failed on every
branch that ran, `main` could not be built at all, and recovery took a
maintainer with shell access on a warm-store machine building 40 checks by
hand and pushing their proofs.

The eviction was the trigger. It was not the reason it lasted a day. Three
independent properties of the proof mechanism turned a bad night into an
outage, and each is separately sufficient to do it again.

### 1. A killed job pushes nothing (#727)

`build-unless-proven.sh` builds, then pushes:

```sh
nix build --keep-going --no-link --print-build-logs "${todo[@]/#/.#checks.x86_64-linux.}" || rc=$?
"$here/cachix-push.sh" --proof "${todo[@]}" || true
```

`--keep-going` survives a partial *failure*. Nothing survives a *kill*. Three
jobs died mid-build on 2026-09-16 — at 14 minutes, at 17, and at exactly
45m00s — and every one of them had built checks successfully. All three pushed
zero proofs, because they never reached that line. Steps 10-23 read `skipped`
on every failed run.

So each run began where the last began. That is what made the outage
self-sustaining: not a full cache, but the impossibility of progress.

### 2. Nothing keeps the proofs alive (#728)

`spec/2026-09-15-697-cache-allowlist.md` section 5 gives the allowlist a
nightly keep-alive: probe every entry on `main`, re-push what is missing.

It covers `.#omarchy`, both toplevels, the MicroVM runners and the packaged
apps — 1622 MiB of content as measured on `main` today. It does not cover the
check proofs, which are **112 bytes each** and are the half CI's speed depends
on. The expensive half is protected; the cheap, load-bearing half is not.

31 proofs went missing on 2026-09-15 and nothing noticed, because nothing
looks.

### 3. The push cannot report failure (#729)

`checks.nixi` is the nixi package itself (`flake.nix:1511`), so its result is a
92-path, 567 MB closure. `cachix-push.sh --proof` refuses it — correctly, a
proof is one path under 1 MiB — sets `fail=1`, and exits 1. It will do that on
every run forever.

`build-unless-proven.sh` discards that with `|| true`, which is right in intent
(#235: a push failure must not fail a build that passed) and leaves the step
with no signal at all. Measured on 2026-09-16: `PUSH EXIT=1` with **39 of 40**
proofs pushed. Exit 1 with **0 of 40** is indistinguishable. A bad token, a
Cachix outage or a quota refusal would be invisible.

That is AGENTS.md §4 in a new shape — a step whose failure is guaranteed and
discarded is not reporting anything.

## Proposed outcome

- A job that is killed part-way still leaves behind proofs for everything it
  proved. The step becomes a ratchet: every run ends at least as far along as
  it started, so no single kill can compound into a deadlock.
- An evicted proof is put back by the nightly, the night it goes missing,
  without anyone noticing it was gone.
- The proof push's exit status means something: refused-by-policy and
  failed-to-push are different outcomes, so a real failure is visible and the
  nightly can fail loudly on one.
- Together: the next eviction is a quiet night, not a day of manual recovery.

## Affected users and systems

- `.github/scripts/cachix-push.sh` — the refusal/failure distinction.
- `.github/scripts/build-unless-proven.sh` — where the push happens relative to
  the build, and what it does with the status.
- `.github/workflows/nightly.yml` — the `cache`/`repush` pair gains the proofs.
  **This is a CI-gate change (AGENTS.md §11): proposed here, merged by a
  human.**
- Possibly `.github/scripts/already-proven.sh`, which already contains the
  probe the nightly needs — it prints exactly the names that are missing.
- No user-visible change. Nothing here ships to a machine.

## Constraints

- **A push failure must still not fail a build that passed** (#235). Making the
  status meaningful must not make it fatal in the job.
- **Nothing large goes into the cache.** The 5 GB tier is why #725 happened;
  `cachix-push.sh`'s size and path-count refusal stays exactly as strict.
- **`checks.nixi` keeps asserting the whole package.** It is cheap to build and
  catches a broken pin before a user's rebuild does. It is not the problem.
- The nightly must not go red on a check that is legitimately unproofable.
- AGENTS.md §1 applies to all three: each fix needs a check that has been
  watched failing, and the kill case has to be provoked, not assumed.

## Decisions (approved by @olafkfreund, 2026-09-16)

1. **Push in batches of 5.** Per-check is the purest ratchet, but today's 39
   pushes were several minutes of almost pure `cachix` process startup. A batch
   of 5 loses at most 4 proofs to a kill, against a build step that takes tens
   of minutes -- so the ratchet still bites, at a fifth of the process overhead.
2. **The nightly rebuilds what is missing**, following `repush`'s existing
   shape, rather than assuming a warm store still holds the result. It works
   from nothing, which is the state that matters: the night after an eviction.
3. **`checks.nixi` is left alone.** It stays the whole package, because it is
   cheap to build and catches a broken pin before a user's rebuild does. The
   script learns that an unproofable check is a category, not an error; the
   check does not change. A marker output for it may be worth doing later and
   is not part of this.

## Open questions

None. The three above are settled.
