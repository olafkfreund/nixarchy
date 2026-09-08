{ inputs, pkgs }:
# Two machines whose only difference is their name build the same system parts.
#
# This is the property the offline image lives or dies by, and until #404 it
# was not true. `networking.hostName` reaches further than it looks:
# nixos/modules/system/boot/systemd/initrd.nix:597 writes it into the INITRD
# unconditionally, and top-level.nix:60 names the toplevel derivation
# "nixos-system-${system.name}-${label}" with system.name defaulting to the
# hostname. So a machine called `isotest` and a machine called `nixarchy`
# had different initrds and different system store paths -- and a system the
# image does not carry has to be BUILT, which with no network is the stage0
# source bootstrap: 677 derivations, measured, dying on a Debian patch.
#
# The fix is to keep the name out of the evaluation and apply it at first
# boot (installer/host.nix). This asserts it stayed out.
#
# It VARIES the thing it is about, which is the whole point: two real
# configurations differing in exactly one input. A check that pinned the
# hostname and asserted the pin would pass with the bug fully present --
# AGENTS.md section 3, on the file that section was written for.
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  machine =
    name:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko
        (import ../installer/host.nix {
          hostname = name;
          username = "someone";
        })
        (import ../installer/disk-config.nix {
          device = "/dev/vda";
          encrypt = false;
        })
        { nixpkgs.hostPlatform = system; }
      ];
    };

  a = machine "alpha";
  b = machine "omega-two";

  # The three that decide whether an offline install has to build anything.
  # unsafeDiscardStringContext, and it is the difference between a check that
  # answers in seconds and one that builds two entire NixOS systems.
  #
  # A drvPath is a string WITH CONTEXT: using it inside another derivation
  # tells nix "realise this first". So comparing two drvPaths the obvious way
  # made this check depend on both machines being BUILT -- a multi-gigabyte
  # download and the better part of an hour, to answer a question that is pure
  # evaluation. The paths are wanted here as text, not as things to build.
  #
  # Safe precisely because nothing here consumes them: they are compared and
  # printed. If this file ever needs to build one, the context must come back.
  drv = p: builtins.unsafeDiscardStringContext p;
  parts = {
    initrd = c: drv c.config.system.build.initialRamdisk.drvPath;
    toplevel = c: drv c.config.system.build.toplevel.drvPath;
    etc = c: drv c.config.system.build.etc.drvPath;
  };

  compare = lib.mapAttrsToList (n: f: {
    name = n;
    same = f a == f b;
    left = f a;
    right = f b;
  }) parts;

  differing = builtins.filter (c: !c.same) compare;
in
pkgs.runCommand "nixarchy-machine-name-free"
  {
    report = lib.concatMapStringsSep "\n" (
      c: "  ${c.name}: ${if c.same then "same" else "DIFFERS"}"
    ) compare;
    bad = lib.concatMapStringsSep "\n" (c: "  ${c.name}\n    ${c.left}\n    ${c.right}") differing;
    checked = toString (builtins.length compare);
  }
  ''
    echo "two machines, named alpha and omega-two:"
    printf '%s\n' "$report"

    # A floor. An empty comparison list would make the test below pass having
    # compared nothing, which is the one wrong answer it can give.
    test "$checked" -ge 3

    if [ -n "$bad" ]; then
      echo >&2
      echo "these parts still carry the machine's name:" >&2
      printf '%s\n' "$bad" >&2
      echo >&2
      echo "A part that differs per machine has to be BUILT by the installer." >&2
      echo "On the offline image there is nothing to build it FROM, so nix walks" >&2
      echo "back to the source bootstrap and the install dies. See #404, and the" >&2
      echo "note on networking.hostName in installer/host.nix." >&2
      exit 1
    fi

    echo "the machine's name is not an input to any of them"
    touch $out
  ''
