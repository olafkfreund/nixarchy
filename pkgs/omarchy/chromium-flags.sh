#!/usr/bin/env bash
set -euo pipefail

flags=()
features=()
declare -A seen=()
has_features=false
config="${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf"
omarchy_path="${OMARCHY_PATH:-/run/current-system/sw/share/omarchy}"
omarchy_path="${omarchy_path%/}"

if [[ -f "$config" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Quoted: bash 5.2 would expand an & in the replacement to the match.
    line="${line//\/usr\/share\/omarchy\//"$omarchy_path"/}"

    if [[ "$line" == --enable-features=* ]]; then
      has_features=true
      IFS=, read -ra entries <<< "${line#--enable-features=}"
      for feature in "${entries[@]}"; do
        if [[ -n "$feature" && -z "${seen[$feature]+x}" ]]; then
          features+=("$feature")
          seen["$feature"]=1
        fi
      done
    else
      flags+=("$line")
    fi
  done < "$config"
fi

if [[ "$has_features" == true ]]; then
  if [[ -n "${NIXOS_OZONE_WL:-}" && -n "${WAYLAND_DISPLAY:-}" && -z "${seen[WaylandWindowDecorations]+x}" ]]; then
    features+=(WaylandWindowDecorations)
  fi
  if ((${#features[@]})); then
    flags+=("--enable-features=$(IFS=,; echo "${features[*]}")")
  fi
fi

exec "${CHROMIUM_REAL:-@chromium@}" "${flags[@]}" "$@"
