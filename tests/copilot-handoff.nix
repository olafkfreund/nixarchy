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
# `gh pr comment`) against a stub `gh` that serves a 500-line failing log --
# large enough to reproduce the SIGPIPE deterministically; see the control
# below. The negative control is the bug reintroduced: a copy of the script
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

    export RUN_ID=1 REPO=o/r BRANCH=update/x DRY_RUN=1

    # The fixed script.
    if ! bash ${../.github/scripts/copilot-handoff.sh} >out.txt 2>err.txt; then
      echo "copilot-handoff.sh (fixed) exited non-zero -- it should not" >&2
      cat err.txt >&2
      exit 1
    fi

    if ! grep -q 'would comment on #1154' out.txt; then
      echo "copilot-handoff.sh (fixed) did not reach the DRY_RUN message" >&2
      cat out.txt >&2
      exit 1
    fi

    excerpt=$(sed -n '/^~~~~$/,/^~~~~$/p' out.txt | sed '1d;$d')
    lines=$(printf '%s\n' "$excerpt" | grep -c . || true)
    if [ "$lines" -lt 1 ] || [ "$lines" -gt 100 ]; then
      echo "the failing-log excerpt has $lines lines, expected 1-100" >&2
      cat out.txt >&2
      exit 1
    fi

    # The negative control: head -100 restored. Prove the edit landed before
    # trusting the run (AGENTS.md #1).
    sed 's/sed -n .1,100p./head -100/' ${../.github/scripts/copilot-handoff.sh} >reverted.sh
    if ! grep -q 'head -100' reverted.sh; then
      echo "control setup failed: reverted.sh does not contain 'head -100'" >&2
      exit 1
    fi

    if bash reverted.sh >control-out.txt 2>control-err.txt; then
      echo "the control passed: a copy of copilot-handoff.sh with" >&2
      echo "head -100 restored exited 0 against the 500-line stub log," >&2
      echo "so this check can no longer tell the bug from the fix." >&2
      echo "500 lines no longer reproduces the SIGPIPE on this machine;" >&2
      echo "raise the line count in tests/copilot-handoff/gh." >&2
      cat control-out.txt control-err.txt >&2
      exit 1
    fi
    echo "control: head -100 against the 500-line stub failed as expected:"
    cat control-err.txt

    echo "copilot-handoff.sh: fixed script posts a $lines-line excerpt;" \
      "the head -100 control fails"
    touch $out
  ''
