#!/usr/bin/env python3
"""Every Omarchy Install row names a package. Is it one this port maps?

Upstream's rows install with `omarchy-pkg-present <arch-package>`. If nothing
in data/ maps that package to nixpkgs, modules/apps.nix does not rewire the
row, and it reaches a user still trying to run pacman. This is the check that
holds data/apps.nix to the claim it makes about itself.

It is one file with two callers because it used to be two copies with one
caller each, and they drifted. build.yml learned to look in data/services.nix
when `tailscale` moved there and became a service; omarchy.yml did not. So the
nightly Omarchy bump failed on a row that was mapped all along, twice, and
Omarchy 4.0.2 -- a security release -- sat unadopted behind a false positive
in our own checker. Two copies of a question is one copy too many.

Both catalogues count, and both spell it the same way:

    data/apps.nix       arch = "brave-bin"    an Install-menu app
    data/services.nix   arch = "tailscale"    a row that became a service

data/arch-extras.nix is deliberately NOT consulted. It exists for packages
"nothing in the menu selects" -- fonts from Style > Font, the system packages
behind omarchy-install-dev-env -- and it carries no menuId, so modules/apps.nix
generates no rewrite from it. A row naming one of those really is unmapped in
the sense this check means: it would still run pacman. Absorbing arch-extras
here would turn a real break into a green light.

Usage: check-menu-mapping.py <omarchy-menu.jsonc> <catalogue.nix>...
"""

import os
import re
import sys


def main(argv):
    if len(argv) < 3:
        sys.exit(f"usage: {argv[0]} <omarchy-menu.jsonc> <catalogue.nix>...")

    menu, catalogues = argv[1], argv[2:]

    known = set()
    for c in catalogues:
        known |= set(re.findall(r'arch = "([^"]+)"', open(c).read()))

    raw = open(menu).read()
    # JSONC. Strip comment lines the way MenuModel.js does before parsing.
    rows = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)

    # Only the install tree: remove.* rows are derived from these.
    wanted = set()
    for rid, body in re.findall(r'"(install\.[a-z0-9.\-]+)":\s*(\{[^}]*\})', rows):
        m = re.search(r"omarchy-pkg-present\s+([a-z0-9._@+\-]+)", body)
        if m:
            wanted.add((rid, m.group(1)))

    if not wanted:
        sys.exit(
            "no install rows found in the menu -- either it changed shape or "
            "this check stopped being able to read it, which is worse"
        )

    # Rows this port has DECIDED not to map, with the reason.
    #
    # data/menu-exceptions.nix, not a list in this file, because
    # tests/options.nix asks the same question and used to carry its own copy
    # -- so recording a decision satisfied one gate and left the other red on
    # the same row. One file, two readers.
    #
    # Parsed with a regex rather than by evaluating Nix: this script is
    # stdlib-only and runs where nix may not, and the file is a flat attrset
    # of string values by construction. A shape it cannot read is reported,
    # never assumed empty -- an unreadable exceptions file that silently
    # excepted nothing would fail every row, and one that silently excepted
    # everything would be worse.
    exceptions = {}
    exc_path = os.path.join(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))), "data", "menu-exceptions.nix")
    if os.path.exists(exc_path):
        text = open(exc_path).read()
        for rid, reason in re.findall(
            r'"(install\.[a-z0-9.\-]+)"\s*=\s*(.+?);\s*$', text, flags=re.M | re.S
        ):
            exceptions[rid] = " ".join(reason.split())
        if not exceptions:
            sys.exit(
                f"{exc_path} exists and yielded no entries -- this check cannot "
                "tell a deliberate exception from an unmapped row, so it refuses "
                "to report either"
            )

    # An exception with no reason is not a decision.
    blank = sorted(r for r, why in exceptions.items() if not why.strip(' "'))
    if blank:
        for r in blank:
            print(f"::error::{r} is in data/menu-exceptions.nix with no reason")
        sys.exit(f"{len(blank)} exceptions carry no reason")

    missing = sorted((r, a) for r, a in wanted if a not in known and r not in exceptions)
    for rid, arch in missing:
        names = " or ".join(catalogues)
        print(f"::error::{rid} installs '{arch}', which {names} does not map")
        print(f"::error::  map it there, or record the decision in data/menu-exceptions.nix")
    if missing:
        sys.exit(f"{len(missing)} unmapped Install rows")

    excepted = sorted(r for r, _ in wanted if r in exceptions)
    print(f"all {len(wanted)} Install rows are mapped "
          f"({len(excepted)} by a recorded exception)")


if __name__ == "__main__":
    main(sys.argv)
