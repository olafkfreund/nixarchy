---
status: approved
issue: 1211
spec: spec/2026-10-07-1211-stable-mesa-glibc.md
---

# Plan: stable machines get a login screen

## Approved decisions (from the spec)

- `hardware.graphics.package` / `package32` come from Hyprland's nixpkgs pin
  only when `lib.versionAtLeast pkgs.glibc.version hyprPkgs.glibc.version`
  (call it `hyprMesaFits`). Otherwise nixarchy sets nothing and nixpkgs' own
  Mesa stays. Unstable is unchanged. On 26.05 (glibc 2.42 against the pin's
  2.44) the system keeps 26.05's Mesa.
- The `#1163` clash check only applies while Hyprland's Mesa is in use. It
  already compares `g.package` against `ours`, so it needs no change.
- Proof is the weekly job's stable session command run on p620. If Hyprland
  cannot start on 26.05's GBM backend, stop and bring the fallback back as a
  spec change.

## Steps

1. **`modules/nixos.nix`.** In the `let` block next to `hyprPkgs` (`:14`), add
   `hyprMesaFits = lib.versionAtLeast pkgs.glibc.version hyprPkgs.glibc.version;`
   with a short comment: glibc is backward but not forward compatible, so
   Hyprland's Mesa is safe system-wide only where the system's glibc is at
   least as new (#1211). Wrap the `hardware.graphics` block (`:1265-1266`) in
   `lib.mkIf hyprMesaFits`, keeping `mkOverride 900`. Extend the comment above
   it by one line naming the rule and #1211.
   → verify unstable is unchanged:
   `nix eval --raw .#nixosConfigurations.vm.config.hardware.graphics.package.outPath`
   and the same for `reference`, before and after: identical paths. Then
   check 26.05 takes the system Mesa: build the session check with the stable
   overrides (step 3) and confirm in its log that the greeter starts.
   Traps: `hyprPkgs.glibc.version` is the pin's glibc; `pkgs.glibc.version` is
   the system's. Do not compare `stdenv` versions. `mkIf` inside a
   `config` attrset that is itself under `mkIf cfg.enable` is fine.

2. **`docs/internals/flake.md:148` section ("Hyprland's Mesa follows its own
   nixpkgs").** Add a short paragraph: the rule, why glibc direction
   decides, and that on a stable machine the system Mesa is kept (#1211).
   → verify by reading it in context.
   Traps: `docs/` is published; keep the anchor id unchanged.

3. **Proof on p620**, announced on the agent bus (1-3 h, partly cached from
   earlier runs):
   `nix build .#checks.x86_64-linux.session --override-input nixpkgs <26.05 locked> --override-input home-manager <hm 26.05 locked>`,
   with the refs read from `flake.lock` through `.nodes.root.inputs`, as
   `weekly.yml` does.
   → the greeter starts (`loginctl list-sessions` shows the greeter) and the
   test goes on to drive the Hyprland session. If it fails **past** that
   point on something else, record it and open an issue; #1211 is still
   done. If Hyprland itself cannot start (GBM backend), stop: that is the
   spec's fallback case.

## Tests

- Unstable Mesa paths identical before/after for `vm` and `reference`.
- `checks.stable-eval`, unstable `checks.session` (CI), `nix fmt -- --ci`,
  statix, deadnix: clean.
- Step 3's stable run as above.

*Result (2026-10-07, p620):* the stable session command passed end to end.
The SDDM greeter started (`Greeter session started successfully`), the login
handed over cleanly, and the whole session script finished, so Hyprland runs
on 26.05's own Mesa (`mesa-26.1.8`) and the spec's GBM backend risk did not
materialise. Unstable `vm` and `reference` kept the identical Mesa path.

## Rollback

Revert the PR. Stable machines lose the greeter again; unstable is untouched
either way.
