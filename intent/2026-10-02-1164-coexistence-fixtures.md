---
status: draft
issue: 1164
author: olafkfreund
---

# Intent: nixarchy is tested beside the user configurations it promises to coexist with

## Problem

nixarchy sets options that users commonly set too, and nothing tests the two
together.

- **What the suite covers today:**
  - nixarchy alone (the reference machines);
  - nixarchy *not there* (`modeAInert` in `tests/options.nix`, against a
    module that is not imported);
  - every nixarchy option both ways.
- **What it misses:** "nixarchy on, *and* the user's own settings beside it".
- **What that cost on 2026-10-02:**
  - #1162 changed `hardware.graphics.package`. Any user with their own
    `mesa` in `extraPackages` then failed to build, on a `buildEnv`
    collision in a derivation they never wrote (#1163).
  - The PR described the risk in a paragraph. Nothing could have gone red.
  - It was found on the owner's own machine.
- **How these breaks happen.** nixarchy contributes to options NixOS merges
  into one derivation (`buildEnv` and the like), and a user's contribution
  can collide with ours there. For example:
  - `hardware.graphics.package`/`extraPackages(32)` (#1162/#1163);
  - `environment.systemPackages`: nixarchy adds many, and
    `modules/nixos.nix:1274` already notes that their order reaches
    `buildEnv`;
  - `fonts.packages` (`modules/nixos.nix:1986`).
- **The evaluation-only checks cannot see this.** A file collision appears
  only when the merged environment is built.

## Proposed outcome

1. **A named set of coexistence fixtures:** user configurations nixarchy
   promises to live beside, each a short module. Examples:
   - `extraPackages = [ pkgs.mesa ]`;
   - `enable32Bit` with `driversi686Linux.mesa`;
   - a user's own `hardware.graphics.package`;
   - common `systemPackages` and `fonts.packages` additions that overlap with
     nixarchy's.

   They live where a contributor adding a setting will see them, beside
   `tests/options.nix`'s fixtures.
2. **A check that builds the collision-prone merged environments** for every
   fixture: `graphics-drivers(-32bit)`, `system-path` (`systemPackages`) and
   the fonts environment. It goes red on a collision, naming the fixture and
   the colliding paths. It must be cheap: those environments are mostly links
   to substitutable paths.
3. **A coexistence section in the spec template.** Whenever a change makes
   nixarchy set an option users commonly set too, the spec names each
   collision mode: priority, list merge, file collision, package swap. The
   answer is a fixture, a warning or an assertion, never only a sentence in
   the PR.
4. **A changed default for a user-facing option** is announced in the
   release notes and Discussions, with the migration step.

## Affected users and systems

- `tests/`: new fixtures and one new check; `tests/AGENTS.md` (what it covers
  and what it cannot).
- The artifact workflow's spec template: the `artifact-workflow` skill, and
  wherever this repo keeps its own copy, if any.
- `docs/AGENTS.md` or `CONTRIBUTING.md`, for the release-note rule.
- **No change to what nixarchy installs.** Only checks and process.

## Constraints

- **Cheap enough for every pull request.** Builds that only link substitutable
  paths count; anything compiling, or downloading gigabytes per run, does not
  (§6, and #697's cache budget).
- **The fixtures must be shown to fail (§1).** Re-introducing #1163's
  collision with the #1163 assertion removed must go red in the new check.
  Other fixtures must each be shown able to fail where that is feasible.
- **Fixtures describe *users*, not nixarchy:** plain NixOS settings, no
  nixarchy options.
- **The owner's real host configs are not imported or built from here.**
  They live in another repository, and are changed elsewhere.

## Open questions

1. **How large is the first fixture set?** The proposal is to start with the
   graphics fixtures (proven by #1163) plus one `systemPackages` and one
   `fonts.packages` overlap, and to add a fixture with every future
   coexistence bug, as a check, not a list to remember.
2. **Where does the spec-template rule live?** The template is in the
   `artifact-workflow` skill, outside this repo. Options:
   - this repo's own `CONTRIBUTING.md`/`AGENTS.md`, which agents here read;
   - a request to whoever owns the skill;
   - both.

   The proposal is AGENTS.md here, as a numbered rule appended at the end
   (never inserted, which would renumber §1–§13).
3. **Building `system-path`** for a fixture may cost more than a link farm
   when nixarchy's package set is not yet in the cache. Should that build
   wait for the `system` job, which already builds the closure, rather than
   being a separate cheap check?
