{ inputs, pkgs }:
# #1037: nixarchy-apply, omarchy-update and autoUpdate built whatever branch the
# flake checkout was on, which is how an agent's unmerged branch reached a live
# desktop. All three now ask pkgs/branch-guard.nix first. This runs the helper
# through every rule, then runs each REAL caller against a checkout on a
# feature branch: taken from nixosConfigurations.vm without building the
# system (tests/apply-staging.nix has the reason).
#
# What it cannot reach: a checkout owned by another user (the sandbox has one
# uid), and the rebuild panel showing the refused unit. tests/AGENTS.md names
# both.
let
  system = pkgs.stdenv.hostPlatform.system;
  vm = inputs.self.nixosConfigurations.vm;
  apply = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-apply"
    ) vm.config.environment.systemPackages
  );
  guard = inputs.self.packages.${system}.nixarchy-branch-guard;
  omarchy = inputs.self.packages.${system}.omarchy;
  # The generated unit script, with a placeholder flake the check fills in.
  autoUpdate =
    (vm.extendModules {
      modules = [
        {
          programs.nixarchy.autoUpdate = {
            enable = true;
            flake = "@FLAKE@";
          };
        }
      ];
    }).config.systemd.services.nixarchy-auto-update;
  autoUpdateScript = pkgs.writeText "nixarchy-auto-update-script" autoUpdate.script;
  # omarchy's bin/ is unwrapped: its commands reach PATH through the module's
  # systemPackages (passthru.runtimeDeps), so that list is where the helper must
  # be. A value, not a store path, so evaluating it builds nothing.
  guardOnSystemPath = builtins.any (
    p: (p.pname or p.name or "") == "nixarchy-branch-guard"
  ) vm.config.environment.systemPackages;
