{ pkgs, ... }:
# A font row run with no terminal reopens itself in one, and only when the
# font is missing (#1304).
#
# The row's action is `omarchy-install-font ...` with nothing attached to its
# stdout, so the missing-font route (omarchy-pkg-add's declarative message)
# printed to nowhere. The fix reopens the command in a floating terminal. The
# installed branch must stay out of it: it is silent and switches the font, and
# session.nix drives it with a piped stdout. The two runs differ in the one
# thing that matters -- whether fontconfig lists the family.
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-install-font-terminal"
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
    calls=$TMPDIR/calls

    stubs=$TMPDIR/stubs
    mkdir -p "$stubs"
    for n in omarchy-launch-floating-terminal-with-presentation omarchy-font-set omarchy-pkg-add; do
      printf '#!%s\necho "%s $*" >> "%s"\nexit 0\n' "$shell" "$n" "$calls" > "$stubs/$n"
    done
    # fc-list answers from a file, so each run decides what fontconfig knows.
    printf '#!%s\ncat "%s/fonts"\n' "$shell" "$TMPDIR" > "$stubs/fc-list"
    chmod +x "$stubs"/*
    export PATH=$stubs:$bin:$PATH

    fails=()

    # Run 1: fontconfig lists nothing.
    : > "$TMPDIR/fonts"; : > "$calls"
    bash "$bin/omarchy-install-font" Iosevka ttf-iosevka-nerd 'Iosevka Nerd Font Mono' > "$TMPDIR/out1" 2>&1 || true
    if ! grep -qF 'omarchy-launch-floating-terminal-with-presentation omarchy-install-font Iosevka' "$calls"; then
      fails+=("the not-installed path wrote to a non-terminal stdout and launched no terminal")
    fi
    if grep -q '^omarchy-pkg-add' "$calls"; then
      fails+=("the not-installed path ran omarchy-pkg-add itself instead of in the terminal")
    fi

    # Run 2: fontconfig lists the family.
    printf 'Iosevka Nerd Font Mono\n' > "$TMPDIR/fonts"; : > "$calls"
    bash "$bin/omarchy-install-font" Iosevka ttf-iosevka-nerd 'Iosevka Nerd Font Mono' > "$TMPDIR/out2" 2>&1 || true
    if ! grep -qF 'omarchy-font-set Iosevka Nerd Font Mono' "$calls"; then
      fails+=("the installed path did not switch the font")
    fi
    if grep -q '^omarchy-launch-floating-terminal-with-presentation' "$calls"; then
      fails+=("the installed path opened a terminal")
    fi

    [ ! -e "$real_home" ] || fails+=("wrote outside the fixture: $real_home")

    if [ "''${#fails[@]}" -gt 0 ]; then
      printf '%s\n' "''${fails[@]}" >&2
      exit 1
    fi
    echo "run 1 (font missing): reopened in a floating terminal, pkg-add not run"
    echo "run 2 (font present): switched the font, opened no terminal"
    touch $out
  ''
