{ pkgs, ... }:
# #1060: a pipe into grep -q can fail because grep matched (#1058). Every
# such line in the tree is either rewritten or listed, with the reason it
# cannot fail, in tests/grep-q-allowlist.txt. This fails on a new one and
# on a listed one that is gone. Why: tests/AGENTS.md#a-pipe-into-grep-q-can-fail-because-grep-matched
let
  inherit (pkgs) lib;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../tests
      ../modules
      ../pkgs
      ../installer
      ../.github
      ../flake.nix
    ];
  };
in
pkgs.runCommand "nixarchy-grep-q-pipefail" { } ''
  cd ${src}
  allow=tests/grep-q-allowlist.txt
  work=$(mktemp -d)

  rc=0
  grep -rnE --include='*.nix' --include='*.sh' --include='*.yml' \
    '(^|[^|])\|[[:space:]]*grep( +-[-a-zA-Z0-9]+)* +(-[a-zA-Z]*q|--quiet|--silent)' \
    tests modules pkgs installer .github flake.nix >"$work/hits" || rc=$?
  [ "$rc" -le 1 ] || { echo "grep failed (exit $rc), so nothing was scanned" >&2; exit 1; }

  # --include misses an extensionless script (37 of our own live in
  # pkgs/omarchy/nix-bin/). Find every extensionless file under the same
  # roots whose first line is a bash/sh shebang, and scan those too. This
  # never reaches the vendored upstream Omarchy tree: that source is fetched
  # by the omarchy derivation at build time and is never part of this git
  # tree, so nothing under pkgs/ here is upstream's.
  : >"$work/shebang_files"
  while IFS= read -r -d "" f; do
    first_line=$(head -n1 "$f")
    if [[ $first_line =~ ^#!.*(/|[[:space:]])(bash|sh)([[:space:]]|$) ]]; then
      printf '%s\n' "$f" >>"$work/shebang_files"
    fi
  done < <(find tests modules pkgs installer .github -type f ! -name '*.*' -print0)

  if [ -s "$work/shebang_files" ]; then
    rc=0
    xargs -r -a "$work/shebang_files" grep -nE \
      '(^|[^|])\|[[:space:]]*grep( +-[-a-zA-Z0-9]+)* +(-[a-zA-Z]*q|--quiet|--silent)' \
      >>"$work/hits" || rc=$?
    [ "$rc" -le 1 ] || { echo "grep failed (exit $rc) on extensionless scripts" >&2; exit 1; }
  fi

  # path TAB trimmed text TAB line number. A comment is prose, not a pipeline.
  awk '{
    p = index($0, ":"); path = substr($0, 1, p - 1); rest = substr($0, p + 1)
    q = index(rest, ":"); ln = substr(rest, 1, q - 1); text = substr(rest, q + 1)
    sub(/^[[:space:]]+/, "", text); sub(/[[:space:]]+$/, "", text)
    if (text ~ /^#/) next
    print path "\t" text "\t" ln
  }' "$work/hits" >"$work/found"

  n=$(wc -l <"$work/found")
  [ "$n" -ge 50 ] || { echo "only $n sites found: the scan is broken, not the tree clean" >&2; exit 1; }

  awk -F'\t' '/^#/ || /^$/ { next } NF != 3 || $3 == "" { print "malformed: " FILENAME ":" FNR }' "$allow" >"$work/malformed"
  if [ -s "$work/malformed" ]; then cat "$work/malformed" >&2; exit 1; fi

  # One entry per occurrence; comm pairs duplicates one for one.
  export LC_ALL=C
  cut -f1,2 "$work/found" | sort >"$work/have"
  awk -F'\t' '/^#/ || /^$/ { next } { print $1 "\t" $2 }' "$allow" | sort >"$work/want"
  comm -23 "$work/have" "$work/want" >"$work/new"
  comm -13 "$work/have" "$work/want" >"$work/stale"

  fail=0
  if [ -s "$work/new" ]; then
    echo "NEW: a pipe into grep -q that nobody has reviewed. Rewrite it, or allowlist it in $allow with a reason:" >&2
    awk -F'\t' 'NR == FNR { new[$0] = 1; next } ($1 "\t" $2) in new { print "  " $1 ":" $3 ": " $2 }' "$work/new" "$work/found" >&2
    fail=1
  fi
  if [ -s "$work/stale" ]; then
    echo "STALE: allowlisted in $allow, but no longer in the tree. Delete the entry:" >&2
    sed 's/^/  /' "$work/stale" >&2
    fail=1
  fi
  [ "$fail" = 0 ] || exit 1
  echo "$n pipes into grep -q, each one allowlisted with its reason"
  touch $out
''
