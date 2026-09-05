{
  pkgs,
  server,
  skill,
}:
# The vendored MCP server, held to the contract its own kit documents (#268).
#
# share/agent-bus/agent_bus_mcp.py is a COPY of a file in the maintainers'
# config repo, and that repo is not visible from CI -- so nothing here can
# diff the two, and a checksum committed alongside only fires when the person
# re-vendoring remembers to update it, which is precisely the person who did
# not forget. The failure worth defending against is the other one: a copy
# that is subtly behind and still runs. #268 puts it plainly -- a stale copy
# that *almost* works is worse than an obviously missing one.
#
# So this asserts the one thing CI CAN see: the vendored file, started over
# real MCP stdio the way an agent starts it, still honours the contract
# SKILL.md hands to guests. Every call shape the skill teaches must be
# accepted; no tool may appear or vanish unannounced; and the `--peek` CLI
# mode hooks/bus-peek.sh shells out to must exist and stay quiet offline.
# A re-vendored copy that breaks any of that fails here, whether or not
# anyone remembered there was a check.
#
# And per AGENTS.md 1, the check proves it can fail: the same comparison runs
# a second time against a deliberately tampered copy, and the check fails if
# THAT run passes. A comparator that extracts nothing and shrugs -- the
# coverage guard's own former failure -- cannot get through this green.
let
  python = pkgs.python3.withPackages (p: [
    p.mcp
    p.httpx
  ]);
in
pkgs.runCommand "nixarchy-bus-mcp" { nativeBuildInputs = [ python ]; } ''
  cp ${server} agent_bus_mcp.py
  cp ${skill} SKILL.md

  # The server writes cursors under XDG state; give it somewhere harmless.
  export HOME=$PWD
  export AGENT_BUS_STATE=$PWD/state
  # Point at a dead loopback port so nothing in this build can reach a real
  # homeserver even by accident -- the sandbox forbids it anyway, but the
  # check should not depend on the sandbox for that property.
  export MATRIX_HOMESERVER=http://127.0.0.1:1
  export MATRIX_ACCESS_TOKEN=syt_not_a_real_token
  export MATRIX_USER_ID=@check:freundcloud.org.uk

  cat > contract.py <<'PY'
  """Start an MCP server over stdio and hold it to SKILL.md's tool table.

  Documented is the contract, actual is the vendored file. The rules are
  directional on purpose:

    1. the tool NAMES must match exactly -- SKILL.md says "Five, over MCP",
       and a sixth tool (or a fourth) is drift someone should look at;
    2. every documented parameter must exist on the tool -- the skill
       teaches calls, and a taught call must be accepted;
    3. every parameter the server REQUIRES must be documented as required --
       a new mandatory argument breaks every caller following the doc;
    4. a parameter documented optional must stay optional, same reason.

  What is deliberately allowed: undocumented OPTIONAL parameters (read_new's
  `limit`, search's `agent`). SKILL.md is guest-facing and simplifies; an
  optional the doc omits breaks no taught call.
  """
  import asyncio
  import re
  import sys

  from mcp import ClientSession, StdioServerParameters
  from mcp.client.stdio import stdio_client

  SIG = re.compile(r"^\|\s*`([a-z_]+)\(([^)]*)\)`")


  def documented(path):
      tools = {}
      for line in open(path):
          m = SIG.match(line)
          if not m:
              continue
          params = [p.strip() for p in m.group(2).split(",") if p.strip()]
          tools[m.group(1)] = {
              "required": {p for p in params if not p.endswith("?")},
              "optional": {p[:-1] for p in params if p.endswith("?")},
          }
      return tools


  async def actual(path):
      params = StdioServerParameters(command=sys.executable, args=[path])
      async with stdio_client(params) as (r, w):
          async with ClientSession(r, w) as session:
              await session.initialize()
              listed = await session.list_tools()
      tools = {}
      for t in listed.tools:
          schema = t.inputSchema or {}
          props = set(schema.get("properties", {}))
          required = set(schema.get("required", []))
          tools[t.name] = {"required": required, "optional": props - required}
      return tools


  def compare(doc, act):
      errs = []
      if set(doc) != set(act):
          errs.append(f"tool names: documented {sorted(doc)}, server offers {sorted(act)}")
      for name in sorted(set(doc) & set(act)):
          d, a = doc[name], act[name]
          taught = d["required"] | d["optional"]
          offered = a["required"] | a["optional"]
          if not taught <= offered:
              errs.append(f"{name}: documented params {sorted(taught - offered)} do not exist")
          if not a["required"] <= d["required"]:
              errs.append(
                  f"{name}: server requires {sorted(a['required'] - d['required'])},"
                  " which SKILL.md does not teach as required"
              )
          if d["optional"] & a["required"]:
              errs.append(
                  f"{name}: {sorted(d['optional'] & a['required'])} documented"
                  " optional but the server now requires it"
              )
      return errs


  doc = documented("SKILL.md")
  # The parser's own tripwire: a SKILL.md whose table this regex no longer
  # matches would make every comparison below vacuously green.
  assert len(doc) == 5, f"parsed {len(doc)} tools from SKILL.md, expected 5: {sorted(doc)}"

  errs = compare(doc, asyncio.run(actual(sys.argv[1])))
  if errs:
      for e in errs:
          print(f"  DRIFT   {e}")
      sys.exit(1)
  for name in sorted(doc):
      print(f"  ok      {name} matches SKILL.md")
  PY

  echo "== the vendored server, against the contract SKILL.md documents"
  python3 contract.py agent_bus_mcp.py

  # hooks/bus-peek.sh runs `agent_bus_mcp.py --peek` and treats exit 0 as
  # "nothing pending, stay quiet" -- including when the homeserver is
  # unreachable, because a hook that nags on network failure takes every
  # Stop down with it. The homeserver above is a dead port, so this is
  # exactly that case: it must exit 0 and print no traceback.
  echo "== --peek, offline"
  if peeked=$(python3 agent_bus_mcp.py --peek 2>&1); then
    if grep -q "Traceback" <<<"$peeked"; then
      echo "  FAILED  --peek exits 0 but spews a traceback:"; sed 's/^/            /' <<<"$peeked"
      exit 1
    fi
    echo "  ok      --peek exits 0 with the homeserver unreachable"
  else
    echo "  FAILED  --peek exits non-zero offline; bus-peek.sh would misfire:"
    sed 's/^/            /' <<<"$peeked"
    exit 1
  fi

  # Prove the comparator can fail (AGENTS.md 1): rename a tool the way a
  # bad re-vendor would and demand the same comparison reject it.
  echo "== the same comparison, against a tampered copy"
  sed 's/^def whoami(/def whoami_v2(/' agent_bus_mcp.py > tampered.py
  if python3 contract.py tampered.py > tamper-out 2>&1; then
    echo "  FAILED  the comparator passed a server missing a documented tool"
    exit 1
  fi
  grep -q "tool names" tamper-out || {
    echo "  FAILED  the comparator failed for the wrong reason:"; sed 's/^/            /' tamper-out
    exit 1
  }
  echo "  ok      a renamed tool is caught"

  echo "the vendored MCP server still honours the contract SKILL.md teaches"
  touch $out
''
