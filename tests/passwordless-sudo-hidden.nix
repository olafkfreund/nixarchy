{
  inputs,
  pkgs,
  omarchy,
}:
# #1385: sudo is configuration on NixOS, so quattro's passwordless-sudo toggle
# is hidden in the menu (all channels) and in the bar (edge, where the
# indicator and its manifest option exist). Each file-based assertion applies
# only where the file exists, so main passes on the menu row alone.
let
  # The generated menu, as menu-verbs.nix reads it.
  menu =
    inputs.self.nixosConfigurations.reference.config.environment.etc."nixarchy/omarchy-menu.jsonc".source;
in
pkgs.runCommand "nixarchy-passwordless-sudo-hidden" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -euo pipefail
  shell=${omarchy}/share/omarchy/shell/plugins/bar

  qml=$shell/indicators/PasswordlessSudo.qml
  if [ -e "$qml" ]; then
    if ! grep -qF 'visible: false;' "$qml"; then
      echo "PasswordlessSudo.qml is not hidden: no 'visible: false;' (#1385)" >&2
      exit 1
    fi
    first=$(sed -n '/function refresh/,/^  }/p' "$qml" | sed -n '2p' | tr -d '[:space:]')
    if [ "$first" != return ]; then
      echo "PasswordlessSudo.qml refresh() still polls: first statement is '$first', not 'return' (#1385)" >&2
      exit 1
    fi
  fi

  manifest=$shell/widgets/Indicators.manifest.json
  if [ -e "$manifest" ] && grep -qF PasswordlessSudo "$manifest"; then
    echo "Indicators.manifest.json still offers PasswordlessSudo (#1385)" >&2
    exit 1
  fi

  when=$(sed '/^\/\//d' ${menu} | jq -r '.["setup.security.passwordless-sudo"].when // ""')
  if [ "$when" != false ]; then
    echo "setup.security.passwordless-sudo has when='$when', not 'false': the menu row is shown (#1385)" >&2
    exit 1
  fi
  touch "$out"
''
