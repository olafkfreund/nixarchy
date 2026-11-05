{ pkgs, ... }:
# Runs a rewritten copy of the shipped script. A green stub proves deletion was asked for,
# not that a reader obeyed; tests/AGENTS.md names that hole.
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-remove-fingerprint"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    script = "${shipped}/share/omarchy/bin/omarchy-remove-security-fingerprint";
    reset = "${shipped}/share/omarchy/bin/omarchy-system-factory-reset";
    shell = pkgs.runtimeShell;
  }
  ''
    set -euo pipefail
    real_home=$HOME
    export HOME=$TMPDIR/home USER=mallory
    export XDG_DATA_HOME=$HOME/.local/share XDG_STATE_HOME=$HOME/.local/state
    export XDG_CONFIG_HOME=$HOME/.config XDG_CACHE_HOME=$HOME/.cache
    unset SUDO_UID
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    fix=$TMPDIR/prints
    log=$TMPDIR/calls
    base=$PATH
    mkdir -p "$TMPDIR/stubs" "$TMPDIR/reader" "$TMPDIR/no-reader" "$fix"
    export fix log
    fails=()
    fail() { fails+=("$1"); }

    for word in omarchy-pkg-drop omarchy-lifecycle-dispatch /etc/pam.d pacman systemctl; do
      if grep -qF "$word" "$script"; then fail "shipped script still names $word"; fi
    done
    [ "$(grep -Ec '\brm\b' "$script")" -eq 2 ] || fail "shipped script has an unexpected rm line"
    for phrase in 'No devices available' 'No fingerprints to delete on' 'deleted on'; do
      grep -aqF "$phrase" ${pkgs.fprintd}/bin/fprintd-delete || fail "fprintd-delete lacks $phrase"
    done
    grep -qi fingerprint "$reset" || fail "factory reset does not mention fingerprints"

    [ "$(grep -oF /run/current-system/sw/bin/id "$script" | wc -l || true)" -eq 2 ] || fail "id rewrite count changed"
    [ "$(grep -oF /var/lib/fprint/ "$script" | wc -l || true)" -eq 3 ] || fail "print path rewrite count changed"
    sed -e "s|/run/current-system/sw/bin/id|$TMPDIR/stubs/id|g" \
      -e "s|/var/lib/fprint/|$fix/|g" "$script" > "$TMPDIR/press"
    if grep -qF /var/lib/fprint/ "$TMPDIR/press"; then fail "print path rewrite left a real path"; fi

    printf '#!%s\nprintf "%%s\\n" "$ID_USER"\n' "$shell" > "$TMPDIR/stubs/id"
    printf '#!%s\ncase "$1" in\n  -n|-v)\n    if [ "$REFUSE" = pre ]; then echo "sudo: refused" >&2; exit 1; fi ;;\n  *)\n    kind=other\n    case "$*" in\n      *fprintd-delete*) kind=delete ;;\n      *"[ -e"*) kind=probe ;;\n      rm\ *) kind=rm ;;\n    esac\n    printf "sudo %%s\\n" "$*" >> "$log"\n    if [ "$REFUSE" = "$kind" ] || { [ "$REFUSE" = rm-fail ] && [ "$kind" = rm ]; }; then\n      echo "sudo: refused" >&2\n      exit 1\n    fi\n    exec "$@" ;;\nesac\n' "$shell" > "$TMPDIR/stubs/sudo"
    printf '#!%s\nprintf "fprintd-delete %%s\\n" "$1" >> "$log"\ncase "$MODE" in\n  deleted) echo "Fingerprints of user $1 deleted on Virtual" ;;\n  nothing) echo "No fingerprints to delete on Virtual" ;;\n  absent) echo "No devices available"; exit 1 ;;\n  fail) echo "failed to claim device"; exit 1 ;;\n  deverr)\n    rm -f -- "$fix/$1/goodix/0/7"\n    rmdir "$fix/$1/goodix/0" "$fix/$1/goodix" "$fix/$1"\n    echo "failed after deleting file"; exit 1 ;;\nesac\n' "$shell" > "$TMPDIR/reader/fprintd-delete"
    for name in pkexec tee usermod gpasswd systemctl pacman omarchy-pkg-drop omarchy-lifecycle-dispatch nmcli; do
      printf '#!%s\necho "forbidden: %s" >> "$log"\nexit 1\n' "$shell" "$name" > "$TMPDIR/stubs/$name"
    done
    chmod +x "$TMPDIR/stubs"/* "$TMPDIR/reader"/*

    seed() {
      rm -rf -- "$fix"
      mkdir -p "$fix/alice/goodix/0" "$fix/bob/goodix/0"
      : > "$fix/alice/goodix/0/7"
      : > "$fix/bob/goodix/0/7"
    }
    press() {
      label=$1 ID_USER=$2 MODE=$3 REFUSE=$4 reader=$5
      export ID_USER MODE REFUSE
      : > "$log"
      if [ "$reader" = yes ]; then
        export PATH=$TMPDIR/stubs:$TMPDIR/reader:$base
      else
        export PATH=$TMPDIR/stubs:$TMPDIR/no-reader:$base
      fi
      rc=0
      bash "$TMPDIR/press" > "$TMPDIR/output" 2>&1 || rc=$?
      if grep -q '^forbidden:' "$log"; then fail "$label: called a forbidden writer"; fi
      printf 'case %s: exit %s\n' "$label" "$rc"
    }
    status() { [ "$rc" -eq "$1" ] || fail "$label: exited $rc, wanted $1"; }
    said() { grep -qF "$1" "$TMPDIR/output" || fail "$label: missing $1"; }
    silent() { if grep -qF "$1" "$TMPDIR/output"; then fail "$label: wrongly said $1"; fi; }
    calls() {
      grep -E '^(fprintd-delete |sudo rm )' "$log" > "$TMPDIR/actual" || true
      : > "$TMPDIR/want"
      if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$TMPDIR/want"; fi
      cmp -s "$TMPDIR/want" "$TMPDIR/actual" || fail "$label: wrong delete/rm calls: $(cat "$TMPDIR/actual")"
    }
    intact() { [ -e "$fix/$1/goodix/0/7" ] || fail "$label: $1 was removed"; }
    gone() { [ ! -e "$fix/$1" ] || fail "$label: $1 remains"; }

    seed
    press a alice deleted none yes
    status 0; calls 'fprintd-delete alice' "sudo rm -rf -- $fix/alice"
    gone alice; intact bob; said "Deleted alice's saved"

    press b alice nothing none yes
    status 0; calls 'fprintd-delete alice' "sudo rm -rf -- $fix/alice"
    gone alice; intact bob; said 'none on record'; said 'may still hold'; silent 'Deleted '

    seed
    press c bob deleted none yes
    status 0; calls 'fprintd-delete bob' "sudo rm -rf -- $fix/bob"
    gone bob; intact alice; said "Deleted bob's saved"

    seed
    press d alice nothing none yes
    status 0; calls 'fprintd-delete alice' "sudo rm -rf -- $fix/alice"
    gone alice; intact bob; said "Deleted alice's saved"

    seed
    press e alice absent none yes
    status 0; calls 'fprintd-delete alice' "sudo rm -rf -- $fix/alice"
    gone alice; intact bob; said 'stay there'

    seed
    press f alice nothing none no
    status 0; calls "sudo rm -rf -- $fix/alice"
    gone alice; intact bob; said "Deleted alice's saved"; said 'fprintd is not available'; silent 'still declared'

    seed
    rm -rf -- "$fix/alice"
    press f2 alice nothing none no
    status 0; calls "sudo rm -rf -- $fix/alice"
    gone alice; intact bob; said 'no saved fingerprints on this disk'; said 'fprintd is not available'; silent 'none on record'

    seed
    press g alice fail none yes
    status 1; calls 'fprintd-delete alice'
    intact alice; intact bob; said 'failed to claim device'; silent 'Deleted '

    seed
    press h alice deverr none yes
    status 1; calls 'fprintd-delete alice'
    gone alice; intact bob; said 'may already be gone'
    press h2 alice nothing none yes
    status 0; calls 'fprintd-delete alice' "sudo rm -rf -- $fix/alice"
    said 'none on record'; said 'may still hold'; silent 'Deleted '

    seed
    press i alice deleted pre yes
    status 1; calls; intact alice; intact bob; said 'administrator rights'

    seed
    press j alice deleted delete yes
    status 1; calls; intact alice; intact bob; said 'administrator rights'; silent 'may already be gone'

    seed
    press k alice deleted probe yes
    status 1; calls 'fprintd-delete alice'
    intact alice; intact bob; said 'administrator rights'

    seed
    press l alice deleted rm-fail yes
    status 1; calls 'fprintd-delete alice' "sudo rm -rf -- $fix/alice"
    intact alice; intact bob; said 'may be incomplete'; silent 'Deleted '

    [ ! -e "$real_home" ] || fail "wrote outside the fixture: $real_home"
    if [ "''${#fails[@]}" -gt 0 ]; then
      printf 'FAIL: %s\n' "''${fails[@]}" >&2
      exit 1
    fi
    touch "$out"
  ''
