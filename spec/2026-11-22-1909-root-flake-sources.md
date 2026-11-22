---
status: approved
issue: 1909
intent: intent/2026-11-22-1909-root-flake-sources.md
---

# Spec: a self-hosted job keeps its own flake source alive through the host's auto-GC

## Design

A new script, `.github/scripts/root-flake.sh <dir>`:

1. `mkdir -p <dir>`.
2. It runs `nix flake archive --json .`. That copies the flake and every input into the store and prints the tree of their store paths (`.path`, `.inputs.<name>.path`, recursively). The output is captured first (`out=$(…) || die`), never through a process substitution (CLAUDE.md §4, the `mapfile < <(cmd)` trap).
3. It collects the paths with `jq -r '[recurse(.inputs[]?) | .path? | strings | select(startswith("/nix/store/"))] | unique | .[]'`. This walks only input nodes, so an input *named* `path` is not mistaken for a path (Codex), and it emits raw lines, not a JSON array (agy). It refuses if the top-level `.path` is missing or if fewer than two paths come back: an empty list must not read as done.
4. It roots each path with `nix-store --add-root <dir>/<n> --realise <path>`. That makes an indirect root through a symlink in `<dir>`, which the daemon allows for an unprivileged client.
5. **It verifies the roots.** `nix-store --check-validity` runs on every path, and `nix-store --gc --print-roots` must list each `<dir>/<n>`. A GC already running can delete a path between the archive and `addPermRoot`, leaving a dangling link that exits 0 (Codex). If any path is invalid or unrooted, the script re-runs from step 2, at most three times, then fails and names the path. This check runs inside the real runner, so it also proves the daemon can see `<dir>`, which is the variable a hand run on p620 cannot vary (agy, §3).
6. It prints how many paths it rooted.

`$RUNNER_TEMP` on p620 is `/run/github-runner/<name>/_temp`, the runner unit's `RuntimeDirectory`. That is a host path, visible to the daemon despite the unit's `PrivateTmp` and `PrivateMounts`, and each runner instance has its own. The runner cleans it at job start, not between steps.

Each self-hosted job gains one step right after its checkout:

```yaml
- name: Root this flake's source and inputs for the job (#1909)
  run: nix shell --inputs-from . nixpkgs#jq -c .github/scripts/root-flake.sh "$RUNNER_TEMP/flake-roots"
```

There are 12 such jobs: nightly's install, install-encrypted, keyboard-boot, microvm, install-iso-net, repush and digest; omarchy-edge's verify; weekly's install-stock-iso and stable-session; release's iso; and install-check's install, whose `runs-on` is chosen at run time and lands on p620. On `digest` the step is `continue-on-error: true`, so a rooting failure cannot suppress the failure digest (Codex).

A new `checks.root-flake` (cheap `runCommand`) has two halves:

- **Script.** It runs the script against a stub `nix` that prints a fixture archive tree (a source, inputs, a nested input, and an input named `path`) and a stub `nix-store` that records `--add-root`, requires the root's directory to exist, and answers `--check-validity` and `--print-roots` from what it recorded. It asserts:
  - every fixture path is rooted, and nothing else is;
  - a failing `nix flake archive` fails the script, with nothing rooted;
  - an archive with no inputs is refused;
  - a path the stub reports invalid on the first pass is retried, and a path invalid on every pass fails the script with its name.
- **Coverage.** It parses every `.github/workflows/*.yml` and fails, naming the job, if a job whose `runs-on` is not a literal hosted label (`ubuntu-*`) has an `actions/checkout` step not followed by the root step. A hand list of jobs fails open (§4); this one cannot.

The check is not on the `claimed` list, so the generated step runs it on every PR (§4).

## Alternatives rejected

- **Lowering or disabling p620's auto-GC (`min-free`).** That is the host's policy, and it lives in the config repo, which agents do not edit. It is also the reason the store stays usable at all. The PR names it as the owner's call.
- **Rooting only in `cache-entries.sh repush`, where it failed.** That fixes one job and leaves ten others exposed to the same race; the next one would fail on an unrelated line.
- **`--out-link` on each build.** That roots outputs after a build, not the source an evaluation reads while it runs, which is the path that was lost.
- **Parsing the archive with `nix eval` instead of jq (agy).** That avoids the `nix shell`, but a stubbed check could no longer run the parser without a working nix in the sandbox, and the window it closes is covered by the step failing loudly.
- **A composite action.** That adds a file type and an indirection for a one-line step.

## Risks

- A job that edits `flake.lock` after the step evaluates inputs that are not rooted. None of the 12 does that before building; edge's `main-pin` job does, but it runs hosted. Such a job is no worse off than today.
- `nix shell --inputs-from . nixpkgs#jq` fetches the flake before the roots exist. A GC in that window fails the step loudly, by name, instead of failing an unrelated build later. The retry covers the window after the archive.
- Out of scope, named here so it is not lost (agy): `--no-link` build outputs between two commands (`cache-entries.sh`'s build then push, nightly `install-iso-net`'s build then size) can also be collected by a concurrent auto-GC. They fail loudly, as a failed push or a missing ISO, not as a wrong answer. Paths fetched during evaluation outside `flake.lock` (IFD, `builtins.fetch*`) are not in the archive either; nixarchy has none known.
- The step costs one flake archive per job, which is seconds on a warm store.

## Verification

- `checks.root-flake` passes, and fails each way when broken (§1). The breaks: go back to the `.. | objects` walk; read the archive through `< <(…)`; drop the fewer-than-two refusal; drop the verify-and-retry; remove the step from one self-hosted job.
- `actionlint` and the generated checks pass.
- On p620, by hand: the script roots all of this tree's paths, `nix-store --delete <source>` refuses while the root exists, and the same delete succeeds once `<dir>` is removed. That proves the root protects the source against collection without running a GC.
- In the real runner: the step's own verification (design step 5) proves the daemon sees the roots. Not verifiable locally: a real auto-GC during a job. `repush` runs only when entries or proofs are missing, so #1909 stays open until a nightly has run that job green with the step, which has to be checked in the run, not assumed (Codex).

## Review

Codex (gpt-6.2-sol) and agy (model not reported) each did one read-only review of this spec's first draft.

- **Confirmed and taken into the design above:**
  - Codex: the GC race between the archive and `addPermRoot`, now caught by the verify-and-retry; the `.. | objects` walk mistaking an input named `path` for a path; a green nightly need not run `repush`; `digest` must not lose its diagnostics.
  - agy: the jq filter printed an array rather than lines; `install-check.yml`'s install job is self-hosted at run time, so a hand-kept job list would fail open; `mkdir -p`; the `--no-link` and IFD gaps, recorded as out of scope.
- **Refuted:** agy's critical finding, that the runner unit's `PrivateTmp`/`PrivateMounts` hide `$RUNNER_TEMP` from the daemon. `systemctl show github-runner-nixarchy-2` puts the work directory at `/run/github-runner/nixarchy-2`, the unit's `RuntimeDirectory`, and its `_temp` is visible from the host namespace. The script's own `--print-roots` check now proves this inside every real job anyway.
- **Considered and not taken:** agy's suggestion to parse with `nix eval` instead of jq (see Alternatives).
