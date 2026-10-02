{
  pkgs,
  omarchy,
  omarchySrc,
}:
# #1155: an Instantiator handed a fresh JS array as its model cannot diff it,
# so ANY plugin change rebuilt every panel, not just the changed one -- 62
# duplicate Panel.qml loads counted on p620 after a single restart. Carries
# omacom/omarchy@0066ea216b (#13439): the panel list lives in a ListModel
# synced in place, so an entry whose plugin still loads the same way keeps
# its Loader.
#
# This runs tests/panel-loaders.py against BUILT shell.qml, and carries its
# own negative control (AGENTS.md section 4, after
# tests/shell-restart-race.nix's pattern): the same script run against
# upstream's unpatched shell.qml MUST fail. If it no longer does, this check
# can no longer tell the bug from the fix.
pkgs.runCommand "nixarchy-panel-loaders"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    script=${./panel-loaders.py}
    upstream=${omarchySrc}/shell/shell.qml
    patched=${omarchy}/share/omarchy/shell/shell.qml
    [ -f "$upstream" ] && [ -f "$patched" ] || { echo "shell.qml missing ($upstream, $patched)" >&2; exit 1; }

    # The negative control: upstream's unpatched shell.qml must fail.
    if python3 "$script" "$upstream" > control.log 2>&1; then
      echo "FAIL: the control passed against upstream's unpatched shell.qml --" \
        "this check can no longer tell the bug from the fix"
      cat control.log
      exit 1
    fi
    # Failing is not enough: it must fail on the bug, not on a crash.
    grep -q 'FAIL: Instantiator' control.log || {
      echo "FAIL: the control failed, but not on the panel Instantiator:"
      cat control.log
      exit 1
    }
    echo "control: upstream's unpatched shell.qml fails, as it should:"
    cat control.log

    # The real check: what ships.
    if ! python3 "$script" "$patched" > built.log 2>&1; then
      echo "FAIL: the built shell.qml does not keep panel loaders across a plugin change:"
      cat built.log
      exit 1
    fi
    cat built.log
    touch $out
  ''
