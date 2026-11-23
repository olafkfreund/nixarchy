{ pkgs, ... }:
# The packaged nixarchy-greeter-publish against a temporary tree (#1927). The
# owner-mismatch case fakes a foreign uid; greeter-theme covers a real one.
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
    [ "$(cat $g/out/current/request)" = 1 ] || fail request

    # bad hex and non-string: key left out, others kept
    reset; printf 'background = "red;"\nforeground = 5\naccent = "#ffff00"\n' > $g/inbox/colors.toml
    $pub
    conf | grep -q background && fail bad-hex
    conf | grep -q foreground && fail non-string
    conf | grep -qx 'accent="#ffff00"' || fail accent-kept

    # missing files: published, empty
    reset; $pub
    [ -n "$(cur)" ] || fail missing-published
    [ -r $g/out/current/theme.conf ] || fail missing-readable
    conf | grep -qx '\[General\]' || fail missing-general
    conf | grep -q wallpaper && fail missing-wallpaper

    # corrupt image: published without it
    reset; echo "$good" > $g/inbox/colors.toml; echo notanimage > $g/inbox/background
    $pub
    [ -n "$(cur)" ] || fail corrupt-published
    conf | grep -q wallpaper && fail corrupt-wallpaper
    conf | grep -q '^background=' || fail corrupt-colors

    # SVG renamed to background: no PNG magic, published without an image
    reset; echo "$good" > $g/inbox/colors.toml
    echo '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>' > $g/inbox/background
    $pub
    [ -n "$(cur)" ] || fail svg-published
    conf | grep -q wallpaper && fail svg-wallpaper
    [ ! -e $g/out/current/background.png ] || fail svg-png
    conf | grep -q '^background=' || fail svg-colors

    # files owned by another uid: defaults, an empty generation
    reset; echo "$good" > $g/inbox/colors.toml; cp blue.png $g/inbox/background
    NIXARCHY_GREETER_UID=$(( $(id -u) + 1 )) $pub
    [ -n "$(cur)" ] || fail owner-published
    [ "$(conf)" = "[General]" ] || fail "owner-defaults: $(conf)"
    [ ! -s $g/out/current/request ] || fail owner-request
    [ ! -e $g/out/current/background.png ] || fail owner-png

    # unsafe: current stays put, and stderr says why
    reset; echo "$good" > $g/inbox/colors.toml; $pub; echo 'background = "#000000"' > $g/inbox/colors.toml
    ln -s /nonexistent $g/inbox/background  # symlink
    first=$(cur); $pub 2>err; [ "$(cur)" = "$first" ] || fail symlink; grep -q "^nixarchy-greeter-publish:" err || fail symlink-stderr
    rm $g/inbox/background; mkfifo $g/inbox/background
    timeout 100 $pub 2>err; [ "$(cur)" = "$first" ] || fail fifo; grep -q "^nixarchy-greeter-publish:" err || fail fifo-stderr
    rm $g/inbox/background; truncate -s 51M $g/inbox/background
    $pub 2>err; [ "$(cur)" = "$first" ] || fail oversized; grep -q "^nixarchy-greeter-publish:" err || fail oversized-stderr
    rm $g/inbox/background; echo 'not = = toml' > $g/inbox/colors.toml
    $pub 2>err; [ "$(cur)" = "$first" ] || fail toml-error; grep -q "^nixarchy-greeter-publish:" err || fail toml-error-stderr

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
