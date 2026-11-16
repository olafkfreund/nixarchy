{ inputs, pkgs }:
let
  testLib = import ./lib.nix { inherit inputs; };
  bin = name: "${testLib.vmPackage "nixarchy-${name}"}/bin/nixarchy-${name}";
  configWith =
    {
      nixarchy ? { },
      useGlobalPkgs ? true,
    }:
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        {
          programs.nixarchy = {
            enable = true;
          }
          // nixarchy;
          home-manager.useGlobalPkgs = useGlobalPkgs;
        }
        {
          users.users.someone = {
            isNormalUser = true;
            home = "/home/someone";
          };
          home-manager.users.someone.home.stateVersion = "25.05";
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;
  unfreeOff = configWith { nixarchy.allowUnfree = false; };
  noScope = configWith { useGlobalPkgs = false; };
  homeAppsTemplate =
    pkgs.writeText "home-apps-template.nix"
      (configWith { }).environment.etc."nixarchy/home-apps-template.nix".text;
  variantBin =
    config: name:
    let
      pname = "nixarchy-${name}";
      package = pkgs.lib.findFirst (
        p: (p.pname or p.name or "") == pname
      ) (throw "${pname} missing from fixture") config.environment.systemPackages;
    in
    "${package}/bin/${pname}";
in
pkgs.runCommand "nixarchy-home-selection"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      getent
      gnugrep
      gnused
      nix
      util-linux
    ];
  }
  ''
    set +e
    fails=0
    bad() { echo "FAILED $1: $2"; fails=$((fails + 1)); }
    export HOME=$PWD/user XDG_CONFIG_HOME=$PWD/user/.config XDG_STATE_HOME=$PWD/user/.local/state
    export NIX_STATE_DIR=$PWD/nix-state NIX_LOG_DIR=$PWD/nix-state
    mkdir -p "$XDG_CONFIG_HOME/nixarchy" "$XDG_STATE_HOME" "$NIX_STATE_DIR"
    homefile=$XDG_CONFIG_HOME/nixarchy/home.nix
    appsfile=$XDG_CONFIG_HOME/nixarchy/apps.nix
    pkgadd=${bin "pkg-add"}
    pkgremove=${bin "pkg-remove"}
    optremove=${bin "opt-remove"}
    apply=${bin "apply"}
    offadd=${variantBin unfreeOff "pkg-add"}
    noscopeadd=${variantBin noScope "pkg-add"}
    noscoperemove=${variantBin noScope "pkg-remove"}
    noscopeoptremove=${variantBin noScope "opt-remove"}

    reset_files() {
      printf '%s\n' '{ pkgs, pkgsOther, ... }:' '{' '  home.packages = with pkgs; [  #@pkgs-begin' '  ];  #@pkgs-end' '}' > "$homefile"
      printf '%s\n' '{ pkgs, ... }:' '{' '  environment.systemPackages = with pkgs; [  #@pkgs-begin' '  ];  #@pkgs-end' '}' > "$appsfile"
    }
    fresh_flake() {
      rm -rf flake "$XDG_STATE_HOME/nixarchy/applied"
      mkdir -p flake
      printf '%s\n' '{ outputs = _: { }; }' >flake/flake.nix
    }
    owned_flake() {
      fresh_flake
      mkdir -p flake/nixarchy
      sed -e "s|@USER@|$1|g" -e 's|@IMPORTS@| ./nixarchy/apps.nix|g' ${homeAppsTemplate} >flake/nixarchy-apps.nix
      printf '%s\n' "$2" >flake/nixarchy/home.nix
    }
    fhash() { find flake -type f | sort | xargs sha256sum | sha256sum; }
    reset_files
    cp "$appsfile" apps.before
    "$pkgadd" --home hello >case1.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF 'hello  #@pkg hello' "$homefile" && cmp -s apps.before "$appsfile" || bad 1 "rc=$rc $(cat case1.out)"

    reset_files
    cp "$homefile" home.before
    "$pkgadd" hello >case2.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF 'hello  #@pkg hello' "$appsfile" && cmp -s home.before "$homefile" || bad 2 "rc=$rc $(cat case2.out)"

    reset_files
    cp "$homefile" home.before; cp "$appsfile" apps.before
    "$pkgadd" --home firefox >case3.out 2>&1
    rc=$?
    [ "$rc" -ne 0 ] && grep -q 'curated' case3.out && cmp -s home.before "$homefile" && cmp -s apps.before "$appsfile" || bad 3 "rc=$rc $(cat case3.out)"

    mkdir -p stub
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo called >> "$SEARCH_CALLS"' >stub/nixarchy-search
    chmod +x stub/nixarchy-search
    export SEARCH_CALLS=$PWD/search.calls
    for args in '--home' '--home no-such-package-1809'; do
      reset_files
      cp "$homefile" home.before; cp "$appsfile" apps.before
      rm -f "$SEARCH_CALLS"
      PATH=$PWD/stub:$PATH script -qec "$pkgadd $args" /dev/null </dev/null >case4.out 2>&1
      rc=$?
      if [ "$args" = --home ]; then expected='usage: nixarchy-pkg-add'; else expected='nixpkgs has no package matching:'; fi
      [ "$rc" -eq 1 ] && grep -qF "$expected" case4.out && [ ! -e "$SEARCH_CALLS" ] && cmp -s home.before "$homefile" && cmp -s apps.before "$appsfile" || bad 4 "$args: rc=$rc $(cat case4.out)"
    done

    reset_files
    cp "$appsfile" apps.before
    "$offadd" --home discord >case5.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF '#@pkg discord' "$homefile" && ! grep -qF '#@unfree-allow' "$homefile" && ! grep -qF '#@unfree-allow' "$appsfile" && cmp -s apps.before "$appsfile" && grep -qF 'allow it in the system configuration' case5.out || bad 5 "rc=$rc $(cat case5.out)"

    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    sed -i '/^}$/i\  a.b = 1;  #@opt a.b' "$homefile"
    cp "$appsfile" apps.before
    "$pkgremove" --home hello >case6pkg.out 2>&1
    pkg_rc=$?
    "$optremove" --home a.b >case6opt.out 2>&1
    opt_rc=$?
    [ "$pkg_rc" -eq 0 ] && [ "$opt_rc" -eq 0 ] && ! grep -qF '#@pkg hello' "$homefile" && ! grep -qF '#@opt a.b' "$homefile" && cmp -s apps.before "$appsfile" || bad 6 "pkg=$pkg_rc opt=$opt_rc $(cat case6pkg.out case6opt.out)"

    reset_files
    cp "$homefile" home.before; cp "$appsfile" apps.before
    for command in "$noscopeadd --home hello" "$noscoperemove --home hello" "$noscopeoptremove --home a.b"; do
      $command >case7.out 2>&1
      rc=$?
      [ "$rc" -eq 1 ] && grep -qF 'home-manager.useGlobalPkgs = true' case7.out && cmp -s home.before "$homefile" && cmp -s apps.before "$appsfile" || bad 7 "$command: rc=$rc $(cat case7.out)"
    done

    nh() { :; }
    nixarchy-branch-guard() { :; }
    export -f nh nixarchy-branch-guard
    fresh_flake
    reset_files
    rm "$homefile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >case8plain.out 2>&1
    rc=$?
    generated=flake/nixarchy-apps.nix
    printf '%s\n' \
      '# Generated by nixarchy-apply. Do not edit -- your files' \
      '# are ~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix and' \
      '# this is regenerated from them on every apply.' \
      '{' '  imports = [ ./nixarchy/apps.nix ];' '}' >plain.expected
    [ "$rc" -eq 0 ] && cmp -s plain.expected "$generated" || bad 8 "without home: rc=$rc $(cat case8plain.out)"
    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >case8home.out 2>&1
    rc=$?
    user=$(id -un)
    sed -e "s|@USER@|$user|g" -e 's|@IMPORTS@| ./nixarchy/apps.nix|g' ${homeAppsTemplate} >home.expected
    [ "$rc" -eq 0 ] && cmp -s "$homefile" flake/nixarchy/home.nix && cmp -s home.expected "$generated" || bad 8 "with home: rc=$rc $(cat case8home.out)"

    cp "$generated" generated.before
    cp flake/nixarchy/home.nix copied.before
    cp flake/nixarchy/apps.nix copied-apps.before
    printf '%s\n' '  # source changed after the last apply' >>"$appsfile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview --expect-sha256 home=$(printf %064d 0) >case9.out 2>&1
    rc=$?
    [ "$rc" -eq 4 ] && grep -qF 'Nothing was copied and nothing was built' case9.out && cmp -s generated.before "$generated" && cmp -s copied.before flake/nixarchy/home.nix && cmp -s copied-apps.before flake/nixarchy/apps.nix || bad 9 "rc=$rc $(cat case9.out)"

    extract() { sed -n "/^$1() {/,/^}/p" "$apply"; }
    : >apply-functions
    for function in valid_user select_home_src snapshot_home classify_home read_owner home_decide account_exists release_allowed replace_file remove_file restore_one write_home_pair; do
      extract "$function" >one-function
      [ -s one-function ] || bad own-7a "$function extraction empty"
      cat one-function >>apply-functions
    done
    source apply-functions
    pinned=$PWD/pinned
    srcdir=$XDG_CONFIG_HOME/nixarchy
    mkdir -p "$pinned"
    printf '%s\n' pinned >"$pinned/home.nix"
    # Both present, with different bytes: only the preference order decides.
    mkdir -p "$srcdir"
    printf '%s\n' live >"$srcdir/home.nix"
    selected=$(select_home_src)
    [ "$selected" = "$pinned/home.nix" ] || bad 10 "pinned selection with a live file present: $selected"
    rm -f "$srcdir/home.nix"
    selected=$(select_home_src)
    [ "$selected" = "$pinned/home.nix" ] || bad 10 "pinned selection: $selected"
    rm "$pinned/home.nix"
    selected=$(select_home_src)
    [ -z "$selected" ] || bad 10 "missing selection: $selected"
    live_count=$(grep -cF '$srcdir/home.nix' "$apply" || true)
    outside_count=$(sed '/^select_home_src() {/,/^}/d; /^snapshot_home() {/,/^}/d' "$apply" | grep -cF '$srcdir/home.nix' || true)
    [ "$live_count" -ge 1 ] && [ "$outside_count" -eq 0 ] || bad 10 'live home source is named outside the selection and snapshot functions'

    # Static, because a PATH stub cannot beat apply's own coreutils: the name check
    # runs only when a user name reaches generated Nix.
    grep -qF 'if [ -n "$render_user" ] && ! valid_user "$render_user"; then' "$apply" || bad 11 'the generated user-name check is not gated on an import'
    for name in alice bob_2; do valid_user "$name" || bad 11 "rejected $name"; done
    for name in Alice 'a b' 'x"y' ""; do valid_user "$name" && bad 11 "accepted [$name]"; done

    dest=$PWD/owner.fixture
    printf '%s\n' 'home-manager.users."alice".imports = [' >"$dest"
    read_owner 2>owner.err
    [ "$?" -eq 0 ] && [ "$owner" = alice ] || bad own-7a 'single owner not parsed'
    printf '%s\n' '    home-manager.users."bob_2".imports = [' >"$dest"
    read_owner 2>owner.err
    [ "$?" -eq 0 ] && [ "$owner" = bob_2 ] || bad own-7a 'indented owner not parsed'
    sed -e 's|@USER@|alice|g' -e 's|@IMPORTS@| ./nixarchy/apps.nix|g' ${homeAppsTemplate} >"$dest"
    read_owner 2>owner.err
    [ "$?" -eq 0 ] && [ "$owner" = alice ] || bad own-7a 'generated owner not parsed exactly once'
    for variant in two duplicate unquoted invalid empty; do
      case "$variant" in
        two) printf '%s\n' 'home-manager.users."alice".imports = [' 'home-manager.users."bob".imports = [' >"$dest" ;;
        duplicate) printf '%s\n' 'home-manager.users."alice".imports = [' 'home-manager.users."alice".imports = [' >"$dest" ;;
        unquoted) printf '%s\n' 'home-manager.users.alice.imports = [' >"$dest" ;;
        invalid) printf '%s\n' 'home-manager.users."-bad".imports = [' >"$dest" ;;
        empty) printf '%s\n' 'home-manager.users."".imports = [' >"$dest" ;;
      esac
      owner=stale
      read_owner 2>owner.err
      [ "$?" -eq 1 ] && [ -z "$owner" ] && grep -qF "$dest names several home owners" owner.err || bad own-7a "$variant was accepted or owner was retained"
    done
    rm "$dest"
    owner=stale
    read_owner 2>owner.err
    [ "$?" -eq 0 ] && [ -z "$owner" ] || bad own-7a 'missing owner file was not unowned'
    printf '%s\n' '{ imports = [ ./nixarchy/apps.nix ]; }' >"$dest"
    owner=stale
    read_owner 2>owner.err
    [ "$?" -eq 0 ] && [ -z "$owner" ] || bad own-7a 'ownerless file was not unowned'

    decision_expected() {
      got=$(home_decide "$1" "$2" "$3")
      rc=$?
      [ "$rc" -eq 0 ] && [ "$got" = "$4" ] || bad own-11 "owner=[$1] caller=$2 state=$3: rc=$rc, got $got, wanted $4"
    }
    decision_expected "" alice edited claim
    decision_expected "" alice seed keep
    decision_expected "" alice absent keep
    decision_expected alice alice seed copy
    decision_expected alice alice edited copy
    decision_expected alice alice absent keep
    decision_expected alice bob absent keep
    decision_expected alice bob seed keep
    decision_expected alice bob edited refuse

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\n" "$*" >> "$GETENT_CALLS"' 'exit "$GETENT_RC"' >stub/getent
    chmod +x stub/getent
    export PATH=$PWD/stub:$PATH GETENT_CALLS=$PWD/getent.calls
    for GETENT_RC in 0 2 127 1; do
      export GETENT_RC
      : >"$GETENT_CALLS"
      release_allowed alice bob 2>release.err
      rc=$?
      case "$GETENT_RC" in
        0) [ "$rc" -eq 1 ] && grep -qF 'home.nix belongs to alice' release.err || bad own-9a 'existing owner was released' ;;
        2) [ "$rc" -eq 0 ] && [ ! -s release.err ] || bad own-9a 'absent owner was refused' ;;
        *) [ "$rc" -eq 1 ] && grep -qF "cannot tell whether alice still has an account (getent exited $GETENT_RC)" release.err || bad own-9a "lookup failure $GETENT_RC was allowed" ;;
      esac
      [ "$(cat "$GETENT_CALLS")" = 'passwd alice' ] || bad own-9a "getent call for $GETENT_RC was not passwd alice"
    done
    : >"$GETENT_CALLS"
    release_allowed alice alice 2>release.err
    [ "$?" -eq 0 ] && [ ! -s "$GETENT_CALLS" ] && [ ! -s release.err ] || bad own-9a 'owner release called getent or was refused'

    base=$PWD/flake
    applied=$XDG_STATE_HOME/nixarchy/applied
    dest=$base/nixarchy-apps.nix
    printf '%s\n' '# seed bytes' >home.template
    printf '%s\n' '# new generated owner' >rendered.dest
    for selection in live pinned; do
      owned_flake alice '# previous owner bytes'
      mkdir -p "$applied"
      printf '%s\n' '# seed bytes' >"$homefile"
      if [ "$selection" = pinned ]; then
        cp home.template "$pinned/home.nix"
      else
        rm -f "$pinned/home.nix"
      fi
      snapshot_home home.template
      snap_rc=$?
      printf '%s\n' '# edited after snapshot' >"$homefile"
      if [ "$selection" = pinned ]; then printf '%s\n' '# pinned edited after snapshot' >"$pinned/home.nix"; fi
      classify_home home.template
      copied=""
      write_home_pair write rendered.dest >pair.out 2>&1
      pair_rc=$?
      [ "$snap_rc" -eq 0 ] && [ "$pair_rc" -eq 0 ] && [ "$home_state" = seed ] && cmp -s home.template flake/nixarchy/home.nix && [ "$copied" = ' home' ] || bad own-12 "$selection snapshot or pair write failed: $(cat pair.out)"
    done
    home_snap=""
    classify_home home.template
    [ "$home_state" = absent ] || bad own-12 'missing snapshot was not absent'
    : >"$pinned/home.snap"
    home_snap=$pinned/home.snap
    classify_home home.template
    [ "$home_state" = edited ] || bad own-12 'zero-byte snapshot was not edited'

    eval "$(declare -f replace_file | sed '1s/replace_file/real_replace_file/')"
    replace_file() {
      replace_calls=$((replace_calls + 1))
      if [ "$replace_calls" -eq 2 ]; then
        [ "$(cat flake/nixarchy/home.nix)" = '# next copy' ] && replace_saw_copy=1
        return 1
      fi
      real_replace_file "$@"
    }
    for previous in yes no; do
      owned_flake alice '# previous owner bytes'
      mkdir -p "$applied"
      cp "$dest" dest.before
      if [ "$previous" = yes ]; then
        cp flake/nixarchy/home.nix copy.before
      else
        rm flake/nixarchy/home.nix
      fi
      record="$applied/$(printf '%s' "$base/nixarchy/home.nix" | sha256sum | cut -c1-16)"
      printf '%s\n' 'old record' >"$record"
      cp "$record" record.before
      printf '%s\n' '# next copy' >"$pinned/home.snap"
      home_snap=$pinned/home.snap
      home_srcmsg=$homefile
      copied=""
      replace_calls=0
      replace_saw_copy=0
      write_home_pair write rendered.dest >pair.out 2>&1
      rc=$?
      [ "$rc" -eq 1 ] && [ "$replace_saw_copy" -eq 1 ] && cmp -s dest.before "$dest" && cmp -s record.before "$record" || bad own-10 "$previous: pair or record was not restored: $(cat pair.out)"
      if [ "$previous" = yes ]; then
        cmp -s copy.before flake/nixarchy/home.nix || bad own-10 'previous copy bytes were not restored'
      else
        [ ! -e flake/nixarchy/home.nix ] || bad own-10 'new copy was left after failed destination write'
      fi
    done
    eval "$(declare -f real_replace_file | sed '1s/real_replace_file/replace_file/')"

    eval "$(declare -f remove_file | sed '1s/remove_file/real_remove_file/')"
    remove_file() {
      cmp -s rendered.dest "$dest" && remove_saw_dest=1
      return 1
    }
    owned_flake alice '# previous owner bytes'
    mkdir -p "$applied"
    cp "$dest" dest.before
    cp flake/nixarchy/home.nix copy.before
    record="$applied/$(printf '%s' "$base/nixarchy/home.nix" | sha256sum | cut -c1-16)"
    sha256sum <flake/nixarchy/home.nix >"$record"
    cp "$record" record.before
    remove_saw_dest=0
    write_home_pair release rendered.dest >pair.out 2>&1
    rc=$?
    [ "$rc" -eq 1 ] && [ "$remove_saw_dest" -eq 1 ] && cmp -s dest.before "$dest" && cmp -s copy.before flake/nixarchy/home.nix && cmp -s record.before "$record" || bad own-14 "release rollback failed: $(cat pair.out)"
    eval "$(declare -f real_remove_file | sed '1s/real_remove_file/remove_file/')"

    for action in write release; do
      owned_flake alice '# previous owner bytes'
      mkdir -p "$applied"
      record="$applied/$(printf '%s' "$base/nixarchy/home.nix" | sha256sum | cut -c1-16)"
      sha256sum <flake/nixarchy/home.nix >"$record"
      printf '%s\n' '# edited in flake' >flake/nixarchy/home.nix
      printf '%s\n' '# next copy' >"$pinned/home.snap"
      home_snap=$pinned/home.snap
      home_srcmsg=$homefile
      copied=""
      write_home_pair "$action" rendered.dest >pair.out 2>&1
      rc=$?
      kept=$(find "$applied" -maxdepth 1 -name 'home.nix.edited-in-flake.*' -print -quit)
      [ "$rc" -eq 0 ] && [ -n "$kept" ] && [ "$(cat "$kept")" = '# edited in flake' ] && grep -qF 'NOTE:' pair.out && grep -qF "$homefile" pair.out || bad own-16a "$action did not retain edited flake bytes: $(cat pair.out)"
      if [ "$action" = write ]; then
        cmp -s "$home_snap" flake/nixarchy/home.nix && [ -f "$record" ] || bad own-16a 'write did not refresh the copy and record'
      else
        [ ! -e flake/nixarchy/home.nix ] && [ ! -e "$record" ] || bad own-16a 'release left the copy or record'
      fi
    done
    for action in write release; do
      owned_flake alice '# previous owner bytes'
      mkdir -p "$applied"
      record="$applied/$(printf '%s' "$base/nixarchy/home.nix" | sha256sum | cut -c1-16)"
      sha256sum <flake/nixarchy/home.nix >"$record"
      printf '%s\n' '# next copy' >"$pinned/home.snap"
      home_snap=$pinned/home.snap
      home_srcmsg=$homefile
      copied=""
      write_home_pair "$action" rendered.dest >pair.out 2>&1
      rc=$?
      kept=$(find "$applied" -maxdepth 1 -name 'home.nix.edited-in-flake.*' -print -quit)
      [ "$rc" -eq 0 ] && [ -z "$kept" ] && ! grep -qF 'NOTE:' pair.out || bad own-16a "$action backed up a matching record: $(cat pair.out)"
    done

    user=$(id -un)
    fresh_flake
    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own1.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF "home-manager.users.\"$user\".imports" "$generated" && cmp -s "$homefile" flake/nixarchy/home.nix || bad own-1 "unowned edited home did not claim: rc=$rc $(cat own1.out)"

    fresh_flake
    reset_files
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own2.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && cmp -s plain.expected "$generated" && ! grep -qF 'home-manager.users' "$generated" && [ ! -e flake/nixarchy/home.nix ] || bad own-2 "unowned seed claimed: rc=$rc $(cat own2.out)"

    owned_flake "$user" '# previous owner bytes'
    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own3edited.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && cmp -s "$homefile" flake/nixarchy/home.nix || bad own-3 "owner edit not copied: rc=$rc $(cat own3edited.out)"
    reset_files
    ! cmp -s "$homefile" flake/nixarchy/home.nix || bad own-3 'pre-seed copy was already seed'
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own3seed.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && cmp -s "$homefile" flake/nixarchy/home.nix || bad own-3 "owner seed not copied: rc=$rc $(cat own3seed.out)"

    owned_flake alice '# previous owner bytes'
    reset_files
    rm "$homefile"
    cp flake/nixarchy/home.nix copy.before
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own4.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF 'home-manager.users."alice".imports' "$generated" && cmp -s copy.before flake/nixarchy/home.nix || bad own-4 "non-owner absent home changed owner: rc=$rc $(cat own4.out)"

    owned_flake alice '# previous owner bytes'
    reset_files
    cp flake/nixarchy/home.nix copy.before
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own5.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF 'home-manager.users."alice".imports' "$generated" && cmp -s copy.before flake/nixarchy/home.nix || bad own-5 "non-owner seed changed owner: rc=$rc $(cat own5.out)"

    owned_flake alice '# previous owner bytes'
    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    printf '%s\n' '# stale apps bytes' >flake/nixarchy/apps.nix
    before=$(fhash)
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own6.out 2>&1
    rc=$?
    [ "$rc" -ne 0 ] && grep -qF alice own6.out && grep -qF -- '--release-home' own6.out && [ "$(fhash)" = "$before" ] || bad own-6 "non-owner edit was copied before refusal: rc=$rc $(cat own6.out)"

    for variant in two duplicate unquoted invalid; do
      owned_flake alice '# previous owner bytes'
      reset_files
      case "$variant" in
        two) printf '%s\n' 'home-manager.users."alice".imports = [' 'home-manager.users."bob".imports = [' >"$generated" ;;
        duplicate) printf '%s\n' 'home-manager.users."alice".imports = [' 'home-manager.users."alice".imports = [' >"$generated" ;;
        unquoted) printf '%s\n' 'home-manager.users.alice.imports = [' >"$generated" ;;
        invalid) printf '%s\n' 'home-manager.users."-bad".imports = [' >"$generated" ;;
      esac
      before=$(fhash)
      NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own7b.out 2>&1
      rc=$?
      [ "$rc" -ne 0 ] && [ "$(fhash)" = "$before" ] || bad own-7b "$variant changed flake or was accepted: rc=$rc $(cat own7b.out)"
    done

    fresh_flake
    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own16b-first.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || bad own-16b "initial owner apply failed: rc=$rc $(cat own16b-first.out)"
    printf '%s\n' '# edited in flake' >flake/nixarchy/home.nix
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >own16b-second.out 2>&1
    rc=$?
    kept=$(find "$applied" -maxdepth 1 -name 'home.nix.edited-in-flake.*' -print -quit)
    [ "$rc" -eq 0 ] && cmp -s "$homefile" flake/nixarchy/home.nix && [ -n "$kept" ] && [ "$(cat "$kept")" = '# edited in flake' ] || bad own-16b "flake edit not retained: rc=$rc $(cat own16b-second.out)"

    [ "$fails" -eq 0 ] || { echo "$fails case(s) failed"; exit 1; }
    touch "$out"
  ''
