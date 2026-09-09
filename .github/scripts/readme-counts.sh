#!/usr/bin/env bash
# Every number in the README that is derived from this repository.
#
#   readme-counts.sh --check   compare, and fail on drift          (pull requests)
#   readme-counts.sh --fix     rewrite the README to agree         (the Omarchy bump)
#
# ## Why this exists
#
# Adopting Omarchy 4.0.3 hit three separate count drifts in one bump -- the
# command count (431 -> 444), and two numbers in the same paragraph that were
# NOT checked and had been wrong for some time (24 -> 32 scripts, "Ten" -> Six
# replaced). Each failed the build. None of them needed a human to decide
# anything: a count has exactly one correct value, derivable from the repo.
#
# Asking a person to type it, and failing the release until they do, is asking
# them to be a calculator. So on a bump these are APPLIED, and the diff is
# what gets reviewed. Decisions -- is this new Install row an app? -- are a
# different thing and stay a checklist (see data/menu-exceptions.nix).
#
# ## Why no marker comments
#
# The obvious design is <!--n:commands-->444<!--/n--> spans. This uses a table
# of patterns instead: the README stays readable in raw form, and adding a
# number is still one entry here rather than a new grep in a workflow -- which
# is the actual complaint. Markers remain the answer if a number ever appears
# somewhere a pattern cannot describe.
#
# ## The rule this file must never break
#
# --fix propagates a WRONG DERIVATION confidently: get a computation wrong and
# the README is silently rewritten to agree with it. So every quantity must
# REFUSE rather than fix when it cannot be computed, and every pattern must
# refuse when it matches nothing. A check that cannot fail is worse than no
# check; an auto-fixer that cannot refuse is worse than a check.
set -uo pipefail

mode=${1:-}
case "$mode" in
  --check | --fix) ;;
  *)
    echo "usage: $0 --check | --fix" >&2
    exit 2
    ;;
esac

root=$(cd "$(dirname "$0")/../.." && pwd)
readme="$root/README.md"
omarchy=${OMARCHY_TREE:-$root/result}

[ -f "$readme" ] || { echo "no README at $readme" >&2; exit 1; }
[ -d "$omarchy/share/omarchy/bin" ] || {
  echo "no omarchy tree at $omarchy -- build it first:" >&2
  echo "  nix build .#omarchy --out-link result" >&2
  echo "or set OMARCHY_TREE to one." >&2
  exit 1
}

fail=0
changed=0
report=""

# A quantity: a name, its value, and a sed expression that finds it in the
# README with the value as \1. Both halves refuse on their own.
quantity() {
  local name=$1 value=$2 find=$3 repl=$4
  local current

  if [ -z "$value" ] || [ "$value" = "0" ]; then
    echo "::error::$name computed as '${value:-empty}' -- refusing to check or fix" >&2
    fail=1
    return
  fi

  current=$(sed -nE "s/$find/\1/p" "$readme" | head -1)
  if [ -z "$current" ]; then
    echo "::error::$name: nothing in README.md matches its pattern" >&2
    echo "::error::  the wording moved, or the pattern is wrong. Not guessing." >&2
    fail=1
    return
  fi

  if [ "$current" = "$value" ]; then
    report="$report  $name: $value\n"
    return
  fi

  if [ "$mode" = "--check" ]; then
    echo "::error::$name: README says $current, the repository says $value" >&2
    fail=1
  else
    # $repl is already a complete sed expression. Wrapping it in another
    # s/.../ produced `s/s/...`, which sed rejected -- and the first version
    # of this function ignored sed's exit status, so it printed "(fixed)" and
    # "README.md updated." while changing nothing at all. An auto-fixer that
    # reports success on failure is worse than no auto-fixer: the next run of
    # --check contradicts it, and the person reading the bump believes the
    # first one.
    #
    # So: run it, and PROVE the file moved. Comparing before and after is the
    # only claim worth making here, because sed exits 0 for a pattern that
    # matched nothing.
    local before after
    before=$(cksum < "$readme")
    if ! sed -i -E "$repl" "$readme"; then
      echo "::error::$name: sed refused the replacement expression" >&2
      fail=1
      return
    fi
    after=$(cksum < "$readme")
    if [ "$before" = "$after" ]; then
      echo "::error::$name: the replacement changed nothing -- its pattern" >&2
      echo "::error::  found the number but could not rewrite it." >&2
      fail=1
      return
    fi
    report="$report  $name: $current -> $value  (fixed)\n"
    changed=1
  fi
}

# ---- the quantities ---------------------------------------------------------

commands=$("$omarchy/bin/omarchy" commands --check 2>/dev/null |
  grep -oE '[0-9]+ commands' | grep -oE '[0-9]+' | head -1)

# The app counts, using the expression build.yml already had -- verbatim, so
# the two cannot drift apart while both exist. The field names are the
# load-bearing part: `x ? option` for the ones that are NixOS modules and
# `x ? unavailable` for the ones with no equivalent. Guessing them (`module`,
# `unavailable or false`) yields zero and an unbound variable, which is how
# this was caught here rather than in a README nobody re-read.
eval "$(cd "$root" && nix eval --raw --impure --expr '
  let lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib;
      a = import ./data/apps.nix;
      c = f: toString (lib.length (lib.attrNames (lib.filterAttrs f a)));
  in "a_total=" + toString (lib.length (lib.attrNames a))
   + " a_mod=" + c (_: x: x ? option)
   + " a_ours=" + c (_: x: x.ours or false)
   + " a_un=" + c (_: x: x ? unavailable)
