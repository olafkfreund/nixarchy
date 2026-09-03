#!/usr/bin/env bash
# What changed for someone running nixarchy, between two tags.
#
# release.yml has always written a fixed preamble -- which image to download,
# how to put the split one back together, how to check the sums -- and then let
# `gh release --generate-notes` append the merged-PR list under it. Between
# v4.0.1-5 and v4.0.2-1 that meant fifty-five PR titles and nothing that said
# the vendored Omarchy had moved to a security release, that a root daemon had
# been turned off, or that screen sharing works again. A person deciding
# whether to upgrade reads a preamble about the download and then a list about
# the repository.
#
# So this derives the four things that are actually about their machine, in the
# order somebody wants them:
#
#   1. which Omarchy is vendored, and what upstream's package set did
#   2. what changed in `programs.nixarchy.*` and in the defaults this port sets
#   3. which pinned packages moved
#   4. everything else, from the commit subjects
#
# Everything is DERIVED. Sections 1 and 3 read files out of git, section 2 asks
# Nix to evaluate the option set at both revisions and diffs the answer, and
# section 4 is the log. Nothing here reads a commit message and decides what it
# meant, because the failure mode of hand-written release notes is that the
# interesting change is the one nobody wrote down.
#
# An app, not a check: it runs git, evaluates two revisions of the flake, and
# asks GitHub what upstream shipped. A sandboxed derivation can do none of
# those. What it does have is tests/release-notes.nix, which drives this whole
# script against a fixture repository with a known answer.
#
# Two classes of failure, treated differently on purpose:
#
#   A scan that stops matching is fatal. Every section greps for a shape --
#   `github:basecamp/omarchy/<tag>` in flake.nix, `version = "..."` in
#   pkgs/apps, `= lib.mkDefault ...` under modules -- and when one of those
#   shapes changes, the honest report is not "nothing changed", it is "I can no
#   longer see". This repo has shipped that bug before (see
#   tests/package-delta.nix), so an empty scan exits non-zero and names the
#   pattern that rotted.
#
#   A network failure is not. GitHub being slow during a release should not
#   stop the release; it should leave a loud line in the notes saying which
#   part is missing and where to look it up by hand.
#
# Usage: release-notes.sh <from-tag> <to-ref>
set -euo pipefail

from=${1:?usage: release-notes.sh <from-tag> <to-ref>}
to=${2:-HEAD}

# Wired in by the flake so the app carries its sibling; overridable so the
# fixture check can run this script straight out of the tree.
delta_script=${NIXARCHY_PACKAGE_DELTA:-@delta@}

die() {
  echo "release-notes: $*" >&2
  exit 1
}

