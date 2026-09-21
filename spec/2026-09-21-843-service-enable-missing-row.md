---
status: draft
issue: 843
intent: intent/2026-09-21-843-service-enable-missing-row.md
---

# Spec: enabling a service works on an older services.nix

Approved in the intent: running the script re-adds a row the user deleted,
because it's an explicit request, and the row goes just before the closing
`}` of the attrset.

## Design

The insertion already exists. `nixarchy-catalogue-diff --add`
(`modules/apps.nix:1153`) finds rows missing by marker and writes them
before the module's closing brace, never after it, for the reason in its
comments: an uncommented row after the final `}` breaks parsing. It has
three properties this change can't use as they are: it adds every missing
row, it covers apps, services and advanced, and it writes a dated heading.
So it gains one narrow mode, and the insertion stays in one place.

### `nixarchy-catalogue-diff --add-one <part> <id>`

- `<part>` is `apps`, `services` or `advanced`, and `<id>` passes the same
  `[a-z0-9_.-]` rule the markers use. Anything else gets usage and exit 2.
- It adds only `#@ <id>` from `<part>-template.nix`, through the same
  before-the-brace path, including the `programs.nixarchy.apps.` rewrite
  for apps. The heading reads `# ── Added by nixarchy-catalogue-diff,
  <date> ──`, as today.
- If the marker is already in the user's file: no change, exit 0. If it's
  not in the template: "no <id> in <template>", exit 1. If the file has no
  closing brace on its own line: today's refusal, exit 1.
- `NIXARCHY_TEMPLATES` is honoured, as it is today.

The loop body becomes a function the existing `--add` and the new mode
both call. No behaviour of today's two modes changes.

### `nixarchy-service-enable`

- `-h` or `--help`, checked before the id validation, prints:
  ```
  usage: nixarchy-service-enable <service-id>
    A row missing from services.nix is added from /etc/nixarchy/services-template.nix.
  ```
  and exits 0. nixarchy-microvm matches on `usage:` plus "missing".
- When the marker is missing from the user's file, it runs
  `nixarchy-catalogue-diff --add-one services "$id"` and says "added the
  <id> row from the template". If that fails (the id isn't in the
  template, or there's no brace), today's message and exit 1 stand.
  Otherwise it continues to the usual enable.
- `runtimeInputs` gains nothing: `nixarchy-catalogue-diff` is on `PATH`
  from the same package set.

## Alternatives rejected

- **Copying the 15-line insertion into `service-enable`.** Two copies of a
  subtle rule (the brace position) drift apart.
- **Calling plain `--add`.** It rewrites far more than the one row the user
  asked for.
- **Regenerating `services.nix`.** The file is the user's, and nothing
  rewrites it once it exists.

## Risks

- `catalogue-diff`'s loop becomes a function. Its existing test
  (`tests/options.nix`, "catalogue-diff finds a missing row and --add
  restores it") guards today's behaviour and must still pass unchanged.
- A user file whose closing `}` isn't on its own line is refused, as with
  `--add` today.

## Verification

In `tests/options.nix`, next to the enable/disable test:

- delete the `#@ $svcid` row from a copy of the template, then run
  `nixarchy-service-enable "$svcid"`. The row is back before the final `}`,
  it's enabled, and every other line is unchanged (diff against the
  template with only that row's comment state differing, plus the heading);
- `nixarchy-service-enable --help` exits 0 and prints `usage:` and
  "missing";
- `nixarchy-catalogue-diff --add-one services bogus` exits 1 and changes
  nothing (cksum);
- the existing catalogue-diff and enable/disable tests pass as they are.

Then `nix flake check` (or the repo's `just check`), and on razer after
merge: `nixarchy-service-enable --help` shows the usage, and
nixarchy-microvm's Kind warning disappears on a file without the row.
