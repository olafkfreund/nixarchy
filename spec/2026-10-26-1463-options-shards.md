---
status: draft
issue: 1463
intent: intent/2026-10-26-1463-options-shards.md
---

# Spec: checks.options runs as parallel shards

Line numbers are against `main` before #1466. They are re-read after #1466
lands, because it edits this file.

## Design

### Cut along fixture families, not by hashing case names

`cases = { ... }` (`tests/options.nix:621-2323`, 174 entries, each
`{ on; off; }`) becomes seven top-level bindings at its existing section
headers, at the same indent so that nixfmt reindents nothing:

| binding | lines | theme | shard |
|---|---|---|---|
| `casesA` | 622-745 | flake inputs, command-not-found | system |
| `casesB` | 746-1088 | MCP, skills, ai-mirror, nixd, Neovim | home |
| `casesC` | 1089-1209 | /etc overlay | system |
| `casesD` | 1210-1790 | nixi, plugins (#766) | home |
| `casesE` | 1791-2002 | free-space floor, loader set | system |
| `casesF` | 2003-2172 | microvm | microvm |
| `casesG` | 2173-2322 | cuda, weights, webui, the rest | system |

```nix
caseRegions = [ casesA casesB casesC casesD casesE casesF casesG ];
shards = {
  system = [ casesA casesC casesE casesG ];
  home = [ casesB casesD ];
  microvm = [ casesF ];
};
```

**Why not hash names into N buckets.** #747 measured where the memory goes:
live memory is set by fixtures reachable at once, about ten deeply-forced
"system-equivalents" (the microvm group, `loaderOff`, `notImported`, the vm
toplevel) plus about forty shallow shared fixtures. Hashing names would put
the shared fixtures into every shard. Themed regions keep each family in one
shard.

### Each case shard checks its own options both ways

`brokenOf cs` and `reportOf cs` are the code at `:3398-3404`, taking the
cases as a parameter. Shard `s` is a `runCommand "nixarchy-options-${s}"`
with `report = reportOf cs`. It prints the report, and fails with today's
message (`:6490`) if `brokenOf cs != { }`.

Gates move with their fixtures:

- `microvmProblems` (`:3662`) goes to `microvm`;
- the top-level `assert` (`:3405-3410`) goes to `system`.

### `options-files` is today's runCommand without the cases

It is the runCommand from `:3411` with `report` removed and the
`broken == { }` branch made unconditional. The flatpak and service gates stay
in it. stdenv's `set -eu` and `coverage.py`'s `os.environ[...]` make a
section that loses its attribute fail loudly.

**Phase 2, only if measurement shows `files` is still heavy:** split it at
the first `$vm` section (around `:4081`).

### The guard: `checks.options-shards`, names only, seconds

It fails when:

- the sorted case names of all regions differ from those assigned to shards
  (it names each side);
- a case is assigned twice;
- a region is bound but assigned nowhere. `deadnix --fail` catches this.

It stays unclaimed, so the generated step builds it on every PR.

### Wiring

- **`tests/options.nix` returns `{ system, home, microvm, files, shards }`.**
  `flake.nix` maps it into `options-<name>` checks. The literal
  `import ./tests/options.nix` stays, for `test-registration`.
- **`generated-checks.sh`:** the claimed list swaps `options` for the four
  case and file shards, so the hosted edge and `omarchy` jobs do not build
  them.
- **`build.yml`: a new job, `options`,** a matrix over the four installables,
  each written out in full (the claim guard greps literal names):
  - `fail-fast: false`, and the concurrency group includes the shard;
  - the `/usr/bin/time` wrapper (live heap, the 14,336 MiB warning), with the
    prefix `options-<shard>:`;
  - hypr-rdp's prebuild is gone with #1466;
  - disk cleanup only for the `files` leg, as matrix data;
  - the two options steps leave `system-checks`;
  - the `system` aggregator adds `options` to `needs:` and to its result
    loop. A matrix job's result is failure if any leg fails.
- **`omarchy-edge.yml:467`:** its literal check list takes the `options-*`
  names from `nix eval`.
- **Docs:**
  - `AGENTS.md` §6 rows (`:558`, `:735`);
  - `tests/AGENTS.md:262-275`;
  - `copilot-setup-steps.yml:40`;
  - `edge-build.sh:24`;
  - the stale "one configuration measured 10.6 GB" comment
    (`tests/options.nix:101-104`, `AGENTS.md:1075-1078`). #747 measured one
    configuration at about 1.7 GB; 10.6 GB was the whole check.

## Alternatives rejected

- **Hash case names into N shards:** every shard pays the shared fixtures.
- **Run `options-files` inside `system-build`, where `vm` is already
  built:** `system-build` is the longest job already. With #1461, `files`
  downloads what the bump branch pushed.

## Risks

- **Shared fixtures are evaluated in each shard that forces them.** That is
  the cost of parallelism, and the measurement says how much.
- **`files` still pays for the `vm` closure on a cold bump.** #1461's push
  makes every later run warm.

## Verification

- **The guard, locally:** three §1 breaks (a region dropped from a shard, a
  case in two regions, a region assigned nowhere), each shown landed by
  `git diff`.
- **Coverage:** the sorted union of the shards' `name: on=… off=` lines
  equals the 174 lines of job 121519966539's log.
- **Each leg, on a throwaway draft PR:** one case broken per case shard and
  one file assertion broken in `files`. Exactly those legs go red, and
  `system` goes red.
- **Per-shard memory,** while CI is idle: cgroup anon, `/usr/bin/time`, live
  heap, wall time. Any shard above about 8 GB is rebalanced.
