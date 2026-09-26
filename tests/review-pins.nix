{ pkgs, ... }:
# The half of `nix run .#review` that can be checked without a network.
#
# review.sh answers "is anything we pin behind upstream", and the way it rots
# is not the comparison -- it is the reading. Someone restructures a
# `version = "x"` line, or renames a file under pkgs/apps, and every probe for
# that package quietly reports nothing at all. A watcher that has stopped
# seeing one of its subjects looks exactly like a watcher with nothing to
# report, which is the failure mode this whole change exists to end.
#
# So this asserts on --list-pins: no network, no gh, no GitHub. Every pin the
# script claims to watch must still be findable, and must still yield a
# version that looks like one.
let
  # The pins review.sh is expected to see. Hardcoded here rather than derived
  # from the script, because a list derived from the thing it checks agrees
  # with it by construction and proves nothing.
  expected = [
    "once"
    "hey-cli"
    "omacalc"
    "omacut"
    "omawrite"
    "ttfx"
  ];
in
pkgs.runCommand "nixarchy-review-pins"
  {
    nativeBuildInputs = with pkgs; [
      bash
      gnused
      coreutils
      # flake-pins.py reads flake.lock; review.sh --list-pins does not need it,
      # but they are checked together.
      python3
    ];
  }
  ''
    # review.sh reads the pin files relative to the repository root, the way
    # it does when someone runs it at a prompt.
    mkdir -p pkgs
    cp -r ${../pkgs/apps} pkgs/apps

    bash ${../pkgs/review.sh} --list-pins > pins.txt || {
      echo "review.sh --list-pins failed outright" >&2
      exit 1
    }

    fail=0

    for name in ${builtins.concatStringsSep " " expected}; do
      line=$(grep -E "^$name	" pins.txt || true)
      if [ -z "$line" ]; then
        echo "review: $name is no longer in the pin list" >&2
        echo "  the script watches it, or it does not -- silence is the bug." >&2
        fail=1
        continue
      fi

      file=$(printf '%s' "$line" | cut -f2)
      version=$(printf '%s' "$line" | cut -f3)

      # A version that does not start with a digit is the shape of a failed
      # read, not of a release: an empty field, or a stray match.
      case "$version" in
        [0-9]*) ;;
        *)
          echo "review: $name ($file) yielded version '$version'" >&2
          echo "  the pin moved or its version line changed shape." >&2
          fail=1
          ;;
      esac
    done

    got=$(wc -l < pins.txt)
    want=${toString (builtins.length expected)}
    if [ "$got" != "$want" ]; then
      echo "review: the pin list has $got entries, expected $want" >&2
      echo "  a pin was added or removed; update tests/review-pins.nix too." >&2
      fail=1
    fi

    if [ "$fail" -ne 0 ]; then
      echo >&2
      echo "What review.sh --list-pins actually printed:" >&2
      cat pins.txt >&2
      exit 1
    fi

    # And the flake's own pins, read out of flake.lock by the same script the
    # review uses. Its silent failure is identical in shape: a lock format it
    # no longer parses yields no rows, and no rows reads as nothing to report.
    cp ${../flake.lock} flake.lock
    python3 ${../pkgs/flake-pins.py} > pins-flake.txt || {
      echo "flake-pins.py could not read flake.lock" >&2
      exit 1
    }

    # One of each shape, because the review asks a different question of each
    # and a classifier that has collapsed to one answer is the bug.
    # One of each shape, and hyprland is named on purpose rather than as a
    # convenient example: it used to be pinned by revision IN THE URL, which
    # `nix flake update` cannot move and the nightly bump silently skipped. It
    # sat at 0.56.0 while nixpkgs reached 0.56.2 -- a pin meant to keep the
    # compositor AHEAD of nixpkgs had put it behind, and nothing said so,
    # because a watcher that reports nothing looks exactly like a watcher with
    # nothing to report.
    #
    # So `hyprland ref` is the assertion, not `hyprland rev`: if someone pins
    # it back to a commit, this fails and says why.
    for want_line in "omarchy	tag" "sops-nix	rev" "hyprland	ref" "nixpkgs	ref"; do
      name=''${want_line%%	*}
      kind=''${want_line##*	}
      got=$(grep -E "^$name	" pins-flake.txt | cut -f2)
      [ "$got" = "$kind" ] || {
        echo "review: flake.lock pins $name as '$got', expected '$kind'" >&2
        echo "  the review asks a different question of each shape." >&2
        cat pins-flake.txt >&2
        exit 1
      }
    done

    # The board row flags any open issue without a milestone, and the review's
    # own issue is an open issue: filed without one, it can never go green
    # (#670). A floor of two, so a renamed call is not a loop over nothing.
    filings=$(grep -E '^\s*gh issue (create|edit) ' ${../pkgs/review.sh})
    n=$(printf '%s\n' "$filings" | grep -c . || true)
    [ "$n" -ge 2 ] || {
      echo "review: expected the create and edit calls, found $n" >&2
      exit 1
    }
    if printf '%s\n' "$filings" | grep -v -- '--milestone'; then
      echo "review: the call above files the review issue without a milestone" >&2
      echo "  and the board row will then report that issue forever." >&2
      exit 1
    fi

    # The nightly files its own issue, and the same row reads it (#683).
    nightly=$(grep -E '^\s*gh issue (create|edit) ' ${../.github/workflows/nightly.yml})
    n=$(printf '%s\n' "$nightly" | grep -c . || true)
    [ "$n" -ge 2 ] || {
      echo "review: expected nightly.yml's create and edit calls, found $n" >&2
      exit 1
    }
    if printf '%s\n' "$nightly" | grep -v -- '--milestone'; then
      echo "review: nightly.yml files its issue without a milestone, and the" >&2
      echo "  board row will then report that issue until someone adds one." >&2
      exit 1
    fi

    # main's install verdict (#652), from fixture runs rather than GitHub. The
    # trap it exists for: a commit the gate judged irrelevant reports its
    # install JOB as success having installed nothing, so a verdict read off
    # the job alone calls an unverified main verified.
    verdict() { # expected, then the TSV on stdin
      local want=$1 got
      got=$(bash ${../pkgs/review.sh} --main-install-verdict | cut -f1,2)
      [ "$got" = "$want" ] || {
        echo "review: main install verdict was '$got', expected '$want'" >&2
        fail=1
      }
    }
    fail=0
    T=$(printf '\t')

    # A burst: HEAD cannot affect an install, and the commit below it that
    # can had its install evicted.
    verdict "unverified''${T}bbb" <<EOF
    aaa''${T}completed''${T}success''${T}success
    bbb''${T}completed''${T}skipped''${T}cancelled
    ccc''${T}completed''${T}skipped''${T}success
    EOF

    # Irrelevant commits above a real install: that install is the answer.
    verdict "verified''${T}ccc" <<EOF
    aaa''${T}completed''${T}success''${T}success
    bbb''${T}completed''${T}success''${T}success
    ccc''${T}completed''${T}skipped''${T}success
    EOF

    # A merge that started no run at all (#671's GITHUB_TOKEN push).
    verdict "none''${T}aaa" <<EOF
    aaa''${T}-''${T}-''${T}-
    bbb''${T}completed''${T}skipped''${T}success
    EOF

    # Evicted, then re-run by hand: the re-run counts.
    verdict "verified''${T}aaa" <<EOF
    aaa''${T}completed''${T}skipped''${T}cancelled
    aaa''${T}completed''${T}skipped''${T}success
    EOF

    # Still installing is not a finding.
    verdict "running''${T}aaa" <<EOF
    aaa''${T}in_progress''${T}skipped''${T}null
    EOF

    # One workflow's row, from fixture gh output (#690). The case that broke:
    # a workflow with no runs, which a jq filter over an empty list turns into
    # "null<TAB>null" -- date refused it and the row vanished from the table.
    now=$(date -d 2026-09-14T12:00:00Z +%s)
    cirow() { # wf hours none line, then the text the row must contain
      local got
      got=$(printf '%s' "$4" | bash ${../pkgs/review.sh} --ci-row "$1" "$2" "$3" "$now" 2>&1)
      case "$got" in
        *"$5"*) ;;
        *)
          echo "review: ci row for '$4' (none=$3) was: $got" >&2
          echo "  expected it to contain: $5" >&2
          fail=1
          ;;
      esac
    }
    cirow nightly.yml 30 finding "" "| nightly.yml | - | no runs at all | **is the workflow disabled?** |"
    cirow nightly.yml 30 finding "null''${T}null" "| nightly.yml | - | no runs at all | **is the workflow disabled?** |"
    cirow release.yml 8760 ok "null''${T}null" "| release.yml | - | no runs retained | ok |"
    # A run IN FLIGHT, which is an EMPTY leading field rather than the "null"
    # the seven cases around this one assume (#1010). gh's --jq renders a null
    # conclusion as nothing at all, and tab is IFS whitespace, so the `read`
    # this file's seven original cases were written against stripped it and
    # shifted the timestamp into $conclusion -- reporting a workflow running
    # right then as disabled. None of the other cases can vary that, because
    # every one of them has a non-empty first field.
    cirow build.yml 30 finding "''${T}2026-09-14T10:00:00Z" "| build.yml | 2h ago | still running | ok |"
    cirow build.yml 30 finding "success''${T}2026-09-14T10:00:00Z" "| build.yml | 2h ago | success | ok |"
    cirow build.yml 30 finding "success''${T}2026-09-12T12:00:00Z" "| build.yml | 48h ago | last run passed | **but nothing has run for 48h** |"
    cirow build.yml 30 finding "failure''${T}2026-09-14T10:00:00Z" "| build.yml | 2h ago | failure | **read the run** |"
    cirow build.yml 30 finding "success''${T}yesterday-ish" "| build.yml | - | unreadable run |"

    [ "$fail" -eq 0 ] || exit 1

    echo "all $want pins are readable, and every version looks like one"
    echo "and flake.lock still classifies tag, rev and ref pins apart"
    touch $out
  ''
