#!/usr/bin/env python3
"""Cheap, synthetic mutation cases for update-launch.py."""

import atexit
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


source = sys.argv[1]
if len(sys.argv) > 2:
    mutations = {
        "scope": ('if not APP.fullmatch(path) or old_mode != "100644" or new_mode != "100644":', 'if old_mode != "100644" or new_mode != "100644":'),
        "settle": ('and any(now.get("address") == address and now.get("pid") == client["pid"]\n                        for now in settled)', 'and True'),
    }
    before, after = mutations[sys.argv[2]]
    code = open(source, encoding="utf-8").read()
    if code.count(before) != 1:
        raise RuntimeError("mutation did not apply exactly once")
    with tempfile.NamedTemporaryFile(mode="w", prefix="update-launch-fixture-", suffix=".py", delete=False) as temporary:
        temporary.write(code.replace(before, after))
        source = temporary.name
    atexit.register(os.unlink, source)

spec = importlib.util.spec_from_file_location("update_launch", source)
launch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch)
sys.argv = [sys.argv[0]]

QT = b'''version = "0.1.0";
src = fetchFromGitHub {
  url = "https://example.test/app";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
};
wrapper = "safe";
'''
HEY = b'''version = "1.0.0";
hashes = {
  "x86_64-linux" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  "aarch64-linux" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
};
'''


def changed(path, old, new, before="100644", after="100644"):
    return {path: (before, after, old, new)}


class Fixture(unittest.TestCase):
    def test_cached_gui_verdict_comes_from_output(self):
        workflow = Path(os.environ["UPDATE_WORKFLOW"]).read_text()
        vm_test = Path(os.environ["UPDATE_VM_TEST"]).read_text()
        self.assertIn('"verdicts.json").write_text(json.dumps(verdicts))', vm_test)
        self.assertIn("--print-out-paths", workflow)
        self.assertFalse('grep -Fq "launch-verdict' in workflow)
        match = re.search(r'gui_result=\$\(jq -er --arg n "\$name" \'([^\']+)\' "\$vm_out/verdicts.json"\)', workflow)
        self.assertIsNotNone(match)
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "verdicts.json"
            output.write_text('{"omacut": "PASS"}')
            (Path(temp) / "gui.log").write_text("")
            self.assertEqual(subprocess.check_output(
                ["jq", "-r", "--arg", "n", "omacut", match.group(1), str(output)], text=True).strip(), "PASS")
            self.assertEqual(subprocess.check_output(
                ["jq", "-r", "--arg", "n", "missing", match.group(1), str(output)], text=True).strip(), "MISSING")

    def test_accept_qt_and_arch_map(self):
        self.assertEqual(launch.scope(changed("pkgs/apps/omacut.nix", QT, QT.replace(b"0.1.0", b"0.2.0"))), ["pkgs/apps/omacut.nix"])
        self.assertEqual(launch.scope(changed("pkgs/apps/hey-cli.nix", HEY, HEY.replace(b"a" * 64, b"c" * 64))), ["pkgs/apps/hey-cli.nix"])

    def test_refuse_scope(self):
        good = ("100644", "100644", QT, QT.replace(b"0.1.0", b"0.2.0"))
        cases = [
            {},
            {"pkgs/apps/omacut.nix": good, "README.md": good},
            changed("pkgs/apps/omacut.nix", QT, QT.replace(b"safe", b"unsafe").replace(b"0.1.0", b"0.2.0")),
            changed("pkgs/apps/omacut.nix", QT, QT.replace(b"example.test", b"evil.test").replace(b"0.1.0", b"0.2.0")),
            changed("pkgs/apps/omacut.nix", QT, QT.replace(b"0.1.0", b"0.2.0"), after="100755"),
            changed("pkgs/apps/omacut.nix", QT, b""),
            changed("pkgs/apps/omacut.nix", QT, b"\xff"),
        ]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(ValueError):
                launch.scope(case)
        with self.assertRaisesRegex(ValueError, "no launch probe mapping"):
            launch.scope(changed("pkgs/apps/unknown.nix", QT, QT.replace(b"0.1.0", b"0.2.0")), {"omacut": {}})

    def test_refuse_incomplete_evidence(self):
        apps = ["pkgs/apps/omacut.nix"]
        base = {"sha": "head", "updater": "clean", "build": "clean", "results": {apps[0]: "PASS"}}
        self.assertTrue(launch.eligible(base, "head", apps))
        for change in (
            {"sha": "stale"}, {"updater": "partial"}, {"build": "partial"},
            {"results": {}}, {"results": {apps[0]: "MANUAL"}},
        ):
            with self.subTest(change=change):
                self.assertFalse(launch.eligible(base | change, "head", apps))
        self.assertFalse(launch.eligible(base, "head", apps + ["pkgs/apps/unknown.nix"]))

    def test_not_eligible_is_a_draft_not_a_failure(self):
        # A manual-only app leaves the PR in draft; the workflow must not go red for it.
        apps = ["pkgs/apps/omarchy-local-ai.nix"]
        verdict = {"sha": "head", "updater": "clean", "build": "clean",
                   "results": {apps[0]: "MANUAL"}}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            import json
            json.dump(verdict, handle)
        original_scope, original_argv = launch.scope_git, sys.argv
        launch.scope_git = lambda base, head: apps
        sys.argv = ["update-launch.py", "eligible", "--base", "b", "--head", "head", "--verdict", handle.name]
        try:
            self.assertEqual(launch.main(), launch.NOT_ELIGIBLE)
            self.assertNotEqual(launch.NOT_ELIGIBLE, 1)
        finally:
            launch.scope_git, sys.argv = original_scope, original_argv
            os.unlink(handle.name)

    def test_window_must_be_new_owned_and_stable(self):
        old = [{"address": "0x1", "class": "omacut", "pid": 10}]
        new = {"address": "0x2", "class": "omacut", "pid": 20}
        self.assertFalse(launch.observed(old, old, old, "omacut", {10}))
        self.assertFalse(launch.observed(old, [new], [], "omacut", {20}))
        self.assertFalse(launch.observed(old, [new], [new], "omacut", set()))
        self.assertTrue(launch.observed(old, [new], [new], "omacut", {20}))


if __name__ == "__main__":
    unittest.main()
