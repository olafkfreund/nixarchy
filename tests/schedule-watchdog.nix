# .github/scripts/schedule-watchdog.sh against a stubbed gh and a fixed clock
# (#1942), plus its job table against .github/workflows/.
#
# The interface this check holds the script to:
#
#   bash schedule-watchdog.sh              decide every row, and dispatch
#   bash schedule-watchdog.sh --dry-run    print the decisions; no dispatch, no
#                                          marker, no notification
#   bash schedule-watchdog.sh --table      print the table and exit 0, calling
#                                          nothing: one row per line, in table
#                                          order, `workflow<TAB>cron<TAB>input`,
#                                          input `-` when the row has none
#
#   NOW           epoch seconds (default: date -u +%s)
#   GH            the gh executable (default: gh)
#   STATE         stands in for XDG_STATE_HOME; markers go under
#                 $STATE/schedule-watchdog/
#   VM_HOST_FREE  run as `bash "$VM_HOST_FREE" install|edge`; anything on stdout
#                 but `free` leaves nightly alone (default: vm-host-free.sh
#                 beside the script). It needs GITHUB_REPOSITORY set.
#
# gh is called exactly so, and the script filters the JSON itself (including
# head_branch):
#   api repos/olafkfreund/nixarchy/actions/workflows/<file>/runs?branch=main&per_page=50
#   api repos/olafkfreund/nixarchy/actions/runs/<id>/jobs
#   workflow run <file> --ref main [-f job=<input>]     with GH_REPO set
#
# `notify-send` is taken from PATH, once per tick that dispatched; it fails
# here, and that must not fail the tick. --dry-run's stdout names every row's
# workflow, and its input, on one line.
{ pkgs, ... }:
let
  gh = pkgs.writeShellScript "gh-stub" ''
    base=repos/olafkfreund/nixarchy/actions
    if [ "$1 $2" = "workflow run" ] && [ "$GH_REPO" = olafkfreund/nixarchy ]; then
      shift 2
      echo "$*" >> "$FIX/dispatched"
      exit 0
    fi
    if [ "$#" = 2 ] && [ "$1" = api ]; then
      case "$2" in
        "$base/workflows/"*"/runs?branch=main&per_page=50")
          wf=''${2#"$base/workflows/"}
          wf=''${wf%%/*}
          echo "$wf" >> "$FIX/reads"
          [ ! -e "$FIX/fail/$wf" ] || exit 1
          # runs2 answers the second and later reads of a tick.
          if [ -e "$FIX/runs2/$wf.json" ] && [ "$(grep -cxF "$wf" "$FIX/reads")" -gt 1 ]; then
            exec cat "$FIX/runs2/$wf.json"
          fi
          exec cat "$FIX/runs/$wf.json"
          ;;
        "$base/runs/"*"/jobs")
          id=''${2#"$base/runs/"}
          exec cat "$FIX/jobs/''${id%/jobs}.json"
          ;;
      esac
    fi
    echo "gh $* (GH_REPO=$GH_REPO)" >> "$FIX/unexpected"
    exit 1
  '';
  # Not executable on its own terms: the script runs it with bash.
  vmHostFree = pkgs.writeShellScript "vm-host-free-stub" ''
    case "$1" in
      install | edge) ;;
      *) echo "vm-host-free $*" >> "$FIX/unexpected"; exit 2 ;;
    esac
    [ "$GITHUB_REPOSITORY" = olafkfreund/nixarchy ] || { echo "vm-host-free: GITHUB_REPOSITORY unset" >> "$FIX/unexpected"; exit 2; }
    case "$(cat "$FIX/vm-$1" 2>/dev/null)" in
      busy) echo "busy: stub run 1 job x"; exit 1 ;;
      unknown) exit 2 ;;
      *) echo free ;;
    esac
  '';
  notify = pkgs.writeShellScriptBin "notify-send" ''
    echo called >> "$FIX/notified"
    exit 1
  '';
in
pkgs.runCommand "nixarchy-schedule-watchdog"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.yq-go
      notify
    ];
  }
  ''
    set +e # the checks below read exit statuses on purpose
    S=${../.github/scripts}/schedule-watchdog.sh
    W=${../.github/workflows}
    export HOME=$TMPDIR GH=${gh} VM_HOST_FREE=${vmHostFree} TZDIR=${pkgs.tzdata}/share/zoneinfo
    fail=0
    bad() { echo "FAIL $*" >&2; fail=1; }

    # ---- fixtures
    run() { # id event branch status conclusion|- "date (UTC)"
      jq -nc --argjson id "$1" --arg e "$2" --arg b "$3" --arg s "$4" --arg c "$5" \
        --arg t "$(date -u -d "$6" +%Y-%m-%dT%H:%M:%SZ)" \
        '{id: $id, event: $e, head_branch: $b, status: $s,
          conclusion: (if $c == "-" then null else $c end), created_at: $t}'
    }
    ok() { run 2 schedule main completed success "$1"; }
    runs() { # workflow [run...]
      wf=$1; shift
      printf '%s\n' "$@" | jq -s '{workflow_runs: .}' > "$FIX/runs/$wf.json"
    }
    jobs() { # run-id name=conclusion...
      id=$1; shift
      jq -n '{jobs: [$ARGS.positional[] | split("=") | {name: .[0], status: "completed", conclusion: .[1]}]}' \
        --args "$@" > "$FIX/jobs/$id.json"
    }
    clock() { export NOW=$(date -u -d "$1" +%s); }
    # A tick at "date (UTC)" where every row is already done; each case takes
    # away the thing it is about.
    setup() {
      clock "$1"
      export FIX=$(mktemp -d)
      export STATE=$FIX/state
      mkdir -p "$FIX/runs" "$FIX/runs2" "$FIX/jobs" "$FIX/fail" "$STATE"
      : > "$FIX/notified"
      for f in nightly omarchy update review omarchy-edge flake-update build weekly; do
        runs $f.yml "$(run 1 schedule main completed success "@$((NOW - 60))")"
      done
      jobs 1 propose=success stable-session=success install-stock-iso=success
    }
    weekly_skipped() { # job...: the covering weekly run skipped these
      for j in "$@"; do
        jq --arg j "$j" '(.jobs[] | select(.name == $j)).conclusion = "skipped"' "$FIX/jobs/1.json" > "$FIX/j"
        cp "$FIX/j" "$FIX/jobs/1.json"
      done
    }
    check() { # name, wanted dispatch lines, ok|error|any, [script args]
      name="$TZ: $1" want=$2 wantrc=$3
      shift 3
      : > "$FIX/dispatched"; : > "$FIX/unexpected"; : > "$FIX/reads"
      bash "$S" "$@" > "$FIX/stdout" 2> "$FIX/stderr"
      rc=$?
      got=ok; [ $rc = 0 ] || got=error
      if [ "$wantrc" != any ] && [ "$got" != "$wantrc" ]; then bad "$name: wanted $wantrc, exit $rc"; cat "$FIX/stderr" >&2; fi
      if [ "$(cat "$FIX/dispatched")" != "$want" ]; then
        bad "$name: wanted dispatches [$want], got [$(cat "$FIX/dispatched")]"
      fi
      if [ -s "$FIX/unexpected" ]; then bad "$name: unexpected call: $(cat "$FIX/unexpected")"; fi
    }

    FU="flake-update.yml --ref main"
    NI="nightly.yml --ref main"
    RV="review.yml --ref main"
    BU="build.yml --ref main"
    WK="weekly.yml --ref main -f job="
    # 2026-11-22 is a Sunday, 23 a Monday, 26 a Thursday.

    cases() {
      # ---- a missed daily job, and the margin
      setup "2026-11-26 12:00"; check "all done" "" ok
      [ ! -s "$FIX/notified" ] || bad "$TZ: notified with nothing dispatched"
      runs flake-update.yml; check "daily missed" "$FU" ok
      setup "2026-11-26 12:00"
      runs flake-update.yml "$(ok "2026-11-25 07:05")"; check "only yesterday's run" "$FU" ok
      setup "2026-11-26 07:44"; runs flake-update.yml; check "44 minutes" "" ok
      setup "2026-11-26 07:45"; runs flake-update.yml; check "45 minutes" "$FU" ok

      # ---- what counts as the slot's run
      for e in schedule workflow_dispatch; do
        setup "2026-11-26 12:00"
        runs flake-update.yml "$(run 2 $e main completed success "2026-11-26 07:05")"
        check "$e run on main" "" ok
      done
      setup "2026-11-26 12:00"
      runs flake-update.yml "$(run 2 schedule main completed failure "2026-11-26 07:00")"
      check "failed run created at the slot" "" ok
      for row in "pull_request main success" "push main success" \
        "workflow_dispatch topic success" "schedule main cancelled"; do
        read -r e b c <<<"$row"
        setup "2026-11-26 12:00"
        runs flake-update.yml "$(run 2 $e $b completed $c "2026-11-26 07:05")"
        check "does not count: $row" "$FU" ok
      done
      setup "2026-11-24 05:00"
      runs build.yml "$(run 2 push main completed success "2026-11-23 06:30")"
      check "build: a push to main counts" "" ok
      runs build.yml "$(run 2 push topic completed success "2026-11-23 06:30")"
      check "build: a push elsewhere does not" "$BU" ok

      # ---- a run in flight. Created before the slot, so only the status test
      # can stop the dispatch.
      for s in queued waiting requested pending in_progress; do
        setup "2026-11-26 12:00"
        runs flake-update.yml "$(run 2 schedule main $s - "2026-11-25 07:05")"
        check "in flight: $s" "" ok
      done
      setup "2026-11-26 12:00"
      runs flake-update.yml "$(run 2 pull_request topic in_progress - "2026-11-26 11:00")"
      check "in flight on another branch" "$FU" ok
      setup "2026-11-26 12:00"
      runs flake-update.yml
      printf '%s\n' "$(run 2 schedule main queued - "2026-11-26 11:59")" |
        jq -s '{workflow_runs: .}' > "$FIX/runs2/flake-update.yml.json"
      check "run appears before the dispatch" "" ok

      # ---- weekly: the named job must have run
      setup "2026-11-22 12:00"; runs weekly.yml; check "weekly missed" "''${WK}stable-session" ok
      setup "2026-11-22 12:00"; weekly_skipped stable-session
      check "weekly run that skipped the job" "''${WK}stable-session" ok
      setup "2026-11-22 12:00"; weekly_skipped propose install-stock-iso
      check "weekly job ran" "" ok
      setup "2026-11-22 12:00"; jobs 1 stable-session=failure
      check "weekly job ran and failed" "" ok

      # ---- review and propose wait for what they read
      setup "2026-11-26 08:00"; runs review.yml; check "review after its night" "$RV" ok
      for f in nightly omarchy update; do
        setup "2026-11-26 08:00"; runs review.yml; runs $f.yml
        check "review waits: $f missing" "$f.yml --ref main" ok
      done
      setup "2026-11-26 08:00"; runs review.yml
      runs nightly.yml "$(run 2 schedule main in_progress - "2026-11-26 03:05")"
      check "review waits: nightly running" "" ok
      runs nightly.yml "$(ok "2026-11-26 03:05")"
      check "review once nightly finished" "$RV" ok
      setup "2026-11-23 08:00"; weekly_skipped propose
      check "propose after its night" "''${WK}propose" ok
      setup "2026-11-23 08:00"; weekly_skipped propose
      runs nightly.yml "$(run 2 schedule main in_progress - "2026-11-23 03:05")"
      check "propose waits: nightly running" "" ok
      setup "2026-11-23 08:00"; weekly_skipped propose
      runs nightly.yml "$(ok "2026-11-22 03:05")"
      check "propose waits: only last night's nightly" "$NI" ok

      # ---- the 24 h bound, and Sunday into Monday
      setup "2026-11-22 23:59"; weekly_skipped install-stock-iso
      check "before midnight" "''${WK}install-stock-iso" ok
      setup "2026-11-23 00:10"; weekly_skipped install-stock-iso
      check "after midnight, Sunday's slot" "''${WK}install-stock-iso" ok
      setup "2026-11-23 15:01"; weekly_skipped install-stock-iso
      check "Sunday 15:00 slot over 24 h old" "" ok
      setup "2026-11-23 08:59"; weekly_skipped stable-session
      check "Sunday 09:00 slot under 24 h old" "''${WK}stable-session" ok
      setup "2026-11-23 09:01"; weekly_skipped stable-session
      check "Sunday 09:00 slot over 24 h old" "" ok
      setup "2026-11-24 05:59"; runs build.yml; check "Monday build under 24 h old" "$BU" ok
      setup "2026-11-24 06:01"; runs build.yml; check "Monday build over 24 h old" "" ok
      setup "2026-11-22 08:30"; weekly_skipped stable-session
      check "Sunday before 09:00" "" ok

      # ---- hours 08 and 09, and a daily slot read from the next day
      for t in 08:08 08:59 09:08 09:09; do
        setup "2026-11-26 $t"; runs flake-update.yml; check "daily at $t" "$FU" ok
      done
      setup "2026-11-26 00:10"; runs flake-update.yml "$(ok "2026-11-25 08:00")"
      check "midnight: yesterday's slot done" "" ok
      runs flake-update.yml "$(ok "2026-11-25 06:00")"
      check "midnight: yesterday's slot missed" "$FU" ok

      # ---- one dispatch per slot
      setup "2026-11-26 12:00"; runs flake-update.yml
      check "marker: first tick" "$FU" ok
      [ -n "$(ls -A "$STATE/schedule-watchdog" 2>/dev/null)" ] || bad "$TZ: no marker under STATE/schedule-watchdog"
      check "marker: same slot again" "" ok
      clock "2026-11-27 12:00"
      for f in nightly omarchy update review omarchy-edge build weekly; do
        runs $f.yml "$(run 1 schedule main completed success "@$((NOW - 60))")"
      done
      check "marker: next slot" "$FU" ok
      setup "2026-11-22 12:00"; weekly_skipped stable-session
      check "marker: weekly first tick" "''${WK}stable-session" ok
      clock "2026-11-22 16:00"; weekly_skipped install-stock-iso
      runs weekly.yml "$(run 1 schedule main completed success "@$((NOW - 60))")"
      check "marker: per weekly input" "''${WK}install-stock-iso" ok

      # ---- nightly waits for the VM host
      for h in install:busy edge:busy install:unknown edge:unknown; do
        setup "2026-11-26 12:00"; runs nightly.yml; runs flake-update.yml
        echo "''${h#*:}" > "$FIX/vm-''${h%:*}"
        # The spec does not say how an unknown host should exit.
        rcw=ok; [ "''${h#*:}" = busy ] || rcw=any
        check "vm host $h" "$FU" $rcw
        rm "$FIX/vm-''${h%:*}"
        runs flake-update.yml "$(ok "2026-11-26 07:05")"
        check "vm host free after $h" "$NI" ok
      done

      # ---- a failed read skips that workflow only
      setup "2026-11-26 12:00"
      for f in omarchy update review flake-update; do runs $f.yml; done
      touch "$FIX/fail/omarchy.yml"
      check "one run list unreadable" "$(printf '%s\n' "update.yml --ref main" "$FU")" error
      setup "2026-11-22 12:00"; rm "$FIX/jobs/1.json"; runs flake-update.yml
      # 12:00 Sunday: flake-update's slot is today's 07:00.
      check "job list unreadable" "$FU" error

      # ---- everything missed on a Monday: table order, one notification
      setup "2026-11-23 12:00"
      for f in nightly omarchy update review omarchy-edge flake-update build weekly; do runs $f.yml; done
      all=$(printf '%s\n' "$NI" "omarchy.yml --ref main" "update.yml --ref main" \
        "omarchy-edge.yml --ref main" "$FU" "$BU" "''${WK}install-stock-iso")
      check "dry run" "" ok --dry-run
      while IFS=$'\t' read -r wf cron input; do
        [ "$input" != - ] || input=""
        awk -v w="$wf" -v i="$input" 'index($0, w) && index($0, i) { f = 1 } END { exit !f }' "$FIX/stdout" ||
          bad "$TZ: dry run prints no decision for $wf $input"
      done <<<"$table"
      [ ! -s "$FIX/notified" ] || bad "$TZ: dry run notified"
      check "all missed, after a dry run" "$all" ok
      [ "$(grep -c . "$FIX/notified")" = 1 ] || bad "$TZ: wanted one notification, got $(grep -c . "$FIX/notified")"
    }

    table=$(bash "$S" --table) || bad "--table: non-zero"
    for TZ in UTC America/New_York; do
      export TZ
      cases
    done
    export TZ=America/New_York
    [ "$(date -d @0 +%H)" = 19 ] || bad "TZ has no effect, so the second pass proved nothing"
    export TZ=UTC

    # ---- the table against the workflow files
    have=$(for f in "$W"/*.yml; do
      n=$(basename "$f") yq -r '.on.schedule[].cron | [strenv(n), .] | @tsv' "$f" || echo "unreadable $f"
    done | sort)
    rows=$(cut -f1,2 <<<"$table" | sort)
    while IFS= read -r l; do
      [ -z "$l" ] || bad "table: no row for the cron in the workflow: $l"
    done <<<"$(comm -23 <(echo "$have") <(echo "$rows"))"
    while IFS= read -r l; do
      [ -z "$l" ] || bad "table: no such cron in the workflow, row: $l"
    done <<<"$(comm -13 <(echo "$have") <(echo "$rows"))"
    while IFS=$'\t' read -r wf cron input; do
      [ -n "$wf" ] || continue
      row="$wf '$cron' $input"
      [ "$(yq -r '.on | has("workflow_dispatch")' "$W/$wf")" = true ] || bad "row $row: no workflow_dispatch"
      [ "$input" != - ] || continue
      options=$(yq -r '.on.workflow_dispatch.inputs.job.options[]' "$W/$wf")
      grep -qxF -- "$input" <<<"$options" || bad "row $row: input is not a job option"
      cond=$(j=$input yq -r '.jobs[strenv(j)].if' "$W/$wf")
      [[ $cond == *"github.event.schedule == '$cron'"* ]] || bad "row $row: the job's if does not name the cron"
      [[ $cond == *"inputs.job == '$input'"* ]] || bad "row $row: the job's if does not name the input"
    done <<<"$table"

    [ "$fail" = 0 ] || exit 1
    touch $out
  ''
