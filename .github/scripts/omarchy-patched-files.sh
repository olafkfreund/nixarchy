#!/usr/bin/env bash
# Which of the files upstream changed are files this port has its hands on.
#
# An Omarchy release touches 167 files (4.0.1 -> 4.0.2). Twenty-seven of them
# are bins this port replaces outright with a NixOS stub, a few dozen more are
# patched by substituteInPlace, one is copied here and pinned by sha256, and
# the whole of config/ is seeded into ~/.config. Everything else upstream
# changed is carried through untouched and needs no thought. The intersection
# is the part that does -- and it is five files out of 167, which is a
# reviewer's ten seconds rather than an afternoon of diffing.
#
# 4.0.2 is the example. `bin/omarchy-plymouth-set` is in the intersection, and
# the commits behind it are "security/plymouth-publication-race (#8934)" and
# "Stop an installed theme from running code (#7884)". A security fix landed
# upstream in a file this port replaces entirely with a stub. Harmless here --
# the stub does not run theme code either -- but that is a conclusion somebody
# should reach on purpose, and nothing in the bump PR said the file had moved.
#
# The set of files this port patches is DERIVED from what the repo already
# states, never listed here. A hand-kept list is the thing that goes stale in
# silence: it keeps naming a bin that was deleted and stops naming the one
# added last week, and the report stays reassuring throughout. The four
# statements it reads:
#
#   pkgs/omarchy/nix-bin/*                     bins replaced by a stub
#   substituteInPlace $out/share/omarchy/PATH  files patched in the package
#   ${src}/PATH beside a sha256sum             a file copied here and pinned
#   seed_dir "${omarchyPath}/config"           the tree seeded into ~/.config
#
# Each of those is a grep, and a grep that matches nothing passes quietly, so
# all four must produce something or this refuses to print. tests/patched-
# files.nix runs it against the real repo files for that reason.
#
# Attribution is a second pass, because it needs a network and this does not:
# --list prints the intersecting paths, the workflow asks GitHub which commits
# in the range touched each one, and the second call renders them.
#
# Usage: omarchy-patched-files.sh [--list] <changed-files> <repo-root> \
#          [attribution-file] [old-tag] [new-tag]
#
#   changed-files     one upstream path per line (gh api compare .files[].filename)
#   attribution-file  optional, "<path><TAB><commit subject>" lines
set -euo pipefail

list_only=""
[ "${1:-}" = "--list" ] && {
  list_only=yes
  shift
}

changed_file=${1:?usage: omarchy-patched-files.sh [--list] <changed-files> <repo-root> [attribution] [old-tag] [new-tag]}
root=${2:?usage: omarchy-patched-files.sh [--list] <changed-files> <repo-root> [attribution] [old-tag] [new-tag]}
attrib=${3:-}
old_tag=${4:-old}
new_tag=${5:-new}

pkg=$root/pkgs/omarchy/default.nix
home=$root/modules/home.nix

# Each source emits "<upstream path><TAB><why this port cares>". A path ending
# in / is a prefix: everything under it counts.
stubs=$(
  find "$root/pkgs/omarchy/nix-bin" -maxdepth 1 -type f -printf 'bin/%f\n' 2>/dev/null |
    sort || true
)
# Literal paths only. `substituteInPlace $out/share/omarchy/bin/$f` inside a
# loop leaves the prefix `bin/`, and a prefix of `bin/` matches every bin
# upstream touched -- 5 files worth reading would become 100 nobody reads. The
# names those loops iterate are recoverable one line above them, so take them
# from there instead.
patched=$(
  {
    grep -ohE 'substituteInPlace \$out/share/omarchy/[A-Za-z0-9._/-]+' "$pkg" 2>/dev/null |
      sed 's|.*share/omarchy/||' | grep -vE '/$' || true
    grep -ohE '^ *for f in (omarchy-[A-Za-z0-9._-]+ *)+; do' "$pkg" 2>/dev/null |
      sed -E 's/^ *for f in //;s/; do$//' | tr ' ' '\n' | sed 's|^|bin/|' || true
  } | grep -vE '^$' | sort -u || true
)
pinned=$(
  grep -ohE '\$\{src\}/[A-Za-z0-9._/-]+' "$pkg" 2>/dev/null |
    sed 's|^\${src}/||' | sort -u || true
)
seeded=$(
  grep -ohE 'seed_dir "\$\{omarchyPath\}/[A-Za-z0-9._/-]+"' "$home" 2>/dev/null |
    sed -E 's|.*omarchyPath\}/||;s|"$|/|' | sort -u || true
)

