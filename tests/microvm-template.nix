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
in
pkgs.runCommand "nixarchy-microvm-template"
  {
    nativeBuildInputs = with pkgs; [
      gnugrep
      coreutils
      util-linux # flock, for the CLI half below
      bash
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
    '') names}

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

    [ "$fail" -eq 0 ] || exit 1
    echo "every template's runner is qemu, shares the host store read-only," \
         "uses user networking, and the KVM/-tcg pair share one guest --" \
         "and nixarchy-vm launches it with an out-link, under a flock."
    touch $out
  ''
