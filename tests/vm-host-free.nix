{ pkgs, ... }:
# Install and edge's VM checks never share p620 (#1365, #1524). The real script
# against a stub `gh` serving fixture JSON, the step-name guard against
# install-check.yml, and five broken copies that must be caught.
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
    workflow = ../.github/workflows/install-check.yml;
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
    INSTALL_WAITING='{"name":"install","status":"in_progress","steps":[{"name":"Run actions/checkout@v5","status":"completed"},{"name":"Wait for edge'"'"'s VM checks to leave this host","status":"in_progress"},{"name":"Install onto a blank disk, and into free space beside a neighbour","status":"queued"}]}'
    INSTALL_BOOTING='{"name":"install","status":"in_progress","steps":[{"name":"Run actions/checkout@v5","status":"completed"},{"name":"Wait for edge'"'"'s VM checks to leave this host","status":"completed"},{"name":"Install onto a blank disk, and into free space beside a neighbour","status":"in_progress"}]}'
    INSTALL_BEFORE_WAIT='{"name":"install","status":"in_progress","steps":[{"name":"Run actions/checkout@v5","status":"in_progress"},{"name":"Wait for edge'"'"'s VM checks to leave this host","status":"queued"},{"name":"Install onto a blank disk, and into free space beside a neighbour","status":"queued"}]}'
    INSTALL_BETWEEN='{"name":"install","status":"in_progress","steps":[{"name":"Run actions/checkout@v5","status":"completed"},{"name":"Wait for edge'"'"'s VM checks to leave this host","status":"completed"},{"name":"Install onto a blank disk, and into free space beside a neighbour","status":"queued"}]}'
    VERIFY_WAITING='{"name":"verify","status":"in_progress","steps":[{"name":"Wait for edge'"'"'s VM checks to leave this host","status":"in_progress"}]}'

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
    fixture "$INST" "$INSTALL_WAITING"
    run edge-vs-waiting-install "$script" edge 0 free
    fixture "$INST" "$INSTALL_BOOTING"
    run edge-vs-booting-install "$script" edge 1 "busy: install-check.yml run 22 job install"
    fixture "$INST" "$INSTALL_BEFORE_WAIT"
    run edge-vs-install-before-wait "$script" edge 1 busy
    fixture "$INST" "$INSTALL_BETWEEN"
    run edge-vs-install-between-steps "$script" edge 1 busy
    fixture "$EDGE" "$VERIFY_WAITING"
    run install-vs-verify-with-wait-named-step "$script" install 1 "busy: omarchy-edge.yml run 11 job verify"
    rm -rf fix; mkdir fix
    printf '{"workflow_runs":[%s,%s]}\n' "$EDGE" "$INST" > fix/runs.json
    printf '{"jobs":[%s]}\n' "$VERIFY_UP" > fix/jobs-11.json
    printf '{"jobs":[%s]}\n' "$INSTALL_WAITING" > fix/jobs-22.json
    run standoff-install "$script" install 1 "busy: omarchy-edge.yml run 11 job verify"
    run standoff-edge "$script" edge 0 free

    guard() {
      name=$(sed -n 's/.*edge) .* wait="\([^"]*\)".*/\1/p' "$script")
      [ -n "$name" ] || { echo "FAILED  guard: wait step name empty in $script" >&2; return 1; }
      grep -qF -- "- name: $name" "$1" || {
        echo "FAILED  guard: step '$name' missing from $1" >&2
        return 1
      }
    }
    guard "$workflow"
    echo "ok  step-name-guard"

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
    # Break 3: no step exemption in edge mode. Must misreport waiting install as busy.
    sed 's/wait="Wait for edge[^"]*"/wait=""/' "$script" > any.sh
    if cmp -s "$script" any.sh; then echo "break 3 did not land" >&2; exit 1; fi
    fixture "$INST" "$INSTALL_WAITING"
    red no-exemption-is-caught any.sh edge 0 free
    # Break 4: a queued wait step also exempts the job. Must misreport before-wait as free.
    sed 's/and \.status == "in_progress")\]/and .status != "completed")]/' "$script" > queued-wait.sh
    if cmp -s "$script" queued-wait.sh; then echo "break 4 did not land" >&2; exit 1; fi
    fixture "$INST" "$INSTALL_BEFORE_WAIT"
    red queued-wait-exempt-is-caught queued-wait.sh edge 1 busy
    # Break 5: renaming the step in install-check.yml is caught by the guard.
    sed "s/- name: Wait for edge's VM checks to leave this host/- name: Wait for edge/" "$workflow" > renamed-wf.yml
    if cmp -s "$workflow" renamed-wf.yml; then echo "break 5 did not land" >&2; exit 1; fi
    if guard renamed-wf.yml 2>/dev/null; then
      echo "FAILED  step-rename-is-caught: broken workflow was not caught" >&2
      exit 1
    fi
    echo "ok  step-rename-is-caught"

    touch $out
  ''
