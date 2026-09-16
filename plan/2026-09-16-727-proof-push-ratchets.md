---
status: approved
issue: 727
spec: spec/2026-09-16-727-proof-push-ratchets.md
---

# Plan: the proof push neither ratchets nor reports

Closes #727, #728, #729.

## The approved decisions, carried over

Self-contained — implementable without opening the intent or spec.

On 2026-09-15 Cachix evicted 31 of 34 check proofs. On 2026-09-16 that became a
day-long outage, because three properties of the proof mechanism compounded:

1. **#727** a killed job pushes nothing. `build-unless-proven.sh` pushes after
   `nix build` returns, so three jobs that died mid-build (14 min, 17 min,
   45m00s) each pushed zero proofs despite having built checks successfully.
2. **#728** nothing keeps proofs alive. The nightly re-pushes evicted
   *allowlist entries* (1622 MiB of content) but not the *proofs* (112 bytes
   each), which are what CI's speed depends on.
3. **#729** the push cannot report failure. `checks.nixi` is the nixi package
   (`flake.nix:1511`), a 92-path 567 MB result, so `cachix-push.sh --proof`
   refuses it and exits 1 on every run forever;
   `build-unless-proven.sh` discards that with `|| true`. Measured:
   `PUSH EXIT=1` with 39 of 40 pushed is indistinguishable from 0 of 40.

Decisions: **batches of 5** (tunable via `PROOF_BATCH`); the nightly
**rebuilds** what is missing rather than assuming a warm store; **`checks.nixi`
is left alone** — the script learns that unproofable is a category, not an
error.

