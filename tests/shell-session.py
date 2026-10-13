"""Live identity and environment publication, without a compositor."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("session", sys.argv.pop(1))
spec = importlib.util.spec_from_loader(loader.name, loader)
session = importlib.util.module_from_spec(spec)
loader.exec_module(session)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.old = Path(self.tmp.name) / "old"
        self.new = Path(self.tmp.name) / "new"
        for tree in (self.old, self.new):
            (tree / "shell").mkdir(parents=True)
            (tree / "shell/shell.qml").touch()
            (tree / "bin").mkdir()
            (tree / "bin/omarchy-system-sleep-lock").touch()
        self.record = {"pid": 42, "config_path": str(self.new / "shell/shell.qml")}
        self.env = {"WAYLAND_DISPLAY": "wayland-1", "HYPRLAND_INSTANCE_SIGNATURE": "test",
                    "PATH": f"{self.old}/bin:/user/bin:/run/current-system/sw/bin"}

    def resolve(self, records=None, display="wayland-1", expected_pid=None, env=True):
        import json
        with patch.object(session, "run", return_value=json.dumps(records or [self.record])), \
             patch.object(session, "process_environment", return_value=self.env if env else None):
            return session.resolve(display, expected_pid)

    def test_stale_caller(self):
        with patch.dict(os.environ, {"OMARCHY_PATH": str(self.old)}):
            self.assertEqual(self.resolve()[1], self.new)

    def test_other_display(self):
        self.assertIsNone(self.resolve(display="wayland-2"))

    def test_ambiguous(self):
        with self.assertRaisesRegex(session.SessionError, "refusing to guess"):
            self.resolve(records=[self.record, dict(self.record, pid=43)])

    def test_unrelated(self):
        self.assertIsNone(self.resolve(records=[dict(self.record, config_path="/other/main.qml")]))

    def test_exited(self):
        self.assertIsNone(self.resolve(env=False))

    def test_wait_for_own_pid(self):
        self.assertIsNone(self.resolve(expected_pid=43))

    def test_missing_display(self):
        with self.assertRaises(session.SessionError):
            self.resolve(display=None)

    def test_no_instances_sentinel(self):
        with patch.object(session, "run", return_value="No running instances."):
            self.assertIsNone(session.resolve("wayland-1"))

    def test_publish_consistently(self):
        with patch.object(session, "run", return_value="ok") as run:
            session.synchronize((self.record, self.new, self.env))
        calls = [call.args[0] for call in run.call_args_list]
        self.assertEqual(len(calls), 3, "publish to both compositor and activation environments")
        self.assertEqual(calls[0][:4], ["hyprctl", "-i", "test", "eval"])
        self.assertIn(str(self.new), calls[0][4])
        self.assertNotIn(str(self.old), calls[0][4])
        self.assertEqual(calls[1], ["hyprctl", "-i", "test", "reload", "config-only"])
        self.assertEqual(calls[2], ["dbus-update-activation-environment", "--systemd",
                                   f"OMARCHY_PATH={self.new}",
                                   f"PATH={self.new}/bin:/user/bin:/run/current-system/sw/bin"])

    def test_compositor_rejection(self):
        with patch.object(session, "run", return_value="error: rejected") as run:
            with self.assertRaises(session.SessionError):
                session.synchronize((self.record, self.new, self.env))
            self.assertEqual(run.call_count, 1)


unittest.main()
