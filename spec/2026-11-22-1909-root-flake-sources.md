---
status: draft
issue: 1909
intent: intent/2026-11-22-1909-root-flake-sources.md
---

# Spec: a self-hosted job keeps its own flake source alive through the host's auto-GC

## Design

A new script, `.github/scripts/root-flake.sh <dir>`:

1. It runs `nix flake archive --json .`. That copies the flake and every input into the store, and prints the tree of their store paths (`.path`, `.inputs.<name>.path`, recursively). Its output is captured first (`out=$(…) || die`), never through a process substitution (CLAUDE.md §4, the `mapfile < <(cmd)` trap).
2. It collects every `path` in that tree with `jq` (`[.. | objects | .path? // empty] | unique`).
3. It refuses with a message if the list has fewer than two entries: a flake with no inputs is not this repo, and an empty list must not read as done.
4. It runs `nix-store --add-root <dir>/<n> --realise <path>` for each entry, which makes an indirect root through a symlink in `<dir>`. That is allowed for an unprivileged runner user through the daemon, and dies with the runner's temp directory.
5. It prints how many paths it rooted.

Each self-hosted job in `nightly.yml`, `omarchy-edge.yml`, `weekly.yml` and `release.yml` gains one step right after its checkout:

```yaml
- name: Root this flake's source and inputs for the job (#1909)
  run: nix shell --inputs-from . nixpkgs#jq -c .github/scripts/root-flake.sh "$RUNNER_TEMP/flake-roots"
```

There are 11 such jobs: nightly's install, install-encrypted, keyboard-boot, microvm, install-iso-net, repush and digest; omarchy-edge's verify; weekly's install-stock-iso and stable-session; and release's iso.

A new `checks.root-flake` (cheap `runCommand`) runs the script against a stub `nix` that prints a fixture archive tree (a source with nested inputs) and a stub `nix-store` that records its arguments. It asserts:

- every path in the fixture, nested inputs included, is rooted exactly once;
- a failing `nix flake archive` fails the script, with nothing rooted;
- an archive with no inputs is refused.

It is not on the `claimed` list, so the generated step runs it on every PR (§4).

## Alternatives rejected

- **Lowering or disabling p620's auto-GC (`min-free`).** That is the host's policy, and it lives in the config repo, which agents do not edit. It is also the reason the store stays usable at all. The PR names it as the owner's call.
- **Rooting only in `cache-entries.sh repush`, where it failed.** That fixes one job and leaves ten others exposed to the same race; the next one would fail on an unrelated line.
- **`--out-link` on each build.** That roots outputs after a build, not the source an evaluation reads while it runs, which is the path that was lost.
- **A composite action.** That adds a file type and an indirection for a one-line step.

## Risks

- A job that edits `flake.lock` after the step (none of the 11 do before building; edge's `main-pin` job does, but runs hosted) evaluates inputs that are not rooted. It is no worse off than today.
- `nix shell --inputs-from . nixpkgs#jq` fetches the flake once before the roots exist. The window is seconds, against the 45-minute one that failed.
- The step costs one flake archive per job, which is seconds on a warm store.

## Verification

- `checks.root-flake` passes, and fails each way when broken (§1). The breaks: keep only the top-level `.path`; read the archive through `< <(…)`; drop the fewer-than-two refusal.
- `actionlint` and the workflow checks the generated set covers pass.
- On p620, the script run by hand against this tree roots the source and every input, shown by `nix-store --gc --print-roots` on the source path.
- Not verifiable locally: a real auto-GC during a job. The nightly is the confirmation, and #1909 stays open until a nightly runs green with the step.
