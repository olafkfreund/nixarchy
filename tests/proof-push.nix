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
    # The real script's contract: <name><TAB><drvPath><TAB><outPath>, saying
    # everything needs building. A name in NO_DRV comes back with both path
    # fields EMPTY -- the refusal path, and a check that would not evaluate --
    # so the caller's fallback to the attribute is exercised, not assumed.
    for c in "$@"; do
      case " ''${NO_DRV:-} " in
        *" $c "*) printf '%s\t\t\n' "$c" ;;
        *) printf '%s\t/nix/store/drv-%s.drv\t/nix/store/out-%s\n' "$c" "$c" "$c" ;;
      esac
    done
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
        # Both spellings: a slice is built by drvPath now (#738), and by attribute
      # on the fallback path. Matching only ".<name>" stopped simulating the
      # kill the moment the caller started passing derivations -- the ratchet
      # case then "passed" with eight pushes instead of five.
      for a in "$@"; do
        case "$a" in
          *".''${POISON:-__no_such_check__}" | *"drv-''${POISON:-__no_such_check__}.drv"*) sleep 300 ;;
        esac
      done
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

    # ---- 4. one evaluation per check, not three (#738) ----
    #
    # already-proven.sh must evaluate every check to learn its output path, and
    # `nix eval` INSTANTIATES -- the derivation is in the store before the cache
    # lookup happens. Discarding it made `nix build` evaluate the same attribute
    # again and `cachix-push.sh --proof` a third time. Measured 2026-09-17:
    # building checks.options by attribute 3m05s, by drvPath 1.3s, both already
    # built, both from a cold evaluation cache.
    rm -f calls/*; : > calls/build; : > calls/push
    bash sut/build-unless-proven.sh a b >/dev/null 2>&1
    grep -q 'drv-a[.]drv^' calls/build || {
      echo "the build ignored the drvPath already-proven.sh handed it, so nix" >&2
      echo "evaluates the attribute a second time (#738):" >&2
      cat calls/build >&2
      exit 1
    }
    if grep -q '[.]#checks' calls/build; then
      echo "the build still names an attribute although drvPaths were given:" >&2
      cat calls/build >&2
      exit 1
    fi
    echo "a slice builds by derivation, so nix does not evaluate it again"

    # And the push takes the outPath rather than deriving it a third time.
    grep -q 'out-a$' calls/push || {
      echo "the proof push did not receive the outPath from its caller:" >&2
      cat calls/push >&2
      exit 1
    }
    echo "the proof push takes the path it was given, and evaluates nothing"

    # ---- 5. an unknown drvPath falls back, and only for that check ----
    #
    # The refusal path emits both fields empty, and so does a check that would
    # not evaluate. Falling back to the attribute is the SAFE direction: it
    # builds rather than silently skipping, which is the failure this script had
    # in another form a day earlier.
    rm -f calls/*; : > calls/build
    NO_DRV="b" bash sut/build-unless-proven.sh a b >/dev/null 2>&1
    grep -q 'checks[.]x86_64-linux[.]b' calls/build || {
      echo "a check with no drvPath was not built by attribute; an empty field" >&2
      echo "must fall back rather than drop the check:" >&2
      cat calls/build >&2
      exit 1
    }
    grep -q 'drv-a[.]drv^' calls/build || {
      echo "the fallback took the whole slice with it; a known drvPath beside an" >&2
      echo "unknown one must still be used:" >&2
      cat calls/build >&2
      exit 1
    }
    echo "an empty drvPath falls back to the attribute, and only for that check"

        touch $out
  ''
