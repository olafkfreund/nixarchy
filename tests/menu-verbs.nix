{ inputs, pkgs }:
# Every menu row's action, against the subcommands the CLI it invokes has.
#
# The case: "trigger.vm.new" ran `nixarchy-vm new`. There is no `new` -- the
# verb is `create` -- so the row printed
#
#   nixarchy-vm: unknown subcommand 'new'
#
# and closed the terminal. It shipped, and a tester found it, because the
# action had been written to match the menu KEY (trigger.vm.new) rather than
# the CLI. Its siblings work only by coincidence: run, stop and rm happen to
# be spelled the same on both sides.
#
# Nothing here could have caught it. The group is gated on `nixarchy-vm
# --check`, which is `exit 0` and says nothing about any verb; the VM tests
# call `nixarchy-vm create` directly, spelling it correctly and never reading
# the menu; and a menu action is a string in a Nix attrset, which evaluation
# does not validate. Sibling of tests/doc-options.nix: text that names a real
# thing is a claim, and a claim gets checked.
#
# Read from the GENERATED menu rather than from modules/apps.nix, because that
# is the file the desktop executes, it is where the box template rows exist at
# all (they are produced by a mapAttrs' and have no source line of their own),
# and a bug in the generator is as capable of breaking a row as a typo is.
let
  system = pkgs.stdenv.hostPlatform.system;

  # reference, plus boxes -- the box group is gated on services.boxes.enable
  # and would otherwise contribute no rows, quietly halving what is checked.
  eval = inputs.self.nixosConfigurations.reference.extendModules {
    modules = [ { programs.nixarchy.services.boxes.enable = true; } ];
  };

  menu = eval.config.environment.etc."nixarchy/omarchy-menu.jsonc".source;

  vmcli = inputs.self.packages.${system}.nixarchy-vm;
  boxcli = inputs.self.packages.${system}.nixarchy-box;

  # nixarchy-channel ships in the omarchy tree rather than as its own package,
  # so it is reached through the built tree the same way the menu reaches it.
  omarchyPkg = (pkgs.extend inputs.self.overlays.default).omarchy;
in
pkgs.runCommand "nixarchy-menu-verbs"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    set -euo pipefail

    # The verbs each CLI accepts, read out of the shipped script's own case
    # block -- the built artifact, not the repo source, so a build that mangles
    # the dispatch is caught too.
    # Two `case` shapes, because both are in use: most of these scripts
    # dispatch on "$1" directly, and nixarchy-channel assigns it to $target
    # first. Verified that adding the second address leaves nixarchy-vm and
    # nixarchy-box's verb lists byte-identical (10 each) -- a helper that
    # claims to read "the shipped script's own case block" should not be
    # silently blind to a script that writes it the other way.
    #
    # The character class allows spaces so `"" | stable | unstable)` parses;
    # the `tr -d ' '` below already removes them.
    verbs_of() {
      sed -n -e '/case "''${1:-}" in/,/^ *esac/p' \
             -e '/case "$target" in/,/^ *esac/p' "$1" \
        | grep -oE '^[[:space:]]*[-a-z|"[:space:]]+\)' \
        | tr -d ' )"' \
        | tr '|' '\n' \
        | grep -vE '^\*?$' \
        | sort -u
    }

    verbs_of ${vmcli}/bin/nixarchy-vm   > vm-verbs
    verbs_of ${boxcli}/bin/nixarchy-box > box-verbs
    verbs_of ${omarchyPkg}/share/omarchy/bin/nixarchy-channel > channel-verbs

    echo "nixarchy-vm accepts:  $(tr '\n' ' ' < vm-verbs)"
    echo "nixarchy-box accepts: $(tr '\n' ' ' < box-verbs)"
    echo "nixarchy-channel accepts: $(tr '\n' ' ' < channel-verbs)"

    # A floor. An empty verb list makes every row below pass, turning "the
    # dispatch stopped parsing" into a green check -- the exact shape of failure
    # this file exists to reject.
    test "$(wc -l < vm-verbs)"  -ge 5
    test "$(wc -l < box-verbs)" -ge 5
    # Two: stable and unstable. `rc` and `dev` are pacman repositories with no
    # NixOS meaning and stay out of the menu, so this floor is 2 and not 4.
    test "$(wc -l < channel-verbs)" -ge 2

    fail=0
    checked=0

    # Both spellings, because both are in use: the vm rows call `nixarchy-vm
    # <verb>` and the box rows go through the top-level `nixarchy box <verb>`.
    scan() {
      local pattern="$1" field="$2" cli="$3" list="$4"
      while read -r verb; do
        [ -n "$verb" ] || continue
        checked=$((checked + 1))
        if ! grep -qx -- "$verb" "$list"; then
          echo "ERROR: a menu row runs '$cli $verb', which $cli does not accept" >&2
          echo "       it accepts: $(tr '\n' ' ' < "$list")" >&2
          fail=1
        fi
      done < <(grep -oE "$pattern" ${menu} | awk "{print \$$field}" | sort -u)
    }

    scan '\bnixarchy-vm +[-a-z]+'      2 nixarchy-vm  vm-verbs
    scan '\bnixarchy +vm +[-a-z]+'     3 nixarchy-vm  vm-verbs
    scan '\bnixarchy-box +[-a-z]+'     2 nixarchy-box box-verbs
    scan '\bnixarchy +box +[-a-z]+'    3 nixarchy-box box-verbs

    # The channel rows (#529). Added with the rows themselves rather than
    # after the first one breaks, because the row this file was written about
    # -- `nixarchy-vm new`, a verb that does not exist -- shipped and was
    # found by a tester.
    scan '\bnixarchy-channel +[-a-z]+'  2 nixarchy-channel channel-verbs
    scan '\bnixarchy +channel +[-a-z]+' 3 nixarchy-channel channel-verbs

    # The second floor: if the menu stopped carrying these rows, every scan
    # above would run zero times and the check would pass having read nothing.
    echo "menu verbs checked: $checked"
    test "$checked" -ge 8

    test "$fail" -eq 0
    echo "every menu row names a subcommand its CLI has"
    touch $out
  ''
