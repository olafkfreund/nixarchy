---
status: approved
issue: 1211
author: olafkfreund
---

# Intent: stable machines get a login screen

## Problem

On nixos-26.05 the SDDM greeter never starts. Its compositor (weston, built
from 26.05 against glibc 2.42) cannot load the system Mesa:

```text
MESA-LOADER: failed to open dri: .../glibc-2.42-84/lib/libm.so.6: version `GLIBC_2.43' not found
fatal: failed to create compositor backend
```

`modules/nixos.nix:1265-1266` sets `hardware.graphics.package` and
`package32` to `hyprPkgs.mesa`, where `hyprPkgs` is Hyprland's own nixpkgs pin
(`:14`, #1158/#1163). The reason is sound on unstable: Hyprland is built
against that pin and loads the drivers into its own process, so they must not
need a newer glibc than Hyprland has. On a stable machine the pin stays
nixos-unstable, because the installer template never overrides it. The
system-wide driver then needs glibc 2.43, while everything built from 26.05
(the greeter, and any OpenGL program in the user's package set) has 2.42.

glibc is backward compatible, not forward compatible. A process with a newer
glibc can load a library built against an older one, but not the reverse.
# 1158 was the reverse direction: a compositor older than the system Mesa. Here
the compositor is newer, so the system's own 26.05 Mesa should load in
Hyprland too.

Found by #1199's weekly stable session test on its first VM boot on 26.05. Not
in any release (`v4.0.4-2` predates #1163). It would ship with the next
release from `main`.

## Proposed outcome

- A stable machine boots to the SDDM greeter, and the Omarchy (Hyprland)
  session starts and draws.
- OpenGL programs from the user's 26.05 package set load the system driver.
- Unstable machines are unchanged: same Mesa, same closure.
- The weekly stable session test goes green, or stops on the next real
  stable-only failure, which gets its own issue.

## Affected users and systems

- Stable (`nixarchy channel stable`) machines, from the next release on.
- `modules/nixos.nix` (the graphics block and the `#1163` clash check that
  compares against `ours`).
- `docs/internals/flake.md` (#1158's explanation).

## Constraints

- No change to unstable machines' Mesa. #1158 must not come back.
- A user's own `hardware.graphics.package` still wins.
- Must land before the next normal release from `main`.

## Open questions

1. **The rule.** Use Hyprland's Mesa only when its glibc is not newer than the
   system's (`lib.versionAtLeast pkgs.glibc.version hyprPkgs.glibc.version`),
   and the system's own Mesa otherwise. Is the version comparison the right
   signal, rather than "is this a stable release"?
2. **Hyprland on the older Mesa.** Hyprland would load 26.05's Mesa and its
   libraries (libdrm, LLVM) alongside its own newer copies. The spec must
   show the session actually starts and draws, not only the greeter.
3. **The #1163 clash check** compares `extraPackages` against `ours`. With the
   system Mesa in charge, does the check still mean anything on stable, or
   should it apply only when Hyprland's Mesa is the one in use?
