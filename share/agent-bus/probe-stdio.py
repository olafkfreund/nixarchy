#!/usr/bin/env python3
"""Start the bus server over real MCP stdio and check the tools it serves.

Exists because the ways this breaks are all silent. A dependency that resolves
to the wrong major (mcp 2.x renamed FastMCP) kills it on import; a renamed tool
leaves a Copilot `tools` allowlist quietly naming something that is not there,
and Copilot reports no error for a tool it was never offered.

Usage: probe-stdio.py <command> [args...]
"""

import json
import queue
import subprocess
import sys
import threading

# Must match the `tools` allowlist in COPILOT.md and the table in SKILL.md.
EXPECTED = {"list_rooms", "post", "read_new", "search", "whoami"}
TIMEOUT = 30


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    proc = subprocess.Popen(
        sys.argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    out: queue.Queue[str] = queue.Queue()
    err: list[str] = []
    threading.Thread(target=lambda: [out.put(x) for x in proc.stdout], daemon=True).start()
    threading.Thread(target=lambda: [err.append(x) for x in proc.stderr], daemon=True).start()

    def fail(why: str) -> int:
        proc.kill()
        print(f"probe: {why}", file=sys.stderr)
        print("".join(err[-20:]), file=sys.stderr)
        return 1

    def send(msg: dict) -> bool:
        try:
            proc.stdin.write(json.dumps(msg) + "\n")
            proc.stdin.flush()
            return True
        except BrokenPipeError:
            return False

    def reply(want_id: int):
        while True:
            try:
                line = out.get(timeout=TIMEOUT)
            except queue.Empty:
                return None
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue  # servers may log non-JSON to stdout
            if msg.get("id") == want_id:
                return msg

    handshake = {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "probe", "version": "0"},
    }
    if not send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": handshake}):
        return fail("server exited before the handshake")
    if reply(1) is None:
        return fail("no initialize response")

    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    listing = reply(2)
    if listing is None:
        return fail("no tools/list response")

    proc.kill()
    got = {t["name"] for t in listing["result"]["tools"]}
    if got != EXPECTED:
        print(f"probe: tools drifted\n  expected {sorted(EXPECTED)}\n  got      {sorted(got)}", file=sys.stderr)
        return 1

    print(f"probe: ok, {len(got)} tools: {', '.join(sorted(got))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
