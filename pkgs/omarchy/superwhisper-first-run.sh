#!/usr/bin/env bash

marker=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/done/superwhisper-notice
if [[ ! -e $marker ]]; then
  selection=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/defaults/dictation
  if [[ -f $selection && $(< "$selection") == superwhisper ]] && ! command -v superwhisper >/dev/null 2>&1; then
    omarchy-notification-send 'Superwhisper is ready to choose' 'Open Setup > Default > Dictation to install it.' || true
  fi
  mkdir -p "${marker%/*}" && touch "$marker" || true
fi
exit 0
