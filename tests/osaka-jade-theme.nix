{ pkgs, omarchy }:

pkgs.runCommand "nixarchy-osaka-jade-theme"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    tree=${omarchy}/share/omarchy
    theme=$tree/themes/osaka-jade

    if [ ! -f "$theme/colors.toml" ]; then
      echo "FAIL: Osaka Jade has no colors.toml" >&2
      exit 1
    fi

    denied=$(find "$theme" \( -name '*.lua' -o -name alacritty.toml -o -name foot.ini -o -name ghostty.conf -o -name kitty.conf -o -name vscode.json \) -print -quit)
    if [ -n "$denied" ]; then
      echo "FAIL: Osaka Jade contains denied file $denied" >&2
      exit 1
    fi

    link=$(find "$theme" -type l -print -quit)
    if [ -n "$link" ]; then
      echo "FAIL: Osaka Jade contains symlink $link" >&2
      exit 1
    fi

    mkdir -p "$PWD/empty-home/.config/omarchy/themes"
    HOME="$PWD/empty-home" OMARCHY_PATH="$tree" ${pkgs.bash}/bin/bash "$tree/bin/omarchy-theme-list" > theme-list.txt
    if grep -Fxq 'Osaka Jade' theme-list.txt; then
      :
    else
      echo "FAIL: omarchy-theme-list does not list Osaka Jade" >&2
      exit 1
    fi

    # shellcheck disable=SC2154  # Nix supplies out to the builder.
    touch "$out"
  ''
