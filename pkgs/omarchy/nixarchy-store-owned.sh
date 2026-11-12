# shellcheck shell=bash

store_owned() {
  local path=${1:-} resolved
  [[ -n $path ]] || return 1

  # #1304: a Home Manager link may point to a file or to its directory.
  while [[ ! -e $path && ! -L $path ]]; do
    path=$(dirname -- "$path")
  done
  resolved=$(readlink -f -- "$path") || return 0
  [[ $resolved == /nix/store/* ]]
}
