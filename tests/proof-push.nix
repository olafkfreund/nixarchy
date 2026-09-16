{ pkgs, ... }:
# The proof push, run against a stubbed cache and a stubbed nix.
#
# Three properties, each of which was false on 2026-09-16 and is why an
# eviction on 2026-09-15 became a day-long outage (#727, #728, #729):
#
#   - a job that is KILLED still leaves behind the proofs it already earned.
#     The old code pushed once, after `nix build` returned, so three jobs that
#     died mid-build (14 min, 17 min, 45m00s) pushed nothing at all and every
#     run began where the last began;
#   - a result that cannot BE a proof is a category, not a failure. checks.nixi
#     is the nixi package -- 92 paths, 567 MB -- so the old script exited 1 on
#     every run forever, and `|| true` in the caller then discarded it. Exit 1
#     with 39 of 40 pushed was indistinguishable from exit 1 with 0 of 40;
#   - a push that genuinely fails still exits non-zero, or the first property
#     is bought by making the script unable to report anything.
#
# nix and cachix are stubs; the scripts are the real files, copied together
# because build-unless-proven.sh calls its siblings by path.
pkgs.runCommand "nixarchy-proof-push"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      jq
    ];
    buildUnlessProven = ../.github/scripts/build-unless-proven.sh;
    cachixPush = ../.github/scripts/cachix-push.sh;
    generatedChecks = ../.github/scripts/generated-checks.sh;
  }
  ''
        mkdir -p stubs sut calls
        work=$PWD
        cp "$buildUnlessProven" sut/build-unless-proven.sh
        cp "$cachixPush" sut/cachix-push.sh
        chmod +w sut/*.sh

        # already-proven.sh says everything needs building, so the slicing is what
        # is under test rather than the cache lookup.
        cat > sut/already-proven.sh <<'EOF'
    #!/usr/bin/env bash
    printf '%s\n' "$@"
    EOF

        # A nix stub whose `build` records the slice and, for the poisoned name,
        # blocks -- which is how a runner dying or a timeout arriving mid-build
        # looks from inside the script.
        cat > stubs/nix <<'EOF'
    #!/usr/bin/env bash
    # The last word of the command line is the installable; a fake out-path is
    # derived from its attribute name so a push can be attributed to a check.
    last=''${*##* }
    case "$1" in
      build)
        echo "BUILD $*" >> "$CALLS/build"
        # POISON names the check this build blocks on, which is how a runner dying
        # or a timeout arriving mid-build looks from inside the script. Defaulted
        # to a name no test uses: an empty POISON would make `*".$POISON"` match
        # every argument and hang every build.
        for a in "$@"; do case "$a" in *".''${POISON:-__no_such_check__}") sleep 300 ;; esac; done
        ;;
      eval) printf '/nix/store/fake-%s' "''${last##*.}" ;;
      path-info)
        case "$*" in
          # NAR_SIZE, not SIZE: SIZE is set in some interactive environments, and a
          # default that the environment can answer for is not a default at all
          # (AGENTS.md section 1).
          *--json*) printf '[{"narSize":%s}]' "''${NAR_SIZE:-112}" ;;
          *) echo /nix/store/fake ;;
        esac
        ;;
    esac
    EOF

        cat > stubs/cachix <<'EOF'
    #!/usr/bin/env bash
    echo "PUSH $3" >> "$CALLS/push"
    [ "''${PUSH_FAILS:-0}" = 1 ] && exit 1
    exit 0
    EOF

        # The sandbox has no /usr/bin/env, and build-unless-proven.sh execs its
        # siblings by path -- so a `#!/usr/bin/env bash` stub is "bad interpreter"
        # here and the script sees an empty list. Point every shebang at the bash
        # this derivation actually has.
        for f in stubs/* sut/*.sh; do
          sed -i "1s|.*|#!$(command -v bash)|" "$f"
        done
        chmod +x stubs/* sut/*.sh
        export PATH=$work/stubs:$PATH CALLS=$work/calls
        export XDG_CONFIG_HOME=$work/config
        mkdir -p "$XDG_CONFIG_HOME/cachix"
        echo stub > "$XDG_CONFIG_HOME/cachix/cachix.dhall"

        # ---- 1. a killed job keeps what it proved (#727) ----
        rm -f calls/*; : > calls/push
        POISON=f timeout 5 bash sut/build-unless-proven.sh a b c d e f g h > ratchet.log 2>&1 || true
        pushed=$(grep -c '^PUSH' calls/push || true)
        # Exactly five, not "at least": if the kill never landed, both slices push
        # and a >= assertion passes without ever testing the thing it is named for.
        [ "$pushed" = 5 ] || {
          echo "a job killed during the second slice kept $pushed proofs; the first" >&2
          echo "slice of five should have survived -- the step is not a ratchet" >&2
          echo "--- script output ---" >&2; cat ratchet.log >&2 || true
          echo "--- builds ---" >&2; cat calls/build >&2 || true
          echo "--- pushes ---" >&2; cat calls/push >&2 || true
          exit 1
        }
        echo "a killed job keeps the proofs it already earned ($pushed of them)"

        # PROOF_BATCH governs the slice, so the cost can be tuned from a workflow.
        rm -f calls/*; : > calls/build
        PROOF_BATCH=2 bash sut/build-unless-proven.sh a b c d >/dev/null 2>&1
        [ "$(grep -c '^BUILD' calls/build)" = 2 ] || {
          echo "PROOF_BATCH=2 over four checks did not produce two builds" >&2
          cat calls/build >&2
          exit 1
        }
        echo "PROOF_BATCH sets the slice size"

        # ---- 2. unproofable is a category, not a failure (#729) ----
        rm -f calls/*; : > calls/push
        bash sut/cachix-push.sh --proof a b > small.log 2>&1 && rc=0 || rc=$?
        [ "$rc" = 0 ] || { echo "a run with nothing unproofable exited $rc" >&2; cat small.log >&2; exit 1; }
        grep -q '2 pushed, 0 skipped' small.log || {
          echo "the summary line does not report two pushed and none skipped:" >&2
          cat small.log >&2
          exit 1
        }

        # A 567 MB result, which is what checks.nixi actually is.
        rm -f calls/*; : > calls/push
        NAR_SIZE=567009328 bash sut/cachix-push.sh --proof nixi > big.log 2>&1 && rc=0 || rc=$?
        [ "$rc" = 0 ] || {
          echo "an unproofable result exited $rc; a package build is a CATEGORY," >&2
          echo "not a push failure, and counting it as one made this script exit 1" >&2
          echo "on every run forever while the caller discarded it" >&2
          cat big.log >&2
          exit 1
        }
        grep -q '0 pushed, 1 skipped (unproofable), 0 failed' big.log || {
          echo "the summary does not name the skip as unproofable:" >&2
          cat big.log >&2
          exit 1
        }
        echo "a result too large to be a proof is skipped, named, and not a failure"

        # ---- 3. and a real push failure is still loud ----
        rm -f calls/*; : > calls/push
        PUSH_FAILS=1 bash sut/cachix-push.sh --proof a > failed.log 2>&1 && rc=0 || rc=$?
        [ "$rc" != 0 ] || {
          echo "cachix push failed and the script exited 0 -- the exit status was" >&2
          echo "made meaningless in the other direction" >&2
          cat failed.log >&2
          exit 1
        }
        grep -q '0 pushed, 0 skipped (unproofable), 1 failed' failed.log || {
          echo "the summary does not separate a failure from a skip:" >&2
          cat failed.log >&2
          exit 1
        }
        echo "a push that actually fails still exits non-zero, and says so"

        touch $out
  ''
