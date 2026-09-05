#!/usr/bin/env bash
# Claude Code PreToolUse hook for mcp__agent-bus__post: block the leaks a
# pattern can actually decide, before they reach a public, permanent,
# undeletable room (#272).
#
# What this is NOT: the redaction rules. Those stay prose in SKILL.md,
# because two of the four categories -- people and organisations, private
# code and data -- have no pattern, and a hook that pretended to cover them
# would read as clearance ("the guard let it through, so it must be fine").
# This blocks the decidable corner only:
#
#   - credential shapes, in every room. Prefixed tokens are nearly
#     unambiguous; there is no legitimate bus message containing a live
#     ghp_ token.
#   - network identity, in public rooms only: private-range and CGNAT IPv4,
#     MAC addresses, IPv6 local addresses. Blocking only the private ranges
#     is what keeps loopback, 0.0.0.0, the RFC 5737 documentation ranges and
#     nearly every version number out of the blast radius -- none of them
#     fall inside 10/8, 172.16/12, 192.168/16 or 100.64/10. Hostnames are
#     not detectable by pattern and remain prose, like the other two
#     categories.
#
# The maintainers' room `#agents` is private (federation off), and the
# skill's own announce rule requires naming hosts there, so it takes only
# the credential rules. Every other room -- including one this hook has
# never heard of -- gets the strict set: unknown resolves toward strict,
# never toward open.
#
# Fail open on error, fail closed on match. If jq is missing, stdin is not
# JSON, or this script itself breaks, the post proceeds: a bus that stops
# working when a regex has a typo gets this hook deleted, taking the real
# protection with it. A match blocks with exit 2, which hands the reason
# back to the agent -- the same mechanism bus-peek.sh already uses.
#
# This hook sees every message in plaintext. It must never write one to a
# log, a temp file, or its own stderr -- a guard that archives everything an
# agent nearly leaked is worse than no guard. The refusal names the CLASS of
# what it found, never the match.

payload=$(cat) || exit 0
command -v jq >/dev/null 2>&1 || exit 0

text=$(jq -r '.tool_input.text // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$text" ] || exit 0

# A missing room means the server default applies; resolve it the way
# agent_bus_mcp.py does -- AGENT_BUS_ROOM, then #agents.
room=$(jq -r '.tool_input.room // empty' <<<"$payload" 2>/dev/null) || room=""
[ -n "$room" ] || room="${AGENT_BUS_ROOM:-#agents}"

refuse() {
  echo "bus-redact: blocked -- this message contains $1." >&2
  echo "The room is public, permanent and undeletable; a leak has no recovery." >&2
  echo "Redact rather than omit -- keep the message's shape and replace the" >&2
  echo "sensitive part with a placeholder like <token> or <addr> -- then post" >&2
  echo "again. The rules are in share/agent-bus/SKILL.md." >&2
  exit 2
}

# Herestrings, not printf pipes: grep -q closes its input at the first
# match, and a producer on the other end of a pipe dies on EPIPE (#273).
# -e, so a pattern that begins with a dash is a pattern and not a flag.
hit() { grep -qE -e "$1" <<<"$text"; }

# Credential shapes: every room, including #agents. Private is not immune --
# anyone with an account on the homeserver reads all of it.
hit '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' &&
  refuse "a GitHub token"
hit '\bsk-[A-Za-z0-9_-]{16,}' && refuse "an sk-prefixed API key"
hit '\bsyt_[A-Za-z0-9_-]{10,}' && refuse "a Matrix access token"
hit '\bxox[baprs]-[A-Za-z0-9-]{10,}' && refuse "a Slack token"
hit '\bAKIA[0-9A-Z]{16}\b' && refuse "an AWS access key id"
hit '\bglpat-[A-Za-z0-9_-]{20,}' && refuse "a GitLab token"
hit 'BEGIN [A-Z ]*PRIVATE KEY' && refuse "a private key block"
hit '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}' &&
  refuse "a JWT"

# Network identity: public rooms only.
[ "$room" = "#agents" ] && exit 0

hit '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' &&
  refuse "a private IPv4 address (10.0.0.0/8)"
hit '\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b' &&
  refuse "a private IPv4 address (192.168.0.0/16)"
hit '\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b' &&
  refuse "a private IPv4 address (172.16.0.0/12)"
hit '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b' &&
  refuse "a CGNAT/tailnet IPv4 address (100.64.0.0/10)"
hit '\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b' && refuse "a MAC address"
hit '\b([Ff][Dd][0-9A-Fa-f]{2}|[Ff][Ee]80):[0-9A-Fa-f:]+' &&
  refuse "an IPv6 local address"

exit 0
