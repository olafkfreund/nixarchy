{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-fingerprint-pam"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    bin = "${shipped}/share/omarchy/bin";
    shell = pkgs.runtimeShell;
  }
  ''
    set -euo pipefail
    if [ ! -e "$bin/omarchy-apply-fingerprint-pam" ]; then
      touch "$out"
      exit 0
    fi

    mkdir -p "$TMPDIR/pam" "$TMPDIR/stubs"
    sed "s|^stacks=/etc/pam.d$|stacks=$TMPDIR/pam|" \
      "$bin/omarchy-apply-fingerprint-pam" > "$TMPDIR/check"
    chmod +x "$TMPDIR/check"
    check() {
      local expected=$1 rule=$2 rc=0
      printf '%s\n' "$rule" > "$TMPDIR/pam/sudo"
      cp "$TMPDIR/pam/sudo" "$TMPDIR/pam/polkit-1"
      "$TMPDIR/check" >/dev/null 2>&1 || rc=$?
      [ "$rc" -eq "$expected" ] || { echo "PAM rule '$rule': exit $rc, wanted $expected" >&2; exit 1; }
    }
    check 0 'auth sufficient pam_fprintd.so'
    check 0 'auth [success=1 default=ignore] /nix/store/example/lib/security/pam_fprintd.so'
    check 1 '# auth sufficient pam_fprintd.so'
    check 1 'auth sufficient pam_fprintdXso'
    printf '%s\n' 'auth sufficient pam_unix.so' > "$TMPDIR/pam/polkit-1"
    if "$TMPDIR/check" >/dev/null 2>&1; then
      echo 'missing polkit-1 rule passed' >&2
      exit 1
    fi

    if [ -e "$bin/omarchy-setup-security-fingerprint-enroll" ]; then
      printf '#!%s\nexit 0\n' "$shell" > "$TMPDIR/stubs/omarchy-hw-fingerprint"
      printf '#!%s\ncase "$*" in\n  *GetDefaultDevice*) echo "o \\"/test\\"" ;;\n  *scan-type*) echo "s \\"press\\"" ;;\n  *) echo "s \\"Reader\\"" ;;\nesac\n' "$shell" > "$TMPDIR/stubs/busctl"
      printf '#!%s\necho tester\n' "$shell" > "$TMPDIR/stubs/id"
      printf '#!%s\nprintf "called\\n" >> "$TEST_LOG"\necho "Enroll result: enroll-completed"\n' "$shell" > "$TMPDIR/stubs/fprintd-enroll"
      chmod +x "$TMPDIR/stubs"/*
      sed \
        -e "s|export PATH=/run/wrappers/bin:/run/current-system/sw/bin|export PATH=$TMPDIR/stubs:$PATH|" \
        -e 's/(( EUID == 0 )) || fail not-root/true/' \
        -e 's/watch_cancel <\&0 \&/: # watcher disabled in fixture/' \
        "$bin/omarchy-setup-security-fingerprint-enroll" > "$TMPDIR/enroll"
      chmod +x "$TMPDIR/enroll"
      env -i PKEXEC_UID=1000 TEST_LOG="$TMPDIR/enroll-called" HOME="$TMPDIR" \
        "$TMPDIR/enroll" enroll right-index-finger > "$TMPDIR/events" 2> "$TMPDIR/errors" || true
      grep -qFx 'step enroll' "$TMPDIR/events"
      grep -qFx called "$TMPDIR/enroll-called"
    fi
    touch "$out"
  ''
