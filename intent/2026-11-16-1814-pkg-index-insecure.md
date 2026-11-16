---
status: draft
issue: 1814
author: olafkfreund
---

# Intent: the package index carries an insecure flag

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
- **Every meta read is guarded.** `try` (`pkg-index.nix:32-38`) wraps
  `tryEval`, and each field is read as `try (v.meta.x or default) default`
  (`:57-66`); the whole row sits under `builtins.tryEval` (`:81`), so a bad
  meta costs one row, not the index.
- **The flags column is built in `modules/apps.nix:3639-3644`**: the jq
  program emits `unfree ` and `broken`, trimmed with `sub(" $"; "")`. The
  one-line summary also gets `  [unfree]` / `  [broken]` suffixes
  (`:3643-3645`), and the preview text gets a "Marked BROKEN" paragraph
  (`:3655`). Insecure has none of the three.
- **Row format.** Five tab-separated fields: kind, name, summary, flags,
  preview (`apps.nix:3582-3586`). For packages the fourth field is a
  space-separated flag list, e.g. `unfree broken curated:firefox`. The
  curated pass appends `curated:<name>` to it (`apps.nix:3679`). The
  version is not a field: it is the line `version:  <v>` inside the preview
  (`apps.nix:3652`).
- **Staleness.** `stamp_key` (`apps.nix:3698-3700`) is the list of
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
  to the panel as `flags` (`nixarchy-pkg` around the `rows:` jq at ~596-614).
  An unknown flag is carried through as a string; `Card.qml:56-59` draws
  whatever flags a row has. It would show a bare `insecure` tag today
  without breaking.
- **It reads the version from the preview.** `labels_tsv` extracts it from
  field 5 after `\nversion:  ` (`nixarchy-pkg` ~506-513) for selected
  packages. It reads field 5 by position, so a new column inserted before it
  would break it.
- **It reproduces the staleness test** (`nixarchy-pkg` ~355-372): the seven
  stamp inputs and their globs, `*-pkg-index.nix` for the walk. It matches
  the shape of the walk's store path, not its content, so a changed walk
  still reads as recognised. The panel's "stale index" notice
  (`Card.qml:576`) is what a user with an old index sees.
- nixarchy-pkg#71 (version in the selection rows) is closed and is the
  consumer of the version-in-preview parse the issue mentions.

## Proposed outcome

- **An `insecure` flag in the flags column** of `pkg` rows, beside `unfree`
  and `broken`: true when `meta.insecure` is true or `meta.knownVulnerabilities`
  is a non-empty list. The walk gains an `insecure` field; the jq builder
  writes it into the flags column in the existing space-separated style.
  Nothing else about the row changes.
- **The summary and preview say it too**, like the other two flags: a
  `  [insecure]` suffix on the summary and a short paragraph in the preview
  that names the known vulnerabilities' count, not their text (see
  Constraints). The panel's duplicate-tag logic (`untag` in nixarchy-pkg)
  only strips `[unfree]` and `[broken]`, so the summary suffix is a
  nixarchy-pkg follow-up to coordinate; see open question 2.
- **`index_stale` treats older indexes as stale.** This comes from the walk
  file's store path changing; the outcome is that a check demonstrates it
  rather than assuming it.
- **No other change** to row order, field count or meaning.

## Affected users and systems

- Anyone using `nixarchy search` or the nixarchy-pkg panel: the next search
  after the rebuild reindexes (about a minute, once; `apps.nix:3624-3625`).
- nixarchy-pkg: the panel can draw an `insecure` tag and warn on a selection
  row. That repository's change is separate and out of scope here.
- Files: `modules/pkg-index.nix`, `modules/apps.nix` (jq at ~3639-3660),
  `modules/AGENTS.md`, `tests/options.nix` (and possibly a new check).
- Mode A: `nixarchy-search` is only built where the apps module is enabled;
  see Constraints.

## Constraints

- **CLAUDE.md section 1: the check fails without the flag.** A check must
  evaluate the walk (or its row builder) against a fixture package with
  `meta.knownVulnerabilities = [ "x" ]` and another with `meta.insecure =
  true`, assert both rows carry `insecure` in the flags column, and a clean
  package does not; and it must be seen to fail with the flag removed from
  the walk. The existing grep at `tests/options.nix:5014` proves only that a
  word is in the file, so it cannot stand in for this. The fixture must not
  name a real package whose vulnerabilities could be fixed upstream.
- **Row format stays backward compatible.** The field count stays five;
  `insecure` is one more word in a field consumers already split on spaces.
  The flag name must not contain `unfree` (`apps.nix:3761`) and must not
  collide with the `curated:` prefix convention. Any consumer that matches
  flags exactly keeps working; only a consumer that rejects unknown flags
  would break, and none was found in either repository.
- **Evaluation cost and safety.** Reading `meta.knownVulnerabilities` for
  ~112,755 attrs (`AGENTS.md:2225`) must not throw or slow the walk
  measurably. It is read like the other meta: `try (v.meta.knownVulnerabilities or [ ]) [ ]`
  and `try (v.meta.insecure or false) false`, inside the existing row
  `tryEval`. The spec measures the walk's time before and after, because
  the walk is the cost of a reindex.
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

1. **A `version` column?** The issue asks to consider one. Recommendation:
   **no, not in this change.**
   - Cost of adding it: an inserted column shifts field 5 (preview). The
     index is read by position in nixarchy-pkg (`labels_tsv` reads `$5`,
     `cmd_search` reads `.[4]` and `.[5]`), `apps.nix` itself (the status
     and curated awk passes read `$3`, `$4`, `$5`) and the flatpak/new-package
     rows (`apps.nix:3699-3700`, already in the five-field shape). Appending
     a sixth column after the preview collides with the `scope` column
     nixarchy-pkg already puts at `.[5]` for its merged rows. So any
     placement breaks something or needs a coordinated change in two
     repositories.
   - Benefit: nixarchy-pkg already reads the version from the preview and
     nothing there waits for a column (the issue says so).
   - Do it later, as its own change with the row-format version bump the
     two repositories agree on.
2. **The `[insecure]` summary suffix.** Writing it keeps the three flags
   consistent in `nixarchy search`, but nixarchy-pkg's `untag` does not strip
   it, so the panel's card would show the tag twice (the problem #30 fixed
   for the other two). Options: write the flag only (no suffix), or write the
   suffix and have nixarchy-pkg's `untag` learn it first. Recommendation:
   flag and preview paragraph now, summary suffix only after nixarchy-pkg
   strips it.
3. **`meta.insecure`.** nixpkgs' own test is `knownVulnerabilities != [ ]`
   (check-meta); `meta.insecure` is not a nixpkgs attribute that I found. The
   issue names both, so the walk reads both. The spec verifies against the
   pinned nixpkgs whether `meta.insecure` is ever set, and drops it if not.
4. **Flag word.** `insecure` (matches the issue and the panel's wording).
   Confirm with the nixarchy-pkg side before it ships.
