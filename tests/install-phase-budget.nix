{ omarchy, pkgs }:
# #997: pkgs/omarchy/default.nix's installPhase reaches the builder as one
# environment string, and execve refuses any string over MAX_ARG_STRLEN with
# "Argument list too long", naming nothing. #948 died that way at 2 KB of
# headroom. This fails first, with numbers and the fix.
#
# Values, not store paths: a path in the environment is a build input
# (tests/AGENTS.md), and this needs only the evaluated string's length.
pkgs.runCommand "nixarchy-install-phase-budget"
  {
    bytes = toString (builtins.stringLength omarchy.installPhase);
    # 8,058 bytes short of the ceiling: two of the largest paragraphs #997
    # moved, so red means "tidy up", never "the build is broken".
    budget = "123000";
    structured = if omarchy.__structuredAttrs or false then "yes" else "no";
  }
  ''
    # The string is installPhase=<value> plus a NUL: 131072 - 13 - 1.
    ceiling=131058
    if [ "$structured" = yes ]; then
      echo "omarchy now uses __structuredAttrs, so installPhase reaches the builder"
      echo "as a file, not an environment string, and MAX_ARG_STRLEN no longer"
      echo "applies to it. This budget measures nothing any more: retire"
      echo "tests/install-phase-budget.nix and its flake.nix entry."
      exit 1
    fi
    echo "omarchy installPhase: $bytes bytes"
    echo "  budget $budget, ceiling $ceiling (execve's MAX_ARG_STRLEN, less 'installPhase=' and NUL)"
    echo "  $((budget - bytes)) bytes before this check fails, $((ceiling - bytes)) before the build does"
    if [ "$bytes" -gt "$budget" ]; then
      echo
      echo "FAIL: the install phase is over its budget. Past $ceiling bytes the build"
      echo "dies with 'Argument list too long' and no hint why (#948, #997)."
      echo "Move explanation out: put it in pkgs/AGENTS.md under a heading and"
      echo "leave a '# Why: pkgs/AGENTS.md#<anchor>' pointer (AGENTS.md section 7)."
      echo "Only this phase is measured. Switching omarchy to __structuredAttrs"
      echo "would remove the limit entirely, and is a larger change."
      exit 1
    fi
    touch $out
  ''
