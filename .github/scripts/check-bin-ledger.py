#!/usr/bin/env python3
"""Every shipped command is either upstream's, or a row saying why it is not.

nixarchy vendors Omarchy's whole `bin/` tree -- 431 commands at v4.0.2 -- and
ships 440. Nothing said which of them this port has its hands on, so an Omarchy
release could add, rename or absorb a command and the only thing that noticed
was a human reading a diff.

The idea is Omahedron's (schema/scripts.lock.json, checks/ledgers.py), and it is
a good one. The shape here is deliberately not theirs, for a measured reason:
384 of the 431 shipped commands are byte-identical to upstream below the shebang
-- `patchShebangs` rewrites line 1 of every script, and nothing else differs.
Omahedron hand-maintains a row for all 432. Writing 384 rows that restate what
`cmp` already proves is the failure mode omarchy-patched-files.sh names out
loud: a hand list that agrees with itself proves nothing.

So the class is DERIVED here, and data/bin-ledger.nix carries only the rows
where the port diverges -- the reason, which no comparison can derive. The check
then asserts derived == declared, both directions.

Modes:

  (default)  check.  Exits non-zero with every problem named.
  --report   one line per finding, for the bump PR body.
  --seed     print skeleton rows for everything unclassified, with the derived
             class filled in and reason = "FIXME". The check REJECTS "FIXME",
             so a seeded ledger cannot pass CI until a person writes the reasons.

Stdlib only, and it refuses to run on an empty tree rather than reporting
nothing -- same discipline as check-menu-mapping.py's "no install rows found".
"""

import argparse
import os
import re
import sys

# Floors. Every enumerating check in this repo has one, because the dangerous
# failure is not a wrong answer, it is a check that stopped seeing its subject
# and reported nothing. `scanned >= 300` in build.yml's pacman step, and
# `derived_or_die` in omarchy-patched-files.sh, are the same idea.
MIN_UPSTREAM = 400
MIN_SHIPPED = 400
MIN_VENDOR = 300
MIN_ROWS = 20

# A class the ledger may declare. `vendor` is derived and normally unwritable --
# a row for a file identical to upstream is a rubber stamp -- with one exception
# carved out below for the pacman allowlist this check subsumes.
CLASSES = ("patch", "replace", "new", "vendor")

# Upstream's package manager, and the AUR helper it reaches for. Word-boundary
# matched after comments are stripped, so prose about pacman does not count.
PACMAN = re.compile(r"\b(pacman|yay)\b")


def die(message):
    print(f"bin-ledger: {message}", file=sys.stderr)
    sys.exit(1)


def body(path):
    """A script's text below its shebang.

    patchShebangs rewrites line 1 of all 431 scripts, so comparing whole files
    reports every one of them as modified -- measured: 2 identical whole, 384
    identical below the shebang. The shebang is the build's business, not the
    ledger's.
    """
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return None
    newline = data.find(b"\n")
    return data if newline < 0 else data[newline + 1 :]


def strip_comments(text):
    """Comment-stripped source, for the pacman scan.

    A bin that only MENTIONS pacman in a comment is not calling it. The
    allowlist step this replaces stripped comments the same way; keeping the
    behaviour keeps the migration honest.
    """
    return "\n".join(re.sub(r"#.*", "", line) for line in text.splitlines())


def derive(upstream_bin, shipped_bin, nix_bin):
    """Classify every shipped command by comparing the two trees.

    Returns {name: class} plus the two name sets, so the caller can assert about
    what is missing as well as what is present.
    """
    upstream = {
        entry
        for entry in os.listdir(upstream_bin)
        if os.path.isfile(os.path.join(upstream_bin, entry))
    }
    shipped = {
        entry
        for entry in os.listdir(shipped_bin)
        if os.path.isfile(os.path.join(shipped_bin, entry))
        and not entry.startswith(".")
    }

    if len(upstream) < MIN_UPSTREAM:
        die(
            f"upstream bin/ has {len(upstream)} commands, expected at least "
            f"{MIN_UPSTREAM}.\n"
            "  Either the tree moved or this check is looking in the wrong "
            "place. It refuses rather than reporting that nothing needs a row."
        )
    if len(shipped) < MIN_SHIPPED:
        die(
            f"the built package ships {len(shipped)} commands, expected at "
            f"least {MIN_SHIPPED}. Same reasoning as above."
        )

    # nix-bin's own convention, already enforced at build time in
    # pkgs/omarchy/default.nix: a file with no upstream counterpart must say so.
    replaced, brand_new = set(), set()
    for entry in sorted(os.listdir(nix_bin)):
        path = os.path.join(nix_bin, entry)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            marked = any(line.startswith("# nixarchy:new") for line in handle)
        (brand_new if marked else replaced).add(entry)

    derived = {}
    for name in sorted(shipped):
        if name in brand_new:
            derived[name] = "new"
        elif name in replaced:
            derived[name] = "replace"
        elif name not in upstream:
            # Shipped, not upstream's, and not from nix-bin. Nothing produces
            # this today -- the pacman shim people reach for as the example is
            # its own derivation (pkgs/omarchy/default.nix:267), in a different
            # store path -- so treat it as unclassifiable rather than inventing
            # a class no mechanism creates.
            derived[name] = "unknown"
        elif body(os.path.join(shipped_bin, name)) == body(
            os.path.join(upstream_bin, name)
        ):
            derived[name] = "vendor"
        else:
            derived[name] = "patch"

    vendored = sum(1 for cls in derived.values() if cls == "vendor")
    if vendored < MIN_VENDOR:
        die(
            f"only {vendored} of {len(shipped)} commands look vendored, "
            f"expected at least {MIN_VENDOR}.\n"
            "  That is not 431 commands needing rows -- it is the comparison "
            "breaking. Check whether patchShebangs still rewrites only line 1."
        )

    return derived, upstream, shipped


