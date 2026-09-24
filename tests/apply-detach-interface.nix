{ inputs, pkgs }:
# #979: nixarchy-apply --detach started a unit and gave its caller nothing to
# hold onto, so nixarchy-flatsnap hard-coded our unit name and SubState
# protocol in another repository. This drives the real script against stub
# systemctl and journalctl.
#
# --expect-sha256's mismatch case asserts that NOTHING WAS COPIED, not that
# a message was printed. Any message satisfies the second; only the first says
# the refusal was real.
let
  apply = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-apply"
    ) inputs.self.nixosConfigurations.vm.config.environment.systemPackages
  );
in
pkgs.runCommand "nixarchy-apply-detach-interface"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      git
    ];
  }
  ''
    export HOME=$PWD/home
    apply=${apply}/bin/nixarchy-apply
    mkdir -p "$HOME/.config/nixarchy" stub flake
    printf '{ }\n' > flake/flake.nix
    printf '{ programs.nixarchy.apps.brave.enable = true; }\n' > "$HOME/.config/nixarchy/apps.nix"
    export NIXARCHY_FLAKE=$PWD/flake

    # printf, not a heredoc: a heredoc body inside an indented Nix string has to
    # start at column zero and nixfmt strips the common indent (AGENTS.md 5).
    # The shebang is the store path, not /usr/bin/env, which the sandbox has not
    # got (AGENTS.md 4).
    printf '%s\n' \
      '#!${pkgs.bash}/bin/bash' \
      'printf "%s" "$SYSTEMCTL_OUT"' > stub/systemctl
    printf '%s\n' \
      '#!${pkgs.bash}/bin/bash' \
      'echo journal' > stub/journalctl
    chmod +x stub/systemctl stub/journalctl
    export PATH=$PWD/stub:$PATH

    fail() { echo "FAIL: $1" >&2; printf '%s\n' "''${res-}" >&2; exit 1; }

    # --status and --log are NOT tested here, and that is a limitation rather
    # than an omission. nixarchy-apply is a writeShellApplication with
    # pkgs.systemd in runtimeInputs (modules/apps.nix), so the strict PATH it
    # builds beats a stub `systemctl` -- the script always gets the real one.
    # A first version of this file stubbed it anyway; the never-ran case
    # "passed" because the real systemctl reports nothing in the sandbox, which
    # is the same answer for the wrong reason. tests/apply-confirm.nix lost to
    # the identical trap with `nh` earlier the same day.
    #
    # So what is asserted below is --expect-sha256, which touches only the file
    # system. The `none`-not-`succeeded` mapping -- the trap the whole status
    # feature exists for -- is unverified here and says so in tests/AGENTS.md.

    # 4. A matching --expect-sha256 proceeds past the check.
    have=$(sha256sum <"$HOME/.config/nixarchy/apps.nix" | cut -d' ' -f1)
    res=$("$apply" --expect-sha256 "apps=$have" 2>&1 || true)
    grep -qi "is not what you checked" <<<"$res" && fail "a matching hash was refused"

    # 5. A mismatch refuses AND COPIES NOTHING. The copy is the assertion; a
    #    message is satisfied by any string.
    rm -rf flake/nixarchy
    res=$("$apply" --expect-sha256 "apps=0000000000000000000000000000000000000000000000000000000000000000" 2>&1 || true)
    grep -qi "is not what you checked" <<<"$res" || fail "a mismatching hash was not refused"
    [ ! -e flake/nixarchy/apps.nix ] || fail "a refused apply copied the file anyway"

    mkdir -p $out
    echo "apply detach interface: 2 cases asserted (--status is unreachable here)"
  ''
