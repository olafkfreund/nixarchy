{ pkgs, ... }:
# copilot-handoff.sh built its failing-log excerpt with `| head -100` at the
# end of a pipeline running under `set -o pipefail`. `head` reads exactly
# 100 lines and exits; if an earlier stage is still writing when it does, that
# stage's next write() gets SIGPIPE, the pipeline reports non-zero, and
# `set -e` kills the whole script before it ever posts to the pull request
# (#1157). `sed -n '1,100p'` reads to EOF, so no upstream stage is ever
# SIGPIPEd.
#
# This runs the real script (DRY_RUN=1, so it prints instead of calling
# `gh pr comment`) against a stub `gh` that serves a 20 000-line failing log.
# Size, not speed, makes the SIGPIPE certain: the stages' output must outgrow
# every pipe buffer, which 500 lines did not, so the control raced (#1381).
# The negative control is the bug reintroduced: a copy of the script
# with `head -100` restored, which must fail against the same stub, or this
# check is not testing what it claims to.
pkgs.runCommand "nixarchy-copilot-handoff"
  {
    nativeBuildInputs = with pkgs; [
      bash
      jq
      gnused
      gawk
      gnugrep
      coreutils
    ];
  }
  ''
    mkdir -p bin
    cp ${./copilot-handoff/gh} bin/gh
    chmod +x bin/gh
    patchShebangs bin/gh
    export PATH="$PWD/bin:$PATH"

    # The script finds its sibling failure-excerpt.sh by path.
    mkdir sut
    cp ${../.github/scripts/copilot-handoff.sh} sut/copilot-handoff.sh
    cp ${../.github/scripts/failure-excerpt.sh} sut/failure-excerpt.sh
    chmod +x sut/*.sh
    patchShebangs sut

    export RUN_ID=1 REPO=o/r BRANCH=update/x DRY_RUN=1

    # The fixed script.
    if ! bash sut/copilot-handoff.sh >out.txt 2>err.txt; then
      echo "copilot-handoff.sh (fixed) exited non-zero -- it should not" >&2
      cat err.txt >&2
      exit 1
    fi

    if ! grep -q 'would comment on #1154' out.txt; then
      echo "copilot-handoff.sh (fixed) did not reach the DRY_RUN message" >&2
      cat out.txt >&2
      exit 1
    fi

    # A draft is pin-fix's (#1459): not handed off. A draft state that cannot
    # be read fails safe the same way.
    for d in true fail; do
      GH_DRAFT=$d bash sut/copilot-handoff.sh >draft.txt 2>&1 || {
        echo "copilot-handoff.sh exited non-zero for GH_DRAFT=$d" >&2
        cat draft.txt >&2
        exit 1
      }
      if grep -q 'would comment' draft.txt || ! grep -q 'not handed off' draft.txt; then
        echo "copilot-handoff.sh handed off (or said nothing) for GH_DRAFT=$d" >&2
        cat draft.txt >&2
        exit 1
      fi
    done

    excerpt=$(sed -n '/^~~~~$/,/^~~~~$/p' out.txt | sed '1d;$d')
    lines=$(printf '%s\n' "$excerpt" | grep -c . || true)
    if [ "$lines" -lt 1 ] || [ "$lines" -gt 100 ]; then
      echo "the failing-log excerpt has $lines lines, expected 1-100" >&2
      cat out.txt >&2
      exit 1
    fi

    # The negative control: head -100 restored. Prove the edit landed before
    # trusting the run (AGENTS.md #1).
    # The excerpt's cap now lives in failure-excerpt.sh (#1384).
    mkdir control
    cp sut/* control/
    sed -i 's/sed -n "1,.{MAX:-40}p"/head -n "''${MAX:-40}"/' control/failure-excerpt.sh
    if ! grep -q 'head -n' control/failure-excerpt.sh; then
      echo "control setup failed: control/failure-excerpt.sh does not contain 'head -n'" >&2
      exit 1
    fi

    if bash control/copilot-handoff.sh >control-out.txt 2>control-err.txt; then
      echo "the control passed: a copy of copilot-handoff.sh with" >&2
      echo "head -100 restored exited 0 against the 20 000-line stub log," >&2
      echo "so this check can no longer tell the bug from the fix." >&2
      echo "the stub log no longer outgrows the pipe buffers between the" >&2
      echo "stages; enlarge it in tests/copilot-handoff/gh (#1381)." >&2
      cat control-out.txt control-err.txt >&2
      exit 1
    fi
    echo "control: head -100 against the 20 000-line stub failed as expected:"
    cat control-err.txt

    # The aggregator `system` fails whenever a half does, so a run whose only
    # real failure is a half that timed out (cancelled) must not be handed off
    # (#1341). The control is the script with the exclusion removed.
    export GH_JOBS='[{"name":"system","conclusion":"failure"},{"name":"system-build","conclusion":"cancelled"},{"name":"system-checks","conclusion":"success"}]'
    if ! bash sut/copilot-handoff.sh >agg-out.txt 2>agg-err.txt; then
      echo "copilot-handoff.sh exited non-zero on an aggregator-only failure" >&2
      cat agg-err.txt >&2
      exit 1
    fi
    if ! grep -q 'not handed off' agg-out.txt; then
      echo "copilot-handoff.sh handed off a run whose only failed job is the aggregator" >&2
      cat agg-out.txt >&2
      exit 1
    fi

    sed 's/ and \.name!="system"//' sut/copilot-handoff.sh >sut/noexcl.sh
    if grep -q 'name!="system"' sut/noexcl.sh; then
      echo "control setup failed: noexcl.sh still contains the exclusion" >&2
      exit 1
    fi
    bash sut/noexcl.sh >noexcl-out.txt 2>noexcl-err.txt || true
    if ! grep -q 'would comment on #1154' noexcl-out.txt; then
      echo "the control did not hand off: this check cannot tell the" >&2
      echo "aggregator exclusion from its absence." >&2
      cat noexcl-out.txt noexcl-err.txt >&2
      exit 1
    fi
    unset GH_JOBS

    echo "copilot-handoff.sh: fixed script posts a $lines-line excerpt;" \
      "the head -100 control fails"
    touch $out
  ''