in
pkgs.runCommand "nixarchy-branch-guard-check"
  {
    nativeBuildInputs = [
      pkgs.git
      guard
    ];
    guardOnSystemPath = if guardOnSystemPath then "yes" else "no";
  }
  ''
    set -uo pipefail
    export HOME=$PWD/home GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    mkdir -p "$HOME"
    fails=0
    ok() { echo "  ok      $1"; }
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }

    # repo <dir> <default-branch>: a clone of a local bare origin, one commit,
    # origin/HEAD set -- the shape of a real config checkout, offline.
    repo() {
      rm -rf "$1" "$1.origin"
      git init -q --bare -b "$2" "$1.origin"
      git clone -q "$1.origin" "$1" 2>/dev/null
      # An empty clone's unborn branch can come out as anything; name it.
      git -C "$1" symbolic-ref HEAD "refs/heads/$2"
      printf '{ }\n' > "$1/flake.nix"
      printf '{}\n' > "$1/flake.lock"
      git -C "$1" add -A
      git -C "$1" commit -qm base
      git -C "$1" push -q origin "$2"
      git -C "$1" remote set-head origin -a >/dev/null
    }
    # expect <want-exit> <name> <dir> [grep-for-in-stderr]
    expect() {
      msg=$(nixarchy-branch-guard "$3" 2>&1) && rc=0 || rc=$?
      if [ "$rc" != "$1" ]; then bad "$2: exit $rc, wanted $1: $msg"; return; fi
      if [ -n "''${4:-}" ] && ! grep -q -- "$4" <<<"$msg"; then
        bad "$2: exit $rc but the message lacks '$4': $msg"; return
      fi
      ok "$2 -> $rc"
    }

    echo "== the rules"
    repo "$PWD/r" main
    expect 0 "on main" "$PWD/r"
    git -C r switch -q -c feature/x
    expect 1 "on a feature branch" "$PWD/r" "refusing to rebuild from 'feature/x'"
    expect 1 "a #attr suffix gets the same answer" "$PWD/r#host" "feature/x"
    ALLOW_BRANCH_DEPLOY=1 expect 0 "feature branch with ALLOW_BRANCH_DEPLOY=1" "$PWD/r"
    git -C r switch -q --detach origin/main
    expect 0 "detached exactly at origin/main" "$PWD/r"
    git -C r commit -q --allow-empty -m ahead
    expect 1 "detached anywhere else" "$PWD/r" "detached HEAD"

    repo "$PWD/m" master
    expect 0 "origin/HEAD -> master, on master" "$PWD/m"
    git -C m switch -q -c main
    expect 1 "origin/HEAD -> master, on main" "$PWD/m" "not master"
    git -C m switch -q master
    git -C m remote set-head origin -d
    expect 1 "origin/HEAD unset on a master repo: main is guessed, and it says so" "$PWD/m" "set-head"

    rm -rf lone; mkdir lone; git -C lone init -q -b topic
    git -C lone commit -q --allow-empty -m x
    expect 0 "no remote at all" "$PWD/lone"
    mkdir -p plain
    expect 0 "not a git checkout" "$PWD/plain"
    expect 0 "a flake reference that is not a directory" "github:owner/repo"

    echo "== nixarchy-apply, the real script"
    applybin=${apply}/bin/nixarchy-apply
    mkdir -p "$HOME/.config/nixarchy"
    printf '%s\n' '{ programs.nixarchy.apps.ghostty.enable = true; }' > "$HOME/.config/nixarchy/apps.nix"
    # An exported FUNCTION, not a file: writeShellApplication puts runtimeInputs
    # first on PATH, and bash resolves functions before PATH (apply-staging).
    nhcalls=$PWD/nh.calls
    nh() { echo "$*" >> "$nhcalls"; return 0; }
    export nhcalls
    export -f nh

    repo "$PWD/a" main
    git -C a switch -q -c agent/unmerged
    : > "$nhcalls"
    msg=$(NIXARCHY_FLAKE=$PWD/a $applybin --yes --no-preview 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ]; then bad "apply on a feature branch exited 0"
    elif ! grep -q "refusing to rebuild from 'agent/unmerged'" <<<"$msg"; then
      bad "apply on a feature branch failed, but not with the refusal: $msg"
    else ok "apply refuses a feature branch"; fi
    [ -z "$(git -C a status --porcelain)" ] && ok "  and leaves the checkout untouched" ||
      bad "apply wrote into a refused checkout: $(git -C a status --porcelain)"
    [ ! -s "$nhcalls" ] && ok "  and never reaches nh" || bad "apply reached nh: $(cat "$nhcalls")"

    # The control: the same checkout on main goes on to write and switch, so the
    # refusal above is the guard and not some other failure.
    git -C a switch -q main
    : > "$nhcalls"
    NIXARCHY_FLAKE=$PWD/a $applybin --yes --no-preview >/dev/null 2>&1 || true
    [ -s "$nhcalls" ] && ok "apply on main still reaches nh (control)" ||
      bad "apply on main did not reach nh either, so the refusal above proves nothing"

    # --detach cannot run here (systemd-run). What must hold is read from the
    # script itself: the parent skips the guard, and the unit gets the override.
    grep -qF '[ -n "$detach" ] || nixarchy-branch-guard "$flake"' "$applybin" &&
      ok "the --detach parent leaves the refusal to the unit" ||
      bad "the guard call in apply is not skipped for the --detach parent"
    grep -qF -- '--setenv=ALLOW_BRANCH_DEPLOY=' "$applybin" &&
      ok "the detached unit is handed ALLOW_BRANCH_DEPLOY" ||
      bad "the detached unit would refuse even with ALLOW_BRANCH_DEPLOY=1"

    echo "== omarchy-update, the shipped script"
    [ "$guardOnSystemPath" = yes ] &&
      ok "the helper is on a machine's PATH, where omarchy-update looks" ||
      bad "nixarchy-branch-guard is not in environment.systemPackages: omarchy-update would not find it"
    repo "$PWD/u" main
    git -C u switch -q -c agent/unmerged
    msg=$(NIXARCHY_FLAKE=$PWD/u bash ${omarchy}/share/omarchy/bin/omarchy-update 2>&1) && rc=0 || rc=$?
    if [ "$rc" != 0 ] && grep -q "refusing to rebuild from 'agent/unmerged'" <<<"$msg"; then
      ok "omarchy-update refuses a feature branch"
    else bad "omarchy-update on a feature branch: exit $rc, $msg"; fi

    echo "== autoUpdate, the generated unit script"
    repo "$PWD/au" main
    git -C au switch -q -c agent/unmerged
    mkdir -p state
    sed -e "s|@FLAKE@|$PWD/au|" -e "s|/var/lib/nixarchy/upgrade-failed|$PWD/state/upgrade-failed|" \
      ${autoUpdateScript} > au.sh
    grep -q "$PWD/au" au.sh || bad "the placeholder flake was not substituted"
    # A stub nix that moves the lock, as tests/options.nix's does: without it
    # `nix flake update` fails for want of nix, and "the lock is untouched"
    # would hold whether or not the guard ran.
    mkdir -p au-stubs
    printf '#!/bin/sh\n[ "$1 $2" = "flake update" ] && echo "#" >> "$5/flake.lock"\nexit 0\n' > au-stubs/nix
    chmod +x au-stubs/nix
    lock=$(sha256sum au/flake.lock)
    msg=$(PATH="$PWD/au-stubs:$PATH" bash au.sh 2>&1) && rc=0 || rc=$?
    if [ "$rc" != 0 ] && grep -q "refusing to rebuild from 'agent/unmerged'" <<<"$msg"; then
      ok "autoUpdate refuses a feature branch"
    else bad "autoUpdate on a feature branch: exit $rc, $msg"; fi
    [ "$(sha256sum au/flake.lock)" = "$lock" ] && ok "  and leaves flake.lock untouched" ||
      bad "autoUpdate moved the lock on a refused branch"
    grep -q "branch nobody chose" state/upgrade-failed 2>/dev/null &&
      ok "  and leaves the doctor a reason" || bad "autoUpdate refused without a note for the doctor"

    [ "$fails" = 0 ] || { echo "$fails failure(s)"; exit 1; }
    touch $out
  ''