from_rev=$(git rev-parse "$from^{commit}")
to_rev=$(git rev-parse "$to^{commit}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- 1. what this release is ------------------------------------------------

# The vendored Omarchy is a flake input, so its tag is in flake.nix at both
# revisions. `|| true` keeps the empty case alive as far as the check below,
# which is the one worth reporting properly.
pin_at() {
  git show "$1:flake.nix" |
    grep -oE 'github:basecamp/omarchy/[^"]+' | head -1 | cut -d/ -f3 || true
}

old_omarchy=$(pin_at "$from_rev")
new_omarchy=$(pin_at "$to_rev")
for pair in "$from:$old_omarchy" "$to:$new_omarchy"; do
  [ -n "${pair#*:}" ] || die \
    "no github:basecamp/omarchy/<tag> in flake.nix at ${pair%%:*}: the scan for the vendored version has stopped matching, and 'unchanged' would be a lie"
done

echo "## What this release is"
echo
if [ "$old_omarchy" = "$new_omarchy" ]; then
  echo "Omarchy \`$new_omarchy\`, packaged for NixOS -- the same upstream release"
  echo "\`$from\` vendored. Everything below is this port's own work."
else
  echo "Omarchy \`$new_omarchy\`, packaged for NixOS, up from \`$old_omarchy\` in"
  echo "\`$from\`. Upstream's notes for it:"
  echo "<https://github.com/basecamp/omarchy/releases/tag/$new_omarchy>"
fi
echo

if [ "$old_omarchy" != "$new_omarchy" ]; then
  # Same lists, same script, same reasoning as the bump PR: Omarchy pins no
  # versions, so the set of packages it installs is the only thing to diff.
  fetched=yes
  for tag in "$old_omarchy" "$new_omarchy"; do
    : >"$work/pkgs-$tag.txt"
    for list in omarchy-base omarchy-other; do
      curl -fsSL --max-time 30 \
        "https://raw.githubusercontent.com/basecamp/omarchy/$tag/install/$list.packages" \
        >>"$work/pkgs-$tag.txt" || fetched=no
    done
  done

  if [ "$fetched" = yes ]; then
    bash "$delta_script" \
      "$work/pkgs-$old_omarchy.txt" "$work/pkgs-$new_omarchy.txt" \
      "$old_omarchy" "$new_omarchy"
  else
    echo "**Upstream's package lists could not be fetched**, so the package"
    echo "delta between \`$old_omarchy\` and \`$new_omarchy\` is missing from these"
    echo "notes rather than absent from the release. Compare"
    echo "\`install/omarchy-base.packages\` between the two tags by hand."
    echo
  fi

  # What a fresh ~/.config is seeded from. A change to one of these is a change
  # to what a new machine starts with, and it reaches nobody through this
  # repo's own diff, because the file lives in a flake input.
  #
  # The paths are the ones modules/home.nix actually copies out of the vendored
  # tree -- config/ wholesale, plus four files by name -- and not `default/`
  # entire: default/pacman/ moves in most Omarchy releases and means nothing
  # here, and default/omarchy/omarchy-menu.jsonc is generated rather than
  # seeded, because it carries this port's install-row rewrites.
  seeded_paths='^(config/|default/hypr/|default/tensaku/|icon[.]txt|logo[.]txt)'
  if compare=$(curl -fsSL --max-time 30 \
    "https://api.github.com/repos/basecamp/omarchy/compare/$old_omarchy...$new_omarchy"); then
    seeded=$(echo "$compare" | jq -r '.files[]?.filename' | grep -E "$seeded_paths" || true)
    if [ -n "$seeded" ]; then
      echo "**Seeded config files that changed.** A machine installed from this"
      echo "release starts with these. One you already run keeps the copies in"
      echo "your \`~/.config\`, which are yours."
      echo
      # shellcheck disable=SC2016  # $/ is sed anchoring a line, not a variable
      echo "$seeded" | sed 's/^/- `/;s/$/`/'
    else
      echo "Nothing changed under the trees a new \`~/.config\` is seeded from,"
      echo "so a fresh install starts with the same files \`$from\` gave it."
    fi
    echo
  else
    echo "**GitHub could not be asked which files upstream changed**, so these"
    echo "notes do not say whether the files a new \`~/.config\` is seeded from"
    echo "moved. Compare \`config/\` between the two tags by hand."
    echo
  fi
fi

# --- 2. configuration changes -----------------------------------------------

echo "## Configuration changes"
echo

# The option set, evaluated rather than read. A commit message says what
# somebody meant to change; `options.programs.nixarchy` says what the module
# system will accept, and what it does when you say nothing.
#
# Submodule options stop here: `apps.<name>` is one option, not a tree. That is
# deliberate -- the interesting default lives at the leaf that has one.
# shellcheck disable=SC2016  # this is Nix source, not shell: nothing here expands
options_apply='o:
  let
    isOpt = v: (v._type or "") == "option";
    go = path: v:
      if isOpt v then
        (let d = builtins.tryEval (if v ? default then builtins.toJSON v.default else "");
         in { "${path}" =
                if !(v ? default) then "(no default)"
                else if d.success then d.value
                else "(not representable)"; })
      else if builtins.isAttrs v then
        builtins.foldl'"'"' (a: n: a // go (path + "." + n) v.${n}) { }
          (builtins.filter (n: builtins.substring 0 1 n != "_") (builtins.attrNames v))
      else { };
  in go "programs.nixarchy" o'

# The fixture check has no network and cannot evaluate a flake inside a
# sandbox, so it hands the two option maps over directly. Nothing else sets
# these.
options_at() { # rev outfile
  if [ -n "${NIXARCHY_OPTIONS_FROM:-}" ] && [ "$1" = "$from_rev" ]; then
    # --no-preserve, because the fixture hands over store files and the
    # normalisation below rewrites this copy in place.
    cp --no-preserve=mode "$NIXARCHY_OPTIONS_FROM" "$2"
  elif [ -n "${NIXARCHY_OPTIONS_TO:-}" ] && [ "$1" = "$to_rev" ]; then
    cp --no-preserve=mode "$NIXARCHY_OPTIONS_TO" "$2"
  else
    # allRefs, because a tag's commit need not be on the checked-out branch.
    nix eval --json \
      "git+file://$(git rev-parse --show-toplevel)?rev=$1&allRefs=1#nixosConfigurations.vm.options.programs.nixarchy" \
      --apply "$options_apply" >"$2"
  fi

  # A store path in a default is the same package under a different hash on
  # every rebuild. Strip the hash and what is left -- omarchy-4.0.1 ->
  # omarchy-4.0.2 -- is the part a reader wanted.
  sed -i -E 's#/nix/store/[a-z0-9]{32}-#store:#g' "$2"
}

options_at "$from_rev" "$work/opts-from.json"
options_at "$to_rev" "$work/opts-to.json"
for f in "$work/opts-from.json" "$work/opts-to.json"; do
  [ "$(jq -r 'length' "$f")" -gt 0 ] || die \
    "the option set at one of the two revisions came back empty: this walk of options.programs.nixarchy has stopped finding options, and 'no option changed' would be a lie"
done

# One row per finding: C(hanged default), A(dded), R(emoved).
jq -s -r '
  .[0] as $a | .[1] as $b
  | ( [ ($a | keys[]) as $k
        | select($b | has($k))
        | select($a[$k] != $b[$k])
        | "C\t\($k)\t\($a[$k])\t\($b[$k])" ]
    + [ ([$b | keys[]] - [$a | keys[]])[] | "A\t\(.)" ]
    + [ ([$a | keys[]] - [$b | keys[]])[] | "R\t\(.)" ] )[]
' "$work/opts-from.json" "$work/opts-to.json" >"$work/optdiff.tsv"

# The added rows need their default, which the set difference above does not
# carry. Joined back on here rather than in jq, where it reads worse.
changed_defaults=$(grep -c '^C' "$work/optdiff.tsv" || true)
added_options=$(grep -c '^A' "$work/optdiff.tsv" || true)
removed_options=$(grep -c '^R' "$work/optdiff.tsv" || true)

if [ "$changed_defaults" -gt 0 ]; then
  # First, in bold, on purpose. An option whose default moved is the one class
  # of change that reaches a machine whose configuration nobody edited.
  echo "**Defaults that changed.** These take effect on a machine whose"
  echo "\`configuration.nix\` says nothing about them."
  echo
  awk -F'\t' '$1 == "C" { printf "- `%s`: `%s` → `%s`\n", $2, $3, $4 }' "$work/optdiff.tsv"
  echo
fi

if [ "$added_options" -gt 0 ]; then
  echo "**New options.**"
  echo
  awk -F'\t' '$1 == "A" { print $2 }' "$work/optdiff.tsv" |
    while read -r key; do
      # shellcheck disable=SC2016  # the backticks are markdown, not a command
      printf -- '- `%s` (default `%s`)\n' "$key" \
        "$(jq -r --arg k "$key" '.[$k]' "$work/opts-to.json")"
    done
  echo
fi

if [ "$removed_options" -gt 0 ]; then
  echo "**Options that are gone.** A build that still sets one of these fails."
  echo "A renamed option appears here and under new options, both."
  echo
  awk -F'\t' '$1 == "R" { printf "- `%s`\n", $2 }' "$work/optdiff.tsv"
  echo
fi

if [ $((changed_defaults + added_options + removed_options)) -eq 0 ]; then
  echo "No option was added, removed or given a different default:"
  echo "\`programs.nixarchy\` means what it meant under \`$from\`."
  echo
fi

# The other half of "configuration", and the half the option diff cannot see:
# defaults this port sets for options NixOS declares.
# `services.printing.browsed.enable = lib.mkDefault false` in #201 turned off a
# daemon that had been running as root on every machine, and it is not an
# option of ours -- so to the walk above it does not exist at all.
# [.] rather than \., because this pattern is handed to awk as well as to grep
# and awk warns about the escape.
mkdefault_body='[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*=[[:space:]]*(lib[.])?mk(Default|Force)'
present=$(git grep -hE "$mkdefault_body" "$to_rev" -- modules | wc -l || true)
[ "${present:-0}" -gt 0 ] || die \
  "no '= lib.mkDefault ...' line anywhere under modules/ at $to: the scan for the defaults this port sets has stopped matching, and reporting that none of them moved would be a lie"

# -U0 so only changed lines come through, and the +++ header is tracked so each
# one can say which module it is in.
#
# The line is quoted as written, which means without the attribute set it sits
# inside: #201's shows as `printing.browsed.enable = ...`, not
# `services.printing.browsed.enable = ...`. Reconstructing that prefix needs a
# Nix parser rather than a diff, and the file name plus the leaf is enough to
# find it. If that stops being true, the fix is to evaluate the two
# configurations and diff them, not to teach awk about nesting.
sysdefaults=$(git diff -U0 "$from_rev" "$to_rev" -- modules |
  awk -v re="^[+-][ \t]*$mkdefault_body" '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    $0 ~ re { printf "%s\t%s\t%s\n", substr($0, 1, 1), file, substr($0, 2) }
  ' || true)

if [ -n "$sysdefaults" ]; then
  echo "**NixOS defaults this port sets.** Not options of ours -- these are"
  echo "settings nixarchy chooses on your behalf, and a machine that never"
  echo "mentioned them follows the new value."
  echo
  echo "$sysdefaults" | awk -F'\t' '
    { gsub(/^[ \t]+|[ \t]+$/, "", $3)
      printf "- %s `%s` in `%s`\n", ($1 == "+" ? "now" : "no longer"), $3, $2 }'
  echo
else
  echo "No NixOS default this port sets moved."
  echo
fi

# --- 3. package changes -----------------------------------------------------

# The hand-pinned apps. Everything else follows nixpkgs or upstream's own
# flake and moves when the lock does; these move because somebody edited a
# version and a hash, which is a decision worth naming.
versions_at() { # rev -> "name<TAB>version" for every pkgs/apps/*.nix that pins one
  local rev=$1 f name v
  for f in $(git ls-tree --name-only "$rev" pkgs/apps/); do
    case $f in
    *.nix) ;;
    *) continue ;;
    esac
    name=$(basename "$f" .nix)
    # The one-liner pkgs/apps/once.nix's own updateScript uses to find the
    # version it is about to rewrite. head -1 because those updateScripts
    # quote the pattern again further down the same file.
    v=$(git show "$rev:$f" | sed -n 's/.*version = "\([^"]*\)".*/\1/p' | head -1 || true)
    if [ -n "$v" ]; then
      printf '%s\t%s\n' "$name" "$v"
    fi
  done
}

