{ pkgs, ... }:
pkgs.runCommand "edge-carry"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.coreutils
    ];
  }
  ''
    export HOME=$PWD/home
    export XDG_CONFIG_HOME=$HOME/.config
    mkdir -p "$HOME"
    git config --global user.name test
    git config --global user.email test@example.invalid
    git config --global init.defaultBranch main
    script=${../.github/scripts/edge-carry.sh}
    fails=0

    commit() {
      git -c user.name="$1" -c user.email="$2" commit -q --allow-empty -m "$3"
      git rev-parse HEAD
    }
    ref() { git fetch -q . "+$2:refs/remotes/origin/$1"; }
    run() {
      local name=$1 expected=$2 actual rc=0
      actual=$(bash "$script") || rc=$?
      if [ "$rc" -ne 0 ] || [ "$actual" != "$expected" ]; then
        echo "  FAILED  $name (exit $rc, got '$actual', wanted '$expected')"
        fails=$((fails + 1))
      else
        echo "  ok      $name"
      fi
    }

    git init -q work
    cd work
    bot='41898282+github-actions[bot]@users.noreply.github.com'
    base=$(commit test test@example.invalid base)
    ref main "$base"
    run 'both refs absent' none
    ref edge-candidate "$base"
    run 'edge absent' none

    cd ..
    git init -q edge-only
    cd edge-only
    edge_only=$(commit test test@example.invalid base)
    ref main "$edge_only"
    ref edge "$edge_only"
    run 'candidate absent' none

    cd ../work
    ref edge "$base"
    run 'candidate equal to edge' none

    bot_commit=$(commit bot "$bot" bot)
    ref edge-candidate "$bot_commit"
    run 'bot commits only' none

    git checkout -q -b main-work "$base"
    main_commit=$(commit human human@example.invalid main)
    ref main "$main_commit"
    git checkout -q main
    GIT_AUTHOR_NAME=bot GIT_AUTHOR_EMAIL="$bot" git merge -q --no-ff -m 'merge main' "$main_commit"
    ref edge-candidate HEAD
    run 'bot candidate with merged human main' none

    git checkout -q -b carry "$base"
    ref main "$base"
    human_carry=$(commit human human@example.invalid carry)
    ref edge-candidate "$human_carry"
    run 'human carry on edge' carry

    git checkout -q -b side1 "$base"
    bot_side1=$(commit bot "$bot" side1)
    git checkout -q -b side2 "$base"
    bot_side2=$(commit bot "$bot" side2)
    git checkout -q side1
    git merge -q --no-ff -m 'human merge' "$bot_side2"
    ref edge-candidate HEAD
    run 'human merge commit' carry

    ref edge-candidate "$human_carry"
    ref edge "$bot_side1"
    run 'human carry with edge moved past it' diverged

    echo
    if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
    echo 'edge-carry: all assertions hold'
    touch "$out"
  ''
