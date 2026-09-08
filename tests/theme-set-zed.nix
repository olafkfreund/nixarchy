{ pkgs, omarchy }:
# omarchy-theme-set-zed, driven against real theme palettes.
#
# Zed was the one editor in the Install menu whose colours never followed the
# system theme, and upstream does not fix it here: omarchy ships
# omarchy-theme-set-{vscode,obsidian,claude,foot,tmux,...} and no -zed. Its own
# installer reaches for a third-party AUR package instead --
# `omarchy-pkg-add zed omazed` -- which cannot work on v4 as published: that
# tool defaults to the v3 theme path, installs into a hook named `theme-set`
# where v4 runs `theme-set.d/`, and hardcodes /usr/bin. Packaging it would have
# shipped a command that silently did nothing.
#
# Four of the six assertions below are about NOT doing damage, and they are the
# reason this is a check rather than a screenshot. settings.json is the user's
# file and usually the only one they have hand-edited; a theme switch that
# eats a keymap is worse than a theme switch that does nothing.
#
# A runCommand and not a VM: the script reads a TOML palette and writes two
# files. checks.session boots a desktop and could in principle drive a theme
# change, but it has no Zed installed -- the one shape where this script
# returns immediately.
pkgs.runCommand "nixarchy-theme-set-zed"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.gnugrep
    ];
  }
  ''
    export HOME=$PWD/home
    theme=$HOME/.local/state/omarchy/current/theme
    zed=$HOME/.config/zed
    mkdir -p "$theme" "$PWD/fakebin"

    # `command -v zed` gates the whole script, so the fixture needs one.
    printf '#!/bin/sh\nexit 0\n' > "$PWD/fakebin/zed"
    chmod +x "$PWD/fakebin/zed"
    export PATH=$PWD/fakebin:$PATH

    run=${omarchy}/bin/omarchy-theme-set-zed

    fails=0
    ok()  { echo "  ok      $1"; }
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }

    # A real palette from the pinned omarchy, not a hand-written one: the
    # point is that this works against what the themes actually ship, and a
    # fixture I wrote would only prove it works against my own assumptions.
    install -m644 ${omarchy}/share/omarchy/themes/tokyo-night/colors.toml "$theme/"

    rm -rf "$zed"
    $run || bad "the setter exits non-zero on a normal run"

    if jq -e . "$zed/themes/omarchy.json" >/dev/null 2>&1; then
      ok "it writes a theme Zed can parse"
    else
      bad "it writes a theme Zed can parse"
    fi

    # The palette must reach the output. tokyo-night's background is #1a1b26,
    # and Zed wants 8-digit hex for anything it composites -- a bare #rrggbb
    # in a field Zed blends renders opaque and the selection swallows the text
    # under it.
    got=$(jq -r '.themes[0].style.background' "$zed/themes/omarchy.json")
    if [ "$got" = "#1a1b26ff" ]; then
      ok "the palette reaches the theme, with an alpha channel"
    else
      bad "the palette reaches the theme (background=$got, wanted #1a1b26ff)"
    fi

    # mode = "dark" in colors.toml must become appearance = "dark", or Zed
    # renders a dark palette with light-theme chrome.
    got=$(jq -r '.themes[0].appearance' "$zed/themes/omarchy.json")
    [ "$got" = dark ] && ok "mode becomes appearance" || bad "mode becomes appearance (got $got)"

    # A light theme must say so. catppuccin-latte is the light one upstream
    # ships, and asserting only the dark case would pass on a script that
    # hardcoded it.
    install -m644 ${omarchy}/share/omarchy/themes/catppuccin-latte/colors.toml "$theme/"
    rm -rf "$zed"; $run >/dev/null 2>&1
    got=$(jq -r '.themes[0].appearance' "$zed/themes/omarchy.json")
    [ "$got" = light ] && ok "and a light theme is light" || bad "a light theme is light (got $got)"

    # ---- the four that are about not doing damage ------------------------

    # Selecting the theme must not discard the rest of settings.json. This is
    # the user's file and usually the only one they have edited by hand.
    install -m644 ${omarchy}/share/omarchy/themes/tokyo-night/colors.toml "$theme/"
    rm -rf "$zed"; mkdir -p "$zed"
    printf '{ "buffer_font_size": 16, "vim_mode": true }\n' > "$zed/settings.json"
    $run >/dev/null 2>&1
    if [ "$(jq -r '.buffer_font_size' "$zed/settings.json")" = 16 ] &&
       [ "$(jq -r '.vim_mode' "$zed/settings.json")" = true ] &&
       [ "$(jq -r '.theme' "$zed/settings.json")" = Omarchy ]; then
      ok "it selects the theme and keeps every other setting"
    else
      bad "it selects the theme and keeps every other setting"
    fi

    # Zed's settings.json is JSONC -- comments and trailing commas -- and jq
    # cannot parse it. A file jq cannot read must be left ALONE: replacing it
    # with something jq can produce would silently delete a user's comments and
    # any key jq choked on. This is the assertion that matters most.
    rm -rf "$zed"; mkdir -p "$zed"
    printf '{\n  // my font\n  "buffer_font_size": 16,\n}\n' > "$zed/settings.json"
    before=$(cat "$zed/settings.json")
    $run >/dev/null 2>&1
    if [ "$(cat "$zed/settings.json")" = "$before" ]; then
      ok "a settings.json with comments is left untouched"
    else
      bad "a settings.json with comments is left untouched -- it was rewritten"
    fi

    # And no Zed at all is a silent no-op, not an error: every per-app setter
    # upstream ships runs on every theme change whether or not that app is
    # installed, so failing here would fail the whole theme switch for anyone
    # without Zed.
    rm -rf "$zed"
    if PATH=/nonexistent $run >/dev/null 2>&1 && [ ! -e "$zed" ]; then
      ok "no Zed installed is a silent no-op"
    else
      bad "no Zed installed is a silent no-op"
    fi

    # A theme with no colors.toml is a theme this cannot render, not a failure
    # of the switch.
    rm -f "$theme/colors.toml"; rm -rf "$zed"
    $run >/dev/null 2>&1 && ok "a theme with no palette is skipped" ||
      bad "a theme with no palette is skipped"

    # ---- and that the switch actually reaches it ------------------------
    #
    # The script is useless if nothing calls it. omarchy-theme-set runs a list
    # of per-app setters and upstream's list has no zed in it; pkgs/omarchy
    # patches it in.
    grep -q 'omarchy-theme-set-zed' ${omarchy}/share/omarchy/bin/omarchy-theme-set ||
      { echo "  FAILED  omarchy-theme-set no longer calls the zed setter"; fails=1; }
    echo "  ok      omarchy-theme-set calls it"

    [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
    echo "Zed follows the Omarchy theme"
    touch $out
  ''