Constraints that do not move: a push failure must never fail a build that
passed (#235); the size and path-count refusal stays exactly as strict (#725);
`nightly.yml` is a CI gate (AGENTS.md §11) — proposed here, merged by a human.

## Steps

1. **`.github/scripts/cachix-push.sh`** — in the `--proof` branch, replace the
   single `fail` counter with three: `pushed`, `skipped`, `failed`. The two
   existing refusals (no built result; more than one path or over
   `proof_max_bytes`) increment `skipped` and keep their `::warning::`; only a
   non-zero `cachix push` increments `failed`. End with one summary line, and
   `exit` non-zero only when `failed` is non-zero.
   → verify: `proofs: N pushed, M skipped (unproofable), K failed` appears, and
   the exit status is 0 for a run whose only non-push is `nixi`.

2. **`.github/scripts/build-unless-proven.sh`** — replace the single
   build-then-push with a loop over slices of `${PROOF_BATCH:-5}`:
   build the slice with the existing flags, then push that slice's proofs.
   `rc` keeps the worst build status across slices; the push stays `|| true`.
   Keep the `--keep-going` and `--no-link` comments with the call they explain,
   since both record a regression that happened when a wrapper moved them.
   → verify: with a stub `nix`, a list of 12 produces three build calls and
   three push calls, in interleaved order.

3. **`.github/scripts/generated-checks.sh`** — new. Prints the check names no
   other job claims, which is what `build.yml`'s omarchy step derives inline
   today. It owns `claimed`, `exempt` and `nightly_only` **with their existing
   comments moved, not summarised** (AGENTS.md §7: long blocks move, they do
   not get deleted), and keeps the two guards that live with them: the
   `tr -s ' \n' ' '` collapse (four checks were silently double-run without
   it) and the implausible-count refusal (`< 20` names means the list is not
   reading the flake — #299 broke exactly this by changing indentation).
   `build.yml`'s step calls the script instead of deriving the list, and its
   two-directional coverage gate keeps reading the same variables from it.
   → verify: step 4 of Tests — the script's output must equal what the inline
   derivation produced on the same commit, compared mechanically.

   **This is the step most likely to do quiet damage.** A disagreement between
   the script and the old inline logic means a check silently stops running,
   which is the failure the coverage gate exists to catch and the reason #164
   was filed. If the comparison in Tests step 4 is not exact, stop and report
   rather than adjusting the expectation.

4. **`.github/workflows/nightly.yml`** — CI gate, §11.
   - `cache` job: a step, `main`-only (`if: github.ref == 'refs/heads/main'`,
     same guard and same reason as the entries probe — a path evaluated on a
     branch is a different path and 404s by construction, which is #473),
     running `already-proven.sh` over `generated-checks.sh`'s output and
     publishing the missing names as the `proofs-missing` output.
   - `repush` job: a step guarded on `needs.cache.outputs.proofs-missing != ''`
     running `build-unless-proven.sh` over those names, with `cachix` supplied
     as `nix shell --inputs-from . nixpkgs#cachix -c …` exactly as the entries
     repush does — a step's PATH on the self-hosted runners carries neither
     `cachix` nor `curl`.
   - **Probe broadly, rebuild narrowly.** The rebuild list is
     `generated-checks.sh`'s output and nothing else: `install-iso` and
     `reinstall-vm` are ~3-hour builds and a keep-alive must never trigger one.
   → verify: step 3 of Tests, against the stub cache.

5. **`tests/cache-entries.nix`** — extend with the four cases in Tests below,
   following its existing stub shape (`stubs/`, `served/`, `calls/`,
   `PUSH_WORKS`). No new `checks.*` entry, so no workflow coverage edit is
   needed for the tests themselves (§4).
   → verify: `nix build .#checks.x86_64-linux.cache-entries`.

6. **Formatting and lint.** `nix fmt -- --ci`, `statix check .`,
   `deadnix --fail .`, and `shellcheck` on all three scripts.
   → verify: all clean. Edit `.nix` files through Bash rather than the Edit
   tool: the local `PostToolUse:Edit` formatter rewrote 204 unrelated lines of
   `modules/home.nix` on 2026-09-16 and the churn had to be reverted.

## Tests

`tests/cache-entries.nix` already runs the real scripts against stubbed `nix`,
`curl` and `cachix`. Each case below starts from a number that is wrong today —
that is the failing output the PR must carry.

```sh
nix build .#checks.x86_64-linux.cache-entries --print-build-logs
```

1. **The ratchet (#727).** Stub `nix` so the first slice succeeds and the
   second hangs; kill the script; assert the push stub received the first
   slice's proofs. **Today that count is zero.**
2. **Refusal versus failure (#729).** Three assertions, because two of them are
   indistinguishable today:
   - all results proofable → exit **0**
   - one oversized result → exit **0**, summary names one skipped
   - `cachix` stub returns non-zero → exit **1**
3. **The keep-alive (#728).** With the stub cache missing one proof, assert the
   probe names it and the repush is invoked with exactly that name — and that a
   `nightly_only` name is never in the rebuild list.
4. **The list refactor.** Compare `generated-checks.sh`'s output against the
   inline derivation **on the same commit**, mechanically:
   ```sh
   diff <(.github/scripts/generated-checks.sh) /tmp/inline-list.txt
   ```
   where `/tmp/inline-list.txt` is captured from the pre-change step before
   step 3 is applied. Any difference is a check that starts or stops running.
5. **Measurement, in one tree** (AGENTS.md §5 — never compare across commits,
   because `flake.outPath` is in the closure and every commit changes every
   derivation): time the omarchy step with `PROOF_BATCH` unset and with it set
   to a large number (one slice, i.e. today's behaviour) on the same checkout.
   Both numbers go in the PR. If slicing costs more than a couple of minutes,
   say so and raise the default rather than hiding it.

Run under **bash**, as a script, not pasted into an interactive shell: zsh does
not word-split unquoted expansions and a verification loop here once reported
PASS for both the working and the broken case for exactly that reason.

Not attempted: a real eviction against the live cache — it cannot be staged
without damaging the shared tier, and the stubs reach the logic that matters.

## Rollback

- **Step 1 or 2 misbehaves** → revert that script alone. Both are
  self-contained; reverting restores today's behaviour, which is working but
  unratcheted.
- **Step 3 disagrees with the old list** → revert step 3 and step 4 together.
  The nightly change depends on the script; the scripts in steps 1-2 do not.
- **The nightly rebuilds too much or competes with install jobs on p620**
  (§6) → revert step 4 only. `timeout-minutes: 60` bounds it meanwhile.
- **Whole change** → `git revert` the implementation commit. Nothing here is
  stateful and nothing is deleted from the cache, so reverting changes only
  what future runs push.
