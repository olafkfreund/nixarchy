{ inputs, pkgs }:
let
  cfg = inputs.self.nixosConfigurations.reference.config.programs.nixarchy;
  installedMise = pkgs.lib.filterAttrs (
    name: row: pkgs.lib.hasPrefix "mise/" name && row.class == "installed"
  ) (import ../data/etc-overlay.nix);
  allow = pkgs.writeText "mise-allow.json" (builtins.toJSON (import ../data/mise-allow.nix));
in
assert pkgs.lib.assertMsg (
  builtins.attrNames installedMise == [ ]
) "mise-free: /etc/mise is installed";
pkgs.runCommand "nixarchy-mise-free"
  {
    nativeBuildInputs = with pkgs; [
      bash
      zsh
      fish
      python3
      coreutils
      gnugrep
    ];
  }
  ''
    export OMARCHY_PATH=${cfg.tree}
    python3 ${../.github/scripts/check-mise-free.py} \
      --allow ${allow} \
      --root "tree=$OMARCHY_PATH" \
      --root "zsh-rc=${../pkgs/omarchy/zsh-rc}" \
      --root "fish-rc=${../pkgs/omarchy/fish-rc}" \
      --root "modules=${../modules}"

    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" \
      "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$TMPDIR/stub"
    chmod 700 "$XDG_RUNTIME_DIR"
    export TERM=dumb
    export MISE_LOG="$TMPDIR/mise.log"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "$MISE_LOG"' > "$TMPDIR/stub/mise"
    chmod +x "$TMPDIR/stub/mise"
    export PATH="$TMPDIR/stub:$PATH"
    mise probe
    test -s "$MISE_LOG"
    : > "$MISE_LOG"

    bash --norc --noprofile -ic \
      'source "$OMARCHY_PATH/default/bash/rc"; source "$OMARCHY_PATH/default/bash/rc"; printf "\n__PATH__%s\n" "$PATH"' \
      > bash.out 2> bash.err
    zsh -f -ic \
      'source "$OMARCHY_PATH/default/zsh/rc"; source "$OMARCHY_PATH/default/zsh/rc"; printf "\n__PATH__%s\n" "$PATH"' \
      > zsh.out 2> zsh.err
    fish --no-config -ic \
      'source "$OMARCHY_PATH/default/fish/rc"; source "$OMARCHY_PATH/default/fish/rc"; printf "\n__PATH__%s\n" (string join : $PATH)' \
      > fish.out 2> fish.err

    test ! -s "$MISE_LOG" || {
      echo 'mise-free: shell rc invoked mise' >&2
      cat "$MISE_LOG" >&2
      exit 1
    }
    for shell in bash zsh fish; do
      path=$(grep '^__PATH__' "$shell.out" | tail -n 1 | cut -c 9-)
      test -n "$path" || { echo "mise-free: $shell did not print PATH" >&2; exit 1; }
      count=$(printf '%s\n' "$path" | tr : '\n' | grep -Fxc "$OMARCHY_PATH/agent-dispatch" || true)
      test "$count" -eq 1 || {
        echo "mise-free: $shell has $count agent-dispatch entries" >&2
        exit 1
      }
    done
    touch "$out"
  ''
