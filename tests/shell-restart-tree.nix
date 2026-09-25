{ pkgs, omarchy }:
# #982: after a rebuild the shell kept reading the LOGIN-TIME omarchy tree,
# even across omarchy-restart-shell, so generated menu data only took effect at
# the next re-login. #961's Ask aliases shipped and were invisible.
#
# The script already read the session's OMARCHY_PATH for the KILL, under a
# comment saying the user manager receives Hyprland's environment at session
# start. It then relaunched through `hyprctl dispatch exec_cmd`, and Hyprland
# spawns that child with ITS OWN environment, fixed at login -- so the careful
# read was used for the kill and discarded for the launch.
#
# And the session value is not fresh either: sessionVariables reach a login
# shell through /etc/set-environment and never reach a RUNNING user manager, so
# `systemctl --user show-environment` answers with the login-time path too.
# Measured on p620: /run/current-system said h2qc3mkc..., the user manager said
# rp5i87d4.... That is why the fix reads the generated file rather than the
# session.
#
# A PATH stub works here and does not in tests/apply-confirm.nix:
# omarchy-restart-shell is upstream's and unwrapped, while nixarchy-apply is a
# writeShellApplication whose strict PATH beats any stub. tests/AGENTS.md
# records that distinction after four failures.
pkgs.runCommand "nixarchy-shell-restart-tree"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    restart=${omarchy}/share/omarchy/bin/omarchy-restart-shell
    [ -x "$restart" ] || { echo "omarchy-restart-shell is not where the package builds it" >&2; exit 1; }

    fail() { echo "FAIL: $1" >&2; printf '%s\n' "''${argv-}" >&2; exit 1; }

    # The script reads /run/current-system/etc/set-environment by absolute
    # path, which a runCommand cannot fake. So the assertions are on the
    # SHIPPED SCRIPT rather than on a run -- static, and said so plainly.
    #
    # The behavioural version would need a machine that has rebuilt since
    # login, which is the one thing no check here has and tests/AGENTS.md
    # records as the hole.

    # 1. The relaunch reads the generation's tree, not the session's.
    grep -q '/run/current-system/etc/set-environment' "$restart" \
      || fail "the relaunch no longer reads the generation's tree (#982)"

    # 2. It passes it explicitly, because Hyprland's exec_cmd child inherits
    #    Hyprland's login-time environment and nothing can change that from
    #    outside for a running instance.
    grep -q 'env OMARCHY_PATH=%s omarchy-launch-shell' "$restart" \
      || fail "the relaunch does not pass OMARCHY_PATH into the exec_cmd child"

    # 3. It falls back to today's behaviour when the generated file names no
    #    tree -- a machine with the module off, or a future where the variable
    #    moves. Parsing that file is reading a format, not an API.
    grep -q "hl.dsp.exec_cmd(\"omarchy-launch-shell\")" "$restart" \
      || fail "the fallback to the unmodified relaunch is gone"

    # 4. The KILL still uses the session value. The running shell registered
    #    under the login-time path, so killing by the new one finds nothing and
    #    leaves two shells. This asymmetry is the point of the change.
    grep -q 'session_omarchy_path=$(systemctl --user show-environment' "$restart" \
      || fail "the kill no longer resolves through the session, so it may miss the running shell"

    mkdir -p $out
    echo "shell restart tree: 4 cases asserted (static; see the comment)"
  ''
