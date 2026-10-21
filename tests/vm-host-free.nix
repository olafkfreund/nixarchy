{ pkgs, ... }:
# Install and edge's VM checks never share p620 (#1365). The real script
# against a stub `gh` serving fixture JSON, plus two broken copies that must
# be caught: any job state counts, and a failed API call read as "free".
pkgs.runCommand "nixarchy-vm-host-free"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      jq
      diffutils
    ];
    script = ../.github/scripts/vm-host-free.sh;
  }
  ''
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[ ! -e "$FIX/fail" ] || exit 1' \
      'case "$2" in' \
      '  */jobs) cat "$FIX/jobs-$(basename "$(dirname "$2")").json" ;;' \
      '  *) cat "$FIX/runs.json" ;;' \
      'esac' > gh
    chmod +x gh
    export GH=$PWD/gh GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=999

    EDGE='{"id":11,"path":".github/workflows/omarchy-edge.yml"}'
    INST='{"id":22,"path":".github/workflows/install-check.yml"}'
    SELF='{"id":999,"path":".github/workflows/install-check.yml"}'
    # fixture <runs-json-array-body> <jobs-json-array-body for the other run>
    fixture() {
      rm -rf fix; mkdir fix
      printf '{"workflow_runs":[%s]}\n' "$1" > fix/runs.json
      printf '{"jobs":[%s]}\n' "$2" > fix/jobs-11.json
      printf '{"jobs":[%s]}\n' "$2" > fix/jobs-22.json
    }
    VERIFY_UP='{"name":"verify","status":"in_progress"}'
    PREPARE_UP='{"name":"prepare","status":"in_progress"},{"name":"verify","status":"queued"}'
    INSTALL_UP='{"name":"install","status":"in_progress"}'

    # try <script> <asker> -> sets rc and got
    try() {
      set +e
      got=$(FIX=$PWD/fix bash "$1" "$2" 2>err)
      rc=$?
      set -e
    }
    # run <name> <script> <asker> <want-rc> <want-output-prefix>
    verdict() {
      try "$2" "$3"
      [ "$rc" = "$4" ] || return 1
      case $got in "$5"*) ;; *) return 1 ;; esac
    }
    run() {
      if verdict "$@"; then echo "ok  $1"; else
        echo "FAILED  $1: exit $rc, output '$got'" >&2; cat err >&2; exit 1
      fi
    }
    red() {
      name=$1; shift
      if verdict "$@"; then echo "FAILED  $name: broken copy was not caught" >&2; exit 1; fi
      echo "ok  $name"
    }

    fixture "$EDGE" "$VERIFY_UP"
    run install-vs-verify "$script" install 1 "busy: omarchy-edge.yml run 11 job verify"
    fixture "$EDGE" "$PREPARE_UP"
    run install-vs-prepare "$script" install 0 free
    fixture "$INST" "$INSTALL_UP"
    run edge-vs-install "$script" edge 1 "busy: install-check.yml run 22 job install"
    fixture "$SELF" "$INSTALL_UP"
    run edge-vs-own-run "$script" edge 0 free
    fixture "" ""
    run nothing-running "$script" install 0 free
    fixture "$EDGE" "$VERIFY_UP"; touch fix/fail
    run api-fails "$script" install 2 ""

    # Break 1: any job state counts. Must misreport the not-yet-started verify.
    sed 's/ and \.status == "in_progress"//' "$script" > any-state.sh
    if cmp -s "$script" any-state.sh; then echo "break 1 did not land" >&2; exit 1; fi
    fixture "$EDGE" "$PREPARE_UP"
    red any-state-is-caught any-state.sh install 0 free
    # Break 2: a failed call read as an empty list. Must misreport as free.
    sed "s/|| unknown \"run list failed\"/|| runs='{\"workflow_runs\":[]}'/" "$script" > fail-open.sh
    if cmp -s "$script" fail-open.sh; then echo "break 2 did not land" >&2; exit 1; fi
    fixture "$EDGE" "$VERIFY_UP"; touch fix/fail
    red fail-open-is-caught fail-open.sh install 2 ""

    touch $out
  ''
