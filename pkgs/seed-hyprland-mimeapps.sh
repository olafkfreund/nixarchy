#!/usr/bin/env bash
set -euo pipefail
src=$1 dest=$2
if [ -e "$dest" ] || [ -L "$dest" ]; then
  exit 0
fi
mkdir -p "$(dirname "$dest")"
cp --no-preserve=mode,ownership "$src" "$dest"
