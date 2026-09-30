{ pkgs, installScript }:
# read_answers, resolve_answers and the secret-handling lines around them
# (#1079): a `#` in a password is data, no secret reaches argv, the fetched
# copy is removed on a refused read, and https cannot redirect to http. The
# nmcli half is proven against a real radio in checks.wifi-hwsim.
pkgs.runCommand "nixarchy-installer-answers"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.diffutils
    ];
  }
  ''
    sed -n '/^read_answers()/,/^}/p' ${installScript} > ra.sh
    grep -q '^read_answers()' ra.sh || { echo "read_answers is not in install.sh any more" >&2; exit 1; }
    sed -n '/^resolve_answers()/,/^}/p' ${installScript} > rs.sh
    grep -q '^resolve_answers()' rs.sh || { echo "resolve_answers is not in install.sh any more" >&2; exit 1; }

    fails=0
    failed() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    ok() { echo "  ok      $1"; }

    # Each run: one secret, so mkpasswd is called once. argv and stdin to files.
    run() { # run <answers file>
      rm -f argv.log stdin.log got
      (
        . ./ra.sh
        mkpasswd() { printf '%s\n' "$*" >> argv.log; cat > stdin.log; echo HASHED; }
        device="" disk_mode="" encrypt="" luks_passphrase="" hostname="" username=""
        password_hash="" build_store_choice="" recovery_hash="" timezone="" keymap=""
        read_answers "$1"
        printf '%s|%s|%s|%s|%s|%s' "$hostname" "$disk_mode" "$keymap" "$password_hash" "$luks_passphrase" "$recovery_hash" > got
      ) > run.out 2>&1 || { failed "read_answers refused $1"; sed 's/^/            /' run.out; }
    }

    printf '%s\n' '# a comment' '   # an indented comment' 'hostname=box' 'disk_mode=whole   # or free' 'password=p#ss word ' > a1
    printf 'keymap=us\r\n' >> a1
    run a1
    printf '%s' 'box|whole|us|HASHED|p#ss word |' > want1
    if cmp -s want1 got; then ok "comments, CRLF, a trailing comment, and a # inside the password"; else failed "a1 parsed as: $(cat got)"; fi
    printf '%s' 'p#ss word ' > want-pw
    if cmp -s want-pw stdin.log; then ok "mkpasswd got the password on stdin, verbatim"; else failed "mkpasswd stdin was: $(cat stdin.log)"; fi
    if grep -qF 'p#ss' argv.log; then failed "the password is in mkpasswd's argv: $(cat argv.log)"; else ok "the password is not in mkpasswd's argv"; fi

    printf '%s\n' 'recovery_passphrase=r#cover ' > a2
    run a2
    printf '%s' 'r#cover ' > want-rc
    if cmp -s want-rc stdin.log; then ok "the recovery passphrase reaches mkpasswd on stdin, verbatim"; else failed "recovery stdin was: $(cat stdin.log)"; fi
    if grep -qF 'r#cover' argv.log; then failed "the recovery passphrase is in mkpasswd's argv"; fi

    # The P1 guard: the old manual's `password=hunter2   # plaintext` must be
    # refused, not installed with the comment inside the password.
    printf '%s\n' 'password=hunter2   # plaintext' > a3
    if ( . ./ra.sh; mkpasswd() { echo HASHED; }; read_answers a3 ) > a3.out 2>&1; then
      failed "a secret with a trailing comment was accepted (P1 guard)"
    elif grep -q 'trailing comment' a3.out; then
      ok "a secret with a trailing comment is refused"
    else
      failed "a3 refused for the wrong reason: $(cat a3.out)"
    fi

    # A read that refuses the file must not leave the fetched copy behind.
    rm -f fetched-path
    (
      . ./rs.sh
      curl() { while [ "$1" != -o ]; do shift; done; printf '%s\n' 'password=x' > "$2"; }
      answers_file=https://example.invalid/answers
      resolve_answers > /dev/null
      printf '%s\n' "$answers_fetched" > fetched-path
      exit 2
    ) || true
    p=$(cat fetched-path)
    if [ -n "$p" ] && [ ! -e "$p" ]; then ok "the fetched answers file is removed on exit"; else failed "the fetched answers file survives an exit before main removes it: $p"; fi

    # Static, where behaviour needs a radio or a network.
    grep -q -- '--proto =https --proto-redir =https' rs.sh || failed "curl can follow an https answers URL to plain http"
    [ "$(grep -c 'mkpasswd -m sha-512 -s' ${installScript})" = 4 ] || failed "not every mkpasswd reads its secret from stdin"
    if grep -q 'mkpasswd -m sha-512 "' ${installScript}; then failed "a secret is passed to mkpasswd as an argument"; fi
    sed -n '/^connect_wifi()/,/^}/p' ${installScript} > cw.sh
    grep -q 'nmcli --ask device wifi connect "$ssid"' cw.sh || failed "connect_wifi no longer pipes the password to nmcli --ask"
    if grep -q 'password "$pw"' cw.sh; then failed "connect_wifi puts the Wi-Fi password on nmcli's command line"; fi

    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1079)" >&2; exit 1; }
    touch $out
  ''
