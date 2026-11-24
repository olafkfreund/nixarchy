{ pkgs, ... }:
# The packaged nixarchy-greeter-sync against a temporary inbox and a fake HOME
# (#1927). The publisher side is tests/greeter-publish.nix.
pkgs.runCommand "greeter-sync-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
  }
  ''
    sync=${pkgs.nixarchy-greeter-sync}/bin/nixarchy-greeter-sync
    export HOME=$PWD/home XDG_RUNTIME_DIR=$PWD/run NIXARCHY_GREETER_DIR=$PWD/g
    state=$HOME/.local/state/omarchy/current
    mkdir -p $state/theme $XDG_RUNTIME_DIR $NIXARCHY_GREETER_DIR/inbox
    inbox=$NIXARCHY_GREETER_DIR/inbox
    fail() { echo "FAIL: $*" >&2; exit 1; }
    ready() { cat $inbox/ready; }

    echo 'background = "#112233"' > $state/theme/colors.toml
    echo png > pic.png
    ln -sfn $PWD/pic.png $state/background

    # valid theme
    $sync
    cmp $inbox/colors.toml $state/theme/colors.toml || fail colors
    cmp $inbox/background pic.png || fail background
    [ -n "$(ready)" ] || fail nonce
    [ -z "$(ls -A $inbox | grep '^\.tmp')" ] || fail leftover-tmp
    [ "$(stat -c %a $inbox/colors.toml)" = 644 ] || fail mode

    # uppercase extension
    mv pic.png PIC.PNG; ln -sfn $PWD/PIC.PNG $state/background
    rm $inbox/background
    $sync
    [ -f $inbox/background ] || fail uppercase

    # video background: image removed
    echo v > clip.mp4; ln -sfn $PWD/clip.mp4 $state/background
    $sync
    [ ! -e $inbox/background ] || fail video

    # missing colors.toml
    rm $state/theme/colors.toml
    $sync
    [ ! -e $inbox/colors.toml ] || fail missing-colors

    # a new nonce each run, and a read-only old ready is replaced
    old=$(ready); chmod 0444 $inbox/ready
    sleep 0.01
    $sync
    [ "$(ready)" != "$old" ] || fail ready-replaced

    # two runs together: run the raw script with a slow fake `install` first on
    # PATH (the packaged one prefixes its own coreutils), which flags any overlap.
    mkdir fake; cat > fake/install <<EOF
    #!${pkgs.runtimeShell}
    if ! mkdir $PWD/busy 2>/dev/null; then touch $PWD/overlap; fi
    sleep 0.3
    rmdir $PWD/busy 2>/dev/null || true
    exec ${pkgs.coreutils}/bin/install "\$@"
    EOF
    chmod +x fake/install
    rawsync() { PATH=$PWD/fake:${pkgs.coreutils}/bin:${pkgs.util-linux}/bin ${pkgs.runtimeShell} ${../pkgs/nixarchy-greeter-sync.sh}; }
    echo 'background = "#aaaaaa"' > $state/theme/colors.toml
    rawsync & p1=$!
    rawsync & p2=$!
    wait $p1 || fail concurrent-exit-1
    wait $p2 || fail concurrent-exit-2
    [ ! -e overlap ] || fail concurrent-overlap
    grep -q aaaaaa $inbox/colors.toml || fail concurrent-result
    [ -z "$(ls -A $inbox | grep '^\.tmp')" ] || fail concurrent-tmp
    echo 'background = "#bbbbbb"' > $state/theme/colors.toml
    $sync
    grep -q bbbbbb $inbox/colors.toml || fail serial-after

    # missing inbox: exit 0, nothing created
    NIXARCHY_GREETER_DIR=$PWD/none $sync || fail missing-inbox-exit
    [ ! -e $PWD/none ] || fail missing-inbox-created

    # read-only inbox: exit 0, nothing written
    mkdir -p ro/inbox; chmod 0555 ro/inbox
    NIXARCHY_GREETER_DIR=$PWD/ro $sync || fail ro-exit
    [ -z "$(ls -A ro/inbox)" ] || fail ro-written
    chmod 0755 ro/inbox

    touch $out
  ''
