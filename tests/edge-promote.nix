{ pkgs, ... }:
# edge-promote.sh is the only thing that moves the branch users' flakes follow,
# so what it REFUSES matters more than what it does (#1278). Each refusal case
# also asserts edge did not move: a refusal that went through anyway would pass
# on exit status alone.
pkgs.runCommand "edge-promote"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.coreutils
    ];
  }
  ''
    export HOME=$PWD/home
    mkdir -p "$HOME"
    git config --global user.name test
    git config --global user.email test@example.invalid
    git config --global init.defaultBranch main
    script=${../.github/scripts/edge-promote.sh}
    fails=0

    git init -q --bare remote.git
    git init -q work
    cd work
    commit() { git commit -q --allow-empty -m "$1"; git rev-parse HEAD; }

    base=$(commit base)
    next=$(commit next)
    # A sibling of $next: shares $base, does not descend from $next.
    git checkout -q -b other "$base"
    diverged=$(commit diverged)
    git checkout -q main

    edge() { git ls-remote ../remote.git refs/heads/edge | cut -f1; }
    # name, expect (ok | a phrase the refusal must contain), edge afterwards, then the
    # script's arguments. The phrase matters: git itself rejects a non-fast-forward
    # push, so exit status alone cannot tell our check from git's.
    run() {
      local name=$1 expect=$2 after=$3 rc=0 err got
      shift 3
      err=$(bash "$script" "$@" 2>&1) || rc=$?
      got=$(edge)
      if { [ "$expect" = ok ] && [ "$rc" -ne 0 ]; } || { [ "$expect" != ok ] && { [ "$rc" -eq 0 ] || [[ "$err" != *"$expect"* ]]; }; }; then
        echo "  FAILED  $name (exit $rc, wanted $expect): $err"
        fails=$((fails + 1))
      elif [ "$got" != "$after" ]; then
        echo "  FAILED  $name (edge is '$got', wanted '$after'): $err"
        fails=$((fails + 1))
      else
        echo "  ok      $name"
      fi
    }

    r=$PWD/../remote.git
    run "first publish with none creates edge" ok "$base" "$r" "$base" none
    run "a fast-forward advances edge" ok "$next" "$r" "$next" "$base"
    run "a diverged candidate is refused, edge unchanged" "not a fast-forward" "$next" "$r" "$diverged" "$next"
    run "a stale expected head is refused, edge unchanged" "stale" "$next" "$r" "$next" "$base"

    echo
    if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
    echo "edge-promote: all assertions hold"
    touch $out
  ''
