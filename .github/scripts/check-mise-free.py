#!/usr/bin/env python3
"""Fail when shipped code gains an unreviewed mise reference."""

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

PATTERN = re.compile(r"\bmise\b|MISE_")
COMMENT = re.compile(r"(^|\s)#.*")
TREE_DIRS = ("bin", "default", "install", "shell", "config", "applications")


def files(label, root):
    root = Path(root)
    if root.is_file():
        yield f"{label}/{label}", root
        return
    starts = (root / name for name in TREE_DIRS) if label == "tree" else (root,)
    seen = set()
    for start in starts:
        for directory, dirs, names in os.walk(start, followlinks=True):
            real = os.path.realpath(directory)
            if real in seen:
                dirs[:] = []
                continue
            seen.add(real)
            relative = Path(directory).relative_to(root)
            # The upstream French translations say "mise à jour" (update).
            if label == "tree" and relative == Path("default/i18n"):
                dirs[:] = []
                continue
            for name in names:
                path = Path(directory) / name
                if label == "modules" and path.suffix != ".nix":
                    continue
                yield f"{label}/{path.relative_to(root)}", path


def scan(roots, allow):
    found = {path: set() for path in allow}
    problems = []
    walked = 0
    for label, root in roots:
        for key, path in files(label, root):
            walked += 1
            try:
                with path.open("rb") as stream:
                    if b"\0" in stream.read(8192):
                        continue
                lines = path.read_text(errors="replace").splitlines()
            except OSError as error:
                problems.append(f"{key}: {error}")
                continue
            for number, line in enumerate(lines, 1):
                clean = COMMENT.sub("", line).strip()
                if not PATTERN.search(clean):
                    continue
                if clean in allow.get(key, {}).get("lines", []):
                    found[key].add(clean)
                else:
                    problems.append(f"{key}:{number}: {clean}")
    for key, row in allow.items():
        if not row.get("reason"):
            problems.append(f"{key}: missing reason")
        for line in row.get("lines", []):
            if line not in found[key]:
                problems.append(f"stale: {key}: {line}")
    return walked, problems


def self_test():
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        (root / "bin").mkdir()
        path = root / "bin/omarchy-new-thing"
        path.write_text("mise use -g foo\n")
        roots = [("tree", root)]
        if not scan(roots, {})[1]:
            raise SystemExit("mise-free: self-test missed a new bin")
        key = "tree/bin/omarchy-new-thing"
        path.write_text("mise use -g foo\nmise install bar\n")
        allowed = {key: {"reason": "self-test", "lines": ["mise use -g foo"]}}
        if not scan(roots, allowed)[1]:
            raise SystemExit("mise-free: self-test missed a new line in an allowed file")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--allow", required=True)
    parser.add_argument("--root", action="append", required=True)
    args = parser.parse_args()
    roots = []
    for item in args.root:
        label, separator, path = item.partition("=")
        if not separator or not label or not path:
            parser.error(f"expected --root label=path, got {item!r}")
        roots.append((label, path))
    with open(args.allow, encoding="utf-8") as stream:
        allow = json.load(stream)
    self_test()
    walked, problems = scan(roots, allow)
    if walked < 1000:
        problems.append(f"mise-free: walked only {walked} files (minimum 1000)")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"mise-free: walked {walked} files; all references recorded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
