---
status: draft
issue: 1814
spec: spec/2026-11-16-1814-pkg-index-insecure.md
coders:
  # The owner's rule: codex or agy write the code; agent-run agy cannot reach /mnt/data worktrees.
  1: codex  # small tricky shell/Nix harness; needs exact extraction and sandbox setup, no build access needed to write it
  2: codex  # small tricky Nix expression with exact try/isAttrs semantics
  3: codex  # small tricky jq (join vs concat, version element)
  4: codex  # mechanical-but-exact writer edits across five producers, explicit \t escapes
  5: lead   # the section 1 breaks: applied, observed and restored by the lead, never a Codex edit
  6: codex  # two fixture edits (NF 5->6, five->six field index)
  7: codex  # docs paragraphs and the stale-wording comments
  8: codex  # check-only: writes measurement script; lead runs it under the gate
reviewers:
  - codex  # reads the diff natively
  - agy    # independent model; given the diff inline
---

# Plan: package index carries an insecure flag and a version column (#1814)

Implements `spec/2026-11-16-1814-pkg-index-insecure.md` (approved) and
nothing beyond it. Line numbers are from branch base `main` at 22cfc89e and
move as steps land; re-find by the quoted text.

## Handoff rules (every Codex prompt says these)

- Codex must not commit, stage, push, deploy, restart, switch or build. The
  lead builds and runs every check, and commits each step before the next
  (agent-run refuses a dirty tree).
- Never print the environment. Never touch `main` or `~/.config/nixos`.
- Work only in `/mnt/data/vmtest/wt-1814`, only on the named files.

## Approved decisions (from the spec)

**Walk (`modules/pkg-index.nix`, `row`, `:55-67`).** After `broken`, add
exactly:

```nix
insecure =
  let
    m = try (v.meta or { }) { };
  in
  builtins.isAttrs m
  && (
    try ((m.insecure or false) == true) false
    || try (
      let
        kv = m.knownVulnerabilities or null;
      in
      builtins.isList kv && kv != [ ]
    ) false
  );
```

`nix fmt` may change layout only. Two separate inner `try`s (a throwing
`insecure` must not hide a list, and the reverse). `meta` is guarded by
structure (`isAttrs`), not `try`, for missing/null/non-set meta. `kv != [ ]`
never forces an element. The row `tryEval` at `:81` is not relied on.
`allowInsecurePredicate = _: true` (`:26`) is unchanged.

**jq builder (`modules/apps.nix:3640-3661`, `pkg`).**
- Field 4 flags: `[ (if .unfree then "unfree" else empty end), (if .broken then "broken" else empty end), (if .insecure then "insecure" else empty end) ] | join(" ")`
  replacing string concat plus `sub(" $"; "")`. Order is
  `unfree broken insecure`. The word `insecure` must not contain `unfree`
  (policy gate `index($4, "unfree")` at `:3761`) and must not start with
  `curated:`.
- Field 3 summary: unchanged. No `[insecure]` suffix.
- Field 5 preview: after the "Marked BROKEN" line (`:3655`) add
  `(if .insecure then "\n\nMarked INSECURE in nixpkgs." else "" end)`. No
  count, no vulnerability text, no claim of a list.
- Field 6: `.version` as the last array element (empty stays empty; the
  preview prints `?` for empty at `:3652`). `@tsv` escapes tab/newline.

**Six fields on every row; field 6 is empty except for `pkg`.**

| Writer | Field 6 |
|---|---|
| `pkg` jq (`apps.nix:3640-3661`) | `.version` |
| `opt` jq (`:3613-3630`) | append `""` to the `@tsv` array |
| `app` awk (`:3596-3604`) | print a trailing empty sixth field |
| `flatpakIndexRows` (`:292-315`), catalogue rows and the Flathub row | empty sixth field after the preview, written with an explicit `\t` escape, never a literal trailing tab |
| `pkgNewIndexRow` (`:321-325`) | same, explicit `\t` |
| curated pass (`:3678-3684`) | no change (assigns `$4`/`$5`, `OFS='\t'`, keeps `$6`) |
| `cat "$flatpakrows"` / `cat "$pkgnewrow"` (`:3687-3692`) | no change |

