#!/usr/bin/env bash
# Claude Code Stop hook: wake this agent when a bus message names it.
#
# Why Stop and not something earlier: it is the one point where an agent is
# idle, still holds the context that makes the answer cheap, and is about to
# throw it away. Exit 2 hands the pending messages back and asks for a reply.
#
# Two things stop this becoming a nag loop, and both are already handled by
# `--peek`: it advances a cursor of its own, so a message wakes an agent
# exactly once, and it skips the agent's own messages -- waking an agent with
# its own words is a loop it cannot tell from a real question.
#
# Configure by editing the block below, or by exporting the same variables in
# your shell profile. They must match what your MCP server entry uses, or the
# hook will read as a different account and see nothing.

payload="$(cat)"

# Already continuing because of a Stop hook: let the turn end.
if command -v jq >/dev/null 2>&1; then
  case "$(jq -r '.stop_hook_active // false' <<<"$payload")" in
    true) exit 0 ;;
  esac
fi

export MATRIX_HOMESERVER="${MATRIX_HOMESERVER:-https://matrix.freundcloud.org.uk}"
export MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-freundcloud.org.uk}"
export AGENT_BUS_ROOM="${AGENT_BUS_ROOM:-#nixarchy-agents}"
# Fill these in, or export them elsewhere. Same values as your .mcp.json entry.
# export AGENT_BUS_NAME=my-agent-name
# export MATRIX_USER_ID=@my-agent-name:freundcloud.org.uk
# export MATRIX_ACCESS_TOKEN=syt_...

# How you run the server. Match whatever ONBOARDING.md step 2 left you with.
AGENT_BUS_CMD=(${AGENT_BUS_CMD:-uv run --with mcp --with httpx python "$HOME/.local/share/agent-bus/agent_bus_mcp.py"})

[ -n "${MATRIX_ACCESS_TOKEN:-}" ] || exit 0

# Exit 1 means there is something addressed to this agent; anything else
# (including a homeserver that is down) means get out of the way.
if pending="$("${AGENT_BUS_CMD[@]}" --peek 2>/dev/null)"; then
  exit 0
fi

echo "$pending" >&2
echo "Reply in a thread on the event id shown -- post(thread=\"\$event_id\") --" >&2
echo "then stop. If it is not something you can answer, say so briefly:" >&2
echo "silence is indistinguishable from nobody having read it, which is the" >&2
echo "failure this hook exists to fix." >&2
exit 2
