---
status: approved
issue: 727
intent: intent/2026-09-16-727-proof-push-ratchets.md
---

# Spec: the proof push neither ratchets nor reports

Closes #727, #728, #729.

Carrying the approved decisions: **batches of 5**, the nightly **rebuilds** what
is missing, and **`checks.nixi` is left alone** — the script learns that an
unproofable check is a category rather than an error.

## Design

### 1. `cachix-push.sh --proof` separates refusal from failure (#729)

Today every non-push sets `fail=1`, so the script exits 1 forever because one
entry can never be proofed. Three outcomes, not two:

| outcome | meaning | counts as |
|---|---|---|
| pushed | the proof is in the cache | success |
| **skipped — unproofable** | result is >1 path or over `proof_max_bytes`; the check is a package build, not a marker-producing test (`checks.nixi`) | **not a failure** |
| **skipped — no result** | under `--keep-going` a failed check produces no output; the build's exit status already reports that | **not a failure** |
| failed | `cachix push` itself returned non-zero | failure |

`exit 1` only when the last row is non-empty. The step ends with one summary
line so the log says what happened rather than leaving it to be inferred:

```
proofs: 39 pushed, 1 skipped (unproofable), 0 failed
```

The size and path-count thresholds do not move. Refusing a 567 MB "proof" is
correct and is what #725 was about; this changes how the refusal is *reported*,
not whether it happens.

### 2. `build-unless-proven.sh` builds and pushes in batches (#727)

Today: one `nix build` over everything, then one push. A job killed mid-build
pushes nothing.

```sh
batch=${PROOF_BATCH:-5}
# for each slice of `batch` names:
nix build --keep-going --no-link --print-build-logs <slice>   || rc=$?
"$here/cachix-push.sh" --proof <slice>                        || true
```

