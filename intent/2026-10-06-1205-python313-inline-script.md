---
status: approved
issue: 1205
author: olafkfreund
---

# Intent: stable machines can build omarchy again

## Problem

The `omarchy` package fails to build against nixpkgs 26.05:

```text
  File "<string>", line 2
    import json, re, sys
IndentationError: unexpected indent
```

`pkgs/omarchy/default.nix:1174` checks the generated menu file with
`${python3}/bin/python3 -c '...'`, and the code inside is indented to match
the surrounding Nix string. Python 3.14 (nixos-unstable) dedents `-c` code
before running it. Python 3.13 (nixos-26.05) does not, and refuses it.
Reproduced with 26.05's own `python3`.

An installed stable machine builds omarchy with its own 26.05 `python3`. The
installer template sets `nixarchy.inputs.nixpkgs.follows = "nixpkgs"`, and
the module takes its package from `pkgs.extend`. That derivation is in no
cache, so the machine builds it and fails. **The current release `v4.0.4-1`
carries the same block (`:1160` on `release`), so stable machines on the
release are affected today.**

Nothing caught it. `checks.stable-eval` only evaluates, and the first build of
# 1199's `checks.stable-session` is what found it.

It is the only site with this shape. The other inline `python3 -c` scripts
(`installer/substitutable.sh:91`, `pkgs/verify.sh:795/811/837`) are
flush-left and run on any Python.

## Proposed outcome

- `omarchy` builds against nixos-26.05 and nixos-unstable alike, with the
  menu validation still running and still failing the build on a bad menu.
- The fix reaches stable machines on the release without waiting for
  everything else on `main`: a hotfix release `v4.0.4-2`, cut from `release`
  by the procedure #1199 documents. This is the first real use of that
  procedure.
- Something fails before merge if inline Python that only 3.14 accepts comes
  back.

## Affected users and systems

- Installed machines on `nixarchy channel stable`, on `v4.0.4-1` and `main`.
- `pkgs/omarchy/default.nix`, and whatever check guards the regression.
- The `release` branch and the release workflow (a hotfix tag).

## Constraints

- No change to the unstable closure beyond the omarchy derivation itself.
- The menu validation must keep running. It has caught real escaping bugs
  (the comment above it says so).
- The hotfix tag ships to every installed machine, so it is pushed only with
  the maintainer's explicit go-ahead at that moment.
- After the hotfix, `release` must be merged back into `main` (`-s ours`), or
  the next normal release cannot fast-forward `release`.

## Open questions

1. **The guard.** Building omarchy against 26.05 on every PR is a real build
   (the derivation is not huge, but it is uncached on stable). Options: a
   `checks.stable-omarchy` that builds only the omarchy package against
   26.05, gated per PR; or rely on #1199's weekly `stable-session`, which
   builds it anyway. A cheap static check is a third option: no indented
   `python3 -c '` in `.nix` files.
2. **Hotfix contents.** Just this fix, or this fix plus #1200's herdr fix?
   `v4.0.4-1` does not contain #792, so it does not have the herdr bug, and the
   hotfix should not carry it.
3. **More stable-only failures behind this one.** The stable session build
   stopped at the first error. Once this is fixed, it may stop on the next one.
   Those get their own issues; this intent covers only this one.
