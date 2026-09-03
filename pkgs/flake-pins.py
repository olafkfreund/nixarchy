#!/usr/bin/env python3
"""What this flake pins, and in which of the three ways it can pin it.

`nix run .#review` asks a different question of each shape, so the shape has
to be read out of flake.lock rather than guessed:

    rev   github:hyprwm/Hyprland/0bd11c7a...   a commit, deliberately
    tag   github:basecamp/omarchy/v4.0.1       a release
    ref   github:NixOS/nixpkgs/nixos-unstable  a branch, or the default one

Only the root's own inputs. flake.lock also carries every input of every
input -- hyprland alone brings a dozen -- and those are upstream's business,
not a pin anyone here can move.

Prints name, kind, owner/repo, the ref or rev, and the locked lastModified,
tab separated. Nothing else, so the caller stays a shell loop.
"""

import json
import sys


def main():
    lock = json.load(open("flake.lock"))
    nodes = lock["nodes"]

    for name, node_name in sorted(nodes["root"]["inputs"].items()):
        node = nodes[node_name]
        original = node.get("original", {})
        locked = node.get("locked", {})

        # Anything not on GitHub has no releases API to ask, and this repo
        # pins nothing that way today.
        if original.get("type") != "github":
            continue

        repo = f"{original.get('owner')}/{original.get('repo')}"
        ref = original.get("ref", "")

        if original.get("rev"):
            kind, at = "rev", original["rev"]
        elif ref[:1] == "v" and ref[1:2].isdigit():
            kind, at = "tag", ref
        else:
            # No ref at all still means a branch -- the default one.
            kind, at = "ref", ref or "(default)"

        print("\t".join([name, kind, repo, at, str(locked.get("lastModified", 0))]))


if __name__ == "__main__":
    sys.exit(main())
