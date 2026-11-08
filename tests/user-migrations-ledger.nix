{ pkgs, omarchySrc }:
# Every Omarchy migration that touches a user's files has a decision in
# data/user-migrations.nix, or is listed there as predating v4.0.6 (#1610).
# Why: pkgs/AGENTS.md#user-file-migrations-1610
let
  ledger = pkgs.writeText "user-migrations.json" (
    builtins.toJSON (import ../data/user-migrations.nix)
  );
in
pkgs.runCommand "nixarchy-user-migrations-ledger"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    hits=$(grep -lE 'HOME|XDG_CONFIG|\.config|shell\.json' ${omarchySrc}/migrations/*.sh) || {
      echo "no migration in ${omarchySrc}/migrations matched the triage grep" >&2
      exit 1
    }
    # An empty list is not "all decided" (AGENTS.md §4).
    [ -n "$hits" ] || { echo "the triage grep found nothing" >&2; exit 1; }
    for f in $hits; do
      f=''${f##*/}
      printf '%s\n' "''${f%.sh}"
    done | sort >triage
    ids=$(jq -r '(del(.predates) | keys[]), .predates[]' ${ledger}) || exit 1
    printf '%s\n' "$ids" | sort >ledger
    status=0
    missing=$(comm -23 triage ledger)
    extra=$(comm -13 triage ledger)
    if [ -n "$missing" ]; then
      echo "migrations that touch user files with no row in data/user-migrations.nix:" >&2
      printf '  %s\n' $missing >&2
      status=1
    fi
    if [ -n "$extra" ]; then
      echo "rows in data/user-migrations.nix that the pinned source does not need:" >&2
      printf '  %s\n' $extra >&2
      status=1
    fi
    dupes=$(sort ledger | uniq -d)
    if [ -n "$dupes" ]; then
      echo "ids both decided and listed in predates:" >&2
      printf '  %s\n' $dupes >&2
      status=1
    fi
    bad=$(jq -r 'del(.predates) | to_entries[]
      | select(.value.decision | IN("ported", "partial", "not-needed", "declined") | not)
      | "\(.key): \(.value.decision)"' ${ledger}) || exit 1
    if [ -n "$bad" ]; then
      echo "rows whose decision is not ported, partial, not-needed or declined:" >&2
      printf '  %s\n' "$bad" >&2
      status=1
    fi
    [ "$status" = 0 ] || exit 1
    echo "$(wc -l <triage) user-file migrations, every one decided"
    touch $out
  ''
