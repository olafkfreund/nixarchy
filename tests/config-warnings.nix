{ inputs, pkgs }:
# Every configuration this repository ships evaluates without warnings.
#
# Not tidiness. Both warnings this check was written after were pointing at
# real defects, and both had been printing for weeks with nobody acting:
#
#   vm: "The user 'omarchy' has multiple of the options ... set to a non-null
#   value" -- installer/host.nix sets hashedPasswordFile, which is load-bearing
#   for #436, and vm/configuration.nix sets `password`. With mutableUsers the
#   FILE wins, and the smoke VM never runs the installer that writes it, so the
#   account had NO usable password. autoLogin walked past it; `sudo` would not
#   have.
#
#   reference-hardware: "mdadm: Neither MAILADDR nor PROGRAM has been set. This
#   will cause the `mdmon` service to crash." #472 answered that for the `iso`
#   configuration and verified its warnings were empty; this one was never
#   checked and went on warning on every ISO build.
#
# A warning nobody acts on trains everyone to read past warnings, which is how
# the next real one is missed. So they are answered, and this fails if a new
# one appears.
#
# Answered, never muted: `lib.mkForce null` on the password file above is a
# statement that the VM has no installer to write it. Silencing a warning we
# do not understand would be worse than the warning.
let
  inherit (pkgs) lib;

  # Everything with a nixosConfigurations entry, derived rather than listed --
  # a hand-written list is one somebody forgets to extend, which is the failure
  # this check exists to prevent, one level up.
  configs = lib.mapAttrs (_: c: c.config.warnings or [ ]) inputs.self.nixosConfigurations;

  # Exemptions, by configuration and with the reason stated. Deliberately not
  # a list of strings to grep for: an exemption that matches by substring
  # silently covers the next warning that happens to share a word.
  #
  # The bar is "this warning is correct, and the thing it warns about is a
  # decision this configuration has already made". Not "it is noisy".
  exempt = {
    vm-big = ''
      A rig for exercising the local-AI wiring, and both warnings are advice it
      has already taken. It sets allowCpu = true -- the option that exists to
      say "I know there is no GPU here" -- and runs qwen3:8b on purpose,
      because 8b is the smallest size shown to follow the skills rather than
      answer from memory while claiming to have read them. The context-window
      warning is the same shape: correct for somebody configuring a machine to
      work on, irrelevant to a VM that exists to prove the wiring.

      Worth revisiting separately: the no-GPU warning fires even when allowCpu
      is explicitly true, which is a user saying "I know" and being told
      anyway.
    '';
  };

  offenders = lib.filterAttrs (n: w: w != [ ] && !(exempt ? ${n})) configs;

  # An exemption for a configuration that no longer warns is a stale entry, and
  # stale entries are how a list stops describing anything -- the same rule
  # tests/reference-initrd.nix applies to its excluded modules.
  stale = lib.filter (n: (configs.${n} or [ ]) == [ ]) (builtins.attrNames exempt);

  report = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: warns:
      "  ${name}:\n"
      + lib.concatStringsSep "\n" (map (w: "    ${lib.head (lib.splitString "\n" w)}") warns)
    ) offenders
  );
in
pkgs.runCommand "nixarchy-config-warnings"
  {
    inherit report;
    count = toString (builtins.length (builtins.attrNames configs));
    bad = toString (builtins.length (builtins.attrNames offenders));

    # Warnings from NIXPKGS' own code are not ours to answer and must not be
    # silenced here. There are none today; if one appears, exempt it BY NAME
    # with the reason, the way tests/reference-initrd.nix exempts modules --
    # an exclusion without a reason is where a real one hides.
    names = lib.concatStringsSep " " (builtins.attrNames configs);
    exemptNames = lib.concatStringsSep " " (builtins.attrNames exempt);
    staleExempt = lib.concatStringsSep " " stale;
  }
  ''
    echo "configurations checked: $count"
    echo "  $names"

    # A floor. An empty attrset satisfies "no offenders" while proving
    # nothing, and this repository has been bitten by a check that passed on
    # an answer it never got.
    if [ "$count" -lt 5 ]; then
      echo "::error::only $count configurations were found, which cannot be" >&2
      echo "  right -- this repository ships iso, iso-net, the references and" >&2
      echo "  the VMs. Refusing rather than passing on nothing." >&2
      exit 1
    fi

    if [ "$bad" != 0 ]; then
      echo "::error::$bad configuration(s) evaluate with warnings:" >&2
      printf '%s\n' "$report" >&2
      echo >&2
      echo "  Answer it, do not mute it. Both warnings this check was written" >&2
      echo "  after were real defects: a VM account with no usable password," >&2
      echo "  and an mdadm service that would crash. If the warning comes from" >&2
      echo "  nixpkgs rather than from us, exempt it by name in this file with" >&2
      echo "  the reason." >&2
      exit 1
    fi

    if [ -n "$staleExempt" ]; then
      echo "::error::these exemptions name configurations that no longer warn:" >&2
      for e in $staleExempt; do echo "  $e" >&2; done
      echo "  Remove them -- an exemption that exempts nothing hides the next" >&2
      echo "  real warning behind a list that looks considered." >&2
      exit 1
    fi

    [ -n "$exemptNames" ] && echo "exempt, with a reason on each: $exemptNames"
    echo "every other configuration evaluates without warnings"
    touch $out
  ''
