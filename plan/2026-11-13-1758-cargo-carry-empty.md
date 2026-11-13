---
status: draft
issue: 1758
spec: spec/2026-11-13-1758-cargo-carry-empty.md
coders:
  1: codex # small, exact edits to the carry and its test fixtures
  2: codex # the review loop's failure path is the tricky part
reviewers:
  - codex # reads the diff natively
  - agy   # second, independent read
---

# Plan: empty the cargo carry now nixpkgs carries both fixes

Approved decisions: `needs` becomes an argument defaulting to `{ }` and the
codex/omp rows leave `pkgs/cargo-system-libs.nix`; consumers are untouched
(all read `carried.<name> or pkgs.<name>`; home.nix only under `needed`); the
test passes the two former rows as fixture `needs` and gains case H for the
empty default; `review.sh` loops over the status's keys and reports an
unreadable status once; `pkgs/AGENTS.md` is updated; no workflow edit.

## Steps

1. `pkgs/cargo-system-libs.nix` lines 1-19: signature `{ lib, prev, needs ? { } }:`,
   delete the `needs = { codex = [...]; omp = [...]; };` binding (keep the
   `# Why:` pointer and a one-line comment that a row is `<pname> = [ libs ];`
   with the upstream commit). `tests/cargo-system-libs.nix`: a `fixtureNeeds`
   binding with the two former rows, passed by `run`
   (`carry { inherit lib prev; needs = fixtureNeeds; }`); add case H:
   `carry { inherit lib; prev = mkPrev { hook = withHook; }; }` has
   `status == { }` and `packages == { }`.
   → verify: `checks.cargo-system-libs` passes; break the default back to the
   old rows (H fails), and empty `fixtureNeeds` (A fails).
   Traps: `builtins.tryEval` cannot catch a missing attribute (§5); `git add`
   before evaluating (§5).
2. `pkgs/review.sh` lines ~517-524: replace `for n in codex omp` with the
   status's keys: `names=$(jq -r 'keys[]' <<<"$carry")`; when `carry` is empty
   (evaluation failed) or not an object, call `carry_row "cargo carry" ""` once.
   Use `out=$(cmd) || ...`, not `mapfile < <(...)` (§4, §5).
   → verify: `checks.review-pins`, `checks.grep-q-pipefail`; `nix run
   .#review` shows no `cargo carry` row; with the carry file made to throw,
   one "carry status unread" row.
3. `pkgs/AGENTS.md` `#cargo-system-libs-1722`: "Add a row" drops the review
   loop instruction; "Drop a row" says an empty table is the resting state and
   the `carry` CI job then reports nothing needed.
   → verify: `checks.docs`-tier cheap checks.
4. Every `generated-checks.sh` target and `vm-toplevel`, `reference-toplevel`,
   `stable-eval`, by tier.

## Tests

As above; statix, deadnix, `nix fmt -- --ci`.

## Rollback

Revert: the rows return as the default and the loop as a fixed list.
