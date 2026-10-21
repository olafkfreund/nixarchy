{ pkgs, omarchy }:
# nixarchy-channel rewrites a file the user owns, so what it REFUSES to do
# matters more than what it does.
#
# Every case here runs offline. `stable` takes an optional release argument
# precisely so it can, and so somebody can follow 25.11 while 26.05 settles --
# a test seam and a real feature being the same thing is the good case.
#
# The fixture is the real installer template with its placeholders filled, not
# a hand-written flake: the whole risk in this command is sed against a shape,
# and a fixture written to match the sed would prove nothing about the file
# users actually have.
let
  template = builtins.readFile ../installer/template/flake.nix;
  filled =
    builtins.replaceStrings
      [ "@nixpkgs_url@" "@nixarchy_url@" ]
      [ "github:NixOS/nixpkgs/nixos-unstable" "github:olafkfreund/nixarchy/release" ]
      template;
in
pkgs.runCommand "nixarchy-channel"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
      pkgs.jq
      pkgs.git
    ];
  }
  ''
    export HOME=$PWD/home
    mkdir -p "$HOME"
    ch=${omarchy}/share/omarchy/bin/nixarchy-channel

    mk() { mkdir -p "$1"; cat > "$1/flake.nix" < ${pkgs.writeText "flake.nix" filled}; }
    fails=0

    # The sandbox has no network, so a real re-lock can only fail. Two stubs:
    # one that re-locks, as it does on a machine, and one that cannot. The
    # first is on PATH throughout; the failing one is put in front where the
    # restore is being asserted.
    mkdir -p lock-ok lock-fail
    printf '#!/bin/sh\nexit 0\n' > lock-ok/nix
    printf '#!/bin/sh\nexit 1\n' > lock-fail/nix
    chmod +x lock-ok/nix lock-fail/nix
    export PATH=$PWD/lock-ok:$PATH

    # The patched upstream command must report a real version or fail, so a
    # missing nixos-version cannot become an empty but successful About line.
    version_channel=${omarchy}/share/omarchy/bin/omarchy-version-channel
    nixos-version() {
      case "''${VERSION_CASE:-good}" in
        fail) return 42 ;;
        empty) return 0 ;;
        good) printf '%s\n' '26.05 (Nixarchy)' ;;
      esac
    }
    export -f nixos-version
    for case_name in fail empty; do
      rc=0
      got=$(VERSION_CASE=$case_name "$version_channel" 2>&1) || rc=$?
      if [ "$rc" -ne 0 ] && [ -z "$got" ]; then
        echo "  ok      version-channel refuses $case_name nixos-version"
      else
        echo "  FAILED  version-channel accepted $case_name nixos-version (exit $rc, output: $got)"
        fails=$((fails + 1))
      fi
    done
    got=$(VERSION_CASE=good "$version_channel" 2>&1)
    if [ "$got" = 26.05 ]; then
      echo '  ok      version-channel prints the version without probing pacman'
    else
      echo "  FAILED  version-channel printed '$got' instead of 26.05"
      fails=$((fails + 1))
    fi

    want() {
      if <<<"$2" grep -q -- "$3"; then echo "  ok      $1"
      else
        echo "  FAILED  $1: no /$3/ in the output"
        printf '%s\n' "$2" | sed 's/^/          | /'
        fails=$((fails + 1))
      fi
    }
    wantnot() {
      if <<<"$2" grep -q -- "$3"; then
        echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
      else echo "  ok      $1"; fi
    }

    mk plain
    r=$(NIXARCHY_FLAKE=$PWD/plain $ch 2>&1 || true)
    want "reports the channel"        "$r" 'follows: unstable'
    want "and says it is the tested one" "$r" 'developed and tested against'
    # THE BUG THIS TEST WAS WRITTEN FOR.
    #
    # The template carries a COMMENTED example of inputs.home-manager.url -- it
    # is the prose telling you to add it by hand. An unanchored grep matches that
    # comment, and the damage is not cosmetic: a switch to stable then rewrites
    # the COMMENT instead of adding a real override, leaving a machine on stable
    # nixpkgs with a master home-manager. That is exactly the pairing this
    # command exists to prevent, arrived at silently and reported as success.
    want "the commented example is not read as a setting" "$r" 'no override here'
    wantnot "and its line number never leaks" "$r" '#   inputs.home-manager'

    # Declining must leave the file byte-identical. A backup is not a substitute
    # for not writing.
    mk decline
    before=$(cksum < decline/flake.nix)
    echo n | NIXARCHY_FLAKE=$PWD/decline $ch stable 25.11 >/dev/null 2>&1 || true
    if [ "$before" = "$(cksum < decline/flake.nix)" ]; then echo "  ok      declining changes nothing"
    else echo "  FAILED  declining rewrote the file"; fails=$((fails + 1)); fi

    # A flake reshaped past recognition is not ours to sed. Printing the edit is
    # the right answer; guessing at it is how a working machine stops booting.
    mk reshaped
    grep -v 'nixpkgs.url' plain/flake.nix > reshaped/flake.nix
    r=$(NIXARCHY_FLAKE=$PWD/reshaped $ch 2>&1 || true)
    want "a reshaped flake is refused"  "$r" 'has been reshaped'

    mk custom
    sed -i 's|nixos-unstable|someone/their-own-branch|' custom/flake.nix
    r=$(NIXARCHY_FLAKE=$PWD/custom $ch stable 25.11 2>&1 || true)
    want "a deliberate choice is kept"  "$r" 'neither channel'
    wantnot "and not overwritten"       "$r" 'Rewrote'

    r=$(NIXARCHY_FLAKE=$PWD/plain $ch unstable 2>&1 || true)
    want "already-on-it is a no-op"     "$r" 'Nothing to do'

    # Arguments that cannot mean anything are refused rather than interpreted.
    r=$(NIXARCHY_FLAKE=$PWD/plain $ch stable banana 2>&1 || true)
    want "a bad release is rejected"    "$r" 'looks like 25.05'
    r=$(NIXARCHY_FLAKE=$PWD/plain $ch unstable 25.11 2>&1 || true)
    want "a release needs stable"       "$r" "only means something with 'stable'"

    # The rewrite itself, offline. Re-locking needs a network and is not part of
    # what this asserts; the file's shape is.
    mk rewrite
    echo y | NIXARCHY_FLAKE=$PWD/rewrite $ch stable 25.11 >/dev/null 2>&1 || true
    f=$(cat rewrite/flake.nix)
    want "nixpkgs moved to the release" "$f" 'github:NixOS/nixpkgs/nixos-25.11'
    # The pairing is the entire point of the command existing.
    want "home-manager moved with it"   "$f" 'home-manager/release-25.11'
    want "beside the follows, as the template's own prose says" \
      "$f" 'inputs.nixpkgs.follows = "nixpkgs";'
    if [ -f rewrite/flake.nix.pre-channel ]; then echo "  ok      the previous file is kept"
    else echo "  FAILED  no .pre-channel backup"; fails=$((fails + 1)); fi

    # The shipped template has one follows. Add another input on BOTH sides
    # so neither a first-match nor a last-match rewrite can pass by accident.
    inject_other() {
      awk -v position="$2" '
        function extra() {
          print "    other = {"
          print "      url = \"github:someone/other\";"
          print "      inputs.nixpkgs.follows = \"nixpkgs\";"
          print "    };"
        }
        position == "before" && /^    nixarchy = [{]$/ { extra() }
        { print }
        position == "after" && /^    nixarchy = [{]$/ { inside = 1 }
        position == "after" && inside && /^    [}];$/ { extra(); inside = 0 }
      ' "$1" > "$1.new"
      mv "$1.new" "$1"
    }
    for position in before after; do
      mk "$position"
      inject_other "$position/flake.nix" "$position"
      other_before=$(sed -n '/^    other = [{]$/,/^    [}];$/p' "$position/flake.nix")
      echo y | NIXARCHY_FLAKE=$PWD/$position $ch stable 25.11 >/dev/null 2>&1 || true
      other_after=$(sed -n '/^    other = [{]$/,/^    [}];$/p' "$position/flake.nix")
      nixarchy_block=$(sed -n '/^    nixarchy = [{]$/,/^    [}];$/p' "$position/flake.nix")
      if [ "$other_before" = "$other_after" ] &&
         <<<"$nixarchy_block" grep -F 'inputs.home-manager.url = "github:nix-community/home-manager/release-25.11";' >/dev/null; then
        echo "  ok      $position: only nixarchy gets the Home Manager override"
      else
        echo "  FAILED  $position: another input changed or nixarchy got no override"
        fails=$((fails + 1))
      fi
    done

    mk missing-follows
    sed -i '/^[[:space:]]*inputs.nixpkgs.follows = /d' missing-follows/flake.nix
    before=$(cksum < missing-follows/flake.nix)
    r=$(echo y | NIXARCHY_FLAKE=$PWD/missing-follows $ch stable 25.11 2>&1 || true)
    if [ "$before" = "$(cksum < missing-follows/flake.nix)" ] &&
       <<<"$r" grep -F 'Cannot find one nixarchy input' >/dev/null; then
      echo "  ok      a reshaped nixarchy input is refused without a write"
    else
      echo "  FAILED  a missing nixarchy follows was rewritten or not diagnosed"
      fails=$((fails + 1))
    fi

    # Back again, and the override must GO -- not be left pointing at a release
    # while nixpkgs follows unstable, which is the same broken pairing mirrored.
    echo y | NIXARCHY_FLAKE=$PWD/rewrite $ch unstable >/dev/null 2>&1 || true
    f=$(cat rewrite/flake.nix)
    want "and back to unstable"         "$f" 'nixos-unstable'
    wantnot "the override is removed"   "$f" 'release-25.11'

    # ---- The Omarchy axis (#1278) -------------------------------------------
    #
    # Two choices that must never touch each other's lines. The walk below
    # visits all six pairings of {unstable, stable} x {stable, edge, dev} in
    # sequence on ONE file, and after every step asserts that the axis it did not
    # move is byte-identical in the lines it owns -- a rewrite that matched a
    # line it should not have owned would otherwise pass every per-axis case.
    fp_np() { grep -E '^[[:space:]]*(nixpkgs\.url|inputs\.home-manager\.url)[[:space:]]*=' "$1/flake.nix" || true; }
    fp_om() { { grep -vE '^[[:space:]]*#' "$1/flake.nix" | grep -E 'olafkfreund/nixarchy|omarchy|flake = false' || true; }; }
    # Fake checkouts: the directories the command looks for, and a HEAD naming
    # a branch, which is where it reads the branch from when git cannot.
    co=$PWD/checkout
    mkdir -p "$co/.git" "$co/bin" "$co/default" "$co/shell"
    echo 'ref: refs/heads/main' > "$co/.git/HEAD"
    co2=$PWD/checkout2
    mkdir -p "$co2/.git" "$co2/bin" "$co2/default" "$co2/shell"
    echo 'ref: refs/heads/main' > "$co2/.git/HEAD"

    mk walk
    cp walk/flake.nix walk-original.nix
    exp_np=unstable
    exp_om=stable
    exp_co=""
    check_state() {
      local label=$1 np om
      np=$(NIXARCHY_FLAKE=$PWD/walk $ch --current 2>&1 || true)
      om=$(NIXARCHY_FLAKE=$PWD/walk $ch omarchy --current 2>&1 || true)
      # Where dev points is part of the state: a rewrite of the wrong url line
      # can leave --current at dev while the checkout is not the one asked for.
      if [ "$exp_om" = dev ] && ! grep -qxF "      url = \"git+file://$exp_co?ref=main\";" walk/flake.nix; then
        np=$np-and-omarchy-not-pointing-at-$exp_co
      fi
      if [ "$np" = "$exp_np" ] && [ "$om" = "$exp_om" ]; then
        echo "  ok      $label: nixpkgs=$np omarchy=$om"
      else
        echo "  FAILED  $label: nixpkgs=$np (wanted $exp_np) omarchy=$om (wanted $exp_om)"
        fails=$((fails + 1))
      fi
    }
    check_state "start"
    # axis, then the command's arguments; the expected state is updated first so
    # that check_state reads what the step was meant to leave behind.
    walk_step() {
      local axis=$1 np_b om_b
      shift
      np_b=$(fp_np walk)
      om_b=$(fp_om walk)
      if [ "$axis" = om ]; then
        echo y | NIXARCHY_FLAKE=$PWD/walk $ch omarchy "$@" >/dev/null 2>&1 || true
        exp_om=$1
        [ "$1" != dev ] || exp_co=$2
        if [ "$(fp_np walk)" = "$np_b" ]; then echo "  ok      omarchy $*: the nixpkgs lines are untouched"
        else echo "  FAILED  omarchy $* changed a nixpkgs line"; fails=$((fails + 1)); fi
      else
        echo y | NIXARCHY_FLAKE=$PWD/walk $ch "$@" >/dev/null 2>&1 || true
        exp_np=$1
        if [ "$(fp_om walk)" = "$om_b" ]; then echo "  ok      $*: the omarchy lines are untouched"
        else echo "  FAILED  $* changed an omarchy line"; fails=$((fails + 1)); fi
      fi
      check_state "after $axis $*"
    }
    walk_step om edge
    walk_step om dev "$co"
    walk_step om dev "$co2"
    walk_step np stable 25.11
    walk_step om edge
    walk_step om stable
    walk_step np unstable

    # Leaving dev removes BOTH lines, not just the url.
    mk leave
    echo y | NIXARCHY_FLAKE=$PWD/leave $ch omarchy dev "$co" >/dev/null 2>&1 || true
    f=$(cat leave/flake.nix)
    want "dev adds the follows inside the nixarchy block" "$f" 'inputs.omarchy.follows = "omarchy";'
    want "and a top-level omarchy that is not a flake"  "$f" 'url = "git+file://'"$co"'?ref=main";'
    echo y | NIXARCHY_FLAKE=$PWD/leave $ch omarchy stable >/dev/null 2>&1 || true
    f=$(cat leave/flake.nix)
    wantnot "leaving dev removes the follows"   "$f" 'inputs.omarchy.follows'
    wantnot "and the omarchy input"             "$f" 'git+file'
    wantnot "and its flake = false"             "$f" 'flake = false'
    # Everything but those lines is back to what the installer wrote.
    if [ "$(cat leave/flake.nix)" = "$(cat walk-original.nix)" ]; then echo "  ok      stable -> dev -> stable is byte-identical to the start"
    else echo "  FAILED  stable -> dev -> stable left a difference"; diff walk-original.nix leave/flake.nix | sed 's/^/          | /'; fails=$((fails + 1)); fi

    # Refusals leave the file alone: a custom nixarchy input, an rc channel, a
    # checkout that is not one, a foreign omarchy input, an unsafe path.
    refuses() {
      local name=$1 dir=$2 want_text=$3 b a r
      shift 3
      b=$(cksum < "$dir/flake.nix")
      r=$(echo y | NIXARCHY_FLAKE=$PWD/$dir $ch "$@" 2>&1 || true)
      a=$(cksum < "$dir/flake.nix")
      if [ "$b" = "$a" ] && [ ! -e "$dir/flake.nix.pre-channel" ] && <<<"$r" grep -qF -- "$want_text"; then
        echo "  ok      $name"
      else
        echo "  FAILED  $name (file changed: $([ "$b" = "$a" ] && echo no || echo YES); wanted /$want_text/)"
        printf '%s\n' "$r" | sed 's/^/          | /'
        fails=$((fails + 1))
      fi
    }
    mk custom-om
    sed -i 's|github:olafkfreund/nixarchy/release|github:someone/their-fork|' custom-om/flake.nix
    r=$(NIXARCHY_FLAKE=$PWD/custom-om $ch omarchy --current 2>&1 || true)
    if [ "$r" = custom ]; then echo "  ok      a nixarchy input of your own reads as custom"
    else echo "  FAILED  custom read as '$r'"; fails=$((fails + 1)); fi
    refuses "a custom nixarchy input is refused, not rewritten" custom-om 'not one of the three channels' omarchy edge
    r=$(NIXARCHY_FLAKE=$PWD/custom-om $ch --current 2>&1 || true)
    if [ "$r" = unstable ]; then echo "  ok      and the nixpkgs axis still reads unstable"
    else echo "  FAILED  nixpkgs axis read '$r' beside a custom nixarchy"; fails=$((fails + 1)); fi

    mk refuse
    refuses "rc is refused"                      refuse 'rc channel is not available' omarchy rc
    mkdir -p nogit/bin nogit/default nogit/shell
    refuses "a dev path with no .git is refused" refuse 'no .git' omarchy dev "$PWD/nogit"
    mkdir -p notomarchy/.git
    refuses "a dev path that is not Omarchy is refused" refuse 'does not look like Omarchy' omarchy dev "$PWD/notomarchy"
    refuses "a dev path that does not exist is refused" refuse 'is not a directory' omarchy dev "$PWD/nowhere"
    mkdir -p "$PWD/un safe/.git" "$PWD/un safe/bin" "$PWD/un safe/default" "$PWD/un safe/shell"
    refuses "a path with a space is refused"     refuse 'Refusing' omarchy dev "$PWD/un safe"
    refuses "a path only means something with dev" refuse 'only means something with' omarchy edge "$co"

    mk foreign
    awk '{ print } /^    nixarchy = [{]$/ { inside = 1 } inside && /^    [}];$/ { print "    omarchy = {"; print "      url = \"github:basecamp/omarchy/v4.0.4\";"; print "      flake = false;"; print "    };"; inside = 0 }' foreign/flake.nix > foreign/new
    mv foreign/new foreign/flake.nix
    refuses "someone else's top-level omarchy input is not overwritten" foreign 'not one of the three channels' omarchy dev "$co"

    # A failed re-lock puts the file back: a flake.nix naming an input the lock
    # does not have cannot evaluate, and nobody asked for that.
    mk relock
    cp relock/flake.nix relock-original.nix
    r=$(echo y | PATH=$PWD/lock-fail:$PATH NIXARCHY_FLAKE=$PWD/relock $ch omarchy edge 2>&1 || true)
    want "a failed re-lock says the file is restored" "$r" 'is restored to what it was'
    want "and says it re-locked nixarchy only"        "$r" 'Re-locking: nixarchy$'
    if cmp -s relock/flake.nix relock-original.nix; then echo "  ok      and the file is the one it was"
    else echo "  FAILED  a failed re-lock left a rewritten file"; diff relock-original.nix relock/flake.nix | sed 's/^/          | /'; fails=$((fails + 1)); fi
    mk relock-dev
    r=$(echo y | PATH=$PWD/lock-fail:$PATH NIXARCHY_FLAKE=$PWD/relock-dev $ch omarchy dev "$co" 2>&1 || true)
    want "dev re-locks omarchy as well"               "$r" 'Re-locking: nixarchy omarchy$'
    if cmp -s relock-dev/flake.nix relock-original.nix; then echo "  ok      and a failed dev re-lock restores too"
    else echo "  FAILED  a failed dev re-lock left a rewritten file"; fails=$((fails + 1)); fi

    # Dev builds what is COMMITTED. Without a ref nix reads the working tree as
    # it is, so an uncommitted edit would be built (and a dirty tree cannot be
    # locked at all); with `?ref=<branch>` the lock is the branch's commit.
    # A real repository, because the point is what git says about it.
    git config --global user.name test
    git config --global user.email test@example.invalid
    git init -q -b main dirty
    mkdir -p dirty/bin dirty/default dirty/shell
    echo one > dirty/bin/a; echo one > dirty/default/a; echo one > dirty/shell/a
    git -C dirty add -A
    git -C dirty commit -q -m first
    echo two >> dirty/bin/a
    echo stray > dirty/untracked
    mk dirty-flake
    r=$(echo y | NIXARCHY_FLAKE=$PWD/dirty-flake $ch omarchy dev "$PWD/dirty" 2>&1 || true)
    f=$(cat dirty-flake/flake.nix)
    want    "a dirty checkout is warned about"          "$r" 'uncommitted changes'
    want    "dev pins the checkout to its branch"       "$f" 'url = "git+file://'"$PWD"'/dirty?ref=main";'
    wantnot "and never as a bare path"                  "$f" 'dirty";'
    r=$(NIXARCHY_FLAKE=$PWD/dirty-flake $ch omarchy 2>&1 || true)
    want    "the report names the checkout"             "$r" "omarchy    $PWD/dirty\$"
    want    "and its branch"                            "$r" 'branch     main'
    cp dirty-flake/flake.nix dirty-first.nix
    echo y | NIXARCHY_FLAKE=$PWD/dirty-flake $ch omarchy stable >/dev/null 2>&1 || true
    echo y | NIXARCHY_FLAKE=$PWD/dirty-flake $ch omarchy dev "$PWD/dirty" >/dev/null 2>&1 || true
    if cmp -s dirty-flake/flake.nix dirty-first.nix; then echo "  ok      leaving and re-entering dev round-trips"
    else echo "  FAILED  dev -> stable -> dev changed the file"; fails=$((fails + 1)); fi
    # Untracked files do not reach a branch's lock, so they are not warned about.
    git -C dirty checkout -q -- bin/a
    mk clean-flake
    r=$(echo y | NIXARCHY_FLAKE=$PWD/clean-flake $ch omarchy dev "$PWD/dirty" 2>&1 || true)
    wantnot "an untracked file alone is not a warning"  "$r" 'uncommitted changes'
    # Another branch is written as it is; a detached HEAD has no branch to pin.
    git -C dirty switch -q -c feature/x
    mk branch-flake
    echo y | NIXARCHY_FLAKE=$PWD/branch-flake $ch omarchy dev "$PWD/dirty" >/dev/null 2>&1 || true
    want    "another branch is written as it is"        "$(cat branch-flake/flake.nix)" 'dirty?ref=feature/x";'
    git -C dirty switch -q --detach
    mk detached-flake
    refuses "a detached HEAD is refused"                detached-flake 'no branch checked out' omarchy dev "$PWD/dirty"
    git -C dirty switch -q -c 'odd+name'
    mk oddbranch-flake
    refuses "a branch name outside the allowlist is refused" oddbranch-flake 'Refusing the branch' omarchy dev "$PWD/dirty"

    # A nested attrset inside the nixarchy block must not end it early. The
    # expected file is built with an awk that keys on the template's own
    # indentation, so it does not share the command's brace counting.
    mk nested
    awk '{ print } /^    nixarchy = [{]$/ { inb = 1 } inb && /^      inputs[.]nixpkgs[.]follows/ { print "      inputs.disko = {"; print "        follows = \"disko\";"; print "      };"; inb = 0 }' nested/flake.nix > nested/new
    mv nested/new nested/flake.nix
    cp nested/flake.nix nested-original.nix
    r=$(NIXARCHY_FLAKE=$PWD/nested $ch omarchy --current 2>&1 || true)
    if [ "$r" = stable ]; then echo "  ok      a nested attrset in the block still reads as stable"
    else echo "  FAILED  nested block read as '$r'"; fails=$((fails + 1)); fi
    awk -v url="git+file://$co?ref=main" '
      /^    nixarchy = [{]$/ { inb = 1 }
      inb && /^      url = / { print "      url = \"github:olafkfreund/nixarchy/edge\";"; print "      inputs.omarchy.follows = \"omarchy\";"; next }
      { print }
      inb && /^    [}];$/ { print "    omarchy = {"; print "      url = \"" url "\";"; print "      flake = false;"; print "    };"; inb = 0 }
    ' nested-original.nix > nested-expected.nix
    echo y | NIXARCHY_FLAKE=$PWD/nested $ch omarchy dev "$co" >/dev/null 2>&1 || true
    if cmp -s nested/flake.nix nested-expected.nix; then echo "  ok      dev puts its input after the whole nixarchy block"
    else echo "  FAILED  dev inside a nested block wrote the wrong file"; diff nested-expected.nix nested/flake.nix | sed 's/^/          | /'; fails=$((fails + 1)); fi
    r=$(NIXARCHY_FLAKE=$PWD/nested $ch omarchy --current 2>&1 || true)
    if [ "$r" = dev ]; then echo "  ok      and reads back as dev"
    else echo "  FAILED  nested dev read as '$r'"; fails=$((fails + 1)); fi
    echo y | NIXARCHY_FLAKE=$PWD/nested $ch omarchy stable >/dev/null 2>&1 || true
    if cmp -s nested/flake.nix nested-original.nix; then echo "  ok      and leaving dev restores the nested file exactly"
    else echo "  FAILED  leaving dev changed the nested file"; diff nested-original.nix nested/flake.nix | sed 's/^/          | /'; fails=$((fails + 1)); fi

    # Declining writes nothing.
    mk decline-om
    b=$(cksum < decline-om/flake.nix)
    echo n | NIXARCHY_FLAKE=$PWD/decline-om $ch omarchy dev "$co" >/dev/null 2>&1 || true
    if [ "$b" = "$(cksum < decline-om/flake.nix)" ] && [ ! -e decline-om/flake.nix.pre-channel ]; then echo "  ok      declining the omarchy switch changes nothing"
    else echo "  FAILED  declining the omarchy switch wrote something"; fails=$((fails + 1)); fi

    # A reshaped flake reports custom on both axes rather than failing.
    r=$(NIXARCHY_FLAKE=$PWD/reshaped $ch --current 2>&1 || true)
    if [ "$r" = custom ]; then echo "  ok      a reshaped flake reads as custom for nixpkgs"
    else echo "  FAILED  reshaped nixpkgs read '$r'"; fails=$((fails + 1)); fi

    # Upstream's own commands hand over to nixarchy-channel (they read pacman,
    # which is not here). They find it on PATH, as they find every other
    # omarchy-* command, and are held to producing the same file.
    bindir=${omarchy}/share/omarchy/bin
    r=$(PATH=$bindir:$PATH NIXARCHY_FLAKE=$PWD/plain "$bindir/omarchy-channel-current" 2>&1 || true)
    if [ "$r" = stable ]; then echo "  ok      omarchy-channel-current prints stable on the fixture"
    else echo "  FAILED  omarchy-channel-current printed '$r', wanted stable"; fails=$((fails + 1)); fi
    mk via-upstream
    mk via-nixarchy
    echo y | PATH=$bindir:$PATH NIXARCHY_FLAKE=$PWD/via-upstream "$bindir/omarchy-channel-set" edge >/dev/null 2>&1 || true
    echo y | NIXARCHY_FLAKE=$PWD/via-nixarchy $ch omarchy edge >/dev/null 2>&1 || true
    if ! cmp -s via-nixarchy/flake.nix walk-original.nix && cmp -s via-upstream/flake.nix via-nixarchy/flake.nix; then
      echo "  ok      omarchy-channel-set edge writes what nixarchy-channel omarchy edge writes"
    else
      echo "  FAILED  omarchy-channel-set edge differs from nixarchy-channel omarchy edge (or neither wrote)"
      diff via-nixarchy/flake.nix via-upstream/flake.nix | sed 's/^/          | /'
      fails=$((fails + 1))
    fi

    # nixarchy-version names the channel of the BUILD, not of the flake's intent:
    # only a build whose version says edge is suffixed, and dev when the flake
    # also names a checkout. The shipped script has a stable version spliced in,
    # so an edge build is made by replacing that one line.
    mk ver-stable
    mk ver-edge
    echo y | NIXARCHY_FLAKE=$PWD/ver-edge $ch omarchy edge >/dev/null 2>&1 || true
    mk ver-dev
    echo y | NIXARCHY_FLAKE=$PWD/ver-dev $ch omarchy dev "$co" >/dev/null 2>&1 || true
    sed "s|^built='.*'|built='edge-20261015-abcdef0'|" "$bindir/nixarchy-version" > version-edge-build
    grep -q "^built='edge-20261015-abcdef0'" version-edge-build || { echo "FAILED  the edge build was not made: no built= line to replace"; exit 1; }
    verline() { # verline <script> <flake dir> -> the Omarchy line
      PATH=$bindir:$PATH NIXARCHY_FLAKE=$PWD/$2 bash "$1" 2>&1 | sed -n 1p  # not head: an early exit is SIGPIPE under pipefail
    }
    # Made, not assumed: on the edge branch the shipped script is an edge build.
    sed "s|^built='.*'|built='4.0.4'|" "$bindir/nixarchy-version" > version-release-build
    r=$(verline version-release-build ver-edge)
    wantnot "a release build is not suffixed, whatever the flake says" "$r" '('
    r=$(verline version-edge-build ver-edge)
    want    "an edge build on the edge channel says (edge)"     "$r" '(edge)'
    r=$(verline version-edge-build ver-dev)
    want    "an edge build on a dev checkout says (dev)"        "$r" '(dev)'
    r=$(verline version-edge-build ver-stable)
    want    "an edge build says (edge) even if the flake says stable" "$r" '(edge)'

    # omarchy-update moves the dev checkout with nixarchy: `-U nixarchy` alone
    # leaves it where the lock last saw it, and the machine rebuilds what it
    # already had. nh and the branch guard are stubs that record or pass; the
    # real nixarchy-channel on PATH decides the channel from the fixture.
    mkdir -p upd-bin
    printf '#!/bin/sh\nexit 0\n' > upd-bin/nixarchy-branch-guard
    printf '#!/bin/sh\necho "$*" >> "$NH_CALLS"\n' > upd-bin/nh
    chmod +x upd-bin/nixarchy-branch-guard upd-bin/nh
    # A lock with the root inputs omarchy-update looks for, not frozen.
    printf '%s\n' '{"nodes":{"root":{"inputs":{"nixarchy":"nixarchy","omarchy":"omarchy"}},"nixarchy":{"original":{"type":"github"}},"omarchy":{}},"root":"root","version":7}' > upd.lock
    updated() { # updated <dir> [flag] -> the arguments nh was called with
      cp upd.lock "$1/flake.lock"
      : > "$PWD/nh.calls"
      echo y | NH_CALLS=$PWD/nh.calls PATH=$PWD/upd-bin:$bindir:$PATH NIXARCHY_FLAKE=$PWD/$1 \
        bash "$bindir/omarchy-update" ''${2:-} >/dev/null 2>&1 || true
      cat "$PWD/nh.calls"
    }
    r=$(updated ver-dev --nixarchy)
    want "dev: --nixarchy also updates the omarchy input"  "$r" '--update-input nixarchy --update-input omarchy'
    r=$(updated ver-dev --system)
    wantnot "dev: --system leaves omarchy alone"           "$r" 'omarchy'
    r=$(updated ver-edge --nixarchy)
    want "edge: --nixarchy still updates nixarchy"         "$r" '--update-input nixarchy'
    wantnot "edge: and does not name omarchy"              "$r" 'omarchy'

    # A floor. Every assertion above fails identically if the command printed
    # nothing at all, which reads as every rule being wrong rather than as the
    # binary being missing.
    [ -x "$ch" ] || { echo "nixarchy-channel is not executable at $ch"; exit 1; }

    echo
    if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
    echo "nixarchy-channel: all assertions hold"
    touch $out
  ''
