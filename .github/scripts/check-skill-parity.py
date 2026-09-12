#!/usr/bin/env python3
"""Upstream's own SKILL.md, classified section by section, and held to it.

pkgs/omarchy/default.nix renames upstream's `omarchy` skill to `nixarchy` and
copies ours over the top. That replacement is correct and stays -- docs/manual/
ai.md says why, under "The skills are rewritten, because upstream's would lie".
Replacing it WITHOUT NOTICING WHAT CHANGED is the problem: upstream's file is
13 KB of 19 headings and 14 command groups, and every one of them can move at a
bump with nothing in this repository able to say so.

The existing guards are all about names and counts -- readme-counts.sh asserts
the skill count and per-skill rows, build.yml asserts exact skill-set equality
and frontmatter. A section added INSIDE upstream's SKILL.md trips none of them.

So data/skill-parity.nix carries one row per upstream section and per command
group, and this holds it to that claim in BOTH directions:

  an upstream section with no row        unclassified
  a row for a section upstream dropped   stale
  a `preserved` heading missing here     the claim is false
  an `anchor` that greps nothing here    the claim is unproven
  a section whose upstream text moved    re-audit, then update the digest

The digest is what makes this more than a heading census. A row pins a short
sha256 of upstream's section body, so upstream can neither add a section nor
rewrite one it already has without a person looking at it. A key-set diff alone
would let upstream replace the whole body of an adapted section in silence --
which is the exact bug this exists to catch.

The idea, and the anchor-proof shape, come from zicochaos/omarchy-nix's
skills/omarchy/skill-parity.json (MIT). The code is ours.

Stdlib only, and it refuses to run on a tree it extracted nothing from -- same
floor discipline as check-bin-ledger.py and omarchy-patched-files.sh, because
the dangerous failure is not a wrong answer, it is a check that stopped seeing
its subject and reported success.
"""

import argparse
import hashlib
import os
import re
import sys

# Floors. Measured at omarchy 0534987: 19 headings, 14 groups.
MIN_HEADINGS = 15
MIN_GROUPS = 10

CLASSES = ("preserved", "adapted", "omitted")

HEADING = re.compile(r"^(#{2,4})\s+(\S.*?)\s*$")
GROUP_ROW = re.compile(r"^\|\s*`(omarchy\s+[a-z-]+)`\s*\|")


def die(message):
    print(f"skill-parity: {message}", file=sys.stderr)
    sys.exit(1)


