{ pkgs, ... }:
# The nightly bump decision (#1403): follow RCs, never go backwards, refuse a
# bad list. The real script, against a stub `gh` that prints a fixture list.
pkgs.runCommand "nixarchy-omarchy-newest"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
    ];
    script = ../.github/scripts/omarchy-newest.sh;
  }
  ''
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'cat "$LIST"' > gh
    chmod +x gh
    export GH=$PWD/gh

    # name current expected-exit expected-output-or-empty list...
    run() {
      name=$1 cur=$2 want_rc=$3 want=$4
      shift 4
      printf '%s\n' "$@" > list
      [ $# -gt 0 ] || : > list
      set +e
      got=$(LIST=$PWD/list bash "$script" "$cur" 2>err)
      rc=$?
      set -e
      if [ "$rc" != "$want_rc" ]; then
        echo "FAILED  $name: exit $rc, wanted $want_rc" >&2
        echo "$got" >&2
        cat err >&2
        exit 1
      fi
      if [ -n "$want" ] && ! grep -qxF "$want" <<<"$got"; then
        echo "FAILED  $name: wanted line '$want' in:" >&2
        echo "$got" >&2
        exit 1
      fi
      echo "ok  $name"
    }

    run rc1-with-older-release   v4.5.0-rc1 0 changed=false v4.0.6
    run rc1-with-itself          v4.5.0-rc1 0 changed=false v4.5.0-rc1
    run rc1-with-rc2             v4.5.0-rc1 0 latest=v4.5.0-rc2 v4.5.0-rc1 v4.5.0-rc2 v4.0.6
    run rc1-with-final           v4.5.0-rc1 0 changed=true v4.5.0 v4.5.0-rc1
    run old-with-rc1             v4.0.6 0 latest=v4.5.0-rc1 v4.5.0-rc1
    run empty-list               v4.5.0-rc1 1 ""
    run injected-tag-only        v4.5.0-rc1 0 changed=false 'v5$(id)'
    run injected-current         'v5$(id)' 1 "" v4.0.6

    touch $out
  ''
