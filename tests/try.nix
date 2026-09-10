{ pkgs, tryScript }:
# nixarchy-try's resolution, refusals and hand-off (#499, #503), run on the
# REAL code against the REAL data. The command exists because three guesses
# go wrong -- `nix run`'s mainProgram fallback, the registry's unstable HEAD,
# and unfree refusing to be tried while installing fine -- so the check's job
# is to prove the code that avoids each guess is still the code that runs.
#
# The two nix expressions are extracted verbatim from the script's heredocs
# and applied AT EVALUATION TIME to the repo's own data/apps.nix and the
# check's own nixpkgs -- not to fixtures shaped like them. android-tools is
# in the table because it is the receipt: the package `nix run` fails on
# outright, and the row the `binary` field (#468) exists for.
#
# The shell halves -- the fallback ladder, the unfree seasoning, the #503
# hand-off -- are sed-extracted and driven with a stubbed `nix`, in the
# manner of tests/preview.nix. Then the wiring assertions: main still calls
# each piece, in the order the honesty requires (footer BEFORE the program
# runs, hand-off after), and no call site anywhere says `nix run` -- matched
# on non-comment lines, because a forbid-pattern that reads prose fails
# against correctly-gated code (tests/AGENTS.md).
let
  inherit (pkgs) lib;
  text = builtins.readFile tryScript;

  # A heredoc body, verbatim. Splitting on the delimiter yields exactly
  # three parts (before, body, after); the body starts with the `' || :`
  # tail of the `read` line. Anything else means the script was reshaped and
  # this extraction is reading garbage -- throw, loudly, rather than test it.
  extract =
    delim:
    let
      parts = lib.splitString delim text;
      raw = builtins.elemAt parts 1;
    in
    if builtins.length parts != 3 then
      throw "tests/try.nix: expected exactly one ${delim} heredoc in nixarchy-try"
    else if !(lib.hasPrefix "' || :\n" raw) then
      throw "tests/try.nix: the ${delim} heredoc is not shaped as expected"
    else
      lib.removePrefix "' || :\n" raw;

  lookup = import (builtins.toFile "try-lookup.nix" (extract "NIX_LOOKUP_EOF"));
  probe = import (builtins.toFile "try-probe.nix" (extract "NIX_PROBE_EOF"));

  apps = import ../data/apps.nix;

  # kind / attr / binary / unfree, against the real catalogue. The rows are
  # chosen for what they exercise, not for convenience: firefox is the
  # module refusal (#499's "name the enable path"), chrome the unfree flag,
  # android-tools the binary field, sublime the unavailable note, and a name
  # not in the catalogue must come back `raw` -- never a guess.
  lookupCases = [
    {
      name = "firefox";
      want = "module\tprograms.firefox";
    }
    {
      name = "chrome";
      want = "app\tgoogle-chrome\t\t1";
    }
    {
      name = "android-tools";
      want = "app\tandroid-tools\tadb\t0";
    }
    {
      name = "alacritty";
      want = "app\talacritty\t\t0";
    }
    {
      name = "not-a-catalogue-row";
      want = "raw";
    }
  ];

  # The probe against this check's own nixpkgs: mainProgram read out where
  # one exists, EMPTY where none does (android-tools -- the fallback ladder's
  # reason to exist), the unfree bit for chrome, and `missing` for an
  # attribute the tree does not carry.
  probeCases = [
    {
      attr = "hello";
      want = "found\thello\t0";
    }
    {
      attr = "android-tools";
      want = "found\t\t0";
    }
    {
      attr = "google-chrome";
      want = "found\tgoogle-chrome-stable\t1";
    }
    {
      attr = "no-such-attribute-anywhere";
      want = "missing";
    }
  ];

  renderCases =
    label: f: cases:
    lib.concatMapStrings (
      c:
      let
        id = f c;
        got = if label == "lookup" then lookup apps c.name else probe pkgs c.attr;
      in
      if got == c.want then
        "echo ${lib.escapeShellArg "  ok      ${label} ${id} -> ${got}"}\n"
      else
        "echo ${lib.escapeShellArg "  FAILED  ${label} ${id}: wanted '${c.want}', got '${got}'"}; fails=1\n"
    ) cases;

  lookupAsserts = renderCases "lookup" (c: c.name) lookupCases;
  probeAsserts = renderCases "probe" (c: c.attr) probeCases;
