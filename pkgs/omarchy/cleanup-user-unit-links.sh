#!/usr/bin/env bash
set -euo pipefail

removed=0
for home in "$@"; do
  home_uid=$(stat -c %u -- "$home") || continue
  for row in \
    bt-agent:graphical-session \
    omarchy-sleep-lock:graphical-session \
    omarchy-crash-watch:graphical-session \
    omarchy-fcitx5:graphical-session \
    omarchy-recover-internal-monitor:graphical-session-pre; do
    unit=${row%%:*}
    target=${row#*:}
    for relative in \
      ".config/systemd/user/$unit.service" \
      ".config/systemd/user/$target.target.wants/$unit.service"; do
      link=$home/$relative
      [[ -L $link ]] || continue
      source=$(readlink -- "$link") || continue
      [[ $source =~ ^/nix/store/[a-z0-9]{32}-unit-${unit}\.service/${unit}\.service$ ]] || continue
      link_uid=$(stat -c %u -- "$link") || continue
      if [[ $link_uid != "$home_uid" ]]; then
        printf 'nixarchy: refusing link owned by another user %s\n' "$link" >&2
        continue
      fi
      if rm -- "$link"; then
        removed=$((removed + 1))
      else
        printf 'nixarchy: could not remove old user unit link %s\n' "$link" >&2
      fi
    done
  done
done

if ((removed > 0)); then
  printf 'nixarchy: removed %d old user unit link(s); an inactive unit starts at next login or with systemctl --user start <unit>\n' "$removed"
fi
