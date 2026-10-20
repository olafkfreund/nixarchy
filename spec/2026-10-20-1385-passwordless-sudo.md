---
status: draft
issue: 1385
intent: intent/2026-10-20-1385-passwordless-sudo.md
---

# Spec: Omarchy's passwordless-sudo toggle is hidden everywhere on nixarchy

## Design

### 1. Edge: the indicator never shows and never runs the command

This applies to quattro's `shell/plugins/bar/indicators/PasswordlessSudo.qml`
(a `BarIndicator`). Two `substituteInPlace --replace-fail` edits in
`pkgs/omarchy/default.nix`, in edge's quattro-only section, beside the
other edge-only patches:

| upstream line | becomes | effect |
|---|---|---|
| `  active: granted` | `  visible: false; active: granted` | never visible, in the default bar or in any saved indicator list |
| `    if (!root.bar) return` (the first line of `refresh()`, the only occurrence) | `    return` | `refresh()` returns before starting `statusProc`, so `omarchy-sudo-passwordless --active` never runs, whether at start, on bar change, or on `refreshRequested` |

The file stays, so a saved list that names `PasswordlessSudo` still
resolves, and nothing errors. `onPressed` cannot fire on an invisible
item.

This is preferred over editing `Indicators.qml`'s `defaultIndicatorEntries`,
because neutering the file covers the defaults *and* every saved list in
one place. The defaults list is left alone.

### 2. Edge: settings no longer offer it

`Indicators.manifest.json` lists `PasswordlessSudo` among the indicator
widget's `options`. Remove that option with `jq`:

```
del(.barWidget.schema[].options[]? | select(.value == "PasswordlessSudo"))
```

Assert afterwards that `PasswordlessSudo` no longer appears, so a jq that
matched nothing fails the build. The plan uses whichever JSON tool
`default.nix` already uses, and adds `jq` to `nativeBuildInputs` only if
none is there.

### 3. Stable: the menu row is hidden

On `main`, `modules/apps.nix` gains the same override edge already
carries:
`"setup.security.passwordless-sudo" = { when = "false"; };`, with edge's
one-line comment. Edge already has it, so a merge of `main` into
`edge-candidate` resolves to one copy. The plan proves that by a trial
merge.

### 4. Unchanged

- `pkgs/omarchy/nix-bin/omarchy-sudo-passwordless`, the stub. Typed by
  hand, it still explains `security.sudo.extraRules`.
- `data/bin-ledger.nix`'s row. It is still `replace`.

## Docs

`docs/manual/security.md`: the paragraph about the menu row says the
toggle is hidden on both channels, in the menu and the bar, and why. The
declarative recipe stays.

## Check (§1)

A cheap `runCommand`, `checks.passwordless-sudo-hidden`, over the shipped
`omarchy` package:

- if `shell/plugins/bar/indicators/PasswordlessSudo.qml` exists (edge), it
  must contain `visible: false;` and its `refresh()` must begin with
  `return`;
- if `Indicators.manifest.json` exists, it must not contain
  `PasswordlessSudo`;
- `setup.security.passwordless-sudo` must evaluate to `when = "false"`,
  read the same way the existing menu checks read the row overrides.

On `main` (4.0.6), only the menu assertion applies; on edge, all three
do. Red runs:
- edge with substitution 1 removed;
- edge with the jq step removed;
- main with the row override removed.

Each must name what failed.

## Alternatives rejected

- **Delete `PasswordlessSudo.qml`:** a saved list naming it would then
  raise a QML load error, which `checks.session` treats as a failure.
- **Port the feature:** the owner chose to hide it (intent).

## Risks

- **A quattro rewrite of these lines** fails the build at
  `--replace-fail`, which is the intended alarm.
- **`BarIndicator` might bind `visible` itself.** A derived item's own
  binding overrides the base's. The plan confirms that on the built shell
  with `checks.session` on edge, which reports no QML errors.

## Verification

- `checks.passwordless-sudo-hidden`: green on main and edge, red for each
  break above.
- `checks.session` on edge is green.
- On p620, after edge publishes: no sudo icon in the bar, and Settings ›
  Bar › Indicators does not list it.
