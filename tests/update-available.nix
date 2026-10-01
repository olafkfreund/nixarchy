{ pkgs, ... }:
# Exercise the bar command with a local lock and a fake remote; no network.
pkgs.runCommand "nixarchy-update-available"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.jq
      pkgs.shellcheck
    ];
  }
  ''
    set -eu
    script=${../pkgs/omarchy/nix-bin/omarchy-update-available}
    shellcheck -s bash "$script"

    mkdir -p fake-bin flake
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      'printf "call\n" >> "$GIT_CALLS"' \
      '[ "$#" -eq 6 ] && [ "$1" = -c ] && [ "$2" = credential.helper= ] && [ "$3" = ls-remote ] && [ "$4" = --heads ] && [ "$5" = --tags ] || exit 99' \
      '[ "$6" = https://github.com/olafkfreund/nixarchy.git ] || exit 97' \
      '[ "$GIT_TERMINAL_PROMPT" = 0 ] || exit 98' \
      '[ "$GIT_CONFIG_GLOBAL" = /dev/null ] && [ "$GIT_CONFIG_NOSYSTEM" = 1 ] || exit 96' \
      '[ "$GIT_ASKPASS" = false ] && [[ -v SSH_ASKPASS && -z $SSH_ASKPASS ]] || exit 95' \
      'cat "$GIT_REFS"' \
      '[ "$GIT_FAIL" != 1 ] || exit 42' \
      '[ "$GIT_SLEEP" != 1 ] || sleep 20' \
      > fake-bin/git
    chmod +x fake-bin/git
    export PATH="$PWD/fake-bin:$PATH"
    export GIT_CALLS=$PWD/calls GIT_REFS=$PWD/refs GIT_FAIL=0 GIT_SLEEP=0

    old=1111111111111111111111111111111111111111
    new=2222222222222222222222222222222222222222
    third=3333333333333333333333333333333333333333
    jq -n --arg rev "$old" '{version: 7, root: "root", nodes: {
      root: {inputs: {nixarchy: "nixarchy"}},
      nixarchy: {
        original: {type: "github", owner: "olafkfreund", repo: "nixarchy", ref: "release"},
        locked: {type: "github", owner: "olafkfreund", repo: "nixarchy", rev: $rev}
      }
    }}' > base.lock
    cp base.lock flake/flake.lock
    printf '%s\t%s\n' \
      "$old" refs/tags/v4.0.3-1 \
      "$new" refs/tags/v4.0.4-1 \
      "$new" refs/heads/release > refs

    check() {
      name=$1 expected=$2 expected_calls=$3
      : > "$GIT_CALLS"
      rc=0
      NIXARCHY_FLAKE=$PWD/flake bash "$script" >output 2>&1 || rc=$?
      calls=$(wc -l < "$GIT_CALLS")
      if [ "$rc" -ne "$expected" ] || [ "$calls" -ne "$expected_calls" ]; then
        echo "FAILED $name: exit $rc (want $expected), Git calls $calls (want $expected_calls)" >&2
        cat output >&2
        exit 1
      fi
      echo "PASS $name: exit $rc, Git calls $calls"
    }

    check 'newer release' 0 1
    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$old" refs/heads/release > refs
    check 'same release' 1 1
    jq '.nodes.root.inputs.nixpkgs = "nixpkgs" | .nodes.nixpkgs = {locked: {rev: "9999999999999999999999999999999999999999"}}' base.lock > flake/flake.lock
    check 'nixpkgs-only update' 1 1
    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$new" refs/tags/v4.0.4-1 "$old" refs/heads/release > refs
    jq --arg rev "$new" '.nodes.nixarchy.locked.rev = $rev' base.lock > flake/flake.lock
    check 'older release tip' 1 1

    cp base.lock flake/flake.lock
    printf '%s\t%s\n' "$old" refs/tags/v4.0.4-9 "$new" refs/tags/v4.0.4-10 "$new" refs/heads/release > refs
    check 'numeric revision order' 0 1
    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$third" refs/tags/v4.0.4-1 "$new" 'refs/tags/v4.0.4-1^{}' "$new" refs/heads/release > refs
    check 'annotated tag peeled commit' 0 1
    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$old" refs/tags/v4.0.4-1 "$new" refs/tags/v4.0.3-2 "$new" refs/heads/release > refs
    check 'highest tag at installed commit' 1 1

    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$new" refs/tags/v4.0.4-1 "$new" refs/heads/release > refs
    jq --arg rev "$third" '.nodes.nixarchy.locked.rev = $rev' base.lock > flake/flake.lock
    check 'untagged installed commit' 1 1
    cp base.lock flake/flake.lock
    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$third" refs/heads/release > refs
    check 'untagged release tip' 1 1
    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 > refs
    check 'missing release branch' 1 1
    : > refs
    check 'empty remote response' 1 1
    printf '%s\n' 'malformed ref line' > refs
    check 'malformed remote response' 1 1

    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$new" refs/tags/v4.0.4-1 "$new" refs/heads/release > refs
    GIT_FAIL=1
    check 'Git failure after valid refs' 1 1
    GIT_FAIL=0 GIT_SLEEP=1
    check 'bounded Git timeout after valid refs' 1 1
    GIT_SLEEP=0

    printf '%s\t%s\n' "$old" refs/tags/v4.0.3-1 "$new" refs/tags/v4.0.4-1 "$new" refs/heads/release > refs
    chmod 000 flake/flake.lock
    check 'unreadable lock' 1 0
    chmod 644 flake/flake.lock
    printf '%s\n' '{broken' > flake/flake.lock
    check 'malformed lock' 1 0
    jq 'del(.nodes.root.inputs.nixarchy)' base.lock > flake/flake.lock
    check 'missing nixarchy input' 1 0
    jq '.nodes.root.inputs.nixarchy = "renamed" | .nodes.renamed = .nodes.nixarchy | del(.nodes.nixarchy)' base.lock > flake/flake.lock
    check 'renamed lock node' 0 1

    jq '.nodes.nixarchy.original.ref = "v4.0.3-1"' base.lock > flake/flake.lock
    check 'fixed tag pin' 1 0
    jq 'del(.nodes.nixarchy.original.ref) | .nodes.nixarchy.original.rev = "1111111111111111111111111111111111111111"' base.lock > flake/flake.lock
    check 'fixed revision pin' 1 0
    jq '.nodes.nixarchy.original.ref = "main"' base.lock > flake/flake.lock
    check 'other branch pin' 1 0
    jq '.nodes.nixarchy.original = {type: "path", path: "/home/alice/nixarchy"}' base.lock > flake/flake.lock
    check 'local path pin' 1 0
    jq '.nodes.nixarchy.original.owner = "someone-else"' base.lock > flake/flake.lock
    check 'other repository' 1 0
    jq '.nodes.nixarchy.locked.rev = "short"' base.lock > flake/flake.lock
    check 'invalid installed SHA' 1 0

    touch "$out"
  ''