def problems(ledger, derived, upstream, shipped, shipped_bin):
    """Every way the ledger and the trees can disagree."""
    found = []

    if len(ledger) < MIN_ROWS:
        found.append(
            f"the ledger has {len(ledger)} rows, expected at least {MIN_ROWS}. "
            "An empty ledger agrees with everything, so it is refused."
        )
        return found

    # 1. Nothing upstream is ever dropped. pkgs/omarchy/default.nix deletes no
    #    bin -- it prunes dev directories only -- and that is a promise worth
    #    checking rather than a fact worth assuming.
    for name in sorted(upstream - shipped):
        found.append(
            f"{name}: upstream ships it and this port does not.\n"
            "    nixarchy drops no upstream command. If that changed on "
            "purpose, this check needs a `drop` class and a row explaining it."
        )

    # 2 and 3. Both directions of the same disagreement.
    for name in sorted(set(derived) | set(ledger)):
        declared = ledger.get(name)
        actual = derived.get(name)

        if declared is None:
            if actual != "vendor":
                found.append(
                    f"{name}: shipped as `{actual}` and has no row.\n"
                    f"    Add one to data/bin-ledger.nix saying why this port "
                    f"diverges. `--seed` prints a skeleton."
                )
            continue

        if actual is None:
            found.append(
                f"{name}: has a row and is not shipped.\n"
                "    Upstream renamed or removed it, or nix-bin lost a file. "
                "Delete the row, or fix what stopped shipping it."
            )
            continue

        if declared.get("class") != actual:
            found.append(
                f"{name}: the row says `{declared.get('class')}` and the build "
                f"produces `{actual}`.\n"
                "    A patch row gone vendor usually means upstream adopted the "
                "change -- delete the row. The other direction means something "
                "started diverging without anyone saying why."
            )
            continue

        # 4. The rubber stamp. A row for a file identical to upstream restates
        #    `cmp`, unless it is carrying a pacman reason (see below).
        if actual == "vendor" and not declared.get("pacman"):
            found.append(
                f"{name}: a row for a file identical to upstream.\n"
                "    Vendored commands do not get rows -- the comparison "
                "already proves it. Delete this, unless it needs a `pacman` "
                "field, which is the one thing a vendor row may carry."
            )

        reason = (declared.get("reason") or "").strip()
        if not reason or "FIXME" in reason:
            found.append(
                f"{name}: reason is empty or still FIXME.\n"
                "    `--seed` fills the class in; the reason is the part only a "
                "person can write, and it is the whole value of the row."
            )

    # 5. The stub biconditional, and only where it can be honest.
    #    nixarchy stubs three ways -- a nix-bin refusal, a --replace-fail branch,
    #    and a sed range-deletion -- and the last two are indistinguishable from
    #    an ordinary patch from the outside. So this is checked for nix-bin
    #    files, where one marker line makes it true, and left as annotation
    #    elsewhere rather than pretended.
    for name, row in sorted(ledger.items()):
        if derived.get(name) not in ("replace", "new"):
            continue
        text = body(os.path.join(shipped_bin, name)) or b""
        marked = b"# nixarchy:stub" in text
        if marked != bool(row.get("stub")):
            found.append(
                f"{name}: `stub = {bool(row.get('stub'))}` and the shipped file "
                f"{'has' if marked else 'has no'} a `# nixarchy:stub` marker.\n"
                "    The marker and the row have to agree, or neither means "
                "anything."
            )

    # 6. The pacman scan, which this check subsumes from build.yml. Same walk,
    #    same comment-stripping, and the same three directions: a bin that calls
    #    pacman without a row, a row whose bin went clean, and a row for a bin
    #    that no longer exists (covered by 3 above).
    for name in sorted(shipped):
        path = os.path.join(shipped_bin, name)
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            continue
        calls = bool(PACMAN.search(strip_comments(text)))
        declared_pacman = bool(ledger.get(name, {}).get("pacman"))

        if calls and not declared_pacman:
            found.append(
                f"{name}: calls pacman or yay and has no `pacman` reason.\n"
                "    Either it needs one, saying why an Arch-only path is "
                "carried and unreachable here, or the call needs patching out."
            )
        elif declared_pacman and not calls:
            found.append(
                f"{name}: carries a `pacman` reason and no longer calls it.\n"
                "    Upstream cleaned it up. Prune the field, so the ledger "
                "keeps meaning what it says."
            )

    return found


