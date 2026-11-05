{ pkgs, ... }:
# Edge's report says what happened (#1602): the real edge-report.sh against a
# stub `gh` serving fixture JSON, and the real edge-build.sh in a scratch repo
# with stubbed nix and sub-scripts. Every case is a row of the plan's outcome
# table or a rule of the held issue, plus the workflow's report step naming what the script reads.
pkgs.runCommand "edge-report"
  {
    workflowFile = ../.github/workflows/omarchy-edge.yml;
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gawk
      git
      gnugrep
      gnused
      jq
    ];
  }
  ''
    export HOME=$PWD/home
    export XDG_CONFIG_HOME=$HOME/.config
    mkdir -p "$HOME"
    git config --global user.name test
    git config --global user.email test@example.invalid
    git config --global init.defaultBranch main
    report=${../.github/scripts/edge-report.sh}
    workflow=$workflowFile
    fails=0
    NOW=1800000000
    NOT_PUB='The Omarchy edge channel is not publishing'
    HELD_T='Omarchy quattro is held back'

    mkdir bin
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[ ! -e "$FIX/fail" ] || exit 1' \
      'if [ -e "$FIX/fail-list" ] && [ "$1 $2" = "issue list" ]; then exit 1; fi' \
      'echo "CALL $*" >> "$FIX/calls"' \
      'case "$1 $2" in' \
      '  "issue list") l=; while [ $# -gt 0 ]; do if [ "$1" = --label ]; then l=$2; fi; shift; done' \
      '    if [ -e "$FIX/list-$l.json" ]; then cat "$FIX/list-$l.json"; else echo "[]"; fi ;;' \
      '  "issue view") cat "$FIX/view.json" ;;' \
      '  "api "*) [ ! -e "$FIX/edge-sha" ] || cat "$FIX/edge-sha" ;;' \
      'esac' \
      'exit 0' > bin/gh
    chmod +x bin/gh

    fail() { echo "  FAILED  $*" >&2; fails=$((fails + 1)); }
    has() { grep -qF -- "$2" fix/calls || fail "$1: expected '$2'"; }
    hasre() { grep -qE -- "$2" fix/calls || fail "$1: expected /$2/"; }
    hasnt() { if grep -qF -- "$2" fix/calls; then fail "$1: unexpected '$2'"; fi; }
    ok0() { [ "$rc" = 0 ] || fail "$1: exit $rc: $(cat err)"; }
    ncomments() { grep -c 'CALL issue comment' fix/calls || true; }

    reset() { rm -rf fix; mkdir fix; }
    list_nopub() { printf '[{"number":7,"title":"%s"}]\n' "$NOT_PUB" > fix/list-omarchy-edge.json; }
    list_held() { printf '[{"number":9,"title":"%s"}]\n' "$HELD_T" > fix/list-omarchy-edge-held.json; }
    iso() { date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }
    # view <body> <comments-json> <age-seconds>
    view() { jq -n --arg b "$1" --argjson c "$2" --arg t "$(iso "$3")" '{body:$b,comments:$c,createdAt:$t}' > fix/view.json; }
    go() {
      : > fix/calls
      set +e
      env -i PATH="$PWD/bin:$PATH" FIX="$PWD/fix" GH_REPO=o/r RUN_URL=https://x/run/1 \
        EDGE_REPORT_NOW="$NOW" "$@" bash "$report" > out 2> err
      rc=$?
      set -e
    }
    HELD="HELD_SHA=abcdef0123456"

    # --- the five outcomes ---
    reset; list_nopub; list_held
    go PROMOTED=true NEWEST=true
    ok0 promoted-newest
    has promoted-newest 'issue close 7 --comment edge was promoted by https://x/run/1'
    has promoted-newest 'issue close 9 --comment quattro is adopted as of https://x/run/1'

    for n in false ""; do
      go PROMOTED=true NEWEST=$n
      ok0 "promoted-newest-$n"
      has "promoted-newest-$n" 'issue close 7 --comment edge was promoted by'
      hasnt "promoted-newest-$n" 'issue close 9'
      hasnt "promoted-newest-$n" 'issue create'
    done

    # fallback: "not publishing" closes, "held back" is filed (none open yet)
    reset; list_nopub
    go PROMOTED=true FALLBACK=true NEWEST=true HELD_BY=bin-ledger $HELD
    ok0 fallback-new
    has fallback-new 'issue close 7 --comment edge was promoted by'
    has fallback-new 'label create omarchy-edge-held --force'
    hasre fallback-new 'issue create --label omarchy-edge-held --milestone Keeping the lights on --title Omarchy quattro is held back --body held-sig: abcdef0: bin-ledger$'
    has fallback-new 'needs a classification row'
    hasnt fallback-new 'label create omarchy-edge --force'
    hasnt fallback-new 'issue comment 7'
    hasnt fallback-new 'issue close 9'

    reset; list_nopub; list_held
    go PREPARE=success SKIP=true
    ok0 skip
    has skip 'issue close 7 --comment edge is current as of https://x/run/1'
    has skip 'issue close 9 --comment quattro is adopted as of https://x/run/1'

    reset; list_nopub; list_held
    view "edge-sig: prepare: omarchy" '[]' 100
    go PREPARE=failure PREPARE_FAILED=omarchy
    ok0 other
    hasnt other 'label create omarchy-edge-held'
    hasnt other 'issue close'
    hasnt other 'issue comment 9'

    reset
    go PREPARE=failure PREPARE_FAILED=omarchy PREPARE_DIGEST='line one'
    ok0 other-new
    hasre other-new 'issue create --label omarchy-edge --milestone Keeping the lights on --title The Omarchy edge channel is not publishing --body edge-sig: prepare: omarchy$'
    has other-new '```text'
    has other-new 'line one'

    # a cancel after the push: the remote already holds the candidate
    reset; list_nopub
    printf 'abc\n' > fix/edge-sha
    go PREPARE=success WAIT=success VERIFY=cancelled CANDIDATE=abc
    ok0 remote-promoted
    has remote-promoted 'issue close 7 --comment edge was promoted by'

    # --- the held issue ---
    reset; list_held
    view "held-sig: abcdef0: bin-ledger" '[]' 100
    go PROMOTED=true FALLBACK=true HELD_BY=bin-ledger $HELD
    ok0 held-same
    [ "$(ncomments)" = 0 ] || fail 'held-same: commented on an unchanged signature'

    reset; list_held
    view "held-sig: abcdef0: bin-ledger" '[]' 100
    go PROMOTED=true FALLBACK=true HELD_BY=skill-parity $HELD
    ok0 held-changed
    has held-changed 'issue comment 9 --body held-sig: abcdef0: skill-parity'

    reset; list_held
    view "held-sig: abcdef0: bin-ledger" '[{"body":"someone looked at this"}]' 100
    go PROMOTED=true FALLBACK=true HELD_BY=bin-ledger $HELD
    ok0 held-human-comment
    [ "$(ncomments)" = 0 ] || fail 'held-human-comment: a person comment defeated dedupe'

    reset; list_nopub
    view "edge-sig: prepare: omarchy" '[{"body":"edge-sig: prepare: omarchy\n\nRun: x"},{"body":"is this known?"}]' 100
    go PREPARE=failure PREPARE_FAILED=omarchy
    ok0 nopub-human-comment
    [ "$(ncomments)" = 0 ] || fail 'nopub-human-comment: a person comment defeated dedupe'

    # wording
    reset
    go PROMOTED=true FALLBACK=true HELD_BY='bin-ledger skill-parity' $HELD
    ok0 wording-listed
    has wording-listed 'needs a classification row'
    reset
    go PROMOTED=true FALLBACK=true HELD_BY='bin-ledger options-system' $HELD
    ok0 wording-unlisted
    has wording-unlisted 'upstream candidate failed; investigate'
    hasnt wording-unlisted 'needs a classification row'
    reset
    go PROMOTED=true FALLBACK=true HELD_BY=etc-sysctl $HELD
    ok0 wording-etc-sysctl
    has wording-etc-sysctl 'a recorded sysctl decision'
    reset
    go PROMOTED=true FALLBACK=true $HELD
    ok0 wording-none
    has wording-none 'upstream candidate failed; investigate'
    hasnt wording-none 'needs a classification row'
    hasre wording-none 'held-sig: abcdef0: unknown$'

    # digest by outcome
    reset
    go PROMOTED=true FALLBACK=true HELD_BY=bin-ledger $HELD HELD_DIGEST='held digest' PREPARE_DIGEST='prepare digest'
    ok0 digest-held
    has digest-held 'held digest'
    hasnt digest-held 'prepare digest'
    reset
    go PREPARE=success WAIT=success VERIFY=failure VERIFY_FAILED=options-system VERIFY_DIGEST='verify digest' PREPARE_DIGEST='prepare digest'
    ok0 digest-verify
    hasre digest-verify 'edge-sig: verify: options-system$'
    has digest-verify 'verify digest'
    hasnt digest-verify 'prepare digest'

    # escalation: once, after 20 h, independent of the signature
    reset; list_held
    view "held-sig: abcdef0: bin-ledger" '[]' 71999
    go PROMOTED=true FALLBACK=true HELD_BY=bin-ledger $HELD
    ok0 escalate-early
    hasnt escalate-early 'held-escalated:'
    view "held-sig: abcdef0: bin-ledger" '[]' 72001
    go PROMOTED=true FALLBACK=true HELD_BY=bin-ledger $HELD
    ok0 escalate-late
    has escalate-late 'issue comment 9 --body held-escalated:'
    [ "$(ncomments)" = 1 ] || fail 'escalate-late: expected exactly the escalation'
    view "held-sig: abcdef0: bin-ledger" '[{"body":"held-escalated: quattro has been held"}]' 80000
    go PROMOTED=true FALLBACK=true HELD_BY=bin-ledger $HELD
    ok0 escalate-again-same
    [ "$(ncomments)" = 0 ] || fail 'escalate-again-same: duplicated a comment'
    go PROMOTED=true FALLBACK=true HELD_BY=skill-parity $HELD
    ok0 escalate-again-changed
    hasnt escalate-again-changed 'held-escalated:'
    [ "$(ncomments)" = 1 ] || fail 'escalate-again-changed: expected one signature comment'
    has escalate-again-changed 'issue comment 9 --body held-sig: abcdef0: skill-parity'

    # signatures
    reset
    go PREPARE=failure PREPARE_FAILED=omarchy BUILD2=failure HELD_BY=omarchy
    ok0 sig-both-red
    hasre sig-both-red 'edge-sig: prepare: fallback also red: omarchy; quattro red: omarchy$'
    go PREPARE=failure PREPARE_FAILED=omarchy BUILD2=success HELD_BY=skill-parity
    hasre sig-held-differs 'edge-sig: prepare: omarchy; quattro red: skill-parity$'
    go PREPARE=failure PREPARE_FAILED=omarchy HELD_BY=omarchy
    hasre sig-held-same 'edge-sig: prepare: omarchy$'
    go PREPARE=success WAIT=success VERIFY=cancelled VERIFY_FAILED=options-a
    hasre sig-cancel-named 'edge-sig: verify: options-a; timed out$'
    go PREPARE=success WAIT=success VERIFY=cancelled
    hasre sig-cancel-bare 'edge-sig: verify: timed out$'
    go PREPARE=success WAIT=cancelled
    hasre sig-wait-cancel 'edge-sig: wait-idle: timed out$'
    go PREPARE=cancelled
    hasre sig-prepare-cancel 'edge-sig: prepare: timed out$'

    # Only the listing fails: $(...) clears set -e, so this reads as "no open issue"
    # unless find_issue passes the failure on. A promotion makes no other gh call.
    reset; touch fix/fail-list
    rc=0; env PROMOTED=true NEWEST=true RUN_URL=u GH_REPO=o/r EDGE_REPORT_NOW=$NOW bash "$report" >/dev/null 2>&1 || rc=$?
    [ "$rc" != 0 ] || fail 'gh-list-fails: a failed listing read as no open issue'

    # a gh failure fails the script
    reset; touch fix/fail
    go PREPARE=failure PREPARE_FAILED=omarchy
    [ "$rc" != 0 ] || fail 'gh-fails: the script exited 0'

    # --- edge-build.sh, in a scratch repo ---
    rootblk() { printf "error: Cannot build '/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-%s.drv'.\n       Reason: builder failed with exit code 1.\n" "$1"; }
    mkb() {
      local b=$PWD/b-$1
      rm -rf "$b" "t-$1"
      mkdir -p "$b/.github/scripts" "$b/bin" "t-$1"
      cp ${../.github/scripts/edge-build.sh} "$b/.github/scripts/edge-build.sh"
      cp ${../.github/scripts/failure-digest.sh} "$b/.github/scripts/failure-digest.sh"
      printf '%s\n' '#!${pkgs.bash}/bin/bash' \
        'case "$STUB_GEN" in list) exit 1 ;; short) printf "a\nb\n" ;; *) printf "a\nb\nc\nd\ne\n" ;; esac' \
        > "$b/.github/scripts/generated-checks.sh"
      printf '%s\n' '#!${pkgs.bash}/bin/bash' \
        '[ -z "$STUB_GEN_LOG" ] || { cat "$STUB_GEN_LOG" >> "$RUNNER_TEMP/build.log"; exit 1; }' \
        > "$b/.github/scripts/build-unless-proven.sh"
      printf '%s\n' '#!${pkgs.bash}/bin/bash' \
        'case "$STUB_README" in refuse) echo edited >> README.md; exit 1 ;; ok) echo edited >> README.md ;; esac' \
        > "$b/.github/scripts/readme-counts.sh"
      printf '%s\n' '#!${pkgs.bash}/bin/bash' \
        '[ -z "$STUB_OMARCHY_LOG" ] || { cat "$STUB_OMARCHY_LOG" >> "$RUNNER_TEMP/build.log"; exit 1; }' \
        > "$b/bin/nix"
      chmod +x "$b"/.github/scripts/*.sh "$b/bin/nix"
      # the sandbox has no /usr/bin/env, which the real scripts name
      patchShebangs "$b/.github/scripts"
      echo original > "$b/README.md"
      (cd "$b" && git init -q && git add -A && git commit -q -m base)
    }
    # runb <name> [VAR=val ...]; leaves rc and t-<name>/out
    runb() {
      local n=$1 b
      shift
      b=$PWD/b-$n
      : > "t-$n/out"
      set +e
      (cd "$b" && env PATH="$b/bin:$PATH" RUNNER_TEMP="$PWD/../t-$n" GITHUB_OUTPUT="$PWD/../t-$n/out" \
        "$@" bash .github/scripts/edge-build.sh) > "t-$n/stdout" 2>&1
      rc=$?
      set -e
    }
    failed_is() {
      grep -qxF -- "failed=$2" "t-$1/out" && return 0
      fail "$1: wanted failed=$2, got '$(cat "t-$1/out")'"
      sed 's/^/    | /' "t-$1/build.log" >&2
    }

    rootblk nixarchy-bin-ledger > gen-root.log
    rootblk nixarchy-stale-scripts >> gen-root.log
    printf 'error: attribute missing\n' > gen-noroot.log
    { rootblk omarchy-edge-1.0; rootblk nixarchy-bin-ledger; } > gen-omarchy-and-root.log
    rootblk omarchy-edge-1.0 > omarchy.log

    mkb root; runb root STUB_GEN_LOG=$PWD/gen-root.log
    [ "$rc" != 0 ] || fail 'build-root: exit 0'
    failed_is root 'bin-ledger stale-scripts'
    mkb noroot; runb noroot STUB_GEN_LOG=$PWD/gen-noroot.log
    failed_is noroot 'generated-checks'
    mkb twice; runb twice STUB_OMARCHY_LOG=$PWD/omarchy.log STUB_GEN_LOG=$PWD/gen-omarchy-and-root.log
    failed_is twice 'omarchy bin-ledger'
    mkb list; runb list STUB_GEN=list
    failed_is list 'generated-checks-list'
    mkb short; runb short STUB_GEN=short
    failed_is short 'generated-checks-list'
    mkb omarchy-list; runb omarchy-list STUB_OMARCHY_LOG=$PWD/omarchy.log STUB_GEN=list
    failed_is omarchy-list 'omarchy generated-checks-list'

    mkb readme-refuse; runb readme-refuse STUB_README=refuse
    [ "$rc" != 0 ] || fail 'readme-refuse: exit 0'
    failed_is readme-refuse 'readme-counts'
    [ "$(cat b-readme-refuse/README.md)" = original ] || fail 'readme-refuse: README.md was not restored'
    mkb readme-ok; runb readme-ok STUB_README=ok
    [ "$rc" = 0 ] || fail "readme-ok: exit $rc"
    failed_is readme-ok ""
    grep -qx edited b-readme-ok/README.md || fail 'readme-ok: the edit was lost'

    # --- the workflow hands the script what it reads ---
    # Only asserted by name: the workflow's first real run is after merge.
    step=$(sed -n '/- name: Update the omarchy-edge issues/,$p' "$workflow")
    [ -n "$step" ] || fail 'wiring: the report step is gone from the workflow'
    vars=$(grep -oE '[A-Z][A-Z0-9_]*=\$\{[A-Z0-9_]*:-' "$report" | cut -d= -f1)
    [ "$(echo "$vars" | wc -l)" -ge 15 ] || fail "wiring: found too few variables in the script: $vars"
    for v in $vars RUN_URL GH_REPO GH_TOKEN; do
      grep -qE "^ +$v: [$][{][{]" <<<"$step" || fail "wiring: the report step does not set $v"
    done

    echo
    if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
    echo 'edge-report: all assertions hold'
    touch $out
  ''
