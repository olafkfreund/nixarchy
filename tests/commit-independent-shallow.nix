{ pkgs, ... }:
# #1719: commit-independent.sh measures check outPaths across a probe commit, so
# it needs the full history. A hosted checkout is depth 1 and Determinate Nix
# refuses it, so the script refuses a shallow tree first, with its own message.
# `nix` is a stub that writes a marker and exits 1: a refusal never reaches it,
# a full clone does. The marker, RUNNER_TEMP and the worktree sit outside every
# tested repository, so "dirty tree" (also exit 2) cannot answer for "shallow".
pkgs.runCommand "nixarchy-commit-independent-shallow"
  {
    nativeBuildInputs = with pkgs; [
      bash
      git
      coreutils
      gnugrep
    ];
  }
  ''
    root=$PWD
    export HOME=$root/home
    mkdir -p "$HOME" bin
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@invalid
    export GIT_CONFIG_GLOBAL=/dev/null
    export root_marker=$root/marker
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo called >> "$root_marker"' 'exit 1' > bin/nix
    chmod +x bin/nix
    export PATH="$root/bin:$PATH"

    fail() { echo "FAIL: $*" >&2; exit 1; }

    git init -q src
    git -C src commit -q --allow-empty -m one
    git -C src commit -q --allow-empty -m two
    git clone -q --depth 1 file://$root/src shallow
    git clone -q file://$root/src full
    git -C shallow worktree add -q --detach $root/wt

    # run <case> <dir>: output lands in err-<case>.txt, the status in rc-<case>.
    run() {
      mkdir -p "$root/tmp-$1"
      rm -f "$root_marker"
      set +e
      (cd "$2" && RUNNER_TEMP=$root/tmp-$1 bash ${../.github/scripts/commit-independent.sh}) > "$root/err-$1.txt" 2>&1
      echo $? > "$root/rc-$1"
      set -e
    }
    refused() { # <case>: exit 2, the message, nothing reached nix
      [ "$(cat rc-$1)" = 2 ] || { cat err-$1.txt >&2; fail "$1: expected exit 2, got $(cat rc-$1)"; }
      grep -qF 'commit-independent: shallow clone; fetch full history' err-$1.txt || { cat err-$1.txt >&2; fail "$1: no shallow-clone message"; }
      [ ! -e "$root_marker" ] || fail "$1: nix was called after the refusal"
    }

    run shallow $root/shallow
    refused shallow

    run worktree $root/wt
    refused worktree

    run full $root/full
    [ "$(cat rc-full)" = 1 ] || { cat err-full.txt >&2; fail "full: expected exit 1, got $(cat rc-full)"; }
    [ -e "$root_marker" ] || { cat err-full.txt >&2; fail "full: the script never reached nix"; }
    if grep -qF 'shallow clone' err-full.txt; then cat err-full.txt >&2; fail "full: refused a full clone"; fi

    echo "commit-independent-shallow: a depth-1 clone and its worktree are refused; a full clone reaches nix"
    touch $out
  ''