Wording "five tab-separated fields" / "five-field" becomes six at
`apps.nix:313`, `:3581`, `:3687` (step 7), `tests/options.nix:4762` and
`:4772` (step 6) and `modules/AGENTS.md:1710` (step 7). Appended, never
inserted: fields 1-5 keep their positions.

**Readers needing no change (audited):** status awk (`:3744-3767`), fzf
(`:3774-3780`, `--with-nth=1,2,3 --nth=2,3`), fzf preview (`:3777`,
`printf "%b\n" {5}`), ctrl-t loop (`:3791`), dispatch loop (`:4032`),
opt lookup (`:3955` `cut -f5`), flatpak lookup (`:4011`),
`stamp_key`/`index_stale` (`:3700-3706`). nixarchy-pkg is out of scope and
read-only.

**Staleness:** no code; `walk=${./pkg-index.nix}` (`:3561`) is in
`stamp_key`.

**Docs:** `modules/AGENTS.md:2210-2218`: add `insecure` to the list
homepage, licence, unfree, broken, plus one sentence that the index has a
sixth `version` column, appended. `modules/AGENTS.md:1710` (the flatpak
rows passage) says "Five tab-separated fields" and moves to six.

**Test (`tests/pkg-index.nix`, new `checks.pkg-index`).** Register by adding
`"pkg-index"` to `uniformChecks` (`flake.nix` ~`:1820-1831`); takes
`{ inputs, pkgs }`; script is `testLib.vmPackage "nixarchy-search"`
(`tests/lib.nix:11-17`). Real walk against a fixture nixpkgs generated with
`pkgs.writeText` (function `{ config ? {}, ... }:` returning
`lib = import ${pkgs.path}/lib` and stub packages
`{ type = "derivation"; name; version; meta; }`; no `./path` literals).
Real `build_index` extracted from the built script with `sed` anchors,
sourced under `set -eo pipefail`, run in a subshell (it `exit 1`s); the
harness fails loudly on empty extraction (as `tests/writer-lock.nix:138`).
The extracted function has no wrapper PATH, so the check's
`nativeBuildInputs` list every command `build_index` and `stamp_key` call
(read from `modules/apps.nix` `build_index()`, ~`:3588-3696`):
`nix` (`nix-instantiate`), `jq`, `gawk` (`awk`), `coreutils` (`mkdir`,
`mktemp`, `cat`, `mv`, `rm`, `tail`, `printf`), `gnused` (the extraction
`sed`), and `bash`; re-read the function before step 1 and add anything it
gained.
`nixpkgs`, `optionsjson`, `appindex`, `apptable`, `cache` overridden to tiny
fixtures; `walk`, `flatpakrows`, `pkgnewrow` stay baked. Sandbox setup as
`tests/writer-lock.nix:131-136` (`NIX_STATE_DIR`, `NIX_LOG_DIR`). No
heredocs in `''` strings: use `printf '%s\n'`.

