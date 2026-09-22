# pkgs/ai-mirror-mcp-remove.nix takes ai-mirror's MCP server back out of the
# agent configs when programs.nixarchy.aiMirror.mcp is off (#773). Two ways it
# can be wrong, and this runs the real package against fixtures for both:
#
# - it leaves nixarchy's entry in place, and turning the option off stops
#   nothing -- the agents can still reach the desktop;
# - it removes an entry the user wrote themselves, which is not ours to touch.
#
# printf, not heredocs: a heredoc in an indented Nix string reindents the file
# under nixfmt (AGENTS.md section 5).
{ pkgs }:
let
  remove = pkgs.callPackage ../pkgs/ai-mirror-mcp-remove.nix { };
  ours = "/nix/store/00000000000000000000000000000000-ai-mirror-2.0.0/bin/ai-mirror";
in
pkgs.runCommand "nixarchy-ai-mirror-mcp-remove" { nativeBuildInputs = [ pkgs.jq ]; } ''
  fail() { echo "FAIL: $*"; exit 1; }

  # nixarchy's entries, beside things that are not ours and must survive.
  printf '%s\n' '{"theme":"dark","mcpServers":{"ai-mirror":{"command":"${ours}","args":["mcp"]},"nixos":{"command":"mcp-nixos"}}}' > claude.json
  printf '%s\n' '{"mcp":{"ai-mirror":{"type":"local","command":["${ours}","mcp"]},"nixos":{"type":"local","command":["mcp-nixos"]}}}' > opencode.json
  printf '%s\n' '[model]' 'name = "x"' "" \
    "# The NixOS MCP server -- added by nixarchy. Delete this block to be rid of it;" \
    "# programs.nixarchy in your configuration decides whether it comes back." \
    '[mcp_servers.nixos]' 'command = "mcp-nixos"' "" \
    "# ai-mirror's MCP server -- added by nixarchy. Delete this block to be rid of it;" \
    "# programs.nixarchy in your configuration decides whether it comes back." \
    '[mcp_servers.ai-mirror]' 'command = "${ours}"' 'args = ["mcp"]' "" \
    '[profiles.work]' 'model = "y"' > codex.toml

  ${remove}/bin/nixarchy-ai-mirror-mcp-remove claude.json opencode.json codex.toml

  jq -e '.mcpServers | has("ai-mirror") | not' claude.json >/dev/null || fail "claude: nixarchy's ai-mirror entry was left in place"
  jq -e '.mcpServers.nixos and .theme == "dark"' claude.json >/dev/null || fail "claude: an unrelated key was lost"
  jq -e '.mcp | has("ai-mirror") | not' opencode.json >/dev/null || fail "opencode: nixarchy's ai-mirror entry was left in place"
  jq -e '.mcp.nixos' opencode.json >/dev/null || fail "opencode: an unrelated server was lost"
  ! grep -qF '[mcp_servers.ai-mirror]' codex.toml || fail "codex: nixarchy's ai-mirror table was left in place"
  ! grep -qF "ai-mirror's MCP server -- added by nixarchy" codex.toml || fail "codex: nixarchy's header for the table was left behind"
  for keep in '[mcp_servers.nixos]' 'command = "mcp-nixos"' '[profiles.work]' 'model = "y"' '[model]' \
    "# The NixOS MCP server -- added by nixarchy."; do
    grep -qF "$keep" codex.toml || fail "codex: lost '$keep', which is not ai-mirror's"
  done

  # Entries the user wrote by hand: a bare command, not a store path. Kept.
  printf '%s\n' '{"mcpServers":{"ai-mirror":{"command":"ai-mirror","args":["mcp"]}}}' > claude.json
  printf '%s\n' '{"mcp":{"ai-mirror":{"type":"local","command":["ai-mirror","mcp"]}}}' > opencode.json
  printf '%s\n' '[mcp_servers.ai-mirror]' 'command = "ai-mirror"' 'args = ["mcp"]' > codex.toml
  cp claude.json claude.before; cp opencode.json opencode.before; cp codex.toml codex.before

  ${remove}/bin/nixarchy-ai-mirror-mcp-remove claude.json opencode.json codex.toml

  cmp -s claude.json claude.before || fail "claude: removed an ai-mirror entry the user wrote"
  cmp -s opencode.json opencode.before || fail "opencode: removed an ai-mirror entry the user wrote"
  cmp -s codex.toml codex.before || fail "codex: removed an ai-mirror table the user wrote"

  # Nothing there at all is not an error.
  ${remove}/bin/nixarchy-ai-mirror-mcp-remove missing.json missing2.json missing.toml

  echo "ai-mirror-mcp-remove: ours removed from all three, the user's kept in all three"
  touch $out
''
