---
status: approved
issue: 997
spec: spec/2026-09-27-997-install-phase-headroom.md
---

# Plan: move the ten largest explanations out of the install phase

Self-contained. The spec and intent do not need opening.

## The approved decisions, carried over

- **Prose moves, not shell.** 54% of the phase is comments (73,052 of 132,868
  bytes) and the largest single paragraph is 4,256 bytes. There is no big
  block to extract; there is a lot of explanation.
- **To `pkgs/AGENTS.md`, with a `# Why: pkgs/AGENTS.md#<anchor>` pointer.**
  Root `AGENTS.md` §7's rule, already used five times in `modules/home.nix`
  and `pkgs/skills-relink.nix`.
- **Four lines or more moves; one to three stays** at the line it protects.
- **Nothing is deleted.** Removed from one file, added to the other, in the
  same commit.
- **Verification is `diff -r` on the built outputs, not `drvPath`.** Moving
  text out of the phase changes the phase, so the derivation hash must change;
  a match would mean the edit had not landed. An empty `diff -r` proves the
  package is bit-identical.
- **Tranches, each its own commit and its own comparison.** A rewrite that
  changes output for several reasons at once cannot be diagnosed.

## The two open questions, answered

- **Scope this pass: the ten largest paragraphs**, ~27 KB, which is
  reviewable and takes headroom from 2.1 KB to roughly 29 KB. Applying the
  four-line rule exhaustively would reclaim most of 73 KB and produce a diff
  nobody can read; it is follow-up work if anyone wants it.
- **The budget check goes in its own pull request.** It is a new check with
  its own break-it-and-watch-it-fail obligation, and bundling it makes one PR
  two reviews.

## The baseline, measured before any edit

```
installPhase bytes: 127703
total env bytes:    128891  (MAX_ARG_STRLEN 131072)
headroom:           2181
```

The ten paragraphs, by first line, all inside `installPhase` (lines 407-2276
of `pkgs/omarchy/default.nix`):

| lines | bytes | opens with |
|---|---|---|
| 1134-1198 | 4256 | the menu is parsed at runtime |
| 1278-1293 | 3411 | `substituteInPlace $skills/diagnose-crash/reporting.md` |
| 1385-1432 | 3321 | nothing may sed /etc/pam.d |
| 1616-1650 | 2505 | enable-user-units.sh enables six user units |
| 2248-2273 | 2493 | the default plugins' binds, in the SEED |
| 1962-1994 | 2490 | a keep-loaded plugin lost its shell API |
| 862-895 | 2353 | 1Password's Chromium extension |
| 2199-2230 | 2290 | `shellBin=$out/share/omarchy/bin/omarchy-shell` |
| 1257-1269 | 2242 | the crash skill is upstream's |
| 705-735 | 2241 | RetroArch was configured to look in /usr/share/libretro |

Three of those (1278, 2199, 705) are code with attached comment; only the
comment moves.

## Steps

1. Capture the baseline output path — `nix build --no-link --print-out-paths
   .#omarchy` — and keep it for every comparison → verify it is a store path

2. `pkgs/AGENTS.md`: add the `##` sections the pointers will name, one per
   moved explanation, keeping the issue numbers each already cites → verify
   the anchors are unique

3-7. Five tranches of two paragraphs each, largest first. Per tranche: move
   the prose, leave a `# Why:` pointer, `nix build`, `diff -r` against the
   baseline → verify an empty diff, and commit the tranche alone

8. `nix fmt`, then read `git diff --stat`. A managed editor hook runs
   `nixpkgs-fmt` and this repo uses `nixfmt`; the tell is `nix fmt -- --ci`
   failing once then passing → verify the diff is the size of the change

9. Re-measure the environment and record it in the PR → verify headroom is in
   the tens of kilobytes

10. Rebase on `main` and re-run the comparison. Another agent merged #1026
    into this file's directory during the work → verify the diff is still
    empty after rebasing

## Tests

```sh
nix build --no-link --print-out-paths .#omarchy
diff -r "$before" "$after"
nix fmt -- --ci
nix build .#checks.x86_64-linux.bin-ledger --print-build-logs
nix build .#checks.x86_64-linux.menu-verbs --print-build-logs
```

`gh run list` before each build; every runner is on p620.

**The verification here is unusual and worth stating plainly: there is no new
check to break.** This changes no behaviour, so §1's contract has nothing to
bite on — the claim is *bit-identical output*, and its proof is an empty
`diff -r`. What can be broken, and is:

| break | must show |
|---|---|
| delete a comment instead of moving it | nothing in `diff -r` — which is why the *diff* is read, not just the build |
| move a line of shell along with its comment | a non-empty `diff -r`, on that tranche alone |
| point `# Why:` at an anchor that does not exist | nothing mechanical — a known gap, named in the spec's risks |

The middle row is the one the tranching exists for: it localises any output
change to two paragraphs.

## Rollback

Every tranche is its own commit and touches two files. Revert any one and the
prose returns to the phase; revert all and the tree is byte-identical to
`main`. No user-facing behaviour is involved at any point, which is the whole
claim being proven.
