---
status: draft
issue: 1814
author: olafkfreund
---

# Intent: the package index carries an insecure flag and a version column

## Problem

The package index marks `unfree` and `broken` and nothing marks an insecure
package, so nixarchy-pkg's panel cannot warn on one (nixarchy-pkg "Selection
rows: mark an insecure package").

Facts, in this repository:

- **The walk drops it.** `modules/pkg-index.nix:55-67` builds each row as
  `attr, version, description, homepage, license, unfree, broken`. It reads
  no `meta.knownVulnerabilities` and no `meta.insecure`.
- **The walk already evaluates insecure packages.** It imports nixpkgs with
  `allowInsecurePredicate = _: true` (`pkg-index.nix:26`), so an insecure
  package costs a row, not an evaluation error. It is "show everything and
  say what it is" (`pkg-index.nix:21-23`) with one thing left unsaid.
- **Meta reads are guarded per field, not per row.** `try`
  (`pkg-index.nix:32-38`) wraps `tryEval`, and each field is read as `try
  (v.meta.x or default) default` (`:57-66`).
  - The `builtins.tryEval` around the row (`:81`) forces the row only to an
    attribute set (weak head normal form). Its fields are forced later, by
    `nix-instantiate --strict --json`, outside any `tryEval`.
  - So a new field is only as safe as its own `try`. That `try` must reduce
    the value to a plain boolean inside it. A `try` that returns a list, to
    be tested later, can still abort the whole walk.
- **The flags column is built by the jq program in `modules/apps.nix:3640-3661`**:
  - it emits `unfree ` and `broken`, trimmed with `sub(" $"; "")`;
  - the one-line summary gets `  [unfree]` / `  [broken]` suffixes
    (`:3644-3645`);
  - the preview text gets a "Marked BROKEN" paragraph (`:3655`).

  Insecure has none of the three.
- **Row format.** Five tab-separated fields: kind, name, summary, flags,
  preview (`apps.nix:3582-3586`). For packages the fourth field is a
  space-separated flag list, e.g. `unfree broken curated:firefox`. The
  curated pass appends `curated:<name>` to it (`apps.nix:3679`). The
  version is not a field: it is the line `version:  <v>` inside the preview
  (`apps.nix:3652`).
- **Staleness.** `stamp_key` (`apps.nix:3701-3703`) is the list of
  `nixpkgs`, `walk`, `optionsjson`, `appindex`, `apptable`, `flatpakrows`,
  `pkgnewrow`; `index_stale` (`:3704-3706`) compares it to the stored
  stamp. `walk=${./pkg-index.nix}` (`:3561`) is a store path hashed from the
  file's content, so editing `pkg-index.nix` changes the key and every
  existing index reads as stale with no further code. This is the behaviour
  the issue asks for, and it already comes with the walk change.
- **The policy gate reads the flags.** `apps.nix:3761` tests
  `index($4, "unfree")`, a substring match on the whole flags field. A new
  flag must not contain `unfree`.
- **Existing checks.** `tests/options.nix:4948-4967` proves `index_stale`
  flips when `nixpkgs` changes. `tests/options.nix:5008-5031` greps the
  walk file for the field names `homepage license unfree broken
  recurseForDerivations`; it does not look at the emitted rows, so it would
  stay green if the flag were never written into the column. `tests/explain.nix:204-212`
  covers the rebuild's insecure refusal, which is a different feature.
  Nothing evaluates the walk or the jq row builder.
