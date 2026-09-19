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
  secretcli = inputs.self.packages.${system}.nixarchy-secret;

  # nixarchy-channel ships in the omarchy tree rather than as its own package,
  # so it is reached through the built tree the same way the menu reaches it.
  omarchyPkg = (pkgs.extend inputs.self.overlays.default).omarchy;

  # Every plugin Home Manager installs on this machine, by source. A row that
  # names a plugin id is checked against these manifests (#766): attribute
  # names are free, so the id has to come from the manifest itself.
  pluginSources = pkgs.lib.concatMap (
    u: pkgs.lib.mapAttrsToList (_: p: "${p.src}") u.programs.nixarchy.plugins
  ) (builtins.attrValues eval.config.home-manager.users);

  # The herdr widget as installed, and the herdr it drives (#771). Its script
  # is upstream's and herdr is nixpkgs', so a bump on either side can rename a
  # subcommand out from under the other -- and the widget would only say
  # "error" in the bar.
  herdrSrc =
    (builtins.head (builtins.attrValues eval.config.home-manager.users))
    .programs.nixarchy.defaultPluginSet.herdr.src;

  # The MicroVMs panel as installed (#766). It drives nixarchy-vm through
  # argv arrays in Model.js, so those are the calls this CLI has to accept.
  microvmSrc =
    (builtins.head (builtins.attrValues eval.config.home-manager.users))
    .programs.nixarchy.defaultPluginSet.microvm.src;
