# Takes ai-mirror's MCP server back out of the three agent configs when
# programs.nixarchy.aiMirror.mcp is off (#773). The helpers that put it there
# only ever add -- mergeJson merges, appendToml appends -- so without this,
# turning the option off would leave every agent still able to reach the
# desktop. Plan: plan/2026-09-22-773-ai-mirror-default.md, deviation 2.
#
# It removes an entry ONLY if its command is a store path ending in
# /bin/ai-mirror, which is what nixarchy writes. An entry the user wrote by
# hand (`command = "ai-mirror"`, or anything else) is theirs and stays.
#
# Its own package so tests/ai-mirror-mcp-remove.nix runs this exact code
# against fixtures, rather than a copy of it.
{
  writeShellApplication,
  jq,
  gawk,
  coreutils,
}:
writeShellApplication {
  name = "nixarchy-ai-mirror-mcp-remove";
  runtimeInputs = [
    jq
    gawk
    coreutils
  ];
  text = ''
    # Usage: nixarchy-ai-mirror-mcp-remove <claude.json> <opencode.json> <codex.toml>
    claude=$1 opencode=$2 codex=$3
    ours='^/nix/store/[a-z0-9]{32}-[^/]+/bin/ai-mirror$'

    # file, the jq path to the entry, the jq path to its command within it
    json_drop() {
      local f=$1 key=$2 cmd=$3 tmp
      [ -s "$f" ] || return 0
      jq -e --arg re "$ours" "($key | $cmd // \"\") | test(\$re)" "$f" >/dev/null 2>&1 || return 0
      tmp=$(mktemp)
      if jq "del($key)" "$f" >"$tmp"; then
        mv "$tmp" "$f"
        echo "nixarchy: removed ai-mirror's MCP server from $f"
      else
        rm -f "$tmp"
        echo "nixarchy: could not remove ai-mirror's MCP server from $f" >&2
      fi
    }
    json_drop "$claude" '.mcpServers["ai-mirror"]' '.command'
    json_drop "$opencode" '.mcp["ai-mirror"]' '.command[0]'

    # Codex: drop the [mcp_servers.ai-mirror] table if its command is ours,
    # with the two comment lines and the blank line appendToml wrote above it.
    [ -s "$codex" ] || exit 0
    tmp=$(mktemp)
    awk -v re="$ours" '
      function flush_pend() { for (i = 1; i <= np; i++) print pend[i]; np = 0 }
      function end_table(   keep, i, c) {
        keep = 1
        for (i = 1; i <= nt; i++) if (tab[i] ~ /^command *= *"/) {
          c = tab[i]; sub(/^command *= *"/, "", c); sub(/".*$/, "", c)
          if (c ~ re) keep = 0
        }
        if (keep) { flush_pend(); for (i = 1; i <= nt; i++) print tab[i] }
        else {
          for (i = 1; i <= np; i++)
            if (pend[i] !~ /^$|-- added by nixarchy\.|programs\.nixarchy in your configuration decides/) print pend[i]
          np = 0; dropped = 1
        }
        nt = 0; intable = 0
      }
      /^\[/ { if (intable) end_table() }
      $0 == "[mcp_servers.ai-mirror]" { intable = 1; tab[++nt] = $0; next }
      intable { tab[++nt] = $0; next }
      /^$|^#/ { pend[++np] = $0; next }
      { flush_pend(); print }
      END { if (intable) end_table(); flush_pend(); exit dropped ? 0 : 3 }
    ' "$codex" >"$tmp" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
      mv "$tmp" "$codex"
      echo "nixarchy: removed ai-mirror's MCP server from $codex"
    else
      rm -f "$tmp"
      [ "$rc" -eq 3 ] || echo "nixarchy: could not read $codex" >&2
    fi
  '';
}
