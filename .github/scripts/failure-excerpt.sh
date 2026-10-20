#!/usr/bin/env bash
# stdin: a failing log. stdout: the lines that name the cause, MAX (40) at most.
# Shared by copilot-handoff.sh and failure-digest.sh (#1384).
#
# nix's `… while calling` frames are dropped: the line that names the cause is
# the `error:` at the bottom of a trace two hundred lines deep, and a tail
# lands past it. Colour is stripped in both spellings: GitHub's log API returns
# the literal text ^[[31m rather than ESC.
set -euo pipefail
# sed, not head: head exits early and the stages before it die of SIGPIPE under pipefail (#1157).
sed 's/\x1b\[[0-9;]*m//g; s/\^\[\[[0-9;]*m//g' \
  | grep -vE '^([^:]*: +)?(… |[0-9]+ *\||\|)' \
  | { grep -E -A6 'error|Error|FAIL|Traceback|AssertionError|RequestedAssertionFailed|does not evaluate|unexpected changes|Failed to' || true; } \
  | sed -n "1,${MAX:-40}p"
