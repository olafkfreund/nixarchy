---
status: draft
issue: 1814
intent: intent/2026-11-16-1814-pkg-index-insecure.md
---

# Spec: the package index carries an insecure flag and a version column

Implements the approved intent and nothing beyond it. Line numbers are
from this worktree (branch base `main` at 22cfc89e).

## Design

### 1. The walk gains one boolean (`modules/pkg-index.nix`)

In `row` (`:55-67`), after `broken`, add:

```nix
insecure = try (
  let
    m = try v.meta { };
    kv = m.knownVulnerabilities or null;
  in
  (m.insecure or false) == true || (builtins.isList kv && kv != [ ])
) false;
```

(Final form is the intent's expression; `nix fmt` decides the layout.)

- One `try`, result is a bool, so `--strict --json` has nothing left to
  force outside it. `kv != [ ]` forces only the list constructor, never an
  element, so a throwing element is harmless.
- `null` or non-bool `insecure` compares unequal to `true`; a non-list
  `knownVulnerabilities` fails `isList`; a throwing field hits the `try`
  and gives `false`. The row-level `tryEval` at `:81` is not relied on.
- Both inputs are read (intent): nixpkgs derives `meta.insecure` from
  `knownVulnerabilities != [ ]` (check-meta.nix `:163-164`, `:613`), so
  they agree on this pin; reading both covers an overlay setting one.
- `allowInsecurePredicate = _: true` (`:26`) is unchanged, so insecure
  packages already cost a row, not an error.

### 2. The row builder (`modules/apps.nix:3640-3661`, the `pkg` jq)

- **Flags (field 4):** build as a list joined with a space instead of
  string concatenation plus `sub(" $"; "")`:
  `[ (if .unfree then "unfree" else empty end), (if .broken then "broken" else empty end), (if .insecure then "insecure" else empty end) ] | join(" ")`.
  Order is `unfree broken insecure`. Concatenation would give
  `brokeninsecure` for a broken, not-unfree row; `join` cannot.
- The flag word is `insecure`: it does not contain `unfree`, so the policy
  gate's substring test `index($4, "unfree")` (`:3761`) is unaffected, and
  it does not start with `curated:`.
- **Summary (field 3): unchanged.** No `[insecure]` suffix (intent:
  nixarchy-pkg's `untag` would leave it showing twice).
- **Preview (field 5):** after the "Marked BROKEN" line (`:3655`) add
  `(if .insecure then "\n\nMarked INSECURE in nixpkgs: it lists known vulnerabilities." else "" end)`.
  No count, no vulnerability text (a count reads "0" for
  `meta.insecure = true` with no list).
- **Version (field 6):** append `.version` as the last array element.
  It is the same value the preview's `version:` line shows, except that
  an empty version stays empty here and the preview prints `?`
  (`:3652`). `@tsv` escapes any tab or newline in it.

### 3. Every writer emits six fields

The intent's check asserts exactly six fields on every row, so all
producers are padded, not only `pkg`. Field 6 is empty except for `pkg`.

| Writer | Change |
|---|---|
| `pkg` jq (`apps.nix:3640-3661`) | element 6 = `.version` (above) |
| `opt` jq (`:3613-3630`) | append `""` to the `@tsv` array |
| `app` awk (`:3596-3604`) | print a trailing empty sixth field |
| `flatpakIndexRows` (`:292-315`), both the catalogue rows and the Flathub row | trailing tab after the preview (the preview already ends the line) |
| `pkgNewIndexRow` (`:321-325`) | trailing tab after the preview |
| curated pass (`:3678-3684`) | none: assigns `$4`/`$5` with `OFS='\t'`, keeps `$6` |
| `cat "$flatpakrows"` / `cat "$pkgnewrow"` (`:3687-3692`) | none: pass-through |

The "five tab-separated fields" wording is updated to six at
`apps.nix:313` (`:3581`, `:3687` too) and `tests/options.nix:4762`;
the flatpak shape test at `tests/options.nix:4768-4780` changes from
`NF != 5` to `NF != 6` and its message from "five" to "six".

### 4. Every reader of the index (audited; none changes)

Appended, never inserted: fields 1-5 keep their positions.

| Reader | Why field 6 is harmless |
|---|---|
| status awk (`apps.nix:3744-3767`, `-F'\t' -v OFS='\t'`) | assigns `$3`/`$5`, which rebuilds the line with tabs and keeps `$6`; the `unfree` test reads `$4` only |
| fzf (`:3774-3780`, `--with-nth=1,2,3 --nth=2,3`) | field 6 is neither shown nor searched |
| fzf preview (`:3777`, `printf "%b\n" {5}`) | prints field 5 only, not the rest of the line |
| ctrl-t loop (`:3791`, `read -r kind name _ _ _`) | last `_` absorbs field 6 |
| dispatch loop (`:4032`, `read -r kind name _ type _`) | field 6 lands in the trailing `_`; `type` is only used for `opt` rows, whose field 4 is never empty, so the whitespace-IFS collapse (CLAUDE.md section 13) cannot shift it |
| opt lookup (`:3955`, `cut -f5`), flatpak lookup (`:4011`, `$1`/`$2`) | positional, unaffected |
| `stamp_key`/`index_stale` (`:3700-3706`) | hashes inputs, not rows |

No display shows "the rest of the line", so none needs fixing. Nothing in
`pkgs/`, `docs/`, `.github/` or `installer/` reads the index.
nixarchy-pkg is read-only here and out of scope: it reads `$1`-`$5`
by position and ignores field 6 until it opts in (intent).

### 5. Staleness

No code. `walk=${./pkg-index.nix}` (`:3561`) is in `stamp_key`
(`:3702`), so editing the walk makes every existing index stale. The new
check demonstrates it (Verification).

### 6. Docs

`modules/AGENTS.md` (`:2210-2218`, the paragraph on what the walk
carries): add `insecure` to the list homepage, licence, unfree, broken,
and one sentence that the index has a sixth `version` column, appended.

## Alternatives rejected

- **Reading only `meta.knownVulnerabilities`** (or only `meta.insecure`):
  the intent reads both so an overlay setting just one is covered.
- **Padding only the `pkg` writer** (the readers audit shows mixed 5/6
  rows are safe): rejected because the intent's check asserts six fields
  on every row, and a uniform shape is one rule instead of two.
- **Inserting version before the preview:** breaks nixarchy-pkg's
  `labels_tsv` (field 5 by position) and every `read` loop.
- **An `[insecure]` summary suffix:** shown twice in nixarchy-pkg until
  its `untag` strips it; follows later.
- **A count or text of vulnerabilities in the row:** long, carries tabs
  and newlines, and a count is wrong for `insecure = true` with no list.
- **Testing the jq with hand-made JSON:** passes while the walk never
  emits the flag (intent, section 1).

## Risks

- **Evaluation cost/abort.** One extra lazy `meta` read per row. Bar and
  measurement below. A malformed field must not abort the walk: covered by
  the throwing, null and non-list fixtures.
- **Existing indexes go stale** on the next rebuild; `nixarchy search`
  reindexes once (about a minute); the nixarchy-pkg panel shows its stale
  notice until reindexed. Intended (intent).
- **Mixed-width rows** if a writer is missed: the `NF != 6` assertion
  names the kind that broke.
- **Test harness.** It extracts `build_index` from the built script with
  `sed` anchors; the harness must fail loudly on empty extraction
  (as `tests/writer-lock.nix:138` does). The built script references
  `optionsjson`, so the check realizes the NixOS options.json that the
  options shards already build.
- **Mode A:** only the index builder changes; no option or default, so no
  new `tests/options.nix` on/off state. Existing options shards must stay
  green as the proof.
- **Formatting:** run `nix fmt` after every `.nix` edit and read
  `git diff --stat` (an editor hook may reformat in another style).

## Verification

### New check `checks.pkg-index` (`tests/pkg-index.nix`)

Registered by adding `"pkg-index"` to `uniformChecks` (`flake.nix`
around `:1820-1831`); `generated-checks.sh` then builds it on PRs with no
workflow edit (CLAUDE.md section 4). Takes `{ inputs, pkgs }`, derives the
script as `testLib.vmPackage "nixarchy-search"` (`tests/lib.nix:11-17`).

**Pipeline, all real except the inputs.** The real walk
(`modules/pkg-index.nix`) runs against a fixture nixpkgs
(`tests/fixtures/pkg-index.nix`: a function `{ config ? {}, ... }:` returning
`lib` from the real nixpkgs plus stub packages
`{ type = "derivation"; name; version; meta; }`, which `lib.isDerivation`
accepts without touching the store). The real `build_index` (extracted from
the built script, sourced under `set -eo pipefail`, called in a subshell
because it `exit 1`s) runs the real jq builder and curated awk. `nixpkgs`,
`optionsjson`, `appindex`, `apptable` and `cache` are overridden to tiny
fixtures; `walk`, `flatpakrows`, `pkgnewrow` stay the baked store paths.
Sandbox setup as `tests/writer-lock.nix:131-136` (`NIX_STATE_DIR`,
`NIX_LOG_DIR`).

**Fixtures** (flags = expected field 4):

| attr | meta | flags |
|---|---|---|
| `fixVuln` | `knownVulnerabilities = [ "x" ]` | `insecure` |
| `fixInsecureOnly` | `insecure = true`, no list | `insecure` |
| `fixClean` | description only | empty |
| `fixNullInsecure` | `insecure = null` | empty |
| `fixThrowVuln` | `knownVulnerabilities = throw "boom"` | empty, row still present |
| `fixStrVuln` | `knownVulnerabilities = "oops"` | empty |
| `fixEmptyList` | `knownVulnerabilities = [ ]` | empty |
| `fixAll` | unfree licence, `broken = true`, `[ "y" ]` | `unfree broken insecure` |
| `fixBrokenInsecure` | `broken = true`, `insecure = true` | `broken insecure` |
| `fixNoVersion` | `insecure = true`, no `version` | `insecure`, field 6 empty |
| `fixCurated` | `[ "z" ]`, plus an `apptable` line naming it | `insecure curated:fixcurated` |
| `sub` | `recurseForDerivations`, one clean package | proves descent |

**Assertions.**

1. Stage 1, walk alone (`nix-instantiate --eval --strict --json --arg
   nixpkgs <fixture> $walk | jq`): exits 0; `[.[].attr]` equals the
   expected set (including `fixThrowVuln`, `fixStrVuln`, `sub.*`); `.insecure`
   is true exactly for `fixVuln`, `fixInsecureOnly`, `fixAll`,
   `fixBrokenInsecure`, `fixNoVersion`, `fixCurated`. Failure messages name
   the walk, so a walk break and a builder break read differently.
2. Stage 2, `build_index` exits 0; pkg row count equals the expected
   count (floor against "iterated nothing"); at least one row of each kind
   (`app`, `opt`, `pkg`, `flatpak`, `new`).
3. `awk -F'\t' 'NF != 6'` over the whole index prints nothing.
4. Field 6: pkg rows equal the version literal and equal the preview's
   `version:` value (sed from field 5, whose newlines are escaped text);
   `fixNoVersion` is empty (preview shows `?`); every other kind is empty.
5. Field 4 equals the table exactly (no leading, trailing or double
   space); an insecure-only row does not match `unfree`.
6. Field 5 of insecure rows contains the "Marked INSECURE" line; clean
   rows do not. `fixAll` keeps `[unfree]  [broken]` in field 3 and
   `Marked BROKEN` in field 5; no row has `[insecure]` in field 3.
7. Fields 1-5 unchanged: a golden `tests/fixtures/pkg-index.golden.tsv`
   is frozen from the unmodified tree before any edit. After the change,
   `cut -f1-5` of non-insecure rows equals it byte for byte; for insecure
   rows only the added word in field 4 and the added paragraph in field 5
   may differ. For the real flatpak and new rows, `cut -f1-5` of the index
   equals `cut -f1-5` of the source file (not goldened: the catalogue moves).

**Walk-only staleness case.** Source `stamp_key`/`index_stale` as
`tests/options.nix:4950-4967` does. Build walk A (`${../modules/pkg-index.nix}`)
and walk B (`pkgs.writeText` of the same text plus a newline), with
`nixpkgs` held fixed. Write the stamp under A; `index_stale` is false
under A and true under B. The existing case flips only `nixpkgs`, so it
cannot see a missing `"$walk"` in the key. This passes on the current tree
(a regression guard, not new behaviour).

### Section 1 breaks (each seen failing, then restored and passing)

Commit a clean baseline first; use `git checkout HEAD -- <path>`, not
`git checkout --`; `git add -A` before building (flake sees tracked files
only); evaluate `nix eval --raw .#checks.x86_64-linux.pkg-index.drvPath`
once, grep the drv for the break, then `nix build '<drv>^*'`; confirm the
break landed with `git diff`.

| Break | Expected failure |
|---|---|
| A. Delete the `insecure =` line from `row` | stage 1 `.insecure` null; stage 2 flag assertions |
| A2. Compute it with no `try` (`v.meta.knownVulnerabilities != [ ]`) | `fixThrowVuln` aborts `--strict`; `build_index` exits 1 |
| B. Drop `insecure` from the jq flags (walk still emits it) | stage 1 passes, stage 2 field 4 fails (stages separable) |
| B2. Concatenate flags without `join` | `fixBrokenInsecure` gives `brokeninsecure` |
| C. Insert version before the preview | golden for fields 1-5 fails |
| C2. Drop the trailing empty field from jq, app awk, opt jq, `flatpakIndexRows` or `pkgNewIndexRow` | `NF != 6` names the kind |
| D. Remove `"$walk"` from `stamp_key` (`:3702`) | staleness case fails |
| E. Name the flag so it contains `unfree` | substring assertion fails |

The PR carries each break's failing output, then the passing run.
Also run `nix fmt -- --ci`, statix and deadnix, `checks.options-*`
shards (Mode A unchanged), `readme-counts.sh` if counts are touched, and
the existing flatpak shape test at its new `NF != 6`.

### Measurement bar

Same nixpkgs pin, machine and evaluator, after the section 6 gate
(no p620 system build, load below 12, `vm-host-free.sh install` and
`edge` both print `free`). Command:
`nix-instantiate --eval --strict --json --arg nixpkgs "$NP" <walk> > out.json`,
baseline against `git show main:modules/pkg-index.nix` saved as
`pkg-index-old.nix` (no `git checkout` between runs). Run in a
`systemd-run --user --scope`, sample the cgroup's `memory.stat` `anon`
every second for the peak (not `memory.peak`, which counts file cache);
`/usr/bin/time` is absent. Equal `GC_INITIAL_HEAP_SIZE`. Bar: identical
`jq length`, and wall time and peak anon each within 10% of baseline,
median of three runs. Also report the count of `.insecure` rows.

### Not covered

nixarchy-pkg's reading of field 6 or the `insecure` flag (separate
repository, owner's call); no VM or panel test.
