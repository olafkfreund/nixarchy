{ pkgs, ... }:
pkgs.runCommand "nixarchy-session-journal-race" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - <<'PY'
  import os
  from pathlib import Path
  import runpy
  import subprocess
  import tempfile

  invocation_journal = runpy.run_path("${./session-journal.py}")["invocation_journal"]
  invocation = "fixture-123"
  command = "journalctl --user -u nixarchy-rebuild --invocation=" + invocation + " --no-pager -o cat"

  stub = """#!/bin/sh
  case " $* " in *" --invocation=fixture-123 "*) ;; *) exit 9 ;; esac
  count=$(cat "$JOURNAL_COUNT" 2>/dev/null || printf 0)
  printf 'Started nixarchy-rebuild.service\nFailed with result exit-code.\n'
  if [ "$JOURNAL_ABSENT" != 1 ] && [ "$count" -ge 1 ]; then
    printf '%s\n' "$JOURNAL_EXPECTED"
  fi
  printf '%s\n' "$((count + 1))" > "$JOURNAL_COUNT"
  """

  class Machine:
      def __init__(self, root, expected, absent=False):
          bin_dir = root / "bin"
          bin_dir.mkdir()
          journalctl = bin_dir / "journalctl"
          journalctl.write_text(stub)
          journalctl.chmod(0o755)
          self.count = root / "count"
          self.env = dict(os.environ)
          self.env.update(
              PATH=str(bin_dir) + os.pathsep + self.env["PATH"],
              JOURNAL_COUNT=str(self.count),
              JOURNAL_EXPECTED=expected,
              JOURNAL_ABSENT="1" if absent else "0",
          )

      def run(self, cmd):
          return subprocess.run(
              ["bash", "-c", "set -euo pipefail; " + cmd],
              env=self.env, text=True, capture_output=True, check=False,
          )

      def succeed(self, cmd):
          result = self.run(cmd)
          assert result.returncode == 0, result.stderr
          return result.stdout

      def wait_until_succeeds(self, cmd, timeout):
          assert timeout == 30, f"unbounded or unexpected timeout: {timeout}"
          for _ in range(3):
              if self.run(cmd).returncode == 0:
                  return
          raise TimeoutError("the fixture journal never showed the marker")

  for label, expected in (
      ("missing-flake", "does not exist"),
      ("refusal", "refusing to rebuild from 'agent/unmerged'"),
      ("override", "Enabled apps:"),
  ):
      with tempfile.TemporaryDirectory() as directory:
          machine = Machine(Path(directory), expected)
          try:
              log = invocation_journal(machine, command, expected, invocation)
          except Exception as exc:
              raise AssertionError(f"FAIL delayed {label}: {exc}") from exc
          assert expected in log
          assert int(machine.count.read_text()) >= 2, "journal was not retried"
          print(f"OK delayed {label} marker appeared after the first journal read")

  with tempfile.TemporaryDirectory() as directory:
      machine = Machine(Path(directory), "never appears", absent=True)
      try:
          invocation_journal(machine, command, "never appears", invocation)
      except AssertionError as exc:
          assert "timed out" in str(exc), str(exc)
          assert invocation in str(exc), str(exc)
          assert "Started nixarchy-rebuild.service" in str(exc), str(exc)
          print("OK permanently absent marker timed out with the scoped journal")
      else:
          raise AssertionError("FAIL a permanently absent marker passed")
  PY
  touch "$out"
''
