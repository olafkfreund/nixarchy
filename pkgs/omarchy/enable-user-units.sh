#!/usr/bin/env bash
# Enable the user units this machine actually has.
#
# Upstream enables six in one `systemctl --user enable --now` under
# `set -euo pipefail`, so one absent unit fails the whole command:
#
#   Failed to enable unit: Unit omarchy-migrate-notify.service does not exist
#
# Two are deliberately absent here. modules/nixos.nix explains that
# omarchy-migrate-notify and omarchy-tailscale-receive can never satisfy their
# ConditionPath* on NixOS, and that both jobs belong elsewhere -- migrations
# arrive with a rebuild, Taildrop with services.tailscale. What was missed is
# that upstream's first-run still NAMES them.
#
# The cost was out of all proportion to the cause. omarchy-provision-first-run
# marks itself done only when EVERY step succeeded, so one absent unit meant
# the marker was never written and first-run ran again at every login -- which
# is a welcome notification on every boot, for the life of the machine.
#
# Filtered at runtime rather than trimmed to a shorter fixed list:
# omarchy-fcitx5 is absent too on a machine with no input method configured,
# and a hardcoded list would need editing every time the module's set changes.
# Units that DO exist still report their own failures, which is the half worth
# keeping -- this makes a MISSING unit non-fatal, not a broken one.
set -euo pipefail

systemctl --user daemon-reload

want=()
for u in \
  bt-agent.service \
  omarchy-recover-internal-monitor.service \
  omarchy-sleep-lock.service \
  omarchy-migrate-notify.service \
  omarchy-fcitx5.service \
  omarchy-crash-watch.service; do
  if systemctl --user cat "$u" >/dev/null 2>&1; then
    want+=("$u")
  fi
done

if [ ${#want[@]} -gt 0 ]; then
  systemctl --user enable --now "${want[@]}"
fi