in
pkgs.runCommand "nixarchy-menu-verbs"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
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
    verbs_of ${secretcli}/bin/nixarchy-secret > secret-verbs
    verbs_of ${omarchyPkg}/share/omarchy/bin/nixarchy-channel > channel-verbs
    for m in ${pkgs.lib.escapeShellArgs pluginSources}; do
      jq -r .id "$m/manifest.json"
    done | sort -u > plugin-ids

    echo "nixarchy-vm accepts:  $(tr '\n' ' ' < vm-verbs)"
    echo "nixarchy-box accepts: $(tr '\n' ' ' < box-verbs)"
    echo "nixarchy-secret accepts: $(tr '\n' ' ' < secret-verbs)"
    echo "nixarchy-channel accepts: $(tr '\n' ' ' < channel-verbs)"
    echo "installed plugin ids: $(tr '\n' ' ' < plugin-ids)"

    # A floor. An empty verb list makes every row below pass, turning "the
    # dispatch stopped parsing" into a green check -- the exact shape of failure
    # this file exists to reject.
    test "$(wc -l < vm-verbs)"  -ge 5
    test "$(wc -l < box-verbs)" -ge 5
    # new, edit, list, where, copy, remove -- plus the three help spellings.
    test "$(wc -l < secret-verbs)" -ge 6
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

    # The Secrets group (#611/#612). Four rows, added with the rows rather
    # than after one of them breaks -- `nixarchy-vm new`, the row this file
    # exists about, was a verb that did not exist and a tester found it.
    scan '\bnixarchy-secret +[-a-z]+'  2 nixarchy-secret secret-verbs
    scan '\bnixarchy +secret +[-a-z]+' 3 nixarchy-secret secret-verbs

    # The channel rows (#529). Added with the rows themselves rather than
    # after the first one breaks, because the row this file was written about
    # -- `nixarchy-vm new`, a verb that does not exist -- shipped and was
    # found by a tester.
    scan '\bnixarchy-channel +[-a-z]+'  2 nixarchy-channel channel-verbs
    scan '\bnixarchy +channel +[-a-z]+' 3 nixarchy-channel channel-verbs

    # The plugin rows (#766): a row opening a plugin that is not installed
    # does nothing at all, so each id has to be one this machine installs.
    scan '\bnixarchy-plugin +[a-z][-a-z.]*'               2 nixarchy-plugin plugin-ids
    scan '\bnixarchy-plugin +--enabled +[a-z][-a-z.]*'    3 nixarchy-plugin plugin-ids
    pluginrows=$(grep -coE '\bnixarchy-plugin +[a-z][-a-z.]*' ${menu} || true)
    # Packages, Podman and Boxes (Boxes is on), GitLab Pipelines, GitHub
    # Actions, Herdr, Sandbox, and Dev environments (#802).
    test "$pluginrows" -ge 8 || {
      echo "ERROR: $pluginrows menu rows open a nixarchy plugin, expected Packages, Podman, Boxes, GitLab Pipelines, GitHub Actions, Herdr, Sandbox and Dev environments" >&2
      exit 1
    }

    # MicroVMs (#766): the Sandbox rows are the panel now, so the verbs that
    # matter are the ones its Model.js runs, as `"nixarchy-vm", "<verb>"`.
    vmcalls=0
    while read -r verb; do
      vmcalls=$((vmcalls + 1))
      grep -qx -- "$verb" vm-verbs || {
        echo "ERROR: the MicroVMs plugin calls nixarchy-vm '$verb', which it does not accept" >&2
        echo "       it accepts: $(tr '\n' ' ' < vm-verbs)" >&2
        fail=1
      }
    done < <(grep -hoE '"nixarchy-vm", *"[-a-z]+"' ${microvmSrc}/Model.js \
               | grep -oE '"[-a-z]+"$' | tr -d '"' | sort -u)
    # list, templates, help, console, run, stop, rm, create, set-template.
    test "$vmcalls" -ge 7 || {
      echo "ERROR: found $vmcalls nixarchy-vm calls in the MicroVMs plugin, expected 7" >&2
      exit 1
    }
    echo "nixarchy-vm verbs the MicroVMs panel runs: $vmcalls, all accepted"

    # herdr (#771): every `<level> <sub>` herdr-sessions sends, spelled either
    # `herdr ...` or through its `"''${base[@]}"` array, must be a subcommand
    # the pinned herdr lists under that level, and its two flags must be in
    # the top-level usage. A floor, because a pattern that stopped matching
    # would check nothing and pass.
    export HOME=$TMPDIR
    herdrcalls=0
    while read -r level sub; do
      herdrcalls=$((herdrcalls + 1))
      ${pkgs.herdr}/bin/herdr "$level" --help 2>&1 \
        | sed -n '/^Commands:/,/^$/p' | awk '{print $1}' | grep -qx -- "$sub" || {
        echo "ERROR: herdr-sessions runs 'herdr $level $sub', which herdr ${pkgs.herdr.version} does not list" >&2
        fail=1
      }
    done < <(grep -hoE '(\bherdr|"\$\{base\[@\]\}") +(session|api|agent) +[a-z-]+' \
               ${herdrSrc}/bin/herdr-sessions \
             | awk '{print $(NF-1), $NF}' | sort -u)
    test "$herdrcalls" -ge 8 || {
      echo "ERROR: found $herdrcalls herdr subcommands in herdr-sessions, expected 8" >&2
      exit 1
    }
    # Captured first: under pipefail, `herdr --help | grep -q` fails whenever
    # grep matches early and herdr takes the SIGPIPE (tests/AGENTS.md).
    herdrusage=$(${pkgs.herdr}/bin/herdr --help 2>&1)
    for flag in --session --remote; do
      grep -q -- "herdr $flag " <<<"$herdrusage" || {
        echo "ERROR: herdr ${pkgs.herdr.version} no longer takes $flag, which herdr-sessions uses" >&2
        fail=1
      }
    done
    echo "herdr subcommands the widget sends: $herdrcalls, all in herdr ${pkgs.herdr.version}"

    # The second floor: if the menu stopped carrying these rows, every scan
    # above would run zero times and the check would pass having read nothing.
    echo "menu verbs checked: $checked"
    test "$checked" -ge 12

    # And the Secrets group specifically. The floor above is a sum, so losing
    # every secret row would drop it from 16 to 12 and still pass -- which is
    # the "a loop that iterated nothing" shape this file already guards
    # against for the CLIs.
    secretrows=$(grep -coE '\bnixarchy-secret +[-a-z]+' ${menu} || true)
    test "$secretrows" -ge 3 || {
      echo "ERROR: the menu has $secretrows Secrets rows; the group is gone" >&2
      exit 1
    }

    test "$fail" -eq 0
    echo "every menu row names a subcommand its CLI has"
    touch $out
  ''
