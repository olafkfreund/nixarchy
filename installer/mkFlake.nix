# Builds the flake the installer writes to /etc/nixos.
#
# `host/` is a machine-shaped directory with the tokens still in it. The
# installer renames it to hosts/<hostname>/ once it knows the name, which is
# why this derivation can be built once and used for any machine -- it has no
# hostname to bake in.
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

  # What the machine ASKS for when it updates, as opposed to what it GOT
  # (`url` above, which is provenance and stays rev-pinned). This goes into
  # flake.nix and the lock's `original`; the rev goes into `locked`. Nix never
  # consults `original` until the user runs `nix flake update`, so first boot
  # still builds the exact installed rev, offline -- but the update command
  # has somewhere to go. A rev here froze every installed machine at its
  # install day: re-resolving a commit returns that commit, forever.
  #
  # `release` moves when a human cuts a release, not with the bot merges that
  # move main. nixpkgs and home-manager are the machine's own inputs and
  # update independently of it.
  ref = "release";
  refUrl = "github:olafkfreund/nixarchy/${ref}";
in
runCommand "nixarchy-flake-template"
  {
    nativeBuildInputs = [ jq ];
    inherit
      rev
      url
      ref
      refUrl
      ;
    inherit (self) narHash;

    # And the timestamp, which nix writes into every lock node it produces and
    # this one was leaving out (#208).
    #
    # An input node without it evaluates: `self.lastModified` is simply absent
    # on the other side, so anything reading it takes its fallback. That made
    # the omission invisible until something in the closure DEPENDED on it --
    # nixarchy-version, which prints the build's date. This flake evaluates to
    # a different omarchy than the one the installer seeded, the offline
    # install cannot copy what it now has to build, and it walks back to the
    # source bootstrap and dies fetching a Debian patch for libssh2. The rev
    # was never the problem: shortRev is identical on both sides.
    lastModified = toString self.lastModified;

    passthru = { inherit url rev refUrl; };
  }
  ''
    mkdir -p $out/host
    cp ${./template}/flake.nix           $out/flake.nix
    cp ${./template}/host/default.nix    $out/host/default.nix
    cp ${./template}/host/configuration.nix $out/host/configuration.nix

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
    printf '{ ... }:\n{ }\n' > $out/host/nixarchy-apps.nix

    # The lock is transformed rather than regenerated. `nix flake lock` on the
    # target would re-resolve every input against whatever is current, so the
    # first `nixos-rebuild switch` would build a different system from the one
    # just installed -- and it needs a network the offline ISO does not have.
    #
    # The `locked`/`original` split is the whole design: `locked` (rev +
    # narHash) is what evaluation reads, and is where reproducibility lives;
    # `original` is read only by `nix flake update`, which re-resolves it. So
    # `locked` carries the installed rev and `original` carries a branch ref.
    # A rev in `original` is what froze every installed machine: update
    # re-resolved the commit back to itself, forever.
    jq --arg rev "$rev" --arg narHash "$narHash" --arg ref "$ref" \
       --argjson lastModified "$lastModified" '
      # nixarchy inherits our root inputs verbatim. NOT a name-to-name map:
      # once nix has disambiguated names, root.nixpkgs points at a node called
      # "nixpkgs_2", and inventing the mapping rather than copying it points
      # the generated flake at a node that does not exist.
      .nodes.root.inputs as $rootInputs

      # An input whose value is an ARRAY is a follows path resolved from the
      # ROOT: disko.nixpkgs is ["nixpkgs"], meaning "whatever the root calls
      # nixpkgs". Once the root'"'"'s inputs are replaced below, every one of
      # those paths points at nothing, and nix refuses with "follows a
      # non-existent input" while trying to update a lock it must never
      # update. So re-root them all under nixarchy. There are around forty,
      # nearly all beneath hyprland, which is why this is structural rather
      # than a list.
      | .nodes |= with_entries(
          if .key == "root" or (.value | has("inputs") | not) then .
          else .value.inputs |= with_entries(
                 if (.value | type) == "array"
                 then .value = ["nixarchy"] + .value
                 else . end)
          end)

      | .nodes.nixarchy = {
          # The machine owns nixpkgs (root input, below) and nixarchy follows
          # it -- the lock half of the template'"'"'s `follows = "nixpkgs"`.
          inputs: ($rootInputs | .nixpkgs = ["nixpkgs"]),
          locked: {
            type: "github",
            owner: "olafkfreund",
            repo: "nixarchy",
            rev: $rev,
            narHash: $narHash,
            lastModified: $lastModified
          },
          original: {
            type: "github",
            owner: "olafkfreund",
            repo: "nixarchy",
            ref: $ref
          }
        }

      # nixpkgs re-exposed at the root, pointing at the SAME already-locked
      # node ($rootInputs.nixpkgs is the disambiguated name -- copy, never
      # invent). Its original already carries the branch this repo tracks, so
      # `nix flake update nixpkgs` works from day one; making it a root input
      # is what lets the user retarget it -- stable instead of unstable -- in
      # a flake.nix they own.
      | .nodes.root.inputs = { nixarchy: "nixarchy", nixpkgs: $rootInputs.nixpkgs }
    ' ${../flake.lock} > $out/flake.lock

    # The nixpkgs URL the machine's flake.nix declares must be EXACTLY the
    # `original` of the node the lock carries -- a mismatch makes nix
    # re-resolve on first use, which needs the network the offline ISO does
    # not have. So it is read out of the lock rather than written down a
    # second time.
    nixpkgs_url=$(jq -r '
      .nodes.root.inputs.nixpkgs as $n
      | .nodes[$n].original
      | "github:\(.owner)/\(.repo)/\(.ref)"
    ' $out/flake.lock)

    # So the installer does not have to recompute what this already knows.
    #
    # Provenance of the REPOSITORY, and nothing more. It is tracked by the
    # `git add -A` install.sh does, so it is committed, pushed, and cloned onto
    # every machine enrolled from this repo with `--from` -- machines this
    # installer never touched. "Did nixarchy write this machine" is a different
    # question and is answered elsewhere: programs.nixarchy.installerManaged,
    # via installer/host.nix. Nothing should gate on this file.
    printf '%s\n' "$url" > $out/.nixarchy-url

    sed -i -e "s|@nixarchy_url@|$refUrl|g" \
           -e "s|@nixpkgs_url@|$nixpkgs_url|g" $out/flake.nix
  ''
