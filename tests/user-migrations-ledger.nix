{ pkgs, omarchySrc }:
# Every Omarchy migration that touches a user's files has a decision in
# data/user-migrations.nix, or is listed there as predating v4.0.6 (#1610).
# Why: pkgs/AGENTS.md#user-file-migrations-1610
let
  # Edge pins carry an `edge-` version; rows may be marked edge = "only" or "absent".
  isEdge = if pkgs.lib.hasPrefix "edge-" pkgs.omarchy.version then "true" else "false";
  ledger = pkgs.writeText "user-migrations.json" (
    builtins.toJSON (import ../data/user-migrations.nix)
  );
  commandsLedger = pkgs.writeText "user-migration-commands.json" (
    builtins.toJSON (import ../data/user-migration-commands.nix)
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
    hits=$(grep -lE 'HOME|XDG_CONFIG|\.config|shell\.json|~/' ${omarchySrc}/migrations/*.sh) || {
      echo "no migration in ${omarchySrc}/migrations matched the triage grep" >&2
      exit 1
    }
    # An empty list is not "all decided" (AGENTS.md §4).
    [ -n "$hits" ] || { echo "the triage grep found nothing" >&2; exit 1; }
    for f in $hits; do
      f=''${f##*/}
      printf '%s\n' "''${f%.sh}"
    done | sort >triage
    : >command-callers
    for f in ${omarchySrc}/migrations/*.sh; do
      id=''${f##*/}
      id=''${id%.sh}
      if grep -qxF "$id" triage; then continue; fi
      words=$(grep -oE 'omarchy-[a-z0-9-]+' "$f") || {
        [ "$?" = 1 ] || exit 1
        continue
      }
      for command in $words; do
        bin=${omarchySrc}/bin/$command
        if [ -f "$bin" ] && grep -qE 'HOME|XDG_CONFIG|\.config|shell\.json|~/' "$bin"; then
          printf '%s\t%s\n' "$command" "$id" >>command-callers
        fi
      done
    done
    cut -f1 command-callers | sort -u >needed-commands
    [ ! -s command-callers ] || [ -s needed-commands ] || {
      echo "the command scan found callers but no commands" >&2
      exit 1
    }
    ids=$(jq -r '(del(.predates) | keys[]), .predates[]' ${ledger}) || exit 1
    printf '%s\n' "$ids" | sort >ledger
    status=0
    # Every row is validated under both pins; only then are inactive ones dropped.
    bad_edge=$(jq -r 'del(.predates) | to_entries[]
      | select(.value | has("edge")) | select(.value.edge | IN("only", "absent") | not)
      | "\(.key): edge=\(.value.edge)"' ${ledger}) || exit 1
    if [ -n "$bad_edge" ]; then
      echo "rows whose edge marker is not only or absent:" >&2
      printf '  %s\n' "$bad_edge" >&2
      status=1
    fi
    jq --argjson edge ${isEdge} 'del(.predates) | with_entries(
      select((.value.edge // "") as $e | ($e == "only" and ($edge | not) or $e == "absent" and $edge) | not))' ${ledger} >active-ledger
    active=$(jq -r 'keys[]' active-ledger && jq -r '.predates[]' ${ledger}) || exit 1
    printf '%s\n' "$active" | sort >active
    old_via=$(jq -r 'del(.predates) | to_entries[] | select(.value | has("via")) | .key' ${ledger}) || exit 1
    if [ -n "$old_via" ]; then
      echo "rows with an obsolete via field:" >&2
      printf '  %s\n' $old_via >&2
      status=1
    fi
    bad_command_edge=$(jq -r 'to_entries[]
      | select(.value | has("edge")) | select(.value.edge | IN("only", "absent") | not)
      | "\(.key): edge=\(.value.edge)"' ${commandsLedger}) || exit 1
    if [ -n "$bad_command_edge" ]; then
      echo "command rows whose edge marker is not only or absent:" >&2
      printf '  %s\n' "$bad_command_edge" >&2
      status=1
    fi
    bad_command=$(jq -r 'to_entries[]
      | select((.value.follow | type) != "boolean" or (.value.reason | type) != "string" or .value.reason == "")
      | "\(.key): follow must be boolean and reason non-empty"' ${commandsLedger}) || exit 1
    if [ -n "$bad_command" ]; then
      echo "malformed rows in data/user-migration-commands.nix:" >&2
      printf '  %s\n' "$bad_command" >&2
      status=1
    fi
    jq --argjson edge ${isEdge} 'with_entries(
      select((.value.edge // "") as $e | ($e == "only" and ($edge | not) or $e == "absent" and $edge) | not))' ${commandsLedger} >active-commands
    jq -r 'keys[]' active-commands >active-command-names
    missing_commands=$(comm -23 needed-commands active-command-names)
    extra_commands=$(comm -13 needed-commands active-command-names)
    if [ -n "$missing_commands" ]; then
      echo "commands a migration runs with no row in data/user-migration-commands.nix:" >&2
      printf '  %s\n' $missing_commands >&2
      status=1
    fi
    if [ -n "$extra_commands" ]; then
      echo "rows in data/user-migration-commands.nix that the pinned source does not need:" >&2
      printf '  %s\n' $extra_commands >&2
      status=1
    fi
    while IFS=$'\t' read -r command id; do
      [ -n "$command" ] || continue
      if [ "$(jq -r --arg command "$command" '.[$command].follow' active-commands)" = true ]; then
        printf '%s\n' "$id" >>triage
      fi
    done <command-callers
    sort -u triage -o triage
    missing=$(comm -23 triage active)
    extra=$(comm -13 triage active)
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
    bad_run=$(jq -r 'del(.predates) | to_entries[]
      | select((.value.decision | IN("ported", "partial")) and (.value.run | IN("bar", "upstream", "edited", "port") | not)
          or ((.value.decision | IN("ported", "partial") | not) and (.value | has("run"))))
      | "\(.key): decision=\(.value.decision), run=\(.value.run // "missing")"' ${ledger}) || exit 1
    if [ -n "$bad_run" ]; then
      echo "rows with a missing, invalid or misplaced run:" >&2
      printf '  %s\n' "$bad_run" >&2
      status=1
    fi
    [ "$status" = 0 ] || exit 1
    echo "$(wc -l <triage) user-file migrations, every one decided"
    touch $out
  ''
