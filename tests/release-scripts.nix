{ pkgs, ... }:
# The release guard and the weekly release-candidate body (#1199).
#
#   release-guard.sh       a tag behind main passes only when it is the newest
#                          green nightly; an empty lookup keeps the old rule.
#   release-candidate.sh   proposes the next packaging tag, says nothing when
#                          release is current, and leads with a warning when a
#                          hotfix was not merged back.
#
# The scripts are the real files, against a small fixture repository:
# main A-B-C-D, release at A, plus a hotfix commit H off A.
pkgs.runCommand "nixarchy-release-scripts"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      git
      gnugrep
      gnused
    ];
    scripts = ../.github/scripts;
  }
  ''
    export HOME=$PWD
    git config --global user.name test
    git config --global user.email test@example.invalid
    git config --global init.defaultBranch main

    git init -q --bare origin.git
    git clone -q origin.git work 2>/dev/null
    cd work
    git commit -q --allow-empty -m root
    root=$(git rev-parse HEAD)
    for c in A B C D; do git commit -q --allow-empty -m "$c"; done
    A=$(git rev-parse HEAD~3) B=$(git rev-parse HEAD~2)
    C=$(git rev-parse HEAD~1) D=$(git rev-parse HEAD)
    git tag v4.0.3-2 "$root"
    git tag v4.0.4-1 "$A"
    git tag v4.0.4x9 "$A" # not a packaging tag; must not count
    git tag v4.0.4-9 "$root"
    git tag v4.0.4-10 "$root" # numeric, not lexical: 10 beats 9
    git tag v4.0.4-rc1 "$root" # not a packaging number; must not count
    git push -q origin main "$A:refs/heads/release" --tags
    git checkout -q -b hotfix "$A"
    git commit -q --allow-empty -m H
    H=$(git rev-parse HEAD)
    git checkout -q main
    git fetch -q origin

    guard() { # name expected-exit tagged nightly
      set +e
      log=$(NIGHTLY_SHA=$4 bash "$scripts/release-guard.sh" vX "$3" "$D" 2>&1)
      rc=$?
      set -e
      if [ "$rc" != "$2" ]; then
        echo "guard $1: exit $rc, wanted $2" >&2
        echo "$log" >&2
        exit 1
      fi
      echo "guard $1: ok"
    }
    guard tip 0 "$D" ""
    guard nightly-behind 0 "$C" "$C"
    guard other-behind 1 "$B" "$C"
    guard empty-lookup 1 "$B" ""
    guard hotfix 0 "$H" "$C"
    warned=$(NIGHTLY_SHA=$C bash "$scripts/release-guard.sh" vX "$C" "$D")
    grep -q '::warning::' <<<"$warned"

    rc() { bash "$scripts/release-candidate.sh" "$@"; }
    body=$(rc "$C" 4.0.4)
    grep -qF 'Proposed tag: `v4.0.4-11`, 2 commits' <<<"$body"
    if grep -q 'not an ancestor' <<<"$body"; then exit 1; fi
    grep -qF "git tag -a v4.0.4-11 $C -m v4.0.4-11" <<<"$body"
    echo "candidate next-tag: ok"

    [ -z "$(rc "$A" 4.0.4)" ]
    echo "candidate release-current: ok"

    grep -qF 'Proposed tag: `v4.0.5-1`' <<<"$(rc "$C" 4.0.5)"
    echo "candidate new-version: ok"

    git push -q origin "$H:refs/heads/release"
    git fetch -q origin
    body=$(rc "$C" 4.0.4)
    [[ ''${body%%$'\n'*} == '**`release` is not an ancestor'* ]]
    echo "candidate missing-merge-back: ok"

    touch $out
  ''