def seed(ledger, derived):
    """Skeleton rows for everything unclassified, class filled, reason not."""
    rows = []
    for name in sorted(derived):
        if name in ledger or derived[name] == "vendor":
            continue
        rows.append(
            f'  "{name}" = {{\n'
            f'    class = "{derived[name]}";\n'
            f'    reason = "FIXME";\n'
            f"  }};"
        )
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", required=True, help="omarchy source tree")
    parser.add_argument("--shipped", required=True, help="built share/omarchy")
    parser.add_argument("--nix-bin", required=True, help="pkgs/omarchy/nix-bin")
    parser.add_argument("--ledger", required=True, help="data/bin-ledger.nix")
    parser.add_argument("--report", action="store_true", help="one line each")
    parser.add_argument("--seed", action="store_true", help="skeleton rows")
    args = parser.parse_args()

    # Nix, read by regex, and not JSON.
    #
    # The ledger belongs in data/ beside apps.nix, services.nix and
    # menu-exceptions.nix, because the load-bearing part of it is the prose --
    # a per-row reason and the header stating the rule that keeps the file
    # honest, neither of which survives JSON. This script stays stdlib-only for
    # the same reason check-menu-mapping.py does, and reads the file the same
    # way that one reads data/apps.nix: a regex over the text rather than an
    # evaluation of Nix.
    #
    # --seed is exempt. It exists to produce a ledger for a repository that has
    # none, and requiring the file it is about to write made it unusable for
    # its only purpose -- it died on the empty file with a JSONDecodeError.
    ledger = {}
    if os.path.exists(args.ledger):
        text = open(args.ledger, encoding="utf-8").read()
        for name, body in re.findall(
            r'"([^"]+)"\s*=\s*\{(.*?)\};', text, re.S
        ):
            row = dict(re.findall(r'(\w+)\s*=\s*"([^"]*)"', body))
            if row:
                ledger[name] = row
    elif not args.seed:
        die(f"no ledger at {args.ledger}")

    for name, row in ledger.items():
        if row.get("class") not in CLASSES:
            die(f"{name}: class {row.get('class')!r} is not one of {CLASSES}")

    upstream_bin = os.path.join(args.upstream, "bin")
    shipped_bin = os.path.join(args.shipped, "bin")
    derived, upstream, shipped = derive(upstream_bin, shipped_bin, args.nix_bin)

    if args.seed:
        rows = seed(ledger, derived)
        print(f"# {len(rows)} rows need writing. reason = FIXME will not pass.")
        print("\n".join(rows))
        return 0

    found = problems(ledger, derived, upstream, shipped, shipped_bin)

    if args.report:
        if not found:
            print(
                f"Every one of the {len(shipped)} shipped commands is upstream's "
                f"or has a row: {len(ledger)} rows, "
                f"{sum(1 for c in derived.values() if c == 'vendor')} vendored "
                "untouched."
            )
        for problem in found:
            print("- " + problem.splitlines()[0])
        return 0

    if found:
        print(
            f"data/bin-ledger.nix and the built package disagree, "
            f"{len(found)} time(s):\n",
            file=sys.stderr,
        )
        for problem in found:
            print("  " + problem, file=sys.stderr)
        print(
            "\n  The ledger records what this port does to upstream's commands "
            "and why.\n"
            "  Vendored commands are not listed -- a row is a claim that the "
            "shipped\n  file differs, and the build is what decides whether it "
            "does.",
            file=sys.stderr,
        )
        return 1

    counts = {}
    for cls in derived.values():
        counts[cls] = counts.get(cls, 0) + 1
    summary = ", ".join(f"{n} {cls}" for cls, n in sorted(counts.items()))
    print(f"{len(shipped)} commands: {summary}. {len(ledger)} rows, all true.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