versions_at "$from_rev" | sort >"$work/pins-from.tsv"
versions_at "$to_rev" | sort >"$work/pins-to.tsv"
[ -s "$work/pins-to.tsv" ] || die \
  "no 'version = \"...\"' line in any pkgs/apps/*.nix at $to: the scan for this repo's pinned versions has stopped matching, and reporting that no package moved would be a lie"

pinmoves=$(join -t"$(printf '\t')" "$work/pins-from.tsv" "$work/pins-to.tsv" | awk -F'\t' '$2 != $3')
newpins=$(join -t"$(printf '\t')" -v2 "$work/pins-from.tsv" "$work/pins-to.tsv")
droppedpins=$(join -t"$(printf '\t')" -v1 "$work/pins-from.tsv" "$work/pins-to.tsv")

echo "## Package changes"
echo
echo "Packages this repo pins by hand, rather than taking from nixpkgs."
echo
if [ -z "$pinmoves$newpins$droppedpins" ]; then
  # Said out loud. An absent section reads the same whether nothing moved or
  # the scan above stopped finding versions, and those mean opposite things.
  echo "None of them moved. Still at the versions \`$from\` shipped:"
  echo
  awk -F'\t' '{ printf "- `%s` %s\n", $1, $2 }' "$work/pins-to.tsv"
  echo