Fixtures (attr: meta -> expected flags):
- `fixVuln`: `knownVulnerabilities = [ "x" ]` -> `insecure`
- `fixInsecureOnly`: `insecure = true`, no list -> `insecure`
- `fixClean`: description only -> empty
- `fixNullInsecure`: `insecure = null` -> empty
- `fixThrowVuln`: `knownVulnerabilities = throw "boom"` -> empty, row present
- `fixThrowElem`: `knownVulnerabilities = [ (throw "boom") ]` -> `insecure`
- `fixThrowInsecureList`: `insecure = throw "boom"`, `knownVulnerabilities = [ "x" ]` -> `insecure`
- `fixThrowMeta`: `meta = throw "boom"` -> empty, row present
- `fixStrVuln`: `knownVulnerabilities = "oops"` -> empty
- `fixEmptyList`: `knownVulnerabilities = [ ]` -> empty
- `fixAll`: unfree licence, `broken = true`, `[ "y" ]` -> `unfree broken insecure`
- `fixBrokenInsecure`: `broken = true`, `insecure = true` -> `broken insecure`
- `fixNoVersion`: `insecure = true`, no `version` -> `insecure`, field 6 empty
- `fixCurated`: `[ "z" ]` plus an `apptable` line naming it -> `insecure curated:fixcurated`
- `sub`: `recurseForDerivations`, one clean package (proves descent)

Not fixtured (spec amendment A): `meta = null` and a missing `meta`. The
walk's existing licence/unfree reads (`try v.meta { }`, no `or`) raise
errors `tryEval` cannot catch, so `main`'s walk cannot produce the golden
with them; their handling is unchanged and out of scope. The new
expression's `v.meta or { }` plus `isAttrs` guard stays.

Assertions:
1. Stage 1, walk alone (`nix-instantiate --eval --strict --json --arg nixpkgs <fixture> $walk | jq`): exit 0; `[.[].attr]` equals the expected set (including `fixThrowVuln`, `fixStrVuln`, `sub.*`); `.insecure` true exactly for `fixVuln`, `fixInsecureOnly`, `fixThrowElem`, `fixThrowInsecureList`, `fixAll`, `fixBrokenInsecure`, `fixNoVersion`, `fixCurated` (spec amendment B). Messages name the walk.
2. Stage 2: `build_index` exits 0; pkg row count equals expected (floor against "iterated nothing"); at least one row of each kind (`app`, `opt`, `pkg`, `flatpak`, `new`).
3. `awk -F'\t' 'NF != 6'` over the whole index prints nothing (names the kind). The `flatpak` and `new` rows come from the live catalogue (spec amendment C), so they are asserted only structurally: six fields, field 6 empty, field 1 the right kind.
4. Field 6: pkg rows equal the version literal and the preview's `version:` value (sed from field 5, newlines are escaped text); `fixNoVersion` empty (preview shows `?`); every other kind empty.
5. Field 4 equals the fixtures list exactly (no leading, trailing or double space); an insecure-only row does not match `unfree`.
6. Field 5 of insecure rows contains "Marked INSECURE"; clean rows do not. `fixAll` keeps `[unfree]  [broken]` in field 3 and `Marked BROKEN` in field 5; no row has `[insecure]` in field 3.
7. Fields 1-5 of the `app`, `opt` and `pkg` rows vs golden `tests/fixtures/pkg-index.golden.tsv`, byte for byte, except insecure `pkg` rows, where only the added word in field 4 and the added paragraph in field 5 may differ. The golden has no `flatpak` or `new` rows, and they are never compared to their own source file (cannot fail).

Walk-only staleness case: source `stamp_key`/`index_stale` as
`tests/options.nix:4950-4967`; walk A (`${../modules/pkg-index.nix}`) and
walk B (`pkgs.writeText` of the same text plus a newline), `nixpkgs` fixed;
stamp written under A; `index_stale` false under A, true under B. Passes on
the current tree (regression guard).

**Golden procedure.** `flatpakIndexRows` and `pkgNewIndexRow` are let-bound
in `modules/apps.nix` to the live catalogue (`data/flatpaks.nix`) and cannot
take a fixture catalogue (spec amendment C), so the golden covers only the
rows the harness controls: `app`, `opt` and `pkg`.
`tests/pkg-index.nix` exposes `passthru.golden`: a pure derivation that runs
the same harness and writes `cut -f1-5` of the `app`/`opt`/`pkg` rows to
`$out`, then exits 0 whatever the assertions would say. `checks.pkg-index`
itself always runs every assertion, including the golden comparison. The
golden is made from `main`'s UNMODIFIED walk and jq (step 1), committed
before any code change.

