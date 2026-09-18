# `nixarchy-plugin <id>` and `nixarchy-plugin --enabled <id>` -- what a menu row
# or a key bind calls to open a plugin's panel.
#
# Its own file for the same reason as pkgs/secret.nix: tests/options.nix runs
# the real command against a fixture shell.json.
#
# Why not `omarchy-shell shell toggle <id>` directly: for a plugin that is
# installed but not enabled the shell accepts the toggle, does nothing and
# exits 0 (modules/home.nix, the nixi comment). A row that silently does
# nothing is the failure #766's intent rules out, so an off plugin is named
# instead, with where to turn it on.
{ writeShellApplication
, jq
, omarchy
,
}:
writeShellApplication {
  name = "nixarchy-plugin";
  runtimeInputs = [
    jq
    omarchy # omarchy-shell, omarchy-notification-send
  ];
  text = ''
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

    # The registry's own rule (PluginRegistry.qml isEnabled/findEntryLocation)
    # for a plugin that is not first-party: named as the bar, anywhere in the
    # bar layout, or in plugins[] -- and not in disabledPlugins. A file read, no
    # IPC, so a menu `when` can afford it on every open.
    enabled() {
      [ -f "$conf" ] && jq -e --arg id "$1" '
        ([.disabledPlugins[]?] | index($id)) == null
        and ((.bar.id? == $id)
          or ([.bar.layout? | .. | objects | .id?] | index($id)) != null
          or ([.plugins[]? | objects | .id?] | index($id)) != null)
      ' "$conf" >/dev/null
    }

    case "''${1:-}" in
      --enabled)
        enabled "''${2:?usage: nixarchy-plugin --enabled <id>}"
        ;;
      "" | -h | --help)
        echo "usage: nixarchy-plugin <id> | nixarchy-plugin --enabled <id>"
        ;;
      *)
        if enabled "$1"; then
          exec omarchy-shell shell toggle "$1" '{}'
        fi
        omarchy-notification-send -u normal "$1 is turned off" \
          "Turn it on in Setup > Plugins, or run: omarchy plugin enable $1"
        exit 1
        ;;
    esac
  '';
}
