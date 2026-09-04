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
    touch $out
  ''
