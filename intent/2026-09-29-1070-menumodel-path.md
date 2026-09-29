---
status: draft
issue: 1070
author: olafkfreund
---

# Intent: The menu plugins load MenuModel.js from the Omarchy they were built against

## Problem

nixarchy-menu (`providers/OmarchyMenu.qml:5`) and nixi (`MenuSearch.qml:21`)
both import

```qml
import "file:///run/current-system/sw/share/omarchy/shell/plugins/menu/MenuModel.js" as MenuModel
```

A QML import is static, so this is a hard-coded runtime path that holds only
where the system profile links `/share/omarchy`.

- **#1069** made nixarchy link it, a hotfix, after #1054 shipped a menu that
  could not load on any nixarchy install.
- The path is still wrong for three reasons:
  - it assumes a NixOS system profile, which rules out standalone Home Manager
    and any non-NixOS host;
  - it points at whatever omarchy the *system* links, not the one the plugin
    was built and tested against;
  - it fails silently: a missing file makes the whole palette unavailable,
    with nothing but a journal warning.

**nixarchy-menu already knows the fix.** Its own `checks` build
(`flake.nix:147-154`) rewrites that exact import to `file://${omarchy}`, its
pinned Omarchy input, which nixarchy makes follow nixarchy's own. The `plugin`
output that users install does not apply it.

## Proposed outcome

Both plugins load `MenuModel.js` from a store path fixed at build time: the
Omarchy they were built against. The menu then works with or without
`/share/omarchy` in the system profile, and a check proves it by building
without #1069's link.

## Affected users and systems

- **nixarchy-menu** (`olafkfreund/nixarchy-menu`): its `plugin` package.
- **nixi** (`olafkfreund/nixi-nixarchy`): its plugin package, or nixarchy's
  packaging of it.
- **nixarchy:** the pin bumps, and whether #1069's `pathsToLink` stays.

## Constraints

- **Cross-repository work in your own repositories.** Each change follows
  that repository's own process, with nixarchy's pin bump after it is
  released.
- **The substitution is `--replace-fail`,** so an upstream change to the
  import fails the build rather than silently falling back.
- **Nothing is posted anywhere but your own repositories.**

## Open questions

1. **Where each fix lives.** Default proposal:
   - **nixarchy-menu:** fix it in its repository, by applying the same
     `substituteInPlace` its checks already use to the `plugin` output. That
     is a few lines, and every Nix consumer benefits. Then bump the pin here.
   - **nixi:** its flake has no `omarchy` input. Either (a) add one, following
     nixarchy's as nixarchy-menu does, and substitute the same way, or (b)
     have nixarchy substitute nixi's import when packaging it, which is
     nixarchy-only. Default proposal: (a). The fix belongs with the plugin.
2. **#1069's `pathsToLink` after this.** Default proposal: keep it. It costs a
   symlink tree, and anything else that assumes the path keeps working.
   Revisit if it ever conflicts.
