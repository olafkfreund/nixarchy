{ lib, prev }:
let
  hookFile = prev.path + "/pkgs/build-support/rust/hooks/cargo-setup-hook.sh";
  hasHook =
    builtins.pathExists hookFile && lib.hasInfix "cargoUseSystemLibs" (builtins.readFile hookFile);
  # Why: pkgs/AGENTS.md#cargo-system-libs-1722
  # The libraries upstream added; drop a row when nixpkgs carries the fix.
  needs = {
    codex = [
      "aws-lc"
      "oniguruma"
      "sqlite"
      "zstd"
    ]; # NixOS/nixpkgs@16b463698a
    omp = [
      "oniguruma"
      "zstd"
    ]; # NixOS/nixpkgs@43c51fe5d9
  };
  present = lib.filterAttrs (n: _: prev ? ${n}) needs;
  missing =
    n: libs:
    let
      have = map (d: d.pname or null) (prev.${n}.buildInputs or [ ]);
    in
    lib.filter (l: !(lib.elem prev.${l}.pname have)) libs;
  carried = lib.mapAttrs (
    n: libs:
    let
      m = missing n libs;
    in
    if !hasHook || m == [ ] then
      prev.${n}
    else
      prev.${n}.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ map (l: prev.${l}) m;
      })
  ) present;
  status = lib.mapAttrs (
    n: libs:
    if !hasHook then
      "inactive"
    else if missing n libs == [ ] then
      "dead"
    else
      "needed"
  ) present;
in
{
  inherit status;
  # codex-acp execs codex by store path, so it must name the carried one. The key
  # set must not read `status`: an overlay's names cannot force prev.codex.
  packages =
    carried
    // lib.optionalAttrs (prev ? codex-acp && carried ? codex) {
      codex-acp =
        if status.codex == "needed" then
          prev.codex-acp.override { inherit (carried) codex; }
        else
          prev.codex-acp;
    };
}