else
  if [ -n "$pinmoves" ]; then
    echo "$pinmoves" | awk -F'\t' '{ printf "- `%s` %s → %s\n", $1, $2, $3 }'
  fi
  if [ -n "$newpins" ]; then
    echo "$newpins" | awk -F'\t' '{ printf "- `%s` %s, packaged here for the first time\n", $1, $2 }'
  fi
  if [ -n "$droppedpins" ]; then
    echo "$droppedpins" | awk -F'\t' '{ printf "- `%s` is no longer packaged here (was %s)\n", $1, $2 }'
  fi
  echo
fi

# --- 4. everything else -----------------------------------------------------

echo "## Everything else"
echo
echo "Every merged change, grouped by where in the tree it landed. This repo"
echo "writes commit subjects as full sentences, so they are already the notes."
echo

# Grouped by path rather than by judgement. The order below IS the rule: the
# first bucket a commit touches wins, so a change that moves the installer and
# its documentation is filed under the installer. Nothing here reads a subject
# and decides what kind of change it was, because that is the step that turns
# derived notes back into invented ones.
bucket() { # rev -> label
  local files
  files=$(git show --pretty=format: --name-only "$1")
  case $files in
  *installer/* | *vm/*) echo "Installing, and the ISO" ;;
  *modules/* | *data/*) echo "The desktop and what it configures" ;;
  *pkgs/*) echo "Packaged programs and the vendored tree" ;;
  *tests/* | *.github/*) echo "Checks and CI" ;;
  *docs/* | *.md*) echo "Documentation" ;;
  *) echo "Elsewhere" ;;
  esac
}

: >"$work/log.tsv"
while read -r rev; do
  [ -n "$rev" ] || continue
  printf '%s\t%s\n' "$(bucket "$rev")" "$(git log -1 --format=%s "$rev")" >>"$work/log.tsv"
done < <(git log --no-merges --format=%H "$from_rev..$to_rev")

[ -s "$work/log.tsv" ] || die "no commits between $from and $to"

for label in \
  "The desktop and what it configures" \
  "Installing, and the ISO" \
  "Packaged programs and the vendored tree" \
  "Checks and CI" \
  "Documentation" \
  "Elsewhere"; do
  grep -F "$label$(printf '\t')" "$work/log.tsv" >"$work/bucket" || continue
  echo "### $label"
  echo
  cut -f2- "$work/bucket" | sed 's/^/- /'
  echo
done

echo "$(wc -l <"$work/log.tsv") changes since \`$from\`."
