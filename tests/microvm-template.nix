# Builds a runner and reads it. Boots nothing.
#
# What a runner *is* -- which hypervisor, whether the store is shared or
# imaged, whether the network needs root -- is written into the package and
# the qemu command line, and those decide whether `nixarchy vm run` works as
# the desktop user with no rebuild and nothing that needs `/dev/kvm`. #221's
# whole argument rests on properties that never boot a kernel to see: this
# check reads them off the built derivation instead.
#
# Two things are read here. `templates` is every entry of
# data/microvm-templates.nix, built both ways (KVM and -tcg) by
# `lib.mkMicrovm` -- the runner itself. `nixarchyVm` is the CLI built over it
# (pkgs/microvm.nix) -- the two behaviours #221 calls load-bearing,
# `nix build --out-link` and the per-name flock, neither of which the runner
# package alone can prove.
{
  pkgs,
  lib,
  templates,
  nixarchyVm,
}:
let
  # One template is enough to prove the runner's shape -- data/microvm-templates.nix
  # carries only `shell` until #225. Every template gets asserted, so a new
  # one is covered for free.
  names = builtins.attrNames templates;

  # #225: "checks.microvm-template should cover at least one template with a
  # volume, since autoCreate and the relative path are exactly what a rename
  # would break silently." The image basename each volume-carrying template
  # writes into `microvm.volumes` -- lib/runners/qemu.nix (the pinned commit,
  # read above) puts this string into `-drive ...,file=${image},...`
  # VERBATIM, with no path resolution of its own, so a template that grew an
  # absolute path here would only fail at boot, on real hardware, never here.
  volumeImages = {
    podman = "var-lib-containers.img";
    persistent = "home.img";
    k3s = "var-lib-rancher.img";
  };

  # The CLI as a machine built from a DIRTY checkout evaluates it: no
  # `self.rev`, only `self.dirtyRev` -- the underlying commit with "-dirty"
  # appended, which is not a ref GitHub can resolve. `nixarchyVm` above is
  # built from whatever state CI's own checkout happens to be in, so the
  # dirty case has to be pinned here or it is only ever tested by accident --
  # and it shipped broken exactly that way: `run` handed
  # `github:olafkfreund/nixarchy/<rev>-dirty` to `nix build`, which 404s with
  # nothing to say why.
  dirtyRev = "0000000000000000000000000000000000000000";
  dirtyVm = pkgs.callPackage ../pkgs/microvm.nix {
    self = {
      dirtyRev = "${dirtyRev}-dirty";
    };
  };