**Also updated:** `tests/app-selection.nix:192` five-field index fixture
becomes six fields; `tests/options.nix:4770` `NF != 5` becomes `NF != 6`
and its message (`:4772`) "five" becomes "six".

**Measurement bar.** Same nixpkgs pin, machine and evaluator, after the
section 6 gate (no p620 system build, 1-minute load below 12,
`vm-host-free.sh install` and `edge` both print `free`).
`nix-instantiate --eval --strict --json --arg nixpkgs "$NP" <walk> > out.json`;
baseline from `git show main:modules/pkg-index.nix` saved as
`pkg-index-old.nix` (no `git checkout` between runs). Run inside
`systemd-run --user --scope`, sample the cgroup's `memory.stat` `anon` each
second for peak (not `memory.peak`); `/usr/bin/time` is absent; equal
`GC_INITIAL_HEAP_SIZE`. Bar: identical `jq length`, wall time and peak anon
each within 10% of baseline, median of three runs. Report the count of
`.insecure` rows.

## Steps

Each step is committed by the lead before the next. Name the step in every
commit message. Build via checks by name; evaluate the drvPath once and
`nix build '<drv>^*'` (CLAUDE.md section 5, stale evaluation). Cheap checks
run one at a time under `flock /mnt/data/vmtest/codex-build.lock`. Run
`nix fmt` after every `.nix` edit and read `git diff --stat`.

### Step 1: check harness plus the pre-change golden (coder: codex, lead builds)

- Create `tests/pkg-index.nix` with the harness, fixtures, the stage 1/2
  assertions and the staleness case, per "Test" above, exposing
  `passthru.golden` (see "Golden procedure"). Register `"pkg-index"` in
  `uniformChecks` (`flake.nix` ~`:1820-1831`). The flatpak and new rows come
  from the baked live rows, asserted structurally only.
- Lead procedure: `git add` the new test and an EMPTY
  `tests/fixtures/pkg-index.golden.tsv`; build
  `.#checks.x86_64-linux.pkg-index.golden` on the unmodified tree; copy its
  output into `tests/fixtures/pkg-index.golden.tsv`; build
  `.#checks.x86_64-linux.pkg-index` on the same tree and confirm it FAILS for
  the expected reasons only (the missing `insecure` flag and `version`
  column: stage 1 `.insecure`, field-count, field 6, flag and preview
  assertions), not for harness errors (empty extraction, missing command,
  eval failure, golden mismatch); save that output for the PR. The lead
  commits harness plus golden before step 2, and confirms
  `git diff main -- modules/` is empty at that commit.
- Verify: `git add -A`; `nix eval --raw .#checks.x86_64-linux.pkg-index.drvPath`;
  `nix build '<drv>^*' --print-build-logs`; read the golden for one row of
  each of `app`, `opt` and `pkg` and confirm no row has `insecure` in
  field 4 (it cannot, pre-change).
- Traps: section 5 flake sees only git-added files (`git add` the new test,
  fixture and golden); `''` strings: escape `${` as `''${`, no heredocs
  (`printf '%s\n'`), `\$` is a literal backslash; `set -e` does not reach
  inside `$(...)` (write `out=$(cmd) || return/exit`); the sed extraction of
  `build_index` must fail loudly when empty; the extracted function has no
  wrapper PATH (see `nativeBuildInputs` above); section 1 pipefail (no
  `| tail` on a status you read); verify under bash; run `nix fmt`.

### Step 2: the walk (coder: codex)

- `modules/pkg-index.nix` `row` (`:55-67`): add the `insecure` expression
  from "Approved decisions", after `broken`. Nothing else in the file.
- Verify (lead): `nix fmt`; `git diff --stat`; build `checks.pkg-index`:
  stage 1 assertions pass now (the field and builder assertions still fail,
  expected until steps 3-4). Steps 2-4 only verify progress; the breaks run
  in step 5.