- **Docs.** `modules/AGENTS.md:2210-2218` says what the walk carries
  (homepage, licence, unfree, broken, #493) and would need the new field.

Facts, in nixarchy-pkg (read-only, `bin/nixarchy-pkg` and the QML files):

- **It reads flags by splitting on spaces.** `cmd_search` takes
  `(.[3] // "") | split(" ")` for every non-option row and hands the result
  to the panel as `flags` (the `rows:` jq, `bin/nixarchy-pkg:600-621`).
  - An unknown flag is carried through as a string.
  - `Card.qml:342-343` picks a tone by exact match on `broken`, `unfree` and
    `other`. Any other flag gets the default tone and still draws.
  - So it would show a bare `insecure` tag today without breaking.
- **Its `untag`** (`UNTAG_JQ`, `bin/nixarchy-pkg:80-83`) strips only
  `[unfree]` and `[broken]` from summaries.
- **It reads the version from the preview.** `labels_tsv` extracts it from
  field 5 after `\nversion:  ` (`nixarchy-pkg` ~506-513) for selected
  packages. It reads field 5 by position, so a new column inserted before it
  would break it.
- **It reproduces the staleness test** (`nixarchy-pkg` ~355-372): the seven
  stamp inputs and their globs, `*-pkg-index.nix` for the walk.
  - It matches the shape of the walk's store path, not its content, so a
    changed walk still reads as recognised.
  - The panel does not reindex by itself. Its search reads the existing
    index and shows a "stale index" notice (`Card.qml:576`), and reindexing
    is a separate action. Terminal `nixarchy search` reindexes
    automatically.
- nixarchy-pkg#71 (version in the selection rows) is closed and is the
  consumer of the version-in-preview parse the issue mentions.

## Proposed outcome

- **An `insecure` flag in the flags column** of `pkg` rows, beside `unfree`
  and `broken`:
  - it is true when `meta.insecure` is `true`, or `meta.knownVulnerabilities`
    is a non-empty list, as the issue asks. Both inputs are read;
  - in the pinned nixpkgs, `meta.insecure` is computed from
    `knownVulnerabilities != [ ]` (`pkgs/stdenv/generic/check-meta.nix:613`,
    `:163-164`), so on current nixpkgs the two agree. Reading both also
    covers an older nixpkgs or an overlay that sets one without the other;
  - the walk gains one boolean field, and the jq builder writes it into the
    flags column in the existing space-separated style.
- **The preview says it too:** a one-line paragraph, like "Marked BROKEN",
  that the package is marked insecure, with no count and no vulnerability
  text. With `meta.insecure = true` and no list, a count would read "0
  vulnerabilities".
- **A `version` column, appended as the sixth field** (the owner chose it
  over the draft's deferral):
  - for `pkg` rows it holds the package's version, the same value the
    preview's `version:` line shows;
  - for `opt`, flatpak and new-package rows it is empty;
  - it is appended, never inserted, so fields 1-5 keep their positions and
    every positional reader keeps working:
    - nixarchy-pkg's `labels_tsv` (`$5`) and `cmd_search` (`$1`-`$5`);
    - `apps.nix`'s status and curated awk passes;
    - `read -r kind name _ _ _` (`apps.nix:3791`), whose last variable absorbs
      fields 5-6 and is discarded;
  - nixarchy-pkg ignores the column until it opts in to read it. Its
    preview parse keeps working, because the preview's `version:` line stays.
- **No `[insecure]` summary suffix in this change.** nixarchy-pkg's `untag`
  strips only `[unfree]` and `[broken]`, so a suffix would show twice on the
  panel's card. It follows once nixarchy-pkg strips it.
- **`index_stale` treats older indexes as stale.** This comes from the walk
  file's store path changing. A check demonstrates it by changing only the
  walk, with `nixpkgs` held fixed, so the existing nixpkgs-change test
  cannot mask a missing dependency.
- **No other change** to the order or meaning of fields 1-5.

## Affected users and systems

- **`nixarchy search` users:** the next search after the rebuild reindexes,
  about a minute, once (`apps.nix:3624-3625`).
- **nixarchy-pkg panel users:** the panel shows its "stale index" notice
  until they reindex. That is a separate action there.
- nixarchy-pkg: the panel can draw an `insecure` tag and warn on a selection
  row. That repository's change is separate and out of scope here.
- Files: `modules/pkg-index.nix`, `modules/apps.nix` (jq at ~3639-3660),
  `modules/AGENTS.md`, `tests/options.nix` (and possibly a new check).
- Mode A: `nixarchy-search` is only built where the apps module is enabled;
  see Constraints.

## Constraints

- **CLAUDE.md section 1: the check fails without the flag, at each stage.**
  - **The pipeline:** fixture packages pass through the actual walk and then
    the actual jq row builder, never fabricated JSON. A builder test fed
    made-up JSON passes even when the walk never emits the flag.
  - **The fixtures:**
    - one with `meta.knownVulnerabilities = [ "x" ]`;
    - one with `meta.insecure = true` and no list;
    - a clean one;
    - malformed ones: `meta.insecure = null`, a throwing
      `knownVulnerabilities`, and a non-list `knownVulnerabilities`;
    - one that is also unfree and broken.
  - **The assertions:**
    - the first two rows carry `insecure`, and the clean one does not;
    - the malformed ones neither carry the flag nor abort the walk;
    - every row has exactly six tab-separated fields, fields 1-5 unchanged
      in content from before. For `pkg` rows field 6 equals the preview's
      `version:` line, and for every other kind it is empty;
    - the unfree and broken flags and the preview are preserved.
  - **Breaks:** it is seen to fail separately when the walk drops the field,
    and when the jq builder drops it.
  - The existing grep (`tests/options.nix:5014`) proves only that a word is
    in the file, so it cannot stand in for this. No fixture names a real
    package whose vulnerabilities could be fixed upstream.
- **Row format stays backward compatible.** `insecure` is one more word in
  a field consumers already split on spaces. The version is a sixth field
  appended after the preview.
  - The spec reads every reader of the index in this repository (awk `-F'\t'`
    passes, `read` loops, fzf's `--with-nth`/`--delimiter`, the preview
    command) and states that each either ignores field 6 or is changed to.
  - A display that shows "the rest of the line" must not start showing the
    version, or its tab, in a picker. The spec finds every such display.
  The flag name must not contain `unfree` (`apps.nix:3761`) and must not
  collide with the `curated:` prefix convention. Any consumer that matches
  flags exactly keeps working; only a consumer that rejects unknown flags
  would break, and none was found in either repository.
- **Evaluation safety.** The flag is computed inside a single `try` that
  reduces to a boolean, with explicit type checks, for example:

  ```nix
  try (
    (v.meta.insecure or false) == true
    || builtins.isList (v.meta.knownVulnerabilities or null)
       && v.meta.knownVulnerabilities != [ ]
  ) false
  ```

  A `null`, a non-list or a throw gives `false` for that row and never aborts
  the walk. The row `tryEval` at `:81` is not relied on.
- **Evaluation cost, with a defined bar.** Both attributes are lazy `meta`
  fields, so cost is expected to be one thunk per row. The spec measures it
  on the same nixpkgs pin, machine and evaluator, before and after:
  wall-clock time, peak memory and emitted row count. The bar: the same row
  count, and time and peak memory each within 10% of before, taking the
  median of three runs.
- **No vulnerability text in the index.** The text can be long and carries
  tabs and newlines; the index is one row per line, tab-separated. Only the
  fact and, at most, the count go in.
- **Mode A untouched.** Only the index builder changes; no option, default
  or module-system behaviour changes, so `tests/options.nix` needs no new
  on/off state. The check that proves it is the existing options shards
  staying as they were.
- **Edit hygiene.** `nix fmt` after any `.nix` edit (an editor hook may
  reformat in another style); heredocs in `''` strings are avoided in the
  check (`CLAUDE.md` section 5).

## Open questions

1. **The version column's consumer.** nixarchy-pkg can then read field 6
   instead of parsing the preview. That is a change in that repository, and
   the owner decides when to make it. This change does not file it there.
2. **Flag word.** `insecure`, which matches the issue and the panel's
   wording, does not contain `unfree`, and does not collide with `curated:`.
