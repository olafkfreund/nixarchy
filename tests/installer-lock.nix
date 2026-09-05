{ pkgs, flakeTemplate }:
# The lock the installer writes, checked for the fields nix would have written
# itself.
#
# installer/mkFlake.nix builds the `nixarchy` node of the generated flake.lock
# by hand, because there is nothing to lock against at build time -- the flake
# it describes does not exist until the installer renames a directory. A node
# assembled by hand is a node that can be missing a field, and a lock missing a
# field does not fail: it evaluates, and whatever reads that field takes its
# fallback.
#
# That is not hypothetical. `lastModified` was left out, `self.lastModifiedDate`
# was therefore absent inside the installed machine's evaluation, and
# nixarchy-version's date became "unknown" -- which changed the omarchy
# derivation, which changed system-path, which meant the offline install had to
# BUILD a system it was supposed to copy, on a machine with no network. It died
# fetching a Debian patch for libssh2 and reported a missing ESP. Two days.
#
# So this asserts the shape of that node instead of trusting the next person to
# remember. It is a runCommand over an already-built derivation: no VM, no
# network, seconds. The 25-minute install check can see the same bug, but only
# after the damage and only as something four levels away.
pkgs.runCommand "nixarchy-installer-lock"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    lock=${flakeTemplate}/flake.lock
    test -f "$lock" || { echo "no flake.lock in the generated template" >&2; exit 1; }

    node=$(jq -c '.nodes.nixarchy.locked // empty' "$lock")
    if [ -z "$node" ]; then
      echo "the generated lock has no nixarchy node at all:" >&2
      jq -c '.nodes | keys' "$lock" >&2
      exit 1
    fi
    echo "nixarchy node: $node"

    # Every field mkFlake writes by hand. `lastModified` is the one that went
    # missing and the reason this check exists, but the others are hand-written
    # too and would fail just as quietly.
    for field in type owner repo rev narHash lastModified; do
      if ! jq -e --arg f "$field" 'has($f)' <<<"$node" >/dev/null; then
        echo "" >&2
        echo "the nixarchy lock node has no '$field'." >&2
        echo "" >&2
        echo "installer/mkFlake.nix writes this node by hand, so a field it" >&2
        echo "omits is simply absent on the installed machine -- the flake" >&2
        echo "still evaluates and whatever reads it takes a fallback." >&2
        echo "" >&2
        echo "For lastModified specifically: self.lastModifiedDate goes" >&2
        echo "absent, nixarchy-version's date becomes \"unknown\", and that" >&2
        echo "string is spliced into the omarchy derivation. The installed" >&2
        echo "system then differs from the one checks.install seeded, so an" >&2
        echo "offline install has to build what it meant to copy and dies" >&2
        echo "fetching a source it cannot reach." >&2
        exit 1
      fi
    done

    # A number, not a string: nix writes it as one, and `jq` comparing a string
    # to a number silently says no rather than complaining.
    kind=$(jq -r '.lastModified | type' <<<"$node")
    [ "$kind" = "number" ] || {
      echo "lastModified is a $kind; nix writes a number" >&2; exit 1; }

    jq -e '.lastModified > 0' <<<"$node" >/dev/null || {
      echo "lastModified is not a positive timestamp" >&2; exit 1; }

    echo "the generated lock carries every field mkFlake writes by hand"

    # The other half of the node: `original` is what `nix flake update`
    # re-resolves, and a rev there resolves to itself -- which is how every
    # machine installed before this check existed was frozen at its install
    # day. `omarchy update` printed "this moves your flake inputs forward"
    # and moved nothing. `locked` (asserted above) is where reproducibility
    # lives; `original` must be somewhere update can GO.
    original=$(jq -c '.nodes.nixarchy.original // empty' "$lock")
    if jq -e 'has("rev")' <<<"$original" >/dev/null 2>&1; then
      echo "" >&2
      echo "the nixarchy lock node's 'original' carries a rev: $original" >&2
      echo "" >&2
      echo "'original' is the update target: nix flake update re-resolves it," >&2
      echo "and re-resolving a commit returns that commit. Every machine" >&2
      echo "installed from this template can never move -- no nixarchy" >&2
      echo "update, and since nixarchy used to carry nixpkgs, no nixpkgs" >&2
      echo "update either. Pin the rev in 'locked'; give 'original' a ref." >&2
      exit 1
    fi
    jq -e '.ref | type == "string" and length > 0' <<<"$original" >/dev/null || {
      echo "the nixarchy 'original' has no ref to update against: $original" >&2
      exit 1
    }

    # And the URL in flake.nix must agree with it, because nix re-resolves on
    # a flake.nix/lock mismatch -- over a network the offline ISO does not
    # have. A rev-shaped URL here is the same freeze wearing different
    # clothes: `nix flake update nixarchy` obeys flake.nix, not the lock.
    ref=$(jq -r '.ref' <<<"$original")
    grep -Fq "url = \"github:olafkfreund/nixarchy/$ref\";" \
      ${flakeTemplate}/flake.nix || {
      echo "flake.nix does not pin nixarchy to the ref the lock names ('$ref'):" >&2
      grep -n 'olafkfreund/nixarchy' ${flakeTemplate}/flake.nix >&2 || true
      exit 1
    }

    # The machine owns nixpkgs: a root input the user can retarget (stable vs
    # unstable) and update on its own, with nixarchy following it. Without
    # the follows re-rooting, nixarchy's locked nixpkgs would shadow the
    # user's choice and this root input would be decoration.
    jq -e '.nodes.root.inputs.nixpkgs | type == "string"' "$lock" >/dev/null || {
      echo "the generated lock has no root nixpkgs input; the machine cannot" >&2
      echo "choose or update its package set:" >&2
      jq -c '.nodes.root.inputs' "$lock" >&2
      exit 1
    }
    jq -e '.nodes.nixarchy.inputs.nixpkgs == ["nixpkgs"]' "$lock" >/dev/null || {
      echo "nixarchy does not follow the machine's nixpkgs; the root input" >&2
      echo "would be dead weight while nixarchy builds from its own:" >&2
      jq -c '.nodes.nixarchy.inputs.nixpkgs' "$lock" >&2
      exit 1
    }

    # flake.nix's nixpkgs URL must be the locked node's own original, or the
    # first offline use re-resolves it and dies without a network.
    nixpkgs_url=$(jq -r '.nodes.root.inputs.nixpkgs as $n
      | .nodes[$n].original | "github:\(.owner)/\(.repo)/\(.ref)"' "$lock")
    grep -Fq "nixpkgs.url = \"$nixpkgs_url\";" ${flakeTemplate}/flake.nix || {
      echo "flake.nix's nixpkgs URL does not match the lock's original" >&2
      echo "($nixpkgs_url); nix would re-resolve it on first use, offline:" >&2
      grep -n 'inputs.nixpkgs.url' ${flakeTemplate}/flake.nix >&2 || true
      exit 1
    }

    echo "and 'original' is a ref nix flake update can actually move"
    touch $out
  ''
