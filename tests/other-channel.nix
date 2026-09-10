{ inputs, pkgs }:
# The per-package escape does what it says, and costs what it says (#530-#532).
#
# Three claims, each of which would be easy to ship broken because nothing
# about them shows up on a machine that does not use the feature:
#
#   1. `pkgsOther` is unusable, LOUDLY, when no other channel is configured.
#      A `null` here would surface as `attribute 'helix' missing`, pointing at
#      the package rather than at the missing input.
#   2. With one configured, a package really does come from it -- a different
#      store path, not merely a second reference to the same one. That is the
#      whole feature, and "same version" is not evidence: the two channels
#      ship btop 1.4.7 and share no paths at all.
#   3. The tools say what it costs before somebody pays it.
#
# Evaluation only. Nothing here builds a package from either channel, which is
# the point -- the feature is about which closure gets built, and asking that
# question does not require building one.
let
  inherit (pkgs) lib;

  mkSystem =
    extra:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # The same shape flake.nix uses for `vm`: `inputs` already carries
      # `self`, so re-adding it is the no-op statix rejects.
      specialArgs = { inherit inputs; };
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        ../vm/configuration.nix
        extra
      ];
    };

  # Unconfigured: forcing pkgsOther must throw, and the message must name the
  # option rather than the attribute.
  unset = builtins.tryEval (
    lib.head
      (mkSystem ({ pkgsOther, ... }: { environment.systemPackages = [ pkgsOther.btop ]; }))
      .config.environment.systemPackages
  );

  # Configured, against the stable nixpkgs this repository already carries for
  # checks.stable-eval. Reusing it rather than adding an input: the question is
  # "does a second package set reach the modules", and any second set answers
  # it.
  configured = mkSystem (
    { pkgsOther, ... }:
    {
      programs.nixarchy.otherChannel.flake = inputs.nixpkgs-stable;
      environment.systemPackages = [ pkgsOther.btop ];
    }
  );

  btops = builtins.filter (p: (p.pname or "") == "btop") configured.config.environment.systemPackages;

  # unsafeDiscardStringContext so naming the paths does not make this check
  # depend on building either btop -- an eval-only check that quietly built
  # two package sets would be neither cheap nor honest about being cheap.
  paths = map (p: builtins.unsafeDiscardStringContext (baseNameOf p.outPath)) btops;

  doctor = "${(pkgs.extend inputs.self.overlays.default).nixarchy-doctor}/bin/nixarchy-doctor";
in
pkgs.runCommand "nixarchy-other-channel"
  {
    inherit doctor;
    unsetThrew = lib.boolToString (!unset.success);
    pathList = lib.concatStringsSep " " paths;
    pathCount = toString (builtins.length paths);
    distinct = toString (builtins.length (lib.unique paths));
  }
  ''
    echo "unconfigured pkgsOther throws: $unsetThrew"
    if [ "$unsetThrew" != true ]; then
      echo "::error::pkgsOther evaluated with no other channel configured." >&2
      echo "  It must throw, naming programs.nixarchy.otherChannel.flake --" >&2
      echo "  otherwise the first sign of a missing input is a confusing" >&2
      echo "  'attribute missing' pointing at the package." >&2
      exit 1
    fi

    echo "btop store paths in the configured system: $pathList"
    if [ "$pathCount" != 2 ]; then
      echo "::error::expected two btops (this machine's and the other" >&2
      echo "  channel's) and found $pathCount. Either the escape stopped" >&2
      echo "  working or vm/configuration.nix stopped carrying btop, and" >&2
      echo "  this check cannot tell which -- so it refuses." >&2
      exit 1
    fi
    if [ "$distinct" != 2 ]; then
      echo "::error::both btops are the SAME store path, so nothing crossed" >&2
      echo "  channels. A package taken from the other channel must be a" >&2
      echo "  different derivation; identical versions are not evidence." >&2
      exit 1
    fi
    echo "the two are different derivations, which is the feature and its cost"

    # The tools have to say what it costs, because nothing else will. A
    # duplicate closure is invisible until a disk fills.
    grep -q 'share no store' $doctor || {
      echo "::error::the doctor no longer says that the channels share no" >&2
      echo "  store paths. That sentence is the only place a user learns" >&2
      echo "  where several gigabytes went." >&2
      exit 1
    }
    grep -q 'follows stable' $doctor || {
      echo "::error::the doctor no longer reports which channel this machine" >&2
      echo "  follows (#532)." >&2
      exit 1
    }
    echo "the doctor names the channel and states the duplication cost"
    touch $out
  ''
