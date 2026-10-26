---
status: draft
issue: 1463
spec: spec/2026-10-26-1463-options-shards.md
---

# Plan: checks.options runs as parallel shards

Rebase onto `main` after #1466 merges, then re-read every line number below
before editing. #1466 removes the hypr-rdp cases and fixtures from
`tests/options.nix`.

This carries the spec's decisions:

- seven region bindings and three case shards, cut by fixture family;
- `brokenOf` and `reportOf` per shard;
- `options-files` is the runCommand without the cases;
- the `options-shards` guard;
- a matrix job under the `system` aggregator;
- claimed names, the edge loop and the docs.

## Steps

1. **`tests/options.nix`.**
   - Split `cases` into `casesA` through `casesG` at their section headers,
     at the same indent.
   - Add `caseRegions` and `shards`.
   - Turn `broken` and `report` into `brokenOf` and `reportOf`, and build
     `mkCases s cs`.
   - Move `microvmProblems` into `microvm`, and the top-level `assert` into
     `system`.
   - Build `files` from the old runCommand without `report`, and with
     `broken == { }` made unconditional.
   - Add `guard`, the `options-shards` runCommand: names only, the union
     comparison, duplicates.
   - Return `{ system; home; microvm; files; shards = guard; }`.
   - Verify: `nix fmt -- --ci`, statix, deadnix. Then `nix eval` of the
     `options-*` attribute names, under the lock, at the cheap tier.
   - Traps:
     - §5: a heredoc reindents the file. Write files with `printf`.
     - §5: `tryEval` does not catch a missing attribute.
     - Do not evaluate any shard locally while CI is busy (11.5 GB-class).
2. **`flake.nix`.** Delete the `options =` entry (around `:2622`). After
   `// lib.genAttrs uniformChecks`, add the `options-<name>` mapping. Keep the
   literal `import ./tests/options.nix`. Verify by building
   `checks.x86_64-linux.options-shards` (cheap) and
   `checks.x86_64-linux.test-registration`.
3. **§1 proofs for the guard,** each shown landed with `git diff`, red output
   kept:
   - (a) drop `casesF` from `shards.microvm`;
   - (b) copy one case into a second region;
   - (c) remove `casesF` from both lists, so deadnix fails.
4. **CI and docs.**
   - `generated-checks.sh`: in the claimed list, `options` becomes
     `options-system options-home options-microvm options-files`.
   - `build.yml`:
     - the new `options` job (matrix, `fail-fast: false`, the concurrency
       group includes the shard, the `/usr/bin/time` wrapper with the
       `options-<shard>:` prefix, disk cleanup for `files` only);
     - delete the two options steps from `system-checks`;
     - add `options` to the aggregator's `needs:` and to its result loop.
   - `omarchy-edge.yml:467`: derive the `options-*` names from `nix eval`.
   - Docs:
     - `AGENTS.md` §6 rows, plus the stale 10.6 GB claim at `:1075-1078`;
     - `tests/AGENTS.md:262-275`;
     - `copilot-setup-steps.yml:40`;
     - `edge-build.sh:24`;
     - `tests/options.nix:101-104`.
   - Verify: actionlint, and the claim guard. This is a §11 change, approved
     by the owner.
5. **§1 per leg, on a throwaway draft PR,** hosted runners only:
   - break one case per case shard, and one file assertion;
   - exactly those legs go red, and `system` goes red;
   - then revert, and close the draft.
6. **Coverage proof:** the sorted union of the new run's `name: on=… off=`
   lines equals job 121519966539's 174 lines, byte for byte.
7. **Measurement,** only when `gh run list --limit 8 --json status -q
   '[.[]|select(.status!="completed")]|length'` prints 0:
   - run each shard's `nix eval --option eval-cache false --raw
     .#checks.x86_64-linux.options-<s>.drvPath` alone, under the lock, in
     `systemd-run --user --scope`;
   - record cgroup anon peak, RSS, live heap (`GC_PRINT_STATS=1`) and wall
     time;
   - rebalance any shard above about 8 GB, or do phase 2 for `files`.

## Tests

- `nix build .#checks.x86_64-linux.{options-shards,test-registration}`
- actionlint
- the CI legs, and the coverage diff

## Rollback

Revert the squash commit. That restores `checks.options` and the
`system-checks` steps.

## Who does what

The `coder` agent does steps 1-4. I run steps 3, 5, 6 and 7, commit, and
review with a fresh Opus agent.