in
pkgs.runCommand "nixarchy-try" { } ''
    set -o pipefail
    fails=0

    # ------------------------------------------------------------------------
    # The two expressions, already applied at evaluation time (see the let
    # above); here only the verdicts land.
    # ------------------------------------------------------------------------
    echo "lookup expression, against the real data/apps.nix:"
    ${lookupAsserts}
    echo "probe expression, against this check's nixpkgs:"
    ${probeAsserts}

    # ------------------------------------------------------------------------
    # resolve_binary: the fallback ladder. The catalogue's word beats
    # mainProgram beats the attribute's last segment -- in that order, because
    # the first two are answers and the last is the guess nix run makes.
    # ------------------------------------------------------------------------
    sed -n '/^resolve_binary()/,/^}/p' ${tryScript} > rb.sh
    test -s rb.sh || { echo "resolve_binary is not in nixarchy-try any more" >&2; exit 1; }
    . ./rb.sh
    t_rb() {
      want=$1 name=$2 row=$3 main=$4 attr=$5
      g=$(resolve_binary "$row" "$main" "$attr")
      if [ "$g" = "$want" ]; then
        echo "  ok      $name -> $g"
      else
        echo "  FAILED  $name: wanted $want, got '$g'"
        fails=1
      fi
    }
    t_rb adb                  "catalogue binary wins"        adb "" android-tools
    t_rb adb                  "catalogue beats mainProgram"  adb wrong android-tools
    t_rb google-chrome-stable "mainProgram next"             "" google-chrome-stable google-chrome
    t_rb ripgrep              "last resort: the attr"        "" "" ripgrep
    t_rb hello                "dotted attr: last segment"    "" "" python3Packages.hello

    # ------------------------------------------------------------------------
    # run_try, with a stubbed nix: the launch is `nix shell -f <tree> <attr>
    # -c <binary>`, and NIXPKGS_ALLOW_UNFREE reaches ONLY the unfree runs.
    # ------------------------------------------------------------------------
    sed -n '/^run_try()/,/^}/p' ${tryScript} > rt.sh
    test -s rt.sh || { echo "run_try is not in nixarchy-try any more" >&2; exit 1; }
    . ./rt.sh
    nix() {
      printf 'call:%s\n' "$*"
      printf 'env:%s\n' "''${NIXPKGS_ALLOW_UNFREE:-unset}"
    }
    t_run() {
      name=$1 unfree=$2 wantenv=$3
      got=$(run_try /some/nixpkgs some-attr some-bin "$unfree" --flag)
      case "$got" in
        "call:shell -f /some/nixpkgs some-attr -c some-bin --flag
  env:$wantenv")
          echo "  ok      $name"
          ;;
        *)
          echo "  FAILED  $name:"
          printf '%s\n' "$got" | sed 's/^/            /'
          fails=1
          ;;
      esac
    }
    t_run "free run: no unfree leak"  0 unset
    t_run "unfree run: env is set"    1 1

    # ------------------------------------------------------------------------
    # The honesty and the hand-off live in named functions; assert the words
    # are still in them, then that main still says them, in the right order.
    # ------------------------------------------------------------------------
    sed -n '/^print_footer()/,/^}/p' ${tryScript} > pf.sh
    test -s pf.sh || { echo "print_footer is not in nixarchy-try any more" >&2; exit 1; }
    for phrase in "NOT a sandbox" "full user privileges" "garbage-collected" \
                  "Nothing is installed" "nixarchy vm"; do
      if grep -qF "$phrase" pf.sh; then
        echo "  ok      footer says: $phrase"
      else
        echo "  FAILED  footer no longer says: $phrase"
        fails=1
      fi
    done

    sed -n '/^next_step()/,/^}/p' ${tryScript} > ns.sh
    test -s ns.sh || { echo "next_step is not in nixarchy-try any more" >&2; exit 1; }
    bold() { echo "$1"; }
    . ./ns.sh
    if next_step app helix | grep -q 'nixarchy-app-enable helix'; then
      echo "  ok      hand-off: catalogue row -> nixarchy-app-enable"
    else
      echo "  FAILED  hand-off for a catalogue row does not name nixarchy-app-enable"
      fails=1
    fi
    if next_step raw ripgrep | grep -q 'nixarchy-pkg-add ripgrep'; then
      echo "  ok      hand-off: raw attr -> nixarchy-pkg-add"
    else
      echo "  FAILED  hand-off for a raw attribute does not name nixarchy-pkg-add"
      fails=1
    fi

    # ------------------------------------------------------------------------
    # Wiring: extracted-and-green is not called-and-green (#133). Match the
    # CALLS, by line number, so the order is the one a user experiences:
    # footer before the program runs, hand-off after.
    # ------------------------------------------------------------------------
    footer_line=$(grep -n '^print_footer$' ${tryScript} | cut -d: -f1 | head -1)
    run_line=$(grep -n '^run_try "' ${tryScript} | cut -d: -f1 | head -1)
    step_line=$(grep -n '^next_step "' ${tryScript} | cut -d: -f1 | head -1)
    for pair in "print_footer:$footer_line" "run_try:$run_line" "next_step:$step_line"; do
      if [ -z "''${pair#*:}" ]; then
        echo "  FAILED  main no longer calls ''${pair%%:*}"
        fails=1
      fi
    done
    if [ -n "$footer_line" ] && [ -n "$run_line" ] && [ -n "$step_line" ] \
      && [ "$footer_line" -lt "$run_line" ] && [ "$run_line" -lt "$step_line" ]; then
      echo "  ok      order: footer ($footer_line) < run ($run_line) < hand-off ($step_line)"
    else
      echo "  FAILED  call order is not footer < run < hand-off ($footer_line/$run_line/$step_line)"
      fails=1
    fi

    # No call site says `nix run`: strip comment lines first, because the
    # script's own comments discuss `nix run` at length and a pattern that
    # reads prose would pass or fail on the wrong thing entirely.
    if grep -vE '^[[:space:]]*#' ${tryScript} | grep -q 'nix run '; then
      echo "  FAILED  a call site invokes 'nix run' -- the mainProgram guess is back"
      fails=1
    else
      echo "  ok      no call site invokes nix run"
    fi

    [ "$fails" = 0 ] || { echo "nixarchy-try assertions failed" >&2; exit 1; }
    echo ok > $out
''