# See the header: four greps against files that move. All four have to find
# something, or the intersection below is empty for a reason that has nothing
# to do with this release.
derived_or_die() {
  [ -n "$1" ] || {
    echo "patched files: found nothing from $2." >&2
    echo "patched files: that source moved or was renamed. Refusing to report" >&2
    echo "patched files: an empty intersection as if it meant nothing changed." >&2
    exit 1
  }
}
derived_or_die "$stubs" "pkgs/omarchy/nix-bin/"
derived_or_die "$patched" "substituteInPlace in pkgs/omarchy/default.nix"
derived_or_die "$pinned" "\${src}/ in pkgs/omarchy/default.nix"
derived_or_die "$seeded" "seed_dir in modules/home.nix"

reasons() {
  echo "$stubs" | sed 's|$|\treplaced entirely by a NixOS stub in `pkgs/omarchy/nix-bin/`|'
  echo "$patched" | sed 's|$|\tpatched by `substituteInPlace` in `pkgs/omarchy/default.nix`|'
  echo "$pinned" | sed 's|$|\tread straight out of the source by `pkgs/omarchy/default.nix` (copied, rewritten, or sha256-pinned)|'
  echo "$seeded" | sed 's|$|\tseeded into `~/.config` by `modules/home.nix`|'
}

ours=$(reasons | grep -vE '^[[:space:]]*$' | sort -u)
total=$(grep -cvE '^\s*$' "$changed_file" || true)

# One pass over the changed files, matching each against the derived set --
# exact for a path, prefix for anything ending in /.
hits=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # No `| head -1` here. Under `set -o pipefail` head closing the pipe early
  # kills the loop with SIGPIPE and the whole command substitution reports
  # failure, which under `set -e` ends the script with no output and no
  # message -- exactly the silent-empty failure this script exists to prevent.
  why=""
  while IFS=$'\t' read -r p reason; do
    [ -n "$why" ] && continue
    case "$p" in
    */) case "$f" in "$p"*) why=$reason ;; esac ;;
    *) if [ "$f" = "$p" ]; then why=$reason; fi ;;
    esac
  done <<<"$ours"
  if [ -n "$why" ]; then hits="$hits$f"$'\t'"$why"$'\n'; fi
done <"$changed_file"
hits=${hits%$'\n'}

if [ -n "$list_only" ]; then
  [ -n "$hits" ] && echo "$hits" | cut -f1
  exit 0
fi

echo "### Files this port patches that $new_tag changed"
echo

if [ -z "$hits" ]; then
  echo "$total files changed between $old_tag and $new_tag, and none of them is"
  echo "a file this port replaces, patches, pins or seeds. Nothing here needs a"
  echo "second reading."
  exit 0
fi

count=$(echo "$hits" | wc -l)
echo "$total files changed between $old_tag and $new_tag. $count of them are files"
echo "this port has its hands on -- where upstream's change and this port's"
echo "change meet. The rest is carried through untouched."
echo

echo "$hits" | while IFS=$'\t' read -r f reason; do
  echo "- \`$f\` — $reason"
  [ -n "$attrib" ] && [ -f "$attrib" ] && {
    awk -F'\t' -v want="$f" '$1 == want { print "  - " $2 }' "$attrib"
  }
done
echo
echo "Read the subjects, not the diffs. An upstream fix in a file this port"
echo "replaces with a stub does not reach a nixarchy machine -- which is fine"
echo "right up until it is a security fix, and then it is a decision somebody"
echo "has to make on purpose."

exit 0
