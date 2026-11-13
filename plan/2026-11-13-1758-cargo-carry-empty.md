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
test passes the two former rows as fixture `needs`, and a new case H checks
the shipped default against real `pkgs`; `review.sh` gains a pure
`--carry-rows <json>` mode that enumerates an object's keys and reports
empty/non-object input once as `cargo carry`, tested in `review-pins`;
`pkgs/AGENTS.md`'s section is brought up to date; no workflow edit.

## Steps

1. `pkgs/cargo-system-libs.nix` lines 1-19: signature `{ lib, prev, needs ? { } }:`,
   delete the `needs = { codex = [...]; omp = [...]; };` binding (keep the
   `# Why:` pointer and a one-line comment that a row is `<pname> = [ libs ];`
   with the upstream commit). `tests/cargo-system-libs.nix`: a `fixtureNeeds`
   binding with the two former rows (codex: aws-lc oniguruma sqlite zstd;
   omp: oniguruma zstd), passed by `run`
   (`carry { inherit lib prev; needs = fixtureNeeds; }`); add case H to the
   forced `results` list: `carry { inherit lib; prev = pkgs // { path = withHook; }; }`
   has `status == { }` and `packages == { }`.
   → verify: `checks.cargo-system-libs` passes; breaks: default
   `needs ? { ripgrep = [ "zstd" ]; }` fails H; `fixtureNeeds = { }` fails A.
   Traps: `builtins.tryEval` cannot catch a missing attribute (§5); `git add`
   before evaluating (§5).
2. `pkgs/review.sh`: a function `carry_rows` and a `--carry-rows` mode beside
   `--carry-row` (lines ~296-312 and the mode dispatch). Input empty → one
   `finding "cargo carry" "-" "-" "carry status unread"`; else
   `names=$(jq -r 'if type == "object" then keys[] else error("not an object") end' <<<"$1")`
   and on failure the same single finding; else `carry_row "$n" "$st"` per
   name (skip when `names` is empty; no `while read <<<""`). The live block
   (~517-524) becomes `carry_rows "$carry"`. `tests/review-pins.nix` (~372-389):
   cases `{}` (empty output), `""`, `[]`, `garbage` (exactly one unread row),
   and `{"codex":"dead","omp":"needed"}` (both rows).
   Use `out=$(cmd) || ...` (§4, §5).
   → verify: `checks.review-pins`, `checks.grep-q-pipefail`; breaks:
   `carry_rows` enumerating nothing fails the populated case; dropping the
   empty-input guard fails `""`.
3. `pkgs/AGENTS.md` `#cargo-system-libs-1722` (lines ~1507-1540): opening says
   the mechanism is empty since 2026-11-13, the two rows being history; "Add a
   row": drop the review-loop step, add "update case H"; "Drop a row": drop
   the loop step and the codex-acp/nixi-wrapper sentence (they stay, dormant
   behind `status.codex == "needed"`); "Full retirement": optional, not
   triggered by an empty table, and includes `build.yml`'s required `carry`
   job (owner's change, §11).
   → verify: the cheap docs checks.
4. Every `generated-checks.sh` target and `vm-toplevel`, `reference-toplevel`,
   `stable-eval`, by tier.

## Tests

As above; statix, deadnix, `nix fmt -- --ci`.

## Rollback

Revert: the rows return as the default and the loop as a fixed list.
