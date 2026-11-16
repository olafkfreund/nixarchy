# Shared config-writer lock and file helpers; see plan/2026-11-15-1789-writer-lock.md.

nx_state=${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy
NX_OWNER=${NX_OWNER:-0}

nx_lock() {
  [ "${NIXARCHY_LOCK_HELD:-}" = 1 ] && return 0
  mkdir -p "$nx_state/applied" || nx_refuse "cannot create $nx_state/applied"
  exec 9>>"$nx_state/applied/lock" || nx_refuse "cannot open $nx_state/applied/lock"
  flock -w 5 9 || nx_refuse "a write or an apply is running -- try again when it finishes. Nothing was changed."
  export NIXARCHY_LOCK_HELD=1
  NX_OWNER=1
}

nx_unlock() {
  unset NIXARCHY_LOCK_HELD
  if [ "$NX_OWNER" = 1 ]; then
    exec 9>&-
    NX_OWNER=0
  fi
}

nx_put() {
  local src=$1 dst=$2 bak='' status
  if [ -e "$dst" ]; then
    [ -f "$dst" ] && [ -w "$dst" ] || nx_refuse "$dst is not a writable file"
    mkdir -p "$nx_state/backup" || nx_refuse "cannot create $nx_state/backup"
    bak=$(mktemp -p "$nx_state/backup") || nx_refuse "cannot create backup for $dst"
    cp --reflink=never -- "$dst" "$bak" || nx_refuse "cannot back up $dst to $bak"
  fi

  trap '' INT TERM HUP QUIT XFSZ || nx_refuse "cannot protect write to $dst"
  if cat -- "$src" > "$dst"; then
    status=0
  else
    status=$?
  fi
  trap - INT TERM HUP QUIT XFSZ || nx_refuse "cannot reset signals after writing $dst"

  if [ "$status" -eq 0 ]; then
    if [ -n "$bak" ]; then
      rm -f -- "$src" "$bak" || nx_refuse "cannot remove temporary files for $dst"
    else
      rm -f -- "$src" || nx_refuse "cannot remove temporary file $src"
    fi
    return 0
  fi

  if [ -n "$bak" ]; then
    if cat -- "$bak" > "$dst"; then
      rm -f -- "$bak" "$src" || nx_refuse "$dst could not be written; its previous content is restored"
      nx_refuse "$dst could not be written; its previous content is restored"
    fi
    nx_refuse "$dst could not be written or restored; its previous content is at $bak"
  fi
  rm -f -- "$dst" "$src" || nx_refuse "$dst could not be written"
  nx_refuse "$dst could not be written"
}

nx_sed() {
  local tmp status
  mkdir -p "$nx_state" || return
  tmp=$(mktemp -p "$nx_state") || return
  if sed "${@:2}" -- "$1" > "$tmp"; then
    nx_put "$tmp" "$1"
  else
    status=$?
    rm -f -- "$tmp" || :
    return "$status"
  fi
}

nx_commit() {
  cmp -s -- "$1" "$3" || nx_refuse "$3 changed while $4 was running; nothing was written. Run it again."
  nx_put "$2" "$3"
}

nx_refuse() {
  nx_unlock
  printf '%s\n' "$1" >&2
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -u critical "nixarchy" "$1" 9>&- || true
  fi
  exit 75
}
