#!/usr/bin/env bash
set -euo pipefail

for home in "${1:-/home}"/*; do
  [[ -d $home ]] || continue
  for relative in \
    .config/systemd/user/bt-agent.service \
    .config/systemd/user/graphical-session.target.wants/bt-agent.service; do
    link=$home/$relative
    if [[ -L $link && $(readlink "$link") == /nix/store/*-unit-bt-agent.service/bt-agent.service ]]; then
      rm -- "$link"
    fi
  done
done