in
pkgs.runCommand "nixarchy-microvm-template"
  {
    nativeBuildInputs = with pkgs; [
      gnugrep
      coreutils
      util-linux # flock, for the CLI half below
      bash
      jq # reads the guest's users-groups.json, for the uid cross-check below
      python3Minimal # binds a unix socket for the console case (#762)
      procps # pkill, to end a detached stub runner and its children
    ];
  }
  ''
    fail=0

    ${lib.concatMapStrings (name: ''
      echo "== template: ${name} =="
      kvm=${templates.${name}.kvm}
      tcg=${templates.${name}.tcg}
      run=$kvm/bin/microvm-run

      # bin/microvm-run and bin/microvm-shutdown exist. Breaking this looks
      # like pointing the package at the toplevel instead of declaredRunner.
      for bin in microvm-run microvm-shutdown; do
        for variant in "$kvm" "$tcg"; do
          if [ ! -x "$variant/bin/$bin" ]; then
            echo "${name}: $variant/bin/$bin is missing or not executable" >&2
            fail=1
          fi
        done
      done

      # share/microvm/hypervisor is qemu. Breaking this looks like setting
      # hypervisor = "cloud-hypervisor", which cannot do user networking.
      for variant in "$kvm" "$tcg"; do
        hv=$(cat "$variant/share/microvm/hypervisor" 2>/dev/null || echo "MISSING")
        if [ "$hv" != qemu ]; then
          echo "${name}: $variant/share/microvm/hypervisor is '$hv', not qemu" >&2
          fail=1
        fi
      done

      # No store disk on the command line, and mount_tag=ro-store IS present.
      # Breaking this looks like removing the /nix/store share -- an erofs
      # build would appear in the closure, which is the cost this catches.
      if grep -oE -- "-drive '[^']*'" "$run" | grep -q store; then
        echo "${name}: bin/microvm-run has a -drive mentioning a store image -- an image was built for it" >&2
        fail=1
      fi
      if ! grep -q 'mount_tag=ro-store' "$run"; then
        echo "${name}: bin/microvm-run has no ro-store 9p share -- the host store is not shared" >&2
        fail=1
      fi

      # -netdev user, is present (SLiRP -- no root needed), and nothing here
      # asks for a tap interface, which does.
      if ! grep -q -- "-netdev 'user," "$run"; then
        echo "${name}: bin/microvm-run has no SLiRP user networking" >&2
        fail=1
      fi
      if [ -s "$kvm/share/microvm/tap-interfaces" ]; then
        echo "${name}: share/microvm/tap-interfaces is non-empty -- this needs root to run" >&2
        fail=1
      fi

      ${lib.optionalString (volumeImages ? ${name}) ''
        # A volume's `file=` is the RELATIVE image path this template
        # declared, not an absolute one. Breaking this looks like a template
        # writing `microvm.volumes[].image` as
        # "/var/lib/nixarchy/${volumeImages.${name}}" instead of a bare
        # filename -- the whole promise of one closure serving every VM of
        # this template, each with its own disk in its own directory
        # (data/microvm-templates.nix's rule), depends on this staying
        # relative.
        if ! grep -qE -- "file=${volumeImages.${name}}(,|')" "$run"; then
          echo "${name}: bin/microvm-run has no -drive for ${volumeImages.${name}}" >&2
          fail=1
        fi
        if grep -qE -- "file=/[^,']*${volumeImages.${name}}" "$run"; then
          echo "${name}: ${volumeImages.${name}} is on the drive line with an absolute path" >&2
          fail=1
        fi
      ''}

      # The KVM and -tcg runners share one share/microvm/system: the guest
      # closure the -cpu flag differs, not the guest itself. Breaking this
      # looks like a -tcg build that quietly diverged into a second guest.
      kvmSys=$(readlink -f "$kvm/share/microvm/system")
      tcgSys=$(readlink -f "$tcg/share/microvm/system")
      if [ "$kvmSys" != "$tcgSys" ]; then
        echo "${name}: KVM and -tcg runners do not share one guest system:" >&2
        echo "  kvm: $kvmSys" >&2
        echo "  tcg: $tcgSys" >&2
        fail=1
      fi

      # -enable-kvm only on the KVM runner, -cpu max only on -tcg -- the one
      # option that removes -enable-kvm on the pinned microvm.nix commit.
      if ! grep -q -- '-enable-kvm' "$kvm/bin/microvm-run"; then
        echo "${name}: KVM runner has no -enable-kvm" >&2
        fail=1
      fi
      if grep -q -- '-enable-kvm' "$tcg/bin/microvm-run"; then
        echo "${name}: -tcg runner still passes -enable-kvm" >&2
        fail=1
      fi

      # The -tcg runner's machine line, and each of these is a bug that
      # already shipped or the door it came through.
      #
      # accel=tcg, PINNED. Upstream's default is the `kvm:tcg` fallback
      # chain, under which qemu silently takes KVM wherever /dev/kvm exists
      # -- so every local run of the "-tcg" artifact measured a KVM boot,
      # and the artifact that cannot boot under real TCG went out measured
      # as working. The flake.nix comment on machineOpts says the rest; this
      # grep is what stops the fallback being "optimised" back in.
      if ! grep -q -- 'accel=tcg[^:]' "$tcg/bin/microvm-run"; then
        echo "${name}: -tcg runner does not pin accel=tcg -- the kvm:tcg fallback is back, and with it the unmeasured artifact" >&2
        fail=1
      fi
      # pit=on and pic=on. The microvm machine's pit=off/pic=off default is
      # correct under KVM (kvmclock) and fatal under TCG (no kvmclock, no
      # HPET, nothing to calibrate early timers from): the guest kernel
      # triple-faults or wedges right after "Poking KASLR". Proved by A/B:
      # five minutes of silence with them off, a 2m13s boot to login with
      # them on, `-cpu qemu64` ruling the CPU model out.
      for knob in pit=on pic=on; do
        if ! grep -q -- "$knob" "$tcg/bin/microvm-run"; then
          echo "${name}: -tcg runner's machine line lacks $knob -- under TCG this guest wedges after 'Poking KASLR'" >&2
          fail=1
        fi
      done
      # And the KVM runner keeps upstream's defaults untouched: kvmclock
      # makes pit=off/pic=off correct there, and this fix must not widen
      # into the path every real user runs.
      for knob in pit=off pic=off; do
        if ! grep -q -- "$knob" "$kvm/bin/microvm-run"; then
          echo "${name}: KVM runner's machine line lost $knob -- the -tcg fix leaked into the KVM path" >&2
          fail=1
        fi
      done
    '') names}

    echo "== every template is in the manual's table =="

    # A hand-maintained list naming things that exist elsewhere (CLAUDE.md #4):
    # docs/manual/sandboxes.md's template table is written by hand and the
    # catalogue is not, so the table fails OPEN -- a template added without a
    # row still works, still ships, and is documented nowhere. This names the
    # missing template rather than comparing a count, because a count only
    # says a number moved.
    # A backtick built with printf rather than written here: the table cells
    # are `name` in code ticks, and a literal backtick inside double quotes is
    # command substitution to bash.
    bt=$(printf '\140')
    for name in ${lib.concatStringsSep " " names}; do
      if ! grep -qF "| $bt$name$bt |" ${../docs/manual/sandboxes.md}; then
        echo "data/microvm-templates.nix has '$name' and docs/manual/sandboxes.md has no row for it" >&2
        fail=1
      fi
    done

    ${lib.concatMapStrings (
      name:
      lib.optionalString (lib.hasPrefix "agent" name) ''
        echo "== ${name}: cannot reach what it was not allowed =="

        # Everything below reads the guest CLOSURE rather than the qemu command
        # line: an egress policy lives inside the guest, so the assertions the
        # rest of this file makes against bin/microvm-run cannot see any of it.
        # Nothing here boots -- see the header for why that matters.
        sys=$(readlink -f ${templates.${name}.kvm}/share/microvm/system)
        units=$sys/etc/systemd/system

        for unit in nftables.service tinyproxy.service nixarchy-agent-allowlist.service; do
          if [ ! -e "$units/$unit" ]; then
            echo "${name}: $unit is not in the guest closure -- the egress restriction is not there" >&2
            fail=1
          fi
        done

        # The allowlist generator runs BEFORE tinyproxy, and tinyproxy does not
        # start without it. tinyproxy reads its filter file once, at start: a
        # tinyproxy that came up first would be enforcing the previous boot's
        # allowlist, or none.
        if [ ! -e "$units/tinyproxy.service.requires/nixarchy-agent-allowlist.service" ]; then
          echo "${name}: tinyproxy does not require nixarchy-agent-allowlist -- it can start without an allowlist" >&2
          fail=1
        fi

        rules=$(grep -oE '/nix/store/[a-z0-9]+-nftables-rules' "$units/nftables.service" | head -1)
        if [ -z "$rules" ] || [ ! -r "$rules" ]; then
          echo "${name}: could not find the nftables ruleset the guest loads at boot" >&2
          fail=1
        else
          if ! grep -q 'table inet nixarchy-agent' "$rules"; then
            echo "${name}: the guest's ruleset has no nixarchy-agent table" >&2
            fail=1
          fi
          # The whole restriction in one line. Without `policy drop` this is an
          # ordinary machine with some accept rules on it.
          if ! grep -qE 'hook output .*policy drop' "$rules"; then
            echo "${name}: the output chain does not default to drop -- egress is unrestricted" >&2
            fail=1
          fi

          # And the accepts are all uid-qualified. An unqualified `dport 53
          # accept` would hand every process in the guest a DNS socket, which is
          # an exfiltration channel needing no allowed host at all -- and it
          # would still LOOK like a locked-down ruleset.
          bare=$(grep -vE '^[[:space:]]*#' "$rules" \
            | grep -E 'dport[^#]*(53|80|443)' \
            | grep -v skuid || true)
          if [ -n "$bare" ]; then
            echo "${name}: these ruleset lines accept traffic from any uid, not just the proxy's:" >&2
            echo "$bare" >&2
            fail=1
          fi

          # The uid in the ruleset is the uid tinyproxy actually gets. Dropping
          # `users.users.tinyproxy.uid` is the quiet version of this bug: the
          # rules still read correctly and permit a uid nothing runs as.
          ruleUid=$(grep -oE 'skuid [0-9]+' "$rules" | head -1 | cut -d' ' -f2)
          usersJson=$(grep -oE '/nix/store/[a-z0-9]+-users-groups.json' "$sys/activate" | head -1)
          realUid=$(jq -r '.users[] | select(.name == "tinyproxy") | .uid' "$usersJson")
          if [ "$ruleUid" != "$realUid" ]; then
            echo "${name}: the ruleset permits uid '$ruleUid' and tinyproxy runs as uid '$realUid'" >&2
            echo "-- the proxy cannot egress, so nothing in this guest can" >&2
            fail=1
          fi
        fi

        conf=$(grep -oE '\-c /nix/store/[^ ]+' "$units/tinyproxy.service" | head -1 | cut -d' ' -f2)
        if [ -z "$conf" ] || [ ! -r "$conf" ]; then
          echo "${name}: could not find tinyproxy's generated configuration" >&2
          fail=1
        else
          # FilterDefaultDeny is what makes the filter file an ALLOWlist. Without
          # it the same file names hosts to refuse and everything else goes
          # through -- the exact inversion of what this template promises, with
          # no other visible difference.
          if ! grep -q '^FilterDefaultDeny yes' "$conf"; then
            echo "${name}: tinyproxy has no FilterDefaultDeny -- the allowlist is a blocklist" >&2
            fail=1
          fi
          # The filter is a runtime path, not a store path: the allowlist is
          # per-VM (data/microvm-templates.nix's rule -- one closure serves every
          # VM of a template), written at boot from /mnt/host/allow-hosts.
          if ! grep -q '^Filter "/run/nixarchy-agent/allow.filter"' "$conf"; then
            echo "${name}: tinyproxy's Filter is not the per-VM file written at boot:" >&2
            grep '^Filter' "$conf" >&2 || echo "  (no Filter line at all)" >&2
            fail=1
          fi
          if ! grep -q '^ConnectPort 443' "$conf"; then
            echo "${name}: tinyproxy does not restrict CONNECT to 443 -- an allowed host is a tunnel to any port on it" >&2
            fail=1
          fi
          if ! grep -q '^Listen 127.0.0.1' "$conf"; then
            echo "${name}: tinyproxy does not listen on loopback only" >&2
            fail=1
          fi
        fi

        # And the guest tells its own processes where the proxy is, in both
        # spellings -- a tool reading only the uppercase pair would otherwise get
        # a dropped connection and no explanation.
        for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
          if ! grep -q "^export $var=\"http://127.0.0.1:8888\"" "$sys/etc/set-environment"; then
            echo "${name}: the guest does not export $var -- nothing in it will find the proxy" >&2
            fail=1
          fi
        done
      ''
    ) names}
    ${lib.optionalString (templates ? agent-claude) ''
      echo "== agent-claude: default hosts in the closure, nothing unfree in it =="
      sys=$(readlink -f ${templates.agent-claude.kvm}/share/microvm/system)
      for host in api.anthropic.com api.openai.com github.com codeload.github.com; do
        if ! grep -qx "$host" "$sys/etc/nixarchy-agent/allow-hosts"; then
          echo "agent-claude: $host is not in the closure-side allowlist" >&2
          fail=1
        fi
      done
      for bin in codex opencode; do
        if [ ! -e "$sys/sw/bin/$bin" ]; then
          echo "agent-claude: $bin is not on the guest's PATH" >&2
          fail=1
        fi
      done
      # CI is a pure evaluation, so this is the public runner. A `claude`
      # here means an unfree package is about to be pushed to a public cache.
      if [ -e "$sys/sw/bin/claude" ]; then
        echo "agent-claude: claude-code is in the runner CI builds -- it must never reach the public cache" >&2
        fail=1
      fi
    ''}

    echo "== nixarchy vm: launch and locking =="

    # A stub `nix` that logs its own argv and then fakes the build: it writes
    # the out-link the real caller asked for, pointing at a stub runner. This
    # is what proves `nix build --out-link` rather than `nix run` without
    # paying for an actual guest build -- checks.microvm-template already
    # does that above, on the real packages.
    mkdir -p bin
    calls=$PWD/nix-calls.log
    cat > bin/nix <<STUB
    #!${pkgs.bash}/bin/bash
    echo "\$*" >> $calls
    if [ "\$1" = build ]; then
      out=""
      prev=""
      for a in "\$@"; do
        if [ "\$prev" = --out-link ]; then out="\$a"; fi
        prev="\$a"
      done
      if [ -z "\$out" ]; then echo "stub nix build: no --out-link seen" >&2; exit 1; fi
      mkdir -p "\$out/bin"
      cat > "\$out/bin/microvm-run" <<'RUNNER'
    #!${pkgs.bash}/bin/bash
    echo "stub guest running" > run.marker
    sleep 30
    RUNNER
      chmod +x "\$out/bin/microvm-run"
      cat > "\$out/bin/microvm-shutdown" <<'SHUT'
    #!${pkgs.bash}/bin/bash
    true
    SHUT
      chmod +x "\$out/bin/microvm-shutdown"
      exit 0
    fi
    echo "stub nix: unexpected subcommand '\$1'" >&2
    exit 1
    STUB
    chmod +x bin/nix
    export PATH="$PWD/bin:$PATH"
    export HOME=$PWD/home
    export XDG_STATE_HOME=$HOME/.local/state
    mkdir -p "$HOME"

    ${nixarchyVm}/bin/nixarchy-vm create sandbox

    # First run: builds via the stub, then execs the stub runner, which
    # sleeps -- backgrounded so the check can also try a second run while
    # the first is still "up".
    ( ${nixarchyVm}/bin/nixarchy-vm run sandbox > run1.log 2>&1; echo $? > run1.status ) &
    first=$!

    # Wait for the stub runner to actually be attached, rather than timing:
    # the marker file only appears once bin/microvm-run itself is running.
    for _ in $(seq 1 50); do
      [ -f "$HOME/.local/state/nixarchy/microvm/sandbox/run.marker" ] && break
      sleep 0.2
    done
    if [ ! -f "$HOME/.local/state/nixarchy/microvm/sandbox/run.marker" ]; then
      echo "the first 'run' never reached the stub guest -- see run1.log:" >&2
      cat run1.log >&2
      fail=1
    fi

    if ! grep -q -- '^build ' "$calls"; then
      echo "nix was never called with 'build' as its first argument:" >&2
      cat "$calls" >&2
      fail=1
    fi
    if grep -q '^run ' "$calls"; then
      echo "nix was called with 'run' -- that registers no GC root:" >&2
      cat "$calls" >&2
      fail=1
    fi
    if ! grep -q -- '--out-link' "$calls"; then
      echo "nix build was never given --out-link:" >&2
      cat "$calls" >&2
      fail=1
    fi

    # A second instance of the same name refuses instead of a second qemu
    # racing the first over the same 9p share and volume image.
    if ${nixarchyVm}/bin/nixarchy-vm run sandbox > run2.log 2>&1; then
      echo "a second 'run sandbox' succeeded while the first was still up:" >&2
      cat run2.log >&2
      fail=1
    else
      echo "second run correctly refused:"
      cat run2.log
    fi

    kill "$first" 2>/dev/null || true
    wait "$first" 2>/dev/null || true

    echo "== nixarchy vm: a machine built from a dirty or unpushed commit =="

    # The URL baked into the dirty-checkout CLI. "<rev>-dirty" is what
    # self.dirtyRev holds, and github:owner/repo/<rev>-dirty is a ref GitHub
    # cannot resolve -- `nixarchy vm run` on any machine built from a dirty
    # tree 404s at build time, with nix's fetch error as the only word on it.
    if grep -q -- '-dirty' ${dirtyVm}/bin/nixarchy-vm; then
      echo "the dirty-checkout CLI embeds a flake URL ending in -dirty:" >&2
      grep -o 'github:[^"]*' ${dirtyVm}/bin/nixarchy-vm | sort -u >&2
      echo "GitHub has no such ref, so 'nixarchy vm run' can never build" >&2
      fail=1
    fi

    # And the pinned commit itself is only a promise: a stripped dirty rev or
    # a clean but unpushed commit resolves no better. A second stub `nix`
    # that refuses everything except .../main -- exactly what GitHub does for
    # a commit it does not have -- so `run` has to fall back to main, out
    # loud, instead of dying on the fetch.
    mkdir -p bin2
    calls2=$PWD/nix-calls2.log
    cat > bin2/nix <<STUB2
    #!${pkgs.bash}/bin/bash
    echo "\$*" >> $calls2
    case "\$2" in
      */main#*) exec $PWD/bin/nix "\$@" ;;
      *) echo "stub nix: cannot find flake reference '\$2' (no such ref)" >&2; exit 1 ;;
    esac
    STUB2
    chmod +x bin2/nix
    export PATH="$PWD/bin2:$PATH"
    export HOME=$PWD/home2
    export XDG_STATE_HOME=$HOME/.local/state
    mkdir -p "$HOME"

    ${dirtyVm}/bin/nixarchy-vm create pinned
    ( ${dirtyVm}/bin/nixarchy-vm run pinned > run3.log 2>&1; echo $? > run3.status ) &
    third=$!
    for _ in $(seq 1 50); do
      [ -f "$XDG_STATE_HOME/nixarchy/microvm/pinned/run.marker" ] && break
      sleep 0.2
    done
    if [ ! -f "$XDG_STATE_HOME/nixarchy/microvm/pinned/run.marker" ]; then
      echo "'run' did not fall back to main after the pinned commit failed to resolve:" >&2
      echo "a machine built from an unpushed (or dirty) commit cannot run a VM at all" >&2
      echo "-- see run3.log:" >&2
      cat run3.log >&2
      fail=1
    else
      # The pin was still tried first -- falling straight to main would throw
      # away the exact-commit match every pushed machine is entitled to.
      if ! grep -q -- "/${dirtyRev}#" "$calls2"; then
        echo "the fallback skipped the pinned commit entirely:" >&2
        cat "$calls2" >&2
        fail=1
      fi
      # And the switch to main was said out loud, not done silently.
      if ! grep -qi 'falling back' run3.log; then
        echo "the fallback to main happened without a word to the user:" >&2
        cat run3.log >&2
        fail=1
      fi
      echo "the pinned commit was tried, refused, and main took over audibly"
    fi
    kill "$third" 2>/dev/null || true
    wait "$third" 2>/dev/null || true

    echo "== nixarchy vm: the plugin's contract (#762) =="

    # nixarchy.microvm reads this CLI and nothing else: JSON listings, a
    # detached run with a console to attach to later, and a template swap.
    # systemd-run and dtach are runtimeInputs, so a stub FILE on PATH is never
    # reached (writeShellApplication puts runtimeInputs first -- the #778
    # lesson). Exported bash functions win over PATH, so they are stubs.
    export HOME=$PWD/home3
    export XDG_STATE_HOME=$HOME/.local/state
    export PATH="$PWD/bin:$PATH"
    export T=$PWD
    mkdir -p "$HOME"
    vm=${nixarchyVm}/bin/nixarchy-vm
    vmdir=$XDG_STATE_HOME/nixarchy/microvm

    # (a) No VMs is an empty array, not the text line.
    got=$($vm list --json 2>&1 || true)
    if ! printf '%s' "$got" | jq -e 'type == "array" and length == 0' > /dev/null 2>&1; then
      echo "(a) 'list --json' with no VMs is not []: $got" >&2
      fail=1
    fi

    # (b) Exactly the four keys, and running follows the lock.
    $vm create sandbox > /dev/null
    keys=$($vm list --json 2>/dev/null | jq -c '[.[0] | keys[]]' 2>/dev/null || echo unparseable)
    if [ "$keys" != '["dir","name","running","template"]' ]; then
      echo "(b) 'list --json' keys are $keys, not dir, name, running, template" >&2
      fail=1
    fi
    if [ "$($vm list --json 2>/dev/null | jq -r '.[0].running' 2>/dev/null)" != false ]; then
      echo "(b) a stopped VM does not read running=false" >&2
      fail=1
    fi
    exec 7>"$vmdir/sandbox/.lock"
    flock -n 7
    if [ "$($vm list --json 2>/dev/null | jq -r '.[0].running' 2>/dev/null)" != true ]; then
      echo "(b) a VM whose lock is held does not read running=true" >&2
      fail=1
    fi

    # (d) set-template: never under a running VM, never onto a missing
    # template, never without a name, and never over volumes unless told.
    if $vm set-template sandbox persistent > sett.log 2>&1; then
      echo "(d) set-template rewrote a running VM's template" >&2
      fail=1
    fi
    exec 7>&-
    if ! $vm set-template sandbox persistent > sett.log 2>&1; then
      echo "(d) set-template refused a stopped VM:" >&2
      cat sett.log >&2
      fail=1
    elif [ "$(cat "$vmdir/sandbox/template")" != persistent ]; then
      echo "(d) set-template succeeded but the template file says $(cat "$vmdir/sandbox/template")" >&2
      fail=1
    fi
    if $vm set-template sandbox no-such-template > /dev/null 2>&1; then
      echo "(d) set-template accepted a template that does not exist" >&2
      fail=1
    fi
    if $vm set-template > /dev/null 2>&1; then
      echo "(d) set-template with no name succeeded" >&2
      fail=1
    fi
    touch "$vmdir/sandbox/home.img"
    if $vm set-template sandbox shell > /dev/null 2>&1; then
      echo "(d) set-template swapped the template under an existing volume" >&2
      fail=1
    fi
    if ! $vm set-template sandbox shell --keep-volumes > sett.log 2>&1; then
      echo "(d) set-template --keep-volumes refused:" >&2
      cat sett.log >&2
      fail=1
    fi
    rm -f "$vmdir/sandbox/home.img"

    # (c) templates --json is the catalogue, name for name.
    idx=$(grep -o 'templates=/nix/store/[^ ]*' "$vm" | head -1 | cut -d= -f2)/index.tsv
    if [ "$($vm templates --json 2>/dev/null | jq -r '.[].name' 2>/dev/null)" != "$(cut -f1 "$idx")" ]; then
      echo "(c) 'templates --json' names do not match the catalogue ($idx)" >&2
      fail=1
    fi
    if [ "$($vm templates --json 2>/dev/null | jq -c '[.[0] | keys[]]' 2>/dev/null)" != '["label","name","note"]' ]; then
      echo "(c) 'templates --json' entries are not {name, label, note}" >&2
      fail=1
    fi

    # (e) run --detach builds here, hands the launch to a user unit wrapped in
    # dtach, and returns only once that unit holds the VM's lock. The stub
    # unit runs its command in the background, so the wait is real.
    systemd-run() {
      echo "$*" > "$T/systemd-run.args"
      while [ "$1" != -- ]; do shift; done
      shift
      shift # the dtach binary
      dtach "$@" > "$T/detached.log" 2>&1 &
      echo $! > "$T/detached.pid"
    }
    dtach() {
      case "$1" in
        -N) shift 3; "$@" ;;
        -a) echo "$*" > "$T/dtach-attach.args" ;;
      esac
    }
    export -f systemd-run dtach
    $vm create detached > /dev/null
    if ! $vm run --detach detached > detach.log 2>&1; then
      echo "(e) 'run --detach' failed:" >&2
      cat detach.log >&2
      fail=1
    fi
    if [ "$($vm list --json 2>/dev/null | jq -r '.[] | select(.name == "detached") | .running' 2>/dev/null)" != true ]; then
      echo "(e) 'run --detach' returned, and the stub saw no lock taken" >&2
      fail=1
    fi
    if ! grep -q 'nixarchy-vm-detached' "$T/systemd-run.args" 2>/dev/null; then
      echo "(e) the user unit is not named nixarchy-vm-detached: $(cat "$T/systemd-run.args" 2>/dev/null)" >&2
      fail=1
    fi
    if [ -s "$T/detached.pid" ]; then
      pkill -P "$(cat "$T/detached.pid")" 2>/dev/null || true
      kill "$(cat "$T/detached.pid")" 2>/dev/null || true
    fi

    # (f) A unit that never takes the lock is a failure, and says where to look.
    systemd-run() { echo "$*" > "$T/systemd-run.args"; }
    export -f systemd-run
    $vm create neverup > /dev/null
    if NIXARCHY_VM_DETACH_TIMEOUT=2 $vm run --detach neverup > neverup.log 2>&1; then
      echo "(f) 'run --detach' exited 0 where 1 was expected: the unit never started" >&2
      fail=1
    elif ! grep -q 'journalctl --user -u nixarchy-vm-neverup' neverup.log; then
      echo "(f) the timeout does not name the unit's journal:" >&2
      cat neverup.log >&2
      fail=1
    fi

    # (g) console: refuses without a socket, attaches to it when there is one.
    $vm create quiet > /dev/null
    if $vm console quiet > con.log 2>&1; then
      echo "(g) 'console' succeeded on a VM that was never detached" >&2
      fail=1
    fi
    python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$vmdir/quiet/console.sock"
    rm -f "$T/dtach-attach.args"
    $vm console quiet > con.log 2>&1 || true
    if ! grep -qF -- "-a $vmdir/quiet/console.sock -e ^]" "$T/dtach-attach.args" 2>/dev/null; then
      echo "(g) 'console' did not attach with dtach -a <sock> -e ^]: $(cat "$T/dtach-attach.args" 2>/dev/null)" >&2
      fail=1
    fi
    unset -f systemd-run dtach

    # (i), (j): a detached run's build is not a window. The first review of
    # #784 (codex, on the agent bus) found detach building with the lock
    # free: `rm` in that window deleted the VM mid-build, and a second
    # detach passed the status check and unlinked the first one's socket.
    # A nix that blocks mid-build, until told, makes both deterministic.
    mkdir -p bin4
    cat > bin4/nix <<STUB4
    #!${pkgs.bash}/bin/bash
    touch "$T/building"
    while [ ! -e "$T/release" ]; do sleep 0.1; done
    exec $PWD/bin/nix "\$@"
    STUB4
    chmod +x bin4/nix
    systemd-run() {
      while [ "$1" != -- ]; do shift; done
      shift 2
      dtach "$@" 9>&- > "$T/racer.log" 2>&1 &
      echo $! > "$T/racer.pid"
    }
    dtach() { [ "$1" = -N ] && { shift 3; "$@"; }; }
    export -f systemd-run dtach
    $vm create racer > /dev/null
    rm -f "$T/building" "$T/release"
    ( PATH="$PWD/bin4:$PATH" $vm run --detach racer > racer-detach.log 2>&1; echo $? > racer.status ) &
    racer=$!
    for _ in $(seq 1 100); do [ -e "$T/building" ] && break; sleep 0.1; done
    if $vm rm racer > racer-rm.log 2>&1; then
      echo "(i) 'rm' deleted a VM while its detached run was still building:" >&2
      cat racer-rm.log >&2
      fail=1
    fi
    if timeout 10 env PATH="$PWD/bin4:$PATH" $vm run --detach racer > racer-second.log 2>&1; then
      echo "(j) a second 'run --detach' of a VM already detaching was not refused" >&2
      fail=1
    elif ! grep -q 'already running' racer-second.log; then
      echo "(j) a second 'run --detach' did not refuse as 'already running' (it built, or hung):" >&2
      cat racer-second.log >&2
      fail=1
    fi
    touch "$T/release"
    wait "$racer" 2>/dev/null || true
    if [ -s "$T/racer.pid" ]; then
      pkill -P "$(cat "$T/racer.pid")" 2>/dev/null || true
      kill "$(cat "$T/racer.pid")" 2>/dev/null || true
    fi
    unset -f systemd-run dtach

    # (k) The handoff gap: detach has let go of the lock, and the unit has
    # not taken it yet. The unit being up is what keeps `rm` and a second
    # run out then.
    # A fresh VM, lock provably free, so only the unit can make it refuse.
    $vm create gap > /dev/null
    exec 6>"$vmdir/gap/.lock"
    if ! flock -n 6; then
      echo "(k) the fixture is wrong: gap's lock is already held" >&2
      fail=1
    fi
    exec 6>&-
    systemctl() { [ "$*" = "--user is-active nixarchy-vm-gap" ] && echo activating; }
    export -f systemctl
    if $vm rm gap > /dev/null 2>&1; then
      echo "(k) 'rm' deleted a VM whose detached unit was still activating" >&2
      fail=1
    fi
    if timeout 10 $vm run gap > /dev/null 2>&1 || [ -e "$vmdir/gap/current" ]; then
      echo "(k) 'run' started a VM whose detached unit was still activating" >&2
      fail=1
    fi
    unset -f systemctl

    # (h) The plugin reads what this CLI can do from `help` alone, with these
    # three patterns (nixarchy-microvm Model.js:973-975 at 481e6c5). A help
    # line reworded is a feature silently switched off in the panel.
    help=$($vm help)
    printf '%s\n' "$help" | grep -qE '\brun\b.*--detach' ||
      { echo "(h) vmDetach pattern no longer matches 'nixarchy vm help'" >&2; fail=1; }
    printf '%s\n' "$help" | grep -qE '\bvm console\b' ||
      { echo "(h) vmConsole pattern no longer matches 'nixarchy vm help'" >&2; fail=1; }
    printf '%s\n' "$help" | grep -qE '\bset-template\b' ||
      { echo "(h) vmSetTemplate pattern no longer matches 'nixarchy vm help'" >&2; fail=1; }

    bash ${./microvm-mutations.sh} ${nixarchyVm}/bin/nixarchy-vm

    [ "$fail" -eq 0 ] || exit 1
    echo "every template's runner is qemu, shares the host store read-only," \
         "uses user networking, and the KVM/-tcg pair share one guest --" \
         "and nixarchy-vm launches it with an out-link, under a flock."
    touch $out
  ''
