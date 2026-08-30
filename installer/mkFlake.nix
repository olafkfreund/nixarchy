# Builds the flake the installer writes to /etc/nixos.
#
# The template files carry @tokens@; the installer substitutes the answers it
# collected. What cannot be a template file is the lock, so it is derived here.
{
  lib,
  runCommand,
  jq,
  self,
}:
let
  # Building from a dirty tree gives no rev, and the generated flake pins
  # nixarchy by commit. Falling back to path:${self} would work offline and
  # dirty, and would pin the user's machine to a store path with no guarantee
  # of surviving garbage collection -- a machine that stops rebuilding one day
  # for reasons nobody can reconstruct. Throwing is the honest failure.
  rev =
    self.rev
      or (throw "flake-template: build from a committed tree; the generated flake pins nixarchy by commit");

  url = "github:olafkfreund/nixarchy/${rev}";

  # Every input of this repo becomes an input of the nixarchy node, so the
  # generated lock is a pure superset of ours -- which is what keeps hyprland
  # on hyprwm's cache rather than silently re-resolving through a follows.
  inputNames = builtins.attrNames (builtins.fromJSON (builtins.readFile ../flake.lock))
    .nodes.root.inputs;
in
runCommand "nixarchy-flake-template"
  {
    nativeBuildInputs = [ jq ];
    inherit rev url;
    inherit (self) narHash;
    inputs = lib.concatStringsSep " " inputNames;
    passthru = { inherit url rev; };
  }
  ''
    mkdir -p $out
    cp ${./template}/flake.nix          $out/flake.nix
    cp ${./template}/configuration.nix  $out/configuration.nix
    # Written rather than shipped as a template file, matching what
    # vm/configuration.nix's activation script already does. The exact header
    # is load-bearing: nixarchy-pkg-add matches `{ ... }:` to rewrite it to
    # `{ pkgs, ... }:` when it needs to add a plain nixpkgs attribute
    # (modules/apps.nix, ensure_block). statix would have this as `_:`, which
    # parses the same and would silently break that rewrite -- so the file is
    # generated here, where the linter cannot ask for it.
    printf '{ ... }:\n{ }\n' > $out/nixarchy-apps.nix

    # Verbatim, never hand-maintained: the user's flake carries its own disk
    # layout so their fileSystems stay declarative without depending on
    # nixarchy's copy moving under them.
    cp ${../installer/disk-config.nix}  $out/disk-config.nix

    # The lock is transformed rather than regenerated. `nix flake lock` on the
    # target would re-resolve every input against whatever is current, so the
    # first `nixos-rebuild switch` would build a different system from the one
    # just installed -- and it needs a network the offline ISO does not have.
    #
    # So: keep every node exactly as built, add a `nixarchy` node pinned to
    # this revision, and make it the root's only input.
    jq --arg rev "$rev" \
       --arg narHash "$narHash" \
       --arg url "$url" \
       --arg inputs "$inputs" '
      ($inputs | split(" ")) as $names
      | .nodes.nixarchy = {
          inputs: ($names | map({ (.): . }) | add),
          locked: {
            type: "github",
            owner: "olafkfreund",
            repo: "nixarchy",
            rev: $rev,
            narHash: $narHash
          },
          original: {
            type: "github",
            owner: "olafkfreund",
            repo: "nixarchy",
            rev: $rev
          }
        }
      | .nodes.root.inputs = { nixarchy: "nixarchy" }
    ' ${../flake.lock} > $out/flake.lock

    # So the installer does not have to recompute what this already knows.
    printf '%s\n' "$url" > $out/.nixarchy-url

    sed -i "s|@nixarchy_url@|$url|g" $out/flake.nix
  ''