- Traps: `builtins.tryEval` does not catch a missing attribute (hence the
  `isAttrs` guard, do not "simplify" it); nixfmt not nixpkgs-fmt (hook may
  reformat); evaluate drvPath once before long builds.

### Step 3: the jq builder (coder: codex)

- `modules/apps.nix` `pkg` jq (`:3640-3661`): flags via the `join(" ")`
  list, the "Marked INSECURE in nixpkgs." preview paragraph after
  "Marked BROKEN" (`:3655`), and `.version` as element 6 of the `@tsv`
  array. Summary unchanged.
- Verify (lead): `nix fmt`; build `checks.pkg-index`: stage 1 and the pkg
  flag, preview, version assertions pass; the six-field assertion still
  fails on the other kinds until step 4. The breaks (B, B2, E) run in step 5.
- Traps: this jq lives inside a Nix `''` string: `${` must be `''${`, and
  `$` in jq is already literal; a tool that "escapes" every `$` as `\$`
  breaks it (section 5); `nix build` exit status, never its last line;
  the flag must not contain `unfree` or start with `curated:`.

### Step 4: the other writers emit six fields (coder: codex)

- `modules/apps.nix`: `opt` jq (`:3613-3630`) append `""`; `app` awk
  (`:3596-3604`) trailing empty field; `flatpakIndexRows` (`:292-315`) both
  the catalogue rows and the Flathub row; `pkgNewIndexRow` (`:321-325`)
  with explicit `\t` escapes (never a literal trailing tab). The "five"
  wording is step 7.
- Verify (lead): `nix fmt`; build `checks.pkg-index`: all assertions pass
  including the golden fields 1-5 of `app`/`opt`/`pkg` rows and `NF != 6`
  (the flatpak and new rows structurally). The breaks (C, C2) run in
  step 5.
- Traps: Nix `''` string escaping of `${` and no heredocs; an awk or `printf`
  with a literal trailing tab can be stripped by an editor hook, so use
  `\t`; the flatpak catalogue rows (`apps.nix` ~`:295`) sit in a `''` string
  with literal tabs, so write the empty sixth field there as `''\t`, while
  the `""` strings (the Flathub row and `pkgNewIndexRow`) use `\t`; `read` with whitespace IFS drops empty fields (the dispatch loop at
  `:4032` is safe only because `type` is non-empty for `opt` rows; do not
  touch it); grep the producers by name before changing what they emit
  (`grep -rn 'flatpakrows\|pkgnewrow\|apptable' modules tests`).

### Step 5: the section 1 breaks (lead only, no coder)

