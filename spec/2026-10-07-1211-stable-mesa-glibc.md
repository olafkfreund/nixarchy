---
status: draft
issue: 1211
intent: intent/2026-10-07-1211-stable-mesa-glibc.md
---

# Spec: stable machines get a login screen

## Design

### 1. Hyprland's Mesa only where its glibc is not newer than the system's

In `modules/nixos.nix`, the graphics block (`:1265-1266`) applies
`hyprPkgs.mesa` / `hyprPkgs.pkgsi686Linux.mesa` only when

```nix
hyprMesaFits = lib.versionAtLeast pkgs.glibc.version hyprPkgs.glibc.version;
```

holds. That is, when the system's glibc is at least as new as the glibc Hyprland's
Mesa was built against. Otherwise the block sets nothing, and the system keeps
nixpkgs' own Mesa (`graphics.nix`'s `mkDefault`).

- **Unstable:** the pin and the system share a glibc, so the rule is true and
  nothing changes. #1158 stays fixed.
- **26.05:** 2.42 < 2.43, so the rule is false. The system Mesa is 26.05's,
  which the greeter, the user's 26.05 OpenGL programs, and (by backward
  compatibility) Hyprland's newer glibc can all load.
- **The #1158 direction** (a compositor older than the system) is the case the
  rule keeps: there the system's glibc is newer, so Hyprland's Mesa is used.

The glibc version is the signal rather than "is this a stable release",
because it is the property the loader actually checks
(`version GLIBC_2.43 not found`), and it stays right when Hyprland's pin and
nixpkgs drift in either direction.

The `#1163` clash check (`:16-26`) compares `extraPackages` against `ours`.
It only means something while `ours` is the system Mesa, so it is gated on the
same `hyprMesaFits`.

The comment above the block and `docs/internals/flake.md` (#1158's section)
gain the rule and its reason.

### 2. Proof: the stable session VM

The open risk is Hyprland's own `libgbm` (from its unstable Mesa) loading
26.05's `dri_gbm.so` backend from `/run/opengl-driver`. That is a GBM backend
ABI question, not a glibc one, and only a boot answers it. The deciding test is
the weekly job's exact command, run on p620:
`nix build .#checks.x86_64-linux.session --override-input nixpkgs <26.05> --override-input home-manager <26.05>`.
It passes the greeter wait (the #1211 failure) and goes on to drive the
Hyprland session.

**If Hyprland fails to start on the older backend**, the fallback is in the
plan, not here: give Hyprland's own process its Mesa through the session
wrapper's `GBM_BACKENDS_PATH` / `__EGL_VENDOR_LIBRARY_FILENAMES` /
`LIBGL_DRIVERS_PATH`, and unset them for children in Hyprland's environment.
It would come back for a spec change first, because it touches every program
the session launches.

## Alternatives rejected

- **Make the installer template follow Hyprland's nixpkgs to the user's
  26.05.** Hyprland would then build from 26.05, with no cache, on every
  stable machine, and #1158's own reason for not following (the binary cache)
  applies.
- **Detect "stable" by `lib.trivial.release`.** It is the wrong question. The
  loader cares about glibc, and the release number says nothing about the pin.
- **Ship Hyprland's Mesa system-wide plus a 26.05 Mesa only for the greeter.**
  It fixes the greeter and leaves every OpenGL program from the user's 26.05
  package set broken.

## Risks

- **GBM backend ABI** between Hyprland's libgbm and 26.05's backend, as above.
  The VM run decides; the fallback is named.
- **The rule's comparison** on a nixpkgs where `pkgs.glibc.version` carries a
  suffix: `lib.versionAtLeast` compares dotted versions, and both sides come
  from the same kind of attribute.
- **Users who set `hardware.graphics.package` themselves.** Unchanged: the
  block is `mkOverride 900`, and a plain assignment still wins.

## Verification

- Unstable: `nixosConfigurations.reference` and `vm` evaluate to the same
  `hardware.graphics.package` path before and after (same Mesa).
- 26.05: the stable session command above passes on p620, or reaches a new
  failure past the greeter and Hyprland start, which gets its own issue.
- `checks.stable-eval` and `checks.session` (unstable) still pass.
- `nix fmt -- --ci`, statix, deadnix: clean.
