---
status: approved
issue: 1758
intent: intent/2026-11-13-1758-cargo-carry-empty.md
---

# Spec: empty the cargo carry now nixpkgs carries both fixes

## Design

1. **`pkgs/cargo-system-libs.nix`**: `needs` becomes an argument,
   `{ lib, prev, needs ? { } }`, and the codex and omp rows leave the file.
   Every consumer already reads `carried.<name> or pkgs.<name>`, and
   `modules/home.nix` reads `carry.packages.codex-acp` only when
   `status.codex == "needed"` (a lazy `let` binding), so all of them fall back
   to nixpkgs with no edit.
2. **`tests/cargo-system-libs.nix`**: `run` passes the two former rows as
   fixture `needs`, so cases A-G keep exercising the mechanism unchanged. A new
   case H checks the shipped resting state against real nixpkgs:
   `carry { inherit lib; prev = pkgs // { path = withHook; }; }` has
   `status == { }` and `packages == { }`. Real `pkgs` holds every package a
   future default row could name, so H fails on any non-empty default (a
   stand-in `prev` would hide rows for packages it lacks). Adding a row
   therefore updates H, and `pkgs/AGENTS.md` says so.
3. **`pkgs/review.sh`**: a pure `--carry-rows <json>` mode, next to
   `--carry-row`, turns a status into rows. An object prints one `carry_row`
   per key (`if type == "object" then keys[] else error end`); `{}` prints
   nothing; empty input, a non-object or unparseable JSON prints one
   `finding "cargo carry" "-" "-" "carry status unread"` (not through
   `carry_row`, whose prefix would double the name). The live block calls it
   with the evaluated status (empty when evaluation fails). Guard empty input
   explicitly: `jq 'keys[]' <<<""` exits 0 with no output.
   `tests/review-pins.nix` covers `{}` (no output), `""`, `[]` and `garbage`
   (one unread row each), and `{"codex":"dead","omp":"needed"}` (both rows).
4. **`pkgs/AGENTS.md#cargo-system-libs-1722`**: the opening says the file is
   the mechanism and is empty since 2026-11-13 (both fixes in nixpkgs), naming
   the two former rows as history; "Add a row" drops the review-loop step and
   says to update case H; "Drop a row" drops the loop step and the claim that
   dropping codex removes codex-acp and the nixi wrapper (both stay, dormant
   behind `status.codex == "needed"`); "Full retirement" stays optional, adds
   `build.yml`'s `carry` job (a required check: the owner's to change, §11),
   and is not triggered by an empty table.

## Alternatives rejected

- **Full retirement now.** Deletes `build.yml`'s required `carry` job, which is
  a CI-gate change for the owner (§11), and four consumer sites, for a
  mechanism the next nixpkgs regression may need again.
- **Delete the rows and leave the test.** Cases A-G assert codex is carried;
  they would fail, or be rewritten into something that cannot fail.

## Risks

- A consumer that reads a carried package without `or`: none exist (grepped:
  `modules/apps.nix` twice, `modules/microvm/templates/agent-claude.nix`,
  `modules/home.nix`). Evaluation of `vm-toplevel` and `reference-toplevel`
  proves it.

## Verification

- `checks.cargo-system-libs` passes; breaks: a default row (`ripgrep = [
  "zstd" ];`) fails case H; the fixture `needs` emptied fails case A.
- `checks.review-pins` passes; breaks: `--carry-rows` enumerating nothing
  fails the populated case; dropping the empty-input guard fails the `""`
  case. `nix run .#review` prints no `cargo carry` rows.
- `vm-toplevel`, `reference-toplevel`, `stable-eval` and every
  `generated-checks.sh` target, by tier.
