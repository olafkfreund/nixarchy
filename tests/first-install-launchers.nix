{ pkgs, ... }:
# omarchy-provision-user --first-install removes the shipped launchers /etc/skel
# seeded. A Home Manager link and an edited copy are the user's and must survive;
# only a copy identical to the shipped file goes (#1907). The link's target is
# byte-identical on purpose: a content test alone would delete it (#1304).
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-first-install-launchers"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
    tree = "${shipped}/share/omarchy";
  }
  ''
    set -euo pipefail
    script=$tree/bin/omarchy-provision-user
    # Any unguarded delete of a launcher, however upstream renames the loop around it.
    if grep -nE 'rm .*\.local/share/applications' "$script"; then
      echo "FAIL: an unguarded launcher delete is left in omarchy-provision-user" >&2
      exit 1
    fi
    # The cleanup block: the `if` that opens the launcher loop, through its `fi`.
    awk '/^if \(\( first_install \)\); then$/ { prev = $0; next }
      prev != "" && /for launcher in/ { print prev; p = 1 }
      { prev = "" }
      p { print; if ($0 == "fi") exit }' "$script" > cleanup.sh
    if [ ! -s cleanup.sh ]; then
      # main's tag and older edge pins ship no first-install cleanup.
      grep -q 'for launcher in' "$script" && { echo "cleanup present but not extracted" >&2; exit 1; }
      echo "skipped: this pin has no first-install launcher cleanup" > $out
      exit 0
    fi
    cat cleanup.sh
    # A stray `fi` match would run the rest of provisioning here, so bound the block.
    [ "$(tail -n1 cleanup.sh)" = fi ] && [ "$(wc -l < cleanup.sh)" -le 8 ] && bash -n cleanup.sh ||
      { echo "FAIL: the extracted cleanup block is not the launcher loop" >&2; exit 1; }

    export HOME=$TMPDIR/home OMARCHY_PATH=$tree
    A=$HOME/.local/share/applications HM=$TMPDIR/hm
    mkdir -p "$A" "$HM"
    names=()
    for f in "$tree"/applications/*.desktop; do names+=("''${f##*/}"); done
    [ "''${#names[@]}" -ge 4 ] || { echo "fewer than four shipped launchers" >&2; exit 1; }
    pristine=''${names[0]} edited=''${names[1]} same=''${names[2]} other=''${names[3]}
    cp "$tree/applications/$pristine" "$A/$pristine"
    { cat "$tree/applications/$edited"; echo "# mine"; } > "$A/$edited"
    cp "$tree/applications/$same" "$HM/$same"
    ln -s "$HM/$same" "$A/$same"
    { cat "$tree/applications/$other"; echo "# mine too"; } > "$HM/$other"
    ln -s "$HM/$other" "$A/$other"

    first_install=1
    . ./cleanup.sh

    fails=()
    [ ! -e "$A/$pristine" ] || fails+=("pristine $pristine was kept")
    [ -f "$A/$edited" ] || fails+=("edited $edited was removed")
    [ -L "$A/$same" ] || fails+=("identical Home Manager link $same was removed")
    [ -L "$A/$other" ] || fails+=("Home Manager link $other was removed")
    if [ "''${#fails[@]}" -gt 0 ]; then printf 'FAIL: %s\n' "''${fails[@]}" >&2; exit 1; fi
    echo ok > $out
  ''