' 2>/dev/null)"
a_total=${a_total:-}
a_mod=${a_mod:-}
a_ours=${a_ours:-}
a_un=${a_un:-}
if [ -n "$a_total" ] && [ -n "$a_mod" ] && [ -n "$a_ours" ] && [ -n "$a_un" ]; then
  a_nixpkgs=$((a_total - a_mod - a_ours - a_un))
  # "never touch this repo" is the nixpkgs ones plus the module-backed ones:
  # both come from upstream nixpkgs, neither is built here.
  a_untouched=$((a_nixpkgs + a_mod))
  # Everything with a nixpkgs equivalent -- the search index cannot carry the
  # ones that have none, which is what the sentence itself says.
  a_indexed=$((a_total - a_un))
else
  a_nixpkgs=""
  a_untouched=""
  a_indexed=""
fi

pac=$(grep -rlE '\b(pacman|yay)\b' "$omarchy/share/omarchy/bin" 2>/dev/null | wc -l)
# mktemp, not a fixed /tmp name: two of the four self-hosted runners share a
# machine, so two jobs writing /tmp/rc-pac.txt at once would read each other's
# half-written file and disagree about a number neither computed.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ls "$root/pkgs/omarchy/nix-bin" 2>/dev/null | sort > "$tmp/nixbin"
grep -rlE '\b(pacman|yay)\b' "$omarchy/share/omarchy/bin" 2>/dev/null |
  xargs -r -n1 basename | sort > "$tmp/pac"
repl_n=$(comm -12 "$tmp/pac" "$tmp/nixbin" | wc -l)

# The one number the README spells as a word.
word_for() {
  case "$1" in
    5) echo Five ;; 6) echo Six ;; 7) echo Seven ;; 8) echo Eight ;;
    9) echo Nine ;; 10) echo Ten ;; 11) echo Eleven ;; 12) echo Twelve ;;
    *) echo "" ;;
  esac
}
repl_word=$(word_for "$repl_n")

quantity "commands" "$commands" \
  '.*\*\*([0-9]+) shell commands\*\*.*' \
  's/\*\*[0-9]+ shell commands\*\*/**'"$commands"' shell commands**/'
quantity "subcommands" "$commands" \
  '.*all ([0-9]+) subcommands.*' \
  's/all [0-9]+ subcommands/all '"$commands"' subcommands/'
quantity "commands-through" "$commands" \
  ".*Omarchy's ([0-9]+) *\|.*" \
  "s/Omarchy's [0-9]+ \|/Omarchy's $commands |/"
quantity "commands-upstream" "$commands" \
  '.*Upstream.s ([0-9]+) commands.*' \
  's/Upstream.s [0-9]+ commands/Upstream'"'"'s '"$commands"' commands/'
quantity "pacman-scripts" "$pac" \
  '.*\*\*([0-9]+) of [0-9]+ scripts\*\*.*' \
  's/\*\*[0-9]+ of [0-9]+ scripts\*\*/**'"$pac"' of '"$commands"' scripts**/'
quantity "pacman-replaced" "$repl_word" \
  '^(Six|Seven|Eight|Nine|Ten|Eleven|Twelve) of those are replaced.*' \
  's/^(Six|Seven|Eight|Nine|Ten|Eleven|Twelve) of those are replaced/'"$repl_word"' of those are replaced/'
quantity "apps-total" "$a_total" \
  '.*\| ([0-9]+) apps in the selection \|.*' \
  "s/\| [0-9]+ apps in the selection \| [0-9]+ from nixpkgs, [0-9]+ as NixOS modules, [0-9]+ built here, [0-9]+ with no equivalent \|/| $a_total apps in the selection | $a_nixpkgs from nixpkgs, $a_mod as NixOS modules, $a_ours built here, $a_un with no equivalent |/"
quantity "apps-untouched" "$a_untouched" \
  '.*\*\*([0-9]+) of the [0-9]+ apps never touch this repo\.\*\*.*' \
  "s/\*\*[0-9]+ of the [0-9]+ apps never touch this repo\.\*\*/**$a_untouched of the $a_total apps never touch this repo.**/"
# The two figures #363 warned about: derived numbers sitting in PROSE, which
# nothing asserted and which therefore went stale silently. That is the exact
# trap this script exists for -- prose beside a checked number is the most
# convincing place for a wrong number to live -- so they become quantities
# rather than being hand-patched and left to rot again.
#
# "N applications are selectable that way" is the whole catalogue, not the
# menu-mapped subset: git history has it moving 56 -> 60 when #337 added four
# apps, in step with the total.
quantity "apps-selectable" "$a_total" \
  '.*\*\*([0-9]+) applications\*\* are selectable.*' \
  "s/\*\*[0-9]+ applications\*\* are selectable/**$a_total applications** are selectable/"
# "N of the M apps" in the search-index sentence, whose own parenthetical
# states the rule: the ones with no nixpkgs equivalent cannot be indexed.
quantity "apps-indexed" "$a_indexed" \
  '.*and ([0-9]+) of the [0-9]+ apps.*' \
  "s/and [0-9]+ of the [0-9]+ apps/and $a_indexed of the $a_total apps/"
quantity "apps-nixpkgs-row" "$a_untouched" \
  '.*\| nixpkgs \(([0-9]+) of [0-9]+ apps\) \|.*' \
  "s/\| nixpkgs \([0-9]+ of [0-9]+ apps\) \|/| nixpkgs ($a_untouched of $a_total apps) |/"

# A floor. Eleven quantities are declared above; a run that checked fewer means
# something stopped matching and this reported calm about numbers it never
# looked at.
checked=$(printf '%b' "$report" | grep -c .)
if [ "$fail" -eq 0 ] && [ "$checked" -lt 11 ]; then
  echo "::error::only $checked of 11 quantities were accounted for" >&2
  fail=1
fi

printf '%b' "$report"
if [ "$mode" = "--fix" ] && [ "$changed" -eq 1 ]; then
  echo "README.md updated."
fi
exit "$fail"
