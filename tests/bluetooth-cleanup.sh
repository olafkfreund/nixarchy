#!/usr/bin/env bash
set -euo pipefail

cleanup=$1
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

alice=$root/alice/.config/systemd/user
bob=$root/bob/.config/systemd/user
mkdir -p "$alice/graphical-session.target.wants" "$bob/graphical-session.target.wants"
ln -s /nix/store/abc-unit-bt-agent.service/bt-agent.service "$alice/bt-agent.service"
ln -s /nix/store/abc-unit-bt-agent.service/bt-agent.service \
  "$alice/graphical-session.target.wants/bt-agent.service"
printf '%s\n' 'user unit' >"$bob/bt-agent.service"
ln -s /nix/store/abc-unit-other.service/bt-agent.service \
  "$bob/graphical-session.target.wants/bt-agent.service"

bash "$cleanup" "$root"
test ! -e "$alice/bt-agent.service" && test ! -L "$alice/bt-agent.service" || {
  echo 'old bt-agent unit symlink survived cleanup' >&2; exit 1;
}
test ! -e "$alice/graphical-session.target.wants/bt-agent.service" && \
  test ! -L "$alice/graphical-session.target.wants/bt-agent.service" || {
    echo 'old bt-agent wants symlink survived cleanup' >&2; exit 1;
  }
test "$(cat "$bob/bt-agent.service")" = 'user unit' || {
  echo 'cleanup changed a user-owned bt-agent unit' >&2; exit 1;
}
test -L "$bob/graphical-session.target.wants/bt-agent.service" || {
  echo 'cleanup removed a foreign bt-agent symlink' >&2; exit 1;
}

echo 'Bluetooth cleanup removes only the two old store-unit symlinks'
