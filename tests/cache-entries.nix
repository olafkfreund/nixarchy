{ pkgs, ... }:
# The nightly's cache step, run against a stubbed cache.
#
# It probes every cache-allowlist.sh entry -- omarchy, the system closures, the
# MicroVM runners, the apps (#697) -- and puts back what nixarchy.cachix.org has
# evicted. Runners that dropped out used to stay out: build.yml pushes an entry
# once per commit. That is only worth having if both halves hold:
#
#   - a runner the cache no longer serves is built and pushed, and the step
#     passes once the cache serves it again;
#   - a push that "succeeds" and delivers nothing (cachix exits 0 on a rejected
#     token) still FAILS, naming the runner -- or the repush turns the one loud
#     signal the cache has into a green step.
#
# nix, curl, cachix-push.sh and the allowlist are stubs; the script is the real
# file, copied beside a fake cache-allowlist.sh because it reads the one next to
# it.
pkgs.runCommand "nixarchy-cache-entries"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
    ];
    real = ../.github/scripts/cache-entries.sh;
  }
  ''
    mkdir -p stubs served calls sut
    work=$PWD

    # The allowlist: one non-runner entry and two templates' runners, so the
    # probe is seen covering more than MicroVMs.
    cp $real sut/cache-entries.sh
    cat > sut/cache-allowlist.sh <<EOF
    #!${pkgs.bash}/bin/bash
    printf '%s\n' .#omarchy .#microvm-agent .#microvm-agent-tcg .#microvm-shell .#microvm-shell-tcg
    EOF
    chmod +x sut/*
    script=$work/sut/cache-entries.sh

    # Two templates, so four runners. A path's "hash" is derived from the attr
    # with no dashes, because the script cuts the store path at the first one.
    cat > stubs/nix <<EOF
    #!${pkgs.bash}/bin/bash
    case "\$*" in
      "eval --raw .#"*".outPath")
        attr=\''${3#.#}; attr=\''${attr%.outPath}
        printf '/nix/store/h%s-microvm-qemu-nixos' "\''${attr//-/}" ;;
      "build "*) echo "\$*" >> $work/calls/build ;;
      *) echo "unexpected nix \$*" >&2; exit 9 ;;
    esac
    EOF
    cat > stubs/curl <<EOF
    #!${pkgs.bash}/bin/bash
    url=\''${!#}; hash=\$(basename "\$url" .narinfo)
    if [ -e "$work/served/\$hash" ]; then printf 200; else printf 404; fi
    EOF
    # The push stub serves what it pushes only when PUSH_WORKS=1, and exits 0
    # either way -- exactly what a rejected cachix token looks like.
    cat > stubs/push <<EOF
    #!${pkgs.bash}/bin/bash
    for a in "\$@"; do
      echo "\$a" >> $work/calls/push
      attr=\''${a#.#}
      [ "\''${PUSH_WORKS:-0}" = 1 ] && touch "$work/served/h\''${attr//-/}"
    done
    exit 0
    EOF
    chmod +x stubs/*
    export PATH=$work/stubs:$PATH PUSH=$work/stubs/push RETRY_SLEEP=0

    # The -tcg runners are served, the KVM ones are not (the 2026-09-15
    # state), and omarchy has been evicted too.
    touch served/hmicrovmagenttcg served/hmicrovmshelltcg

    missing=$(bash "$script" probe 2>/dev/null)
    [ "$missing" = "$(printf '.#omarchy\n.#microvm-agent\n.#microvm-shell')" ] || {
      echo "probe did not name exactly the three missing entries:" >&2
      printf '%s\n' "$missing" >&2
      exit 1
    }
    echo "probe names every allowlist entry the cache no longer serves, and only those"

    # A push that delivers nothing must still fail, naming the runner.
    if bash "$script" repush .#microvm-agent > rejected.log 2>&1; then
      echo "repush exited 0 when the push delivered nothing -- a rejected token reads as green" >&2
      cat rejected.log >&2
      exit 1
    fi
    grep -q 'microvm-agent was built and pushed' rejected.log || {
      echo "a push that delivered nothing failed without naming the runner:" >&2
      cat rejected.log >&2
      exit 1
    }
    grep -q '#microvm-agent' calls/build || { echo "repush never built microvm-agent" >&2; exit 1; }
    echo "a push the cache never receives still fails, and names the runner"

    # A push that lands: built, pushed, served, green.
    rm -f calls/*
    PUSH_WORKS=1 bash "$script" repush $missing > landed.log 2>&1 && landed=0 || landed=$?
    for a in omarchy microvm-agent microvm-shell; do
      grep -qx ".#$a" calls/push 2>/dev/null || { echo "repush did not push $a" >&2; exit 1; }
    done
    [ "$landed" = 0 ] || {
      echo "repush failed although both runners were pushed and are served:" >&2
      cat landed.log >&2
      exit 1
    }
    [ -z "$(bash "$script" probe 2>/dev/null)" ] || {
      echo "after a working repush the probe still reports runners missing" >&2
      exit 1
    }
    echo "missing runners are built, pushed and served again"

    touch $out
  ''
