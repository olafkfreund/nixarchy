{ pkgs, script }:
# #1342: the login hook seeds hyprland-mimeapps.list only into nothing. A file
# stays, and so does a DANGLING symlink: `-e` alone is false for it, and GNU cp
# refuses to write through it, so without `-L` the seed would fail at every
# login. The control is the script with the `-L` test removed.
pkgs.runCommand "nixarchy-seed-hyprland-mimeapps"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    root=$PWD
    printf '%s\n' 'seeded' > src
    mkdir -p d

    bash ${script} src d/absent/list || { echo "the seed failed into nothing" >&2; exit 1; }
    cmp src d/absent/list || { echo "the list was not copied" >&2; exit 1; }

    printf '%s\n' 'mine' > d/file
    bash ${script} src d/file || { echo "the seed failed over a file" >&2; exit 1; }
    [ "$(cat d/file)" = mine ] || { echo "the seed overwrote the user's file" >&2; exit 1; }

    ln -s "$root/d/nowhere" d/dangling
    bash ${script} src d/dangling || { echo "the seed failed on a dangling link" >&2; exit 1; }
    [ "$(readlink d/dangling)" = "$root/d/nowhere" ] && [ ! -e d/nowhere ] ||
      { echo "the seed touched a dangling link" >&2; exit 1; }
    echo "  ok      absent is seeded; a file and a dangling link are left alone"

    # control: without -L the dangling link is not "present"
    sed 's/ || \[ -L "\$dest" \]//' ${script} > nolink.sh
    if grep -qF -- '-L' nolink.sh; then echo "the sed did not remove the -L test" >&2; exit 1; fi
    if bash nolink.sh src d/dangling 2>/dev/null; then
      echo "the control passed on a dangling link, so this check cannot see the -L test" >&2; exit 1
    fi
    echo "  ok      without -L the seed fails on a dangling link"
    touch $out
  ''
