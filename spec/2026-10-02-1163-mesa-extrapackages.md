---
status: draft
issue: 1163
intent: intent/2026-10-02-1163-mesa-extrapackages.md
---

# Spec: nixarchy's driver Mesa never collides with a user's own Mesa

## One departure from the approved intent (decide on approval)

The intent's outcome says "a check builds `graphics-drivers` and
`graphics-drivers-32bit` for a fixture that lists its own `mesa`". With the
chosen fix (an assertion), that fixture **fails evaluation by design**, so
there is no derivation left to build. The check here instead verifies the
assertion: present exactly when the collision would happen, absent otherwise.
That is an evaluation-time check, and cheap.

**Red on today's `main`** means the assertion is missing for the colliding
fixture. Building merged environments for user-like fixtures in general is
#1164's job, and stays there.

## Design

### D1. The assertion (`modules/nixos.nix`, beside the #1162 `hardware.graphics` block)

Inside `config = lib.mkIf cfg.enable`, appended to the module's existing
`assertions` list (`:841`):

```nix
let
  g = config.hardware.graphics;
  isMesa = p: (p.pname or (lib.getName p)) == "mesa";
  ours = hyprPkgs.mesa; ours32 = hyprPkgs.pkgsi686Linux.mesa;
  clash = mine: extras: lib.filter (p: isMesa p && p.outPath != mine.outPath) extras;
  clash64 = lib.optionals (g.package.outPath == ours.outPath) (clash g.package g.extraPackages);
  clash32 = lib.optionals (g.enable32Bit && g.package32.outPath == ours32.outPath)
              (clash g.package32 g.extraPackages32);
in
```

with one assertion per side, `assertion = clash64 == [ ]` (and `clash32`).

- **Fires only when nixarchy's choice is in effect.** If the user set
  `hardware.graphics.package` themselves, so it is no longer `ours`, their
  `package` and `extraPackages` are theirs to reconcile, and nixarchy stays
  out of it.
- **Fires only for a *different* Mesa.** A user listing the identical store
  path (on today's `main`, `pkgs.mesa` is that path) collides with nothing:
  `buildEnv` takes identical paths.
- **Detection is by `pname` (`lib.getName` as the fallback),** not attribute
  name, so `pkgs.mesa`, `driversi686Linux.mesa` and an overridden Mesa are
  all caught. A package that merely ships Mesa files under another name is
  not; that is #1164's general case.
- **The message names everything the user needs,** for example:

  > programs.nixarchy: hardware.graphics.extraPackages contains
  > mesa-26.2.3 (/nix/store/v8v8…), but nixarchy sets
  > hardware.graphics.package to Hyprland's own Mesa (/nix/store/1vkz…) so
  > the drivers Hyprland loads share its glibc (#1158). Two different Mesa
  > builds collide in graphics-drivers (#1163). Remove mesa from
  > hardware.graphics.extraPackages: Hyprland's Mesa already provides it.
  > Or, to keep your own, set hardware.graphics.package = pkgs.mesa;
  > yourself, and then keeping its glibc in step with Hyprland's is yours to
  > check (docs/internals/flake.md#hyprlands-mesa-follows-its-own-nixpkgs).

  The 32-bit message is the same, with `extraPackages32`/`package32` and
  `pkgs.driversi686Linux.mesa`.
- **Cost.** `outPath` of Mesa derivations is already evaluated for any toplevel
  build, and `extraPackages` is short.
- **Mode A:** inside `mkIf cfg.enable`, so it is inert there.

### D2. `checks.graphics-mesa-clash` (`tests/graphics-mesa-clash.nix`, evaluation only)

Fixtures are built the way `tests/options.nix` builds machines
(`configWith`), each reading only `config.assertions` (no toplevel):

| fixture | expect |
|---|---|
| `extraPackages = [ fakeMesa ]`: a `runCommand` with `pname = "mesa"` | the #1163 64-bit assertion **fails**, and its message names `extraPackages` and the fix |
| `enable32Bit = true; extraPackages32 = [ fakeMesa32 ]` | the 32-bit assertion fails |
| `extraPackages = [ <Hyprland's Mesa, the same path> ]` | no #1163 assertion fails |
| `package = fakeMesa; extraPackages = [ fakeMesa ]`, i.e. the user's own package | no #1163 assertion fails |
| the reference default, no user Mesa | none fails |

- **Why a fake.** On `main`, `pkgs.mesa` is Hyprland's path, so a real "other
  Mesa" would need building one, about 1.1 GB. The fake is a one-file
  derivation named `mesa` with `share/glvnd/egl_vendor.d/50_mesa.json`, the
  file that collides. Only its `pname` and `outPath` matter to the
  assertion; it is never built by the check.
- **How it reports.** The check is a `runCommand` whose script prints each
  fixture's verdict, computed in Nix, and fails on any mismatch.
- **§1, red on today's `main`.** Today the first two fixtures report "no
  assertion", so the check is red. Shown in the PR.
- **Wiring.** A `checks.*` entry; CI runs it with no workflow edit (§4).

### D3. Docs

- **`docs/internals/flake.md`** (`hyprlands-mesa-follows-its-own-nixpkgs`):
  one paragraph on the collision and the assertion, and the two ways out.
- **`modules/AGENTS.md`'s `hardware.graphics` row** mentions the assertion.
- **The manual,** if it has a GPU or graphics page, gets one line; otherwise
  none.

## Alternatives rejected

- **(b) Step aside, or (c) use the user's Mesa:** the owner chose (a). Both
  can leave a machine that builds and then cannot start Hyprland.
- **Filtering the user's list** (dropping their `mesa` from `extraPackages`):
  nixarchy would edit a user's setting. It is forbidden by the constraints,
  and impossible without `mkForce` on a list.
- **`buildEnv { ignoreCollisions = true; }`:** that is NixOS' derivation, not
  ours. It would also silently pick one `50_mesa.json`, possibly the
  glibc-mismatched one.
- **Building the real collision in the check:** about 1.1 GB per run, for a
  property the assertion check proves for free.

## Risks

- **Rebuilds that worked now fail evaluation.** Anyone whose two Mesas happen
  not to collide on a path today (none known; `50_mesa.json` is in every
  Mesa) would now fail to build. Accepted: the message is precise, and the
  alternative is a time bomb.
- **A Mesa under another `pname`** (a renamed fork) is not caught, and falls
  back to the `buildEnv` collision. Documented; #1164.
- **`outPath` comparison forces evaluation of the user's extra packages'
  derivations.** They are evaluated for the toplevel anyway.

## Verification

1. `checks.graphics-mesa-clash`: red on `main` (the first two fixtures report
   no assertion), and green with D1. Output in the PR.
2. `checks.graphics-glibc` and `checks.options` still green; Mode A inert.
3. A p620-shaped fixture: `extraPackages` holding the real Mesa from #1154's
   nixpkgs, evaluated in a `git worktree --detach` scratch tree, never on the
   owner's host config. It produces the assertion with p620's actual paths in
   the message. Shown in the PR.
4. fmt, statix, deadnix.
