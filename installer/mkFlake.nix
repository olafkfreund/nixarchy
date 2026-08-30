# Builds the flake the installer writes to /etc/nixos.
#
# The template files carry @tokens@; the installer substitutes the answers it
# collected. What cannot be a template file is the lock, so it is derived here.
{
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
in
runCommand "nixarchy-flake-template"
  {
    nativeBuildInputs = [ jq ];
    inherit rev url;
    inherit (self) narHash;
    passthru = { inherit url rev; };
  }
  ''
    mkdir -p $out
    cp ${./template}/flake.nix          $out/flake.nix
    cp ${./template}/configuration.nix  $out/configuration.nix

    # Verbatim, never hand-maintained: the user's flake carries its own disk
    # layout so their fileSystems stay declarative without depending on
    # nixarchy's copy moving under them.
    cp ${../installer/disk-config.nix}  $out/disk-config.nix

    # Written rather than shipped as a template file, matching what
    # vm/configuration.nix's activation script already does. The exact header
    # is load-bearing: nixarchy-pkg-add matches `{ ... }:` to rewrite it to
    # `{ pkgs, ... }:` when it needs to add a plain nixpkgs attribute
    # (modules/apps.nix, ensure_block). statix would have this as `_:`, which
    # parses the same and would silently break that rewrite -- so the file is
    # generated here, where the linter cannot ask for it.
    printf '{ ... }:\n{ }\n' > $out/nixarchy-apps.nix

    # The lock is transformed rather than regenerated. `nix flake lock` on the
    # target would re-resolve every input against whatever is current, so the
    # first `nixos-rebuild switch` would build a different system from the one
    # just installed -- and it needs a network the offline ISO does not have.
    jq --arg rev "$rev" --arg narHash "$narHash" '
      # nixarchy inherits our root inputs verbatim. NOT a name-to-name map:
      # once nix has disambiguated names, root.nixpkgs points at a node called
      # "nixpkgs_2", and inventing the mapping rather than copying it points
      # the generated flake at a node that does not exist.
      .nodes.root.inputs as $rootInputs

      # An input whose value is an ARRAY is a follows path resolved from the
      # ROOT: disko.nixpkgs is ["nixpkgs"], meaning "whatever the root calls
      # nixpkgs". Once nixarchy is the root'"'"'s only input every one of those
      # paths points at nothing, and nix refuses with "follows a non-existent
      # input" while trying to update a lock it must never update. So re-root
      # them all under nixarchy. There are around forty, nearly all beneath
      # hyprland, which is why this is structural rather than a list.
      | .nodes |= with_entries(
          if .key == "root" or (.value | has("inputs") | not) then .
          else .value.inputs |= with_entries(
                 if (.value | type) == "array"
                 then .value = ["nixarchy"] + .value
                 else . end)
          end)

      | .nodes.nixarchy = {
          inputs: $rootInputs,
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
