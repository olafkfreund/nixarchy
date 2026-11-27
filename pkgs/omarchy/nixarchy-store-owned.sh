# shellcheck shell=bash

store_owned() {
  local path=${1:-} resolved target hops
  [[ -n $path ]] || return 1

  # #1304: a Home Manager link may point to a file or to its directory.
  while [[ ! -e $path && ! -L $path ]]; do
    path=$(dirname -- "$path")
  done
  for ((hops = 0; hops < 40; hops++)); do
    [[ -L $path ]] || break
    target=$(readlink -- "$path") || return 0
    if [[ $target == /* ]]; then
      path=$target
    else
      path=$(realpath -m -s -- "$(dirname -- "$path")/$target")
    fi
    [[ $path == /nix/store/* ]] && return 0
  done
  ((hops < 40)) || return 0
  resolved=$(readlink -f -- "$path") || return 0
  [[ $resolved == /nix/store/* ]]
}