def normalise(lines):
    """Body text with the whitespace noise taken out.

    Trailing spaces and blank-line runs are formatting, not content, and a
    digest that moves when a blank line does is a digest nobody will trust.
    """
    text = "\n".join(line.rstrip() for line in lines)
    return re.sub(r"\n{2,}", "\n\n", text).strip()


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def sections(path):
    """Every heading and command-group row upstream's SKILL.md carries.

    Keyed the way a reader would grep for it: the heading line verbatim, and
    `group: omarchy pkg` for a row of the Command Groups table. A heading's
    body runs to the next heading of any level.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    found = {}
    key = None
    body = []
    headings = groups = 0
    for line in lines:
        match = HEADING.match(line)
        if match:
            if key:
                found[key] = normalise(body)
            key = line.strip()
            body = []
            headings += 1
            continue
        body.append(line)
        row = GROUP_ROW.match(line)
        if row:
            found[f"group: {row.group(1)}"] = normalise([line])
            groups += 1
    if key:
        found[key] = normalise(body)

    if headings < MIN_HEADINGS:
        die(
            f"{headings} headings extracted from {path}, expected at least "
            f"{MIN_HEADINGS}. A parse that sees nothing agrees with everything, "
            "so it is refused."
        )
    if groups < MIN_GROUPS:
        die(
            f"{groups} command groups extracted from {path}, expected at least "
            f"{MIN_GROUPS}. Same reason."
        )
    return found


def ours(directory):
    """Everything this port's own skill says, as one blob.

    Anchors and `preserved` headings are looked for here rather than in the
    built package: the claim is about what we wrote, and reading the source
    tree keeps this check an evaluation rather than a package build.
    """
    text = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".md"):
            with open(os.path.join(directory, name), encoding="utf-8") as handle:
                text.append(handle.read())
    if not text:
        die(f"no .md files under {directory}")
    return "\n".join(text)


def problems(manifest, upstream, mine):
    found = []

    for key in sorted(set(upstream) - set(manifest)):
        found.append(
            f"unclassified: upstream's SKILL.md has {key!r} and "
            f"data/skill-parity.nix does not.\n"
            f"    Upstream changed. Decide what this port does with it and add "
            f'a row: class, upstream = "{digest(upstream[key])}", and an anchor '
            f"or a reason."
        )

    for key in sorted(set(manifest) - set(upstream)):
        found.append(
            f"stale: data/skill-parity.nix classifies {key!r} and upstream's "
            f"SKILL.md no longer has it.\n"
            f"    Upstream removed or renamed it. Delete the row, or retarget "
            f"it at the new name."
        )

    for key in sorted(set(manifest) & set(upstream)):
        row = manifest[key]
        klass = row.get("class")
        anchor = row.get("anchor")
        reason = row.get("reason")

        pinned = row.get("upstream")
        current = digest(upstream[key])
        if pinned != current:
            found.append(
                f"moved: upstream rewrote {key!r}.\n"
                f"    Pinned {pinned}, upstream is now {current}. Read the new "
                f"text, decide whether the classification still holds, then "
                f'set upstream = "{current}".'
            )

        if klass == "omitted":
            if not reason:
                found.append(
                    f"{key!r} is omitted with no reason. An omission with no "
                    f"reason is indistinguishable from an oversight."
                )
            if anchor:
                found.append(
                    f"{key!r} is omitted and carries an anchor. An omitted "
                    f"section has nothing here to point at."
                )
            continue

        if not anchor:
            found.append(
                f"{key!r} is {klass} and has no anchor. The claim that it "
                f"survived here is unproven without one."
            )
        elif anchor not in mine:
            found.append(
                f"{key!r} is {klass} and its anchor is not in this port's "
                f"skill: {anchor!r}.\n"
                f"    Either the content went and the row should say omitted, "
                f"or the anchor text was edited and needs updating."
            )

        if klass == "preserved" and not key.startswith("group: ") and key not in mine:
            found.append(
                f"{key!r} is preserved and this port's skill has no such "
                f"heading. Preserved means the section is still here under the "
                f"same heading -- if it moved or was renamed, it is adapted."
            )

    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True, help="omarchy source tree")
    parser.add_argument("--skill", required=True, help="our skills/nixarchy dir")
    parser.add_argument("--manifest", required=True, help="data/skill-parity.nix")
    parser.add_argument("--report", action="store_true", help="digests, for a bump")
    args = parser.parse_args()

    # Nix, read by regex, and not JSON -- the same call check-bin-ledger.py
    # makes and for the same reason: the load-bearing part of the file is the
    # prose, and a per-row reason does not survive JSON.
    if not os.path.exists(args.manifest):
        die(f"no manifest at {args.manifest}")
    text = open(args.manifest, encoding="utf-8").read()
    manifest = {}
    for key, body in re.findall(r'"([^"]+)"\s*=\s*\{(.*?)\};', text, re.S):
        row = dict(re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', body))
        if row:
            manifest[key] = {k: v.replace('\\"', '"') for k, v in row.items()}
    if not manifest:
        die(f"no rows parsed from {args.manifest}. An empty manifest agrees "
            "with everything, so it is refused.")

    for key, row in manifest.items():
        if row.get("class") not in CLASSES:
            die(f"{key}: class {row.get('class')!r} is not one of {CLASSES}")

    skill_md = os.path.join(
        args.upstream, "default", "agents", "skills", "omarchy", "SKILL.md"
    )
    if not os.path.exists(skill_md):
        die(f"upstream SKILL.md not found at {skill_md}")

    upstream = sections(skill_md)
    mine = ours(args.skill)

    if args.report:
        for key in sorted(upstream):
            print(f'"{key}" -- upstream = "{digest(upstream[key])}"')
        return

    found = problems(manifest, upstream, mine)
    if found:
        print(
            f"data/skill-parity.nix and upstream's SKILL.md disagree, "
            f"{len(found)} problem(s):\n",
            file=sys.stderr,
        )
        for problem in found:
            print(f"  {problem}\n", file=sys.stderr)
        print(
            "  Upstream's SKILL.md is replaced wholesale by this port, on "
            "purpose. This manifest is the record of what that replacement "
            "decided, so a bump cannot change upstream's file without somebody "
            "deciding again. See docs/manual/ai.md and #643.",
            file=sys.stderr,
        )
        sys.exit(1)

    classes = {}
    for row in manifest.values():
        classes[row["class"]] = classes.get(row["class"], 0) + 1
    summary = ", ".join(f"{n} {c}" for c, n in sorted(classes.items()))
    print(
        f"{len(upstream)} upstream sections and command groups, all "
        f"classified: {summary}."
    )


if __name__ == "__main__":
    main()
