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

    ${lib.optionalString (templates ? agent) ''
      echo "== the agent template cannot reach what it was not allowed =="

      # Everything below reads the guest CLOSURE rather than the qemu command
      # line: an egress policy lives inside the guest, so the assertions the
      # rest of this file makes against bin/microvm-run cannot see any of it.
      # Nothing here boots -- see the header for why that matters.
      sys=$(readlink -f ${templates.agent.kvm}/share/microvm/system)
      units=$sys/etc/systemd/system

      for unit in nftables.service tinyproxy.service nixarchy-agent-allowlist.service; do
        if [ ! -e "$units/$unit" ]; then
          echo "agent: $unit is not in the guest closure -- the egress restriction is not there" >&2
          fail=1
        fi
      done

      # The allowlist generator runs BEFORE tinyproxy, and tinyproxy does not
      # start without it. tinyproxy reads its filter file once, at start: a
      # tinyproxy that came up first would be enforcing the previous boot's
      # allowlist, or none.
      if [ ! -e "$units/tinyproxy.service.requires/nixarchy-agent-allowlist.service" ]; then
        echo "agent: tinyproxy does not require nixarchy-agent-allowlist -- it can start without an allowlist" >&2
        fail=1
      fi

      rules=$(grep -oE '/nix/store/[a-z0-9]+-nftables-rules' "$units/nftables.service" | head -1)
      if [ -z "$rules" ] || [ ! -r "$rules" ]; then
        echo "agent: could not find the nftables ruleset the guest loads at boot" >&2
        fail=1
      else
        if ! grep -q 'table inet nixarchy-agent' "$rules"; then
          echo "agent: the guest's ruleset has no nixarchy-agent table" >&2
          fail=1
        fi
        # The whole restriction in one line. Without `policy drop` this is an
        # ordinary machine with some accept rules on it.
        if ! grep -qE 'hook output .*policy drop' "$rules"; then
          echo "agent: the output chain does not default to drop -- egress is unrestricted" >&2
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
          echo "agent: these ruleset lines accept traffic from any uid, not just the proxy's:" >&2
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
          echo "agent: the ruleset permits uid '$ruleUid' and tinyproxy runs as uid '$realUid'" >&2
          echo "-- the proxy cannot egress, so nothing in this guest can" >&2
          fail=1
        fi
      fi

      conf=$(grep -oE '\-c /nix/store/[^ ]+' "$units/tinyproxy.service" | head -1 | cut -d' ' -f2)
      if [ -z "$conf" ] || [ ! -r "$conf" ]; then
        echo "agent: could not find tinyproxy's generated configuration" >&2
        fail=1
      else
        # FilterDefaultDeny is what makes the filter file an ALLOWlist. Without
        # it the same file names hosts to refuse and everything else goes
        # through -- the exact inversion of what this template promises, with
        # no other visible difference.
        if ! grep -q '^FilterDefaultDeny yes' "$conf"; then
          echo "agent: tinyproxy has no FilterDefaultDeny -- the allowlist is a blocklist" >&2
          fail=1
        fi
        # The filter is a runtime path, not a store path: the allowlist is
        # per-VM (data/microvm-templates.nix's rule -- one closure serves every
        # VM of a template), written at boot from /mnt/host/allow-hosts.
        if ! grep -q '^Filter "/run/nixarchy-agent/allow.filter"' "$conf"; then
          echo "agent: tinyproxy's Filter is not the per-VM file written at boot:" >&2
          grep '^Filter' "$conf" >&2 || echo "  (no Filter line at all)" >&2
          fail=1
        fi
        if ! grep -q '^ConnectPort 443' "$conf"; then
          echo "agent: tinyproxy does not restrict CONNECT to 443 -- an allowed host is a tunnel to any port on it" >&2
          fail=1
        fi
        if ! grep -q '^Listen 127.0.0.1' "$conf"; then
          echo "agent: tinyproxy does not listen on loopback only" >&2
          fail=1
        fi
      fi

      # And the guest tells its own processes where the proxy is, in both
      # spellings -- a tool reading only the uppercase pair would otherwise get
      # a dropped connection and no explanation.
      for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
        if ! grep -q "^export $var=\"http://127.0.0.1:8888\"" "$sys/etc/set-environment"; then
          echo "agent: the guest does not export $var -- nothing in it will find the proxy" >&2
          fail=1
        fi
      done
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

    [ "$fail" -eq 0 ] || exit 1
    echo "every template's runner is qemu, shares the host store read-only," \
         "uses user networking, and the KVM/-tcg pair share one guest --" \
         "and nixarchy-vm launches it with an out-link, under a flock."
    touch $out
  ''