`rc` keeps the worst status across slices, so the job's verdict is unchanged —
the exit status is still the build's, never the push's (#235).

`PROOF_BATCH` is an environment variable with a default of 5, so the size can
be tuned from a workflow without another PR if the measurement below says so.

**The cost, stated plainly.** Splitting one `nix build` into N invocations
means N evaluations instead of one, and evaluation is not free here —
`already-proven.sh` spends about eight minutes doing 43 of them in CI. Eight
slices of five could therefore add minutes to a step whose 45-minute limit is
already the thing that killed `fix/701`. This is the main risk in the change
and is why the batch size is tunable rather than baked.

It is also why the decision was 5 rather than 1: per-check pushing is the
purest ratchet and the worst case for evaluation overhead.

### 3. The generated check list moves into a script (#728's prerequisite)

`build.yml` derives the omarchy job's targets from the flake, with `claimed` as
an opt-OUT list, and the header says why:

> This list is the opt-OUT. Everything not on it is built by the next step,
> which derives its targets from the flake — so adding a check now runs it,
> with no YAML to write and nothing to forget.

The nightly needs the same set. Writing it out a second time is the failure
AGENTS.md §4 names — *a hand-maintained list fails OPEN* — found three times in
one day in this repo. So the derivation moves to
`.github/scripts/generated-checks.sh`, which prints the names no other job
claims, and both `build.yml` and `nightly.yml` call it.

`claimed` stays where it is, with its comment; the script reads it rather than
owning it, so the existing two-directional coverage gate keeps working
unchanged.

### 4. The nightly keeps the proofs alive (#728)

Following the existing `cache` → `repush` shape exactly:

- **`cache` job** gains a step, `main` only, for the same reason the entries
  probe is main-only: a path evaluated on a branch is a different path, and
  probing it 404s by construction (#473 was filed against a cache that was
  serving `main` correctly the whole time). It runs `already-proven.sh` over
  `generated-checks.sh`'s output and publishes the missing names as
  `proofs-missing`.
- **`repush` job** gains a step, guarded on `proofs-missing != ''`, running
  `build-unless-proven.sh` over those names on the self-hosted runner. That
  rebuilds and pushes in one call, which is decision 2 — it works from nothing,
  which is the state the night after an eviction.
- `cachix` comes through `nix shell --inputs-from . nixpkgs#cachix` exactly as
  the entries repush does: a step's PATH on the self-hosted runners carries
  neither `cachix` nor `curl` (AGENTS.md §4).

With §1 in place, `checks.nixi` being unproofable no longer turns the nightly
red, so no exclusion list is needed and none is added.

## Alternatives rejected

- **Push per check (batch of 1).** The purest ratchet and the worst evaluation
  overhead; rejected as decision 1 of the approved intent.
- **Keep one `nix build` and push from a background watcher.** Clever, and it
  would preserve full parallelism — but it means tracking build completion out
  of band, and a wrapper that is hard to reason about is how `--keep-going` got
  silently dropped once before.
- **Give `checks.nixi` a marker output.** Removes the special case at source
  and is probably right eventually, but it is an upstream change in a different
  repository and was explicitly deferred (decision 3).
- **A second check list in `nightly.yml`.** AGENTS.md §4. The whole reason
  `claimed` is an opt-out is so nobody maintains a list of what to run.
- **Make the push status fatal in the job.** Violates #235 — a push failure
  must not fail a build that passed. §1 makes the status *meaningful*; the
  nightly is where it is allowed to be loud.

## Risks

- **Evaluation overhead may cost more than the ratchet buys.** Eight extra
  evaluations in a step with a 45-minute limit, on a job that has already been
  killed by that limit. Mitigated by `PROOF_BATCH` and by measuring before and
  after on the same commit; if the step gets materially slower the batch size
  goes up, and the finding belongs in the PR either way.
- **Extracting the check list touches the coverage gate's input.** If
  `generated-checks.sh` disagrees with what `build.yml` used to generate, some
  check silently stops running — exactly what the gate exists to catch. The
  verification below compares the two lists explicitly rather than trusting the
  refactor.
- **`nightly.yml` is a CI gate** (AGENTS.md §11): proposed on this branch,
  merged by a human. The `repush` job also runs on `[self-hosted, nixos, kvm,
  big]`, so a nightly that rebuilds many checks competes with install jobs on
  p620 (§6) — it is already bounded by `timeout-minutes: 60`.
- **A quieter failure.** Making unproofable results non-fatal means a check
  that becomes unproofable by accident — someone changes a check's output shape
  — no longer shows up as an error. The summary line names the count, and the
  verification asserts the *reason* is reported, not merely that the exit
  status is 0.

## Verification

All three need a check watched failing (AGENTS.md §1), and the kill has to be
provoked rather than assumed.

The harness already exists: `tests/cache-budget.nix` and `tests/cache-entries.nix`
run the real scripts against stubbed `nix`, `curl` and `cachix`. Extending
`tests/cache-entries.nix` keeps this out of a new `checks.*` entry, which would
need a workflow edit and maintainer sign-off under §4 — the nightly change needs
that anyway, but the tests should not.

1. **The ratchet (#727).** Drive `build-unless-proven.sh` with a stubbed `nix`
   that succeeds for the first slice and then hangs, kill it, and assert the
   cache stub received the first slice's proofs. Under today's code that count
   is **zero**; that zero is the failing output for the PR.
2. **Refusal versus failure (#729).** Run `cachix-push.sh --proof` over a list
   of proofable stubs and assert exit 0 — today it is 0 only if nothing is
   unproofable. Add an oversized result and assert exit **0** with the summary
   naming one skipped. Then make the `cachix` stub fail and assert exit **1**.
   Today the second and third cases are indistinguishable, which is the point.
3. **The keep-alive (#728).** With a stub cache missing one proof, assert the
   probe names it and that the repush step is invoked with that name. The
   existing `cache-entries.nix` stubs (`PUSH_WORKS`, `served/`, `calls/`) are
   the shape to copy.
4. **The list refactor.** Assert `generated-checks.sh` prints exactly what the
   inline derivation printed on the same commit — compare, do not eyeball.
5. **Measurement, in one tree** (AGENTS.md §5 — never across commits): time the
   omarchy step before and after on the same checkout, and put both numbers in
   the PR. If batching costs more than a couple of minutes, say so and raise
   `PROOF_BATCH`.

Not attempted: a real eviction against the live cache. It cannot be staged
without damaging the shared tier, and the stubs reach the logic that matters.
