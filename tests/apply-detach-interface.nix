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

    # 5. --detach forwards the pins into the unit (#986).
    #
    # The gap this closes: the --detach branch exited before the hash loop
    # ran, so a caller that pinned what it checked and asked for a detached
    # build got an UNPINNED build, silently. Case 4 passed throughout, because
    # it never passed --detach -- section 3's lesson landing on a check I
    # wrote: it held constant the one variable that mattered.
    #
    # STATIC, and that is a limitation rather than a choice. The obvious
    # behavioural test stubs systemd-run and reads the unit's command line;
    # that cannot work, because nixarchy-apply is a writeShellApplication with
    # pkgs.systemd in runtimeInputs and the strict PATH beats any stub. The
    # first version of this case did it anyway and failed for that reason, not
    # for the bug -- the fourth time in this repository a PATH stub has lost to
    # runtimeInputs (see tests/AGENTS.md).
    #
    # So the assertion is on the shipped script: the systemd-run invocation
    # must expand the expect array. It cannot tell a forwarded pin from a
    # malformed one, and says so rather than implying otherwise.
    grep -q 'expect-sha256=' "$apply" \
      || fail "the --detach branch does not forward --expect-sha256 into the unit"
    grep -A6 'systemd-run --user --unit=nixarchy-rebuild' "$apply" | grep -q 'expect-sha256=' \
      || fail "--expect-sha256 is accepted but not forwarded by the systemd-run call"

    # 6. The bytes that were hashed are the bytes that get built (#986 item 2).
    #
    # apply used to hash the file and then `cp` it 28 lines later, with nothing
    # held in between, so a write in that window was built unchecked -- the pin
    # proved the bytes at check time, not the bytes that were built. It now
    # snapshots the file, hashes the snapshot, and copies the snapshot.
    #
    # ASSERTED STATICALLY, and that is a limitation rather than a preference.
    # The behavioural version races a writer against apply; the window is
    # microseconds on this machine, a 0.3 s sleep never landed in it, and the
    # case stayed GREEN with the snapshot removed. A timing fixture that cannot
    # fail is the green light section 1 is about, so it was deleted rather than
    # shipped. What is asserted is that the copy loop reads the snapshot.
    grep -q 'src="\$pinned/\$part.nix"' "$apply" \
      || fail "the copy loop no longer reads the pinned snapshot (#986 item 2)"
    grep -q 'sha256sum <"\$pinned/\$part.nix"' "$apply" \
      || fail "the hash is no longer taken from the snapshot"

    mkdir -p $out
    echo "apply detach interface: 4 cases asserted (--status is unreachable here)"
  ''
