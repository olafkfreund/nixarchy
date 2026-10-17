{ inputs, pkgs }:
# Every visible menu row's action, followed into the scripts it runs, against
# the reasons in data/menu-actions.nix (#1304). See
# .github/scripts/check-menu-actions.py for what it can and cannot see.
let
  # The same machine menu-verbs reads, so both checks see the same rows.
  eval = inputs.self.nixosConfigurations.reference.extendModules {
    modules = [
      {
        programs.nixarchy.services.boxes.enable = true;
        programs.nixarchy.services.devenv.enable = true;
      }
    ];
  };
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-menu-actions"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    menu = eval.config.environment.etc."nixarchy/omarchy-menu.jsonc".source;
    bin = "${shipped}/share/omarchy/bin";
    entries = pkgs.writeText "menu-actions.json" (builtins.toJSON (import ../data/menu-actions.nix));
    script = ../.github/scripts/check-menu-actions.py;
    ledger = ../.github/scripts/check-bin-ledger.py;
  }
  ''
    python3 -B $script --no-pending --menu "$menu" --bin "$bin" --entries "$entries" --ledger-script "$ledger"
    touch $out
  ''
