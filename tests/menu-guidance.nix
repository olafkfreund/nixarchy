{ inputs, pkgs }:
# The menu scripts patched to explain and exit 1 (#1304) call no writer.
#
# checks.menu-actions classifies rows; it cannot tell that a patched script
# really stops before its first writer, because it reads text. This runs each
# one with every writer stubbed to record its call, and holds three things:
# nothing was written, the declarative line was printed, and the exit was 1.
# Writes are checked first, so a script that reaches a stub and exits 0
# because the stub succeeded reports the writer, not just its status.
#
# Two cases vary their input on purpose, because a check that holds the input
# constant proves nothing about it: fingerprint with and without fprintd (the
# enabled run must get as far as enrollment), and the timezone under two picks.
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-menu-guidance"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
    bin = "${shipped}/share/omarchy/bin";
    shell = pkgs.runtimeShell;
  }
  ''
    set -euo pipefail
    real_home=$HOME
    export HOME=$TMPDIR/home
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_CACHE_HOME=$HOME/.cache
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    export USER=tester
    base=$PATH
    writes=$TMPDIR/writes
    notify=$TMPDIR/notify

    # mk <dir> <name> <exit> [record]: a stub that exits <exit>.
    mk() {
      mkdir -p "$1"
      if [ "''${4:-}" = record ]; then
        printf '#!%s\necho "%s $*" >> "%s"\nexit %s\n' "$shell" "$2" "$writes" "$3" > "$1/$2"
      else
        printf '#!%s\nexit %s\n' "$shell" "$3" > "$1/$2"
      fi
      chmod +x "$1/$2"
    }

    rec=$TMPDIR/rec
    for w in sudo pkexec nmcli tee usermod gpasswd systemctl pacman omarchy-pkg-drop rm; do
      mk "$rec" "$w" 0 record
    done
    # timedatectl records only a set-*; a list answers from the pick.
    printf '#!%s\ncase "$1" in\n  set-*) echo "timedatectl $*" >> "%s" ;;\n  list-timezones) cat "%s/pick" ;;\nesac\nexit 0\n' "$shell" "$writes" "$TMPDIR" > "$rec/timedatectl"
    chmod +x "$rec/timedatectl"
    for q in fprintd-verify omarchy-shell omarchy-state; do mk "$rec" "$q" 0; done

    fails=()
    ok=()

    # case <label> <stubdir> <marker-file> <marker> <script> [args...]
    run_case() {
      local label=$1 stubs=$2 where=$3 marker=$4 script=$5
      shift 5
      : > "$writes"; : > "$notify"
      export PATH=$stubs:$rec:$bin:$base
      local rc=0
      bash "$bin/$script" "$@" > "$TMPDIR/out" 2>&1 </dev/null || rc=$?
      local bad=0
      if [ -s "$writes" ]; then
        fails+=("menu-guidance: $label called $(head -n1 "$writes")"); bad=1
      fi
      local file=$TMPDIR/out
      [ "$where" = notify ] && file=$notify
      if ! grep -qF -- "$marker" "$file"; then
        fails+=("menu-guidance: $label did not name $marker"); bad=1
      fi
      if [ "$rc" -ne 1 ]; then
        fails+=("menu-guidance: $label exited $rc"); bad=1
      fi
      if [ "$bad" -eq 0 ]; then ok+=("$label: exit 1, named $marker, no writer called"); fi
    }

    mk "$TMPDIR/s-gum" gum 0
    run_case "dns Cloudflare" "$TMPDIR/s-gum" out 'networking.nameservers' omarchy-dns Cloudflare
    run_case "dns Custom" "$TMPDIR/s-gum" out 'networking.nameservers' omarchy-dns Custom

    mk "$TMPDIR/s-sd-set" gum 0
    mk "$TMPDIR/s-sd-set" omarchy-sudo-docker 0
    run_case "setup sudoless-docker" "$TMPDIR/s-sd-set" out 'extraGroups' omarchy-setup-security-sudoless-docker
    mk "$TMPDIR/s-sd-rm" gum 0
    mk "$TMPDIR/s-sd-rm" omarchy-sudo-docker 1
    run_case "remove sudoless-docker" "$TMPDIR/s-sd-rm" out 'extraGroups' omarchy-remove-security-sudoless-docker

    run_case "remove fingerprint" "$TMPDIR/s-gum" out 'Nothing on this machine was changed' omarchy-remove-security-fingerprint
    run_case "remove fido2" "$TMPDIR/s-gum" out 'only then delete the registration' omarchy-remove-security-fido2

    mk "$TMPDIR/s-fp" gum 0
    mk "$TMPDIR/s-fp" omarchy-hw-fingerprint 0
    run_case "setup fingerprint, fprintd off" "$TMPDIR/s-fp" out 'Enable the reader first' omarchy-setup-security-fingerprint

    # The opposite: with fprintd on, the guard must let the script reach enrollment.
    mk "$TMPDIR/s-fp-on" gum 0
    mk "$TMPDIR/s-fp-on" omarchy-hw-fingerprint 0
    mk "$TMPDIR/s-fp-on" fprintd-enroll 0
    : > "$writes"
    export PATH=$TMPDIR/s-fp-on:$rec:$bin:$base
    bash "$bin/omarchy-setup-security-fingerprint" > "$TMPDIR/out" 2>&1 </dev/null || true
    if [ "$(head -n1 "$writes")" = "sudo fprintd-enroll tester" ]; then
      ok+=("setup fingerprint, fprintd on: reached sudo fprintd-enroll tester")
    else
      fails+=("menu-guidance: setup fingerprint never reaches fprintd-enroll with fprintd on")
    fi

    # The timezone under two picks: the line must carry the pick it was given.
    for tz in Europe/Oslo Asia/Tokyo; do
      printf '%s\n' "$tz" > "$TMPDIR/pick"
      mkdir -p "$TMPDIR/s-tz"
      printf '#!%s\ncat "%s/pick"\n' "$shell" "$TMPDIR" > "$TMPDIR/s-tz/omarchy-menu-select"
      printf '#!%s\necho "$*" >> "%s"\n' "$shell" "$notify" > "$TMPDIR/s-tz/omarchy-notification-send"
      chmod +x "$TMPDIR"/s-tz/*
      run_case "timezone $tz" "$TMPDIR/s-tz" notify "time.timeZone = \"$tz\"" omarchy-menu-timezone
    done

    [ ! -e "$real_home" ] || fails+=("menu-guidance: wrote outside the fixture: $real_home")

    if [ "''${#ok[@]}" -gt 0 ]; then printf 'ok: %s\n' "''${ok[@]}"; fi
    if [ "''${#fails[@]}" -gt 0 ]; then
      printf '%s\n' "''${fails[@]}" >&2
      exit 1
    fi
    touch $out
  ''
