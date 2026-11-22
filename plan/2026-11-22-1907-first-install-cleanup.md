---
status: draft
issue: 1907
spec: spec/2026-11-22-1907-first-install-cleanup.md
coders:
  1: claude  # three-line substitution in a file the session already holds; a handoff would cost more than it saves
  2: claude  # small check whose extraction needs the exact upstream text in view
reviewers:
  - codex  # second reading of the guard's set -e and quoting behaviour
  - agy    # second reading of whether the fixture can vary the ownership test
---

# Plan: first-install cleanup deletes only pristine launchers

Decisions carried from the spec: patch only where the pin ships the loop line;
compare content in bash, not `cmp`; the check's fixture includes a symlink to a
byte-identical launcher, the case a content test alone would delete (#1304); a pin
without the cleanup reports skipped, and a present but uncut loop fails.

## Steps

1. `pkgs/omarchy/quattro-user-files.sh` (append): under
   `grep -qF '"$OMARCHY_PATH"/applications/*.desktop; do'` (the loop, so
   `--replace-fail` still catches a reworded delete), substitute
   `rm -f ~/.local/share/applications/"${launcher##*/}"`
   that line with `seeded=…` and
   `if [[ -f $seeded && ! -L $seeded && "$(<"$seeded")" == "$(<"$launcher")" ]]; then rm -f "$seeded"; fi`.
   → verify by building `.#omarchy` and grepping the built script for `! -L $seeded`.
   Traps: `''${` in Nix strings does not apply (this is a plain `.sh` file); the
   installPhase size budget (`checks.install-phase-budget`) is why it lives here.
2. `tests/first-install-launchers.nix` (new) and its name in `flake.nix`'s check
   list, after `firmware-guard`. It also fails on any `rm` into
   `.local/share/applications` left in the built script, and bounds the cut-out
   block (ends in `fi`, at most eight lines, `bash -n`). → verify by `nix build .#checks.x86_64-linux.first-install-launchers`.
   Traps: §5, the new file must be `git add`ed before evaluation; run `nix fmt`
   and read `git diff --stat` (the editor hook reformats with nixpkgs-fmt).

## Tests

- Break proof (§1): build with step 1 reverted; the check must fail naming the
  identical Home Manager link and the edited copy.
- All generated checks under the carry pin, main's v4.5.0 tag and efcf615.

## Review

Codex (gpt-6.2-sol) and agy (model not reported), read-only, on the drafts and
diff. Confirmed and taken: the gate on the exact delete line made `--replace-fail`
unable to fail (agy); a renamed loop would read as skipped (Codex, agy); a stray
`fi` match would widen the extracted block (agy); the intent named one upstream
caller of two (agy). Confirmed and kept as a stated risk: bash's comparison drops
trailing newlines and NULs (Codex), and a symlinked applications directory
(agy). Refuted: an unreadable launcher matching an empty one, since a shipped
launcher is never empty.

## Rollback

Revert the two commits; the cleanup returns to upstream's unconditional delete.
