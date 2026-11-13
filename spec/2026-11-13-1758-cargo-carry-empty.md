---
status: draft
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
   case H calls the carry with no `needs` and asserts `status == { }` and
   `packages == { }` (the shipped default).
3. **`pkgs/review.sh`**: the `for n in codex omp` loop iterates the status's
   own keys (`jq -r 'keys[]'`), so an empty carry prints no rows and a new row
   needs no review edit. A failed evaluation still prints the existing
   "carry status unread" finding, once, under the name `cargo carry`.
4. **`pkgs/AGENTS.md#cargo-system-libs-1722`**: "Add a row" no longer says to
   edit the review's loop; "Drop a row" notes that an empty table is the
   resting state, and "Full retirement" stays as written for whoever chooses it.

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

- `checks.cargo-system-libs` passes; breaks: default `needs` back to the old
  rows fails case H; the fixture `needs` emptied fails case A.
- `checks.review-pins` passes; `nix run .#review` prints no `cargo carry` rows
  (break: make the carry's evaluation fail and see "carry status unread").
- `vm-toplevel`, `reference-toplevel`, `stable-eval` and every
  `generated-checks.sh` target, by tier.
