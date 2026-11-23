{ pkgs, ... }:
# The packaged nixarchy-greeter-publish against a temporary tree (#1927). The
# owner-mismatch case needs a second uid and is covered by greeter-theme.
pkgs.runCommand "greeter-publish-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.imagemagick
      pkgs.python3
    ];
  }
  ''
    pub=${pkgs.nixarchy-greeter-publish}/bin/nixarchy-greeter-publish
    export NIXARCHY_GREETER_DIR=$PWD/g NIXARCHY_GREETER_UID=$(id -u)
    g=$NIXARCHY_GREETER_DIR
    fail() { echo "FAIL: $*" >&2; exit 1; }
    reset() {
      rm -rf $g; mkdir -p $g/inbox $g/out
      echo 1 > $g/inbox/ready
    }
    cur() { readlink $g/out/current || true; }
    conf() { cat $g/out/current/theme.conf; }
    gens() { ls $g/out | grep -c '^gen-' || true; }
    magick -size 64x64 xc:blue blue.png
    magick -size 5000x3000 xc:red -quality 90 big.jpg
    magick -size 8x8 xc:red a.png; magick -size 8x8 xc:green b.png; magick -size 8x8 xc:blue c.png
    magick a.png b.png c.png anim.gif
    good='background = "#ff0000"
    foreground = "#00ff00"
    accent = "#ffff00"
    red = "#ff00ff"'

    # valid input
    reset; echo "$good" > $g/inbox/colors.toml; cp blue.png $g/inbox/background
    $pub
    conf | grep -qx 'background="#ff0000"' || fail bg
    conf | grep -qx 'failed="#ff00ff"' || fail red
    conf | grep -q '^wallpaper="gen-[0-9]*/background.png"' || fail wallpaper
    [ -f $g/out/current/background.png ] || fail png

    # bad hex and non-string: key left out, others kept
    reset; printf 'background = "red;"\nforeground = 5\naccent = "#ffff00"\n' > $g/inbox/colors.toml
    $pub
    conf | grep -q background && fail bad-hex
    conf | grep -q foreground && fail non-string
    conf | grep -qx 'accent="#ffff00"' || fail accent-kept

    # missing files: published, empty
    reset; $pub
    [ -n "$(cur)" ] || fail missing-published
    conf | grep -q wallpaper && fail missing-wallpaper

    # corrupt image: published without it
    reset; echo "$good" > $g/inbox/colors.toml; echo notanimage > $g/inbox/background
    $pub
    [ -n "$(cur)" ] || fail corrupt-published
    conf | grep -q wallpaper && fail corrupt-wallpaper
    conf | grep -q '^background=' || fail corrupt-colors

    # unsafe: current stays put
    reset; echo "$good" > $g/inbox/colors.toml; $pub; echo 'background = "#000000"' > $g/inbox/colors.toml
    ln -s /nonexistent $g/inbox/background  # symlink
    first=$(cur); $pub; [ "$(cur)" = "$first" ] || fail symlink
    rm $g/inbox/background; mkfifo $g/inbox/background
    timeout 100 $pub; [ "$(cur)" = "$first" ] || fail fifo
    rm $g/inbox/background; truncate -s 51M $g/inbox/background
    $pub; [ "$(cur)" = "$first" ] || fail oversized
    rm $g/inbox/background; echo 'not = = toml' > $g/inbox/colors.toml
    $pub; [ "$(cur)" = "$first" ] || fail toml-error

    # JPEG becomes a PNG within 3840x2160; GIF gives one PNG
    reset; cp big.jpg $g/inbox/background; $pub
    [ "$(magick identify -format '%m %w %h' $g/out/current/background.png)" = "PNG 3600 2160" ] || fail jpeg
    reset; cp anim.gif $g/inbox/background; $pub
    [ "$(magick identify $g/out/current/background.png | wc -l)" = 1 ] || fail gif

    # only two generations kept; a leftover .current-new does not block
    reset; ln -s gen-0 $g/out/.current-new
    for _ in 1 2 3 4; do $pub; done
    [ "$(gens)" = 2 ] || fail "generations: $(gens)"

    # a nonce change during the run triggers a catch-up
    reset; cp blue.png $g/inbox/background
    python3 - ${../pkgs/nixarchy-greeter-publish.py} <<'PY' || fail catchup
    import os, runpy, subprocess, sys
    real = subprocess.run
    calls = []
    def run(*a, **k):
        if not calls:
            with open(os.environ["NIXARCHY_GREETER_DIR"] + "/inbox/ready", "w") as f:
                f.write("2\n")
        calls.append(1)
        return real(*a, **k)
    subprocess.run = run
    runpy.run_path(sys.argv[1], run_name="not_main")["publish"](os.getuid())
    assert len(calls) == 2, calls
    PY

    touch $out
  ''