Runs AFTER step 4, once `checks.pkg-index` passes end to end. Every break
(A, A2, A3, A4, B, B2, C, C2, D, E from the spec's table; C3 is dropped) is
applied from a clean HEAD, proved to have landed (`git diff`, and grep the
drv), seen failing for its named reason, then restored with
`git checkout HEAD -- <path>` (never `git checkout --`) and seen passing.
Commit a clean baseline first; `git add -A` before each build; evaluate
`nix eval --raw .#checks.x86_64-linux.pkg-index.drvPath` once, then
`nix build '<drv>^*'`. Save each failing output for the PR.

- A: remove the WHOLE `insecure` binding from `row` (every line of it, not
  just the `insecure =` line), then confirm the walk still evaluates
  (`nix-instantiate --eval --strict --json --arg nixpkgs <fixture> <walk>`
  exits 0) so the failure is the missing field, not a syntax error.
- A3 fails on `fixThrowMeta` alone.
- C: version before the preview in the `pkg` jq (golden fails) and
  separately in `flatpakIndexRows` (structural field assertion fails).
- D: remove `"$walk"` from `stamp_key` (`apps.nix:3703`), observed in the
  walk-only staleness case of `checks.pkg-index`. The lead does this; it is
  not a Codex edit.
- Traps: a break that stays green may be one that never applied; a stale
  background evaluation can rebuild an old drv; `git checkout -- <path>`
  restores the index, not HEAD.

### Step 6: the other tests (coder: codex)

- `tests/options.nix:4762` wording "five" to "six" and `:4770`
  `NF != 5` to `NF != 6` with its message (`:4772`);
  `tests/app-selection.nix:192` fixture to six fields.
- Verify (lead): `nix fmt`; build `checks.app-selection`; build one options
  shard that contains the flatpak shape case (the lead finds which with the
  case name; shards are heavy, gate per the section 6 VM/options tier and
  `options-shards` is cheap).
- Traps: options shards peak ~11.5 GB each; at most two at once and only
  when `gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'`
  prints `0`; ask again when the slot is taken; a deliberate model change
  that turns an old check red means ask what the check asserts (section 1
  read backwards), and say so in the PR.

### Step 7: docs (coder: codex)

- `modules/AGENTS.md:2210-2218`: add `insecure` to the walk's carried list
  and one sentence about the appended sixth `version` column.
  `modules/AGENTS.md:1710` (the flatpak rows passage, "Five tab-separated
  fields") moves to six. The "five-field" comments in `modules/apps.nix`
  (~`:313`, `:3581`, `:3687`) say six. Check
  `docs/` and `README` counts: run `.github/scripts/readme-counts.sh` only
  if a counted thing changed (none expected).
- Verify (lead): `git diff --stat`; read the paragraphs;
  `grep -rniE 'five[- ](tab|field)' modules tests` returns nothing stale
  (the `tests/options.nix` hits are step 6).
- Traps: no new numbered sections in CLAUDE.md (none are added here);
  area lessons go in `modules/AGENTS.md`, general ones in CLAUDE.md in the
  same PR if this work cost an hour.

### Step 8: the measurement (lead runs, codex writes the script)

- Codex writes the measurement script in the scratchpad (not committed):
  `#!/usr/bin/env bash`, `set -euo pipefail`, three runs each of old and new
  walk, wall time and peak `anon` from the scope's `memory.stat`, equal
  `GC_INITIAL_HEAP_SIZE`, emits the median and the `.insecure` row count.
- The lead runs it only when the section 6 gate holds. Record the numbers
  and the bar result (identical `jq length`, time and peak within 10%) in
  the PR. If the bar fails, stop and ask; do not retry-until-green.
- Traps: `set -e` does not reach inside `$(...)`; zsh does not word-split,
  run as a bash script; never `pkill` by name; a wedged `nix` process looks
  alive, check `etime`/`%cpu` against the log mtime; do not start while an
  install or edge verify job is in flight.

## Tests

Run by the lead, one at a time by tier, before every push:

- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
  `nix run nixpkgs#deadnix -- --fail .`
- `nix build .#checks.x86_64-linux.pkg-index --print-build-logs`: all
  assertions pass; each break in the spec's table seen failing then
  restored; failing output kept for the PR.
- `checks.app-selection`; `checks.options-*` shards as gated (Mode A
  unchanged is proven by them staying green); `checks.options-shards`.
- Every target `.github/scripts/generated-checks.sh` prints, plus claimed
  checks whose files changed. Say in the PR what could not run locally.
- Before pushing: `git merge-base origin/main HEAD` is what is expected and
  `git show --stat` lists only these files.

## Rollback

Each step is its own commit, so `git revert` the step commits in reverse
order (8 has none, 5 changes no files). Reverting steps 2-4 alone restores the five-field
format; `walk=${./pkg-index.nix}` changes the stamp again, so every index
reads stale once more and `nixarchy search` reindexes (about a minute). The
golden and harness (step 1) stay valid for the pre-change tree in
`GOLDEN` mode. No option, default or module-system behaviour changes, so no
user migration.
