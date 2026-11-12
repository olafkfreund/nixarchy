---
status: draft
issue: 1763
spec: spec/2026-11-12-1763-migration-triage-follows-commands.md
coders:
  1: codex   # the check's new step: small, exact shell and jq logic
  2: agy     # command rows: reading 22 scripts and writing one row each, mechanical
  3: agy     # migration rows: 12 rows and 11 predates entries, mechanical
  4: agy     # docs: the AGENTS.md section and two file headers
reviewers:
  - codex    # reviews the rows agy wrote against the scripts
  - agy      # reviews the check codex wrote
---

# Plan: the user-migration triage follows the commands a migration runs

Lands as an `edge-candidate` carry on top of #1760, after #1760 is promoted,
because the `via` field and the hard-coded command exist only on edge.

Approved decisions, from the spec:

- New `data/user-migration-commands.nix`: a row per `omarchy-*` command a
  migration runs whose own script matches
  `HOME|XDG_CONFIG|\.config|shell\.json`, as
  `{ follow = <bool>; reason = "<why>"; }`, with optional
  `edge = "only" | "absent"`.
- A `follow = true` command triages its callers. One level only.
- The check fails on: a needed command with no row; a stale command row; a row
  without a boolean `follow` or a non-empty `reason`; an empty command list
  when the scan found commands.
- The edge block that hard-codes `omarchy-cmd-editor-mimetypes`, the `via`
  validation and the `via` field on `1794390043` are removed.
- The grep, for migrations and commands, also matches `~/`.
- The check computes the new rows per pin; an id in v4.0.6's `migrations/`
  and triaged on both pins joins `predates`; others get decided rows, with
  `edge = "only"` when only quattro needs them. Most are `not-needed`.
- A command row's `edge` marker says on which pin it is needed:
  `omarchy-update-keyring` is `follow = false, edge = "only"` (`GNUPGHOME`
  is a temporary keyring).

## Steps

1. `tests/user-migrations-ledger.nix`: widen the grep with `~/`, add the
   command step, and remove the
   `isEdge` indirect block (lines 31-39) and the `via` handling (lines 56-78).
   Read the commands ledger as JSON beside the migration ledger, apply the
   edge filter to it the same way, and validate rows before filtering.
   → verify: the check builds and fails, naming each needed command, while
   the command ledger is empty.
   Traps: `$(...)` drops `set -e`, so write `out=$(cmd) || exit 1` (§5); a
   `grep -o` with no match exits 1 under `pipefail`; `''${` inside the Nix
   string; build on both pins.
2. `data/user-migration-commands.nix`: one row per command the step-1 check
   names, on each pin. Read each `bin/<command>` in the pinned sources, and
   mark `edge = "only"` for commands that exist only on quattro. The two pins'
   sources are given to the coder as paths.
   → verify: the check names only migrations, no commands.
   Traps: the decision is about whether the command writes the user's files,
   not whether it reads them; state markers and `omarchy-migrate` are
   `follow = false`.
3. `data/user-migrations.nix`: each id the check names that is in v4.0.6's
   `migrations/` and named on both pins goes into `predates`; the others get rows with `decision` and `reason` (and `run`
   only for `ported`/`partial`, which none is expected to be). Drop `via` from
   `1794390043`, and mark rows for quattro-only ids `edge = "only"`.
   → verify: `checks.user-migrations-ledger` is green on both pins.
   Traps: `predates` is checked against both pins, so an id triaged on one
   pin only is a row with an `edge` marker, never a `predates` entry.
4. `pkgs/AGENTS.md` "User-file migrations (#1610)": add the command rule to
   the bump instructions and note the one-level hole. Update both data files'
   header comments to match.
   → verify: reads correctly, and `readme-counts.sh --check` is unchanged.
   Traps: the doc words are not checked; say "one level" exactly.
5. The lead runs the spec's five break proofs and the full non-VM set on
   both pins, commits per step, pushes to `edge-candidate` (fast-forward),
   and dispatches `omarchy-edge.yml` with `from_candidate=true`.

## Tests

- `nix build .#checks.x86_64-linux.user-migrations-ledger` on the carry
  and on the v4.5.0 scratch tree: green.
- The spec's five break proofs, each red for its own reason.
- `nix fmt -- --ci`, statix, deadnix; the generated-checks set on both pins.

## Rollback

Revert the carry commits. Nothing that ships changes, so a revert only
returns the check to the hand-written `via` triage.
