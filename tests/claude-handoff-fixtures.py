import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("handoff", os.environ["HANDOFF_SCRIPT"])
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


def job(name, conclusion, step="Check formatting"):
    return {"name": name, "conclusion": conclusion,
            "steps": [{"name": step, "conclusion": conclusion}]}


def pull(sha="deadbeef", draft=False):
    return {"number": 19, "draft": draft,
            "head": {"repo": {"full_name": "o/r"}, "ref": "update/x", "sha": sha}}


class HandoffFixtures(unittest.TestCase):
    def test_lint_commands_use_pinned_nixpkgs(self):
        self.assertEqual(handoff.command("statix"),
                         ["nix", "run", "--inputs-from", ".", "nixpkgs#statix", "--", "check", "."])
        self.assertEqual(handoff.command("deadnix"),
                         ["nix", "run", "--inputs-from", ".", "nixpkgs#deadnix", "--", "--fail", "."])

    def test_draft_and_stale_sha(self):
        for candidate in (pull(draft=True), pull(sha="old")):
            with self.subTest(candidate=candidate), patch.object(handoff, "gh", return_value=[candidate]):
                with self.assertRaises(ValueError):
                    handoff.pr_state("o/r", "update/x", "deadbeef")

    def test_cancelled_and_vm_refused(self):
        for jobs in ([job("system", "failure"), job("system-build", "cancelled")],
                     [job("system-session", "failure", "Drive a session and the app-selection loop")]):
            with self.subTest(jobs=jobs), self.assertRaises(ValueError):
                handoff.check_name(jobs)

    def test_deduplication(self):
        replies = [[pull()], {"jobs": [job("lint", "failure")]}, {"login": "bump"},
                   [[{"user": {"login": "bump"},
                      "body": "<!-- claude-handoff sha=deadbeef -->"}]]]
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "output"
            env = {"REPO": "o/r", "BRANCH": "update/x", "SHA": "deadbeef",
                   "RUN_ID": "1", "GITHUB_OUTPUT": str(output)}
            with patch.dict(os.environ, env), patch.object(handoff, "gh", side_effect=replies):
                with self.assertRaisesRegex(ValueError, "already handed off"):
                    handoff.gate()
            self.assertFalse(output.exists())

    def test_two_attempt_cap(self):
        comments = [[{"user": {"login": "bump"},
                     "body": f"<!-- claude-handoff sha=old{i} -->"} for i in range(2)]]
        replies = [[pull()], {"jobs": [job("lint", "failure")]}, {"login": "bump"}, comments]
        with tempfile.TemporaryDirectory() as temp:
            env = {"REPO": "o/r", "BRANCH": "update/x", "SHA": "deadbeef",
                   "RUN_ID": "1", "GITHUB_OUTPUT": str(Path(temp) / "output")}
            with patch.dict(os.environ, env), patch.object(handoff, "gh", side_effect=replies):
                with self.assertRaisesRegex(ValueError, "two handoffs"):
                    handoff.gate()

    def test_unreadable_auto_merge_refused(self):
        with patch.dict(os.environ, {"REPO": "o/r", "BRANCH": "update/nixpkgs-1",
                                     "SHA": "deadbeef", "PR": "19"}), \
             patch.object(handoff, "pr_state", return_value=pull()), \
             patch.object(handoff, "gh", return_value={}):
            with self.assertRaisesRegex(ValueError, "auto-merge"):
                handoff.publish()

    def test_pinned_packages_disables_auto_merge_before_publish(self):
        with tempfile.TemporaryDirectory() as temp:
            previous = os.getcwd()
            try:
                os.chdir(temp)
                Path("verified-files.json").write_text('{"files": []}')
                with patch.dict(os.environ, {"REPO": "o/r", "BRANCH": "update/pinned-packages",
                                             "SHA": "deadbeef", "PR": "19"}), \
                     patch.object(handoff, "pr_state", return_value=pull()), \
                     patch.object(handoff, "gh", side_effect=[{"auto_merge": {"enabled_at": "now"}},
                                                             {"data": {"createCommitOnBranch": {"commit": {"oid": "new"}}}}]), \
                     patch.object(handoff.subprocess, "run") as run:
                    handoff.publish()
                    run.assert_called_once_with(
                        ["gh", "pr", "merge", "19", "--repo", "o/r", "--disable-auto"], check=True)
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
