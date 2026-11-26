#!/usr/bin/env python3
"""Fail-closed diff and launch verdicts for update.yml (#1943)."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


APP = re.compile(r"pkgs/apps/[a-z0-9-]+\.nix\Z")
PIN = re.compile(r'^(\s*)(version|hash|sha256|cargoHash|npmDepsHash|vendorHash) = "([^"]+)";(\s*)$')
ARCH = re.compile(r'^(\s*)"(x86_64-linux|aarch64-linux)" = "([^"]+)";(\s*)$')
VERSION = re.compile(r"[0-9][A-Za-z0-9.+_-]*\Z")
HASH = re.compile(r"(?:sha256-[A-Za-z0-9+/]{43}=|[a-fA-F0-9]{64}|[a-z0-9]{52})\Z")


def git(*args):
    return subprocess.check_output(["git", *args])


def normalized(data, path):
    try:
        lines = data.decode("utf-8").splitlines(keepends=True)
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path}: unreadable text") from exc
    result = []
    pins = []
    in_hashes = False
    in_updater = False
    for line in lines:
        body = line.removesuffix("\n")
        if re.match(r"^\s*passthru\.updateScript =", body):
            in_updater = True
        if re.match(r"^\s*hashes = \{$", body):
            in_hashes = True
        elif in_hashes and re.match(r"^\s*\};$", body):
            in_hashes = False
        match = PIN.fullmatch(body) if not in_updater else None
        arch = ARCH.fullmatch(body) if not in_updater and in_hashes and path in ("pkgs/apps/hey-cli.nix", "pkgs/apps/once.nix") else None
        if match or arch:
            key, value = (match.group(2), match.group(3)) if match else (arch.group(2), arch.group(3))
            valid = VERSION if key == "version" else HASH
            if not valid.fullmatch(value):
                raise ValueError(f"{path}: invalid {key} literal")
            pins.append((key, value))
            start, end = (match or arch).span(3)
            body = body[:start] + "<pin>" + body[end:]
        result.append(body + ("\n" if line.endswith("\n") else ""))
    return "".join(result), pins


def scope(changes, probes=None):
    """changes: path -> (old mode, new mode, old bytes, new bytes)."""
    if not changes:
        raise ValueError("empty PR diff")
    for path, (old_mode, new_mode, old, new) in changes.items():
        if not APP.fullmatch(path) or old_mode != "100644" or new_mode != "100644":
            raise ValueError(f"{path}: outside approved regular app files or mode changed")
        if probes is not None and path.removeprefix("pkgs/apps/").removesuffix(".nix") not in probes:
            raise ValueError(f"{path}: no launch probe mapping")
        before, old_pins = normalized(old, path)
        after, new_pins = normalized(new, path)
        if before != after or [p[0] for p in old_pins] != [p[0] for p in new_pins]:
            raise ValueError(f"{path}: content outside version and hash literals changed")
        if old_pins == new_pins:
            raise ValueError(f"{path}: no pin changed")
    return sorted(changes)


def tree_entry(rev, path):
    line = git("ls-tree", rev, "--", path).decode().strip()
    if not line:
        return "", b""
    mode, kind, _, listed = re.split(r"[ \t]", line, maxsplit=3)
    if kind != "blob" or listed != path:
        return "", b""
    return mode, git("show", f"{rev}:{path}")


def scope_git(base, head):
    paths = git("diff", "--name-only", "-z", base, head).decode().strip("\0").split("\0")
    changes = {}
    for path in paths:
        old_mode, old = tree_entry(base, path)
        new_mode, new = tree_entry(head, path)
        changes[path] = old_mode, new_mode, old, new
    probes = json.loads((Path(__file__).resolve().parents[2] / "data/update-launch.json").read_text())
    return scope(changes, probes)


def observed(before, opened, settled, expected, alive):
    old = {client.get("address") for client in before}
    for client in opened:
        address = client.get("address")
        if (address not in old and client.get("class", "").lower() == expected.lower()
                and isinstance(client.get("pid"), int) and client["pid"] > 0
                and any(now.get("address") == address and now.get("pid") == client["pid"]
                        for now in settled) and client["pid"] in alive):
            return True
    return False


def eligible(verdict, sha, apps):
    if verdict.get("sha") != sha or verdict.get("updater") != "clean" or verdict.get("build") != "clean":
        return False
    results = verdict.get("results")
    return bool(apps) and isinstance(results, dict) and set(results) == set(apps) and all(
        results[app] == "PASS" for app in apps
    )


NOT_ELIGIBLE = 3  # stays a draft; distinct from 1, a real failure


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("scope", "eligible"))
    parser.add_argument("--base")
    parser.add_argument("--head")
    parser.add_argument("--verdict")
    args = parser.parse_args()
    try:
        if args.command == "scope":
            if not args.base or not args.head:
                raise ValueError("base and head are required")
            print(json.dumps(scope_git(args.base, args.head)))
        else:
            if not args.head or not args.verdict:
                raise ValueError("head and verdict are required")
            verdict = json.load(open(args.verdict, encoding="utf-8"))
            apps = scope_git(args.base, args.head)
            if not eligible(verdict, args.head, apps):
                # Not an error: the PR stays a draft for a person (a manual-only
                # app, a failed probe, a stale head). Exit 3 tells the workflow so.
                print("update launch: not eligible: incomplete or stale launch verdict", file=sys.stderr)
                return NOT_ELIGIBLE
            print("eligible")
    except (ValueError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f"update launch: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
