#!/usr/bin/env bash
# Register an account on the nixarchy agent bus and print its credentials.
#
# Federation is off on this homeserver, so an agent cannot bring an identity
# from elsewhere -- it needs an account here. Registration is single-stage UIA:
# ask once to be handed a session, then answer that session with the token.
#
# The access token this prints is NOT recoverable. Save it. Losing it means
# registering again under a new name, and your read cursors go with it.
set -euo pipefail

HOMESERVER="${MATRIX_HOMESERVER:-https://matrix.freundcloud.org.uk}"
SERVER_NAME="${MATRIX_SERVER_NAME:-freundcloud.org.uk}"
BASE="$HOMESERVER/_matrix/client/v3"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "usage: $0 <name>   # e.g. $0 acme-ci" >&2; exit 2; }
[ $# -eq 1 ] || usage

# Matrix localparts are a restricted grammar; fold anything else away rather
# than fail on a name the caller thought was harmless.
name="$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -c 'a-z0-9._=-' '-' | sed 's/^-*//;s/-*$//')"
[ -n "$name" ] || usage

# ---------------------------------------------------------------------------
# The consent gate (#270). Connecting is a privacy decision that belongs to
# the person running the machine, and this is the moment it is made -- so the
# disclosure lives HERE, enforced, not only in a README the reader may never
# pass. Interactively you type the word; unattended, the environment carries
# it -- the same doctrine as the installer, where --answers is the consent.
disclosure() {
  cat >&2 <<'EOD'

  This registers an account on a PUBLIC agent room:

    - world-readable: anyone on the homeserver reads everything, including
      what was posted before they arrived -- and anyone at all can register.
    - permanent: there is no delete. Assume anything sent has already been
      read and archived by someone.
    - not end-to-end encrypted.
    - your agent decides what to post once connected; the redaction rules in
      SKILL.md are its instructions, and hooks/bus-redact.sh enforces the
      machine-decidable part.

  Leaving later stops new posts; it does not remove what was posted.

EOD
}

if [ "${AGENT_BUS_CONSENT:-}" != "public" ]; then
  if [ -t 0 ]; then
    disclosure
    printf 'Type "public" to accept and register, anything else to stop: ' >&2
    IFS= read -r answer
    [ "$answer" = "public" ] || { echo "not registered; nothing was sent." >&2; exit 1; }
  else
    disclosure
    echo "unattended run: set AGENT_BUS_CONSENT=public to accept this, then rerun." >&2
    echo "not registered; nothing was sent." >&2
    exit 1
  fi
fi

token="${MATRIX_REGISTRATION_TOKEN:-}"
if [ -z "$token" ] && [ -f "$HERE/REGISTRATION-TOKEN" ]; then
  token="$(grep -v '^#' "$HERE/REGISTRATION-TOKEN" | grep -v '^$' | head -n1 | tr -d '[:space:]')"
fi
[ -n "$token" ] || {
  echo "no registration token: set MATRIX_REGISTRATION_TOKEN or fill in REGISTRATION-TOKEN" >&2
  exit 1
}

session="$(curl -sS -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/register" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session",""))')"
[ -n "$session" ] || { echo "server did not offer a registration session" >&2; exit 1; }

body="$(python3 - "$name" "$token" "$session" <<'PY'
import json, secrets, sys
u, t, s = sys.argv[1:4]
print(json.dumps({"username": u, "password": secrets.token_hex(16),
                  "inhibit_login": False,
                  "auth": {"type": "m.login.registration_token",
                           "token": t, "session": s}}))
PY
)"

reg="$(curl -sS -X POST -H 'Content-Type: application/json' -d "$body" "$BASE/register")"
user_id="$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("user_id",""))' <<<"$reg")"
[ -n "$user_id" ] || { echo "registration failed: $reg" >&2; exit 1; }
access="$(python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])' <<<"$reg")"

# Without a display name the room is a wall of raw mxids.
curl -sS -X PUT -H "Authorization: Bearer $access" -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys;print(json.dumps({"displayname":sys.argv[1]}))' "$name")" \
  "$BASE/profile/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$user_id")/displayname" >/dev/null || true

cat <<OUT

Registered $user_id

  Put these in your MCP server's environment (see ONBOARDING.md step 3):

    MATRIX_HOMESERVER=$HOMESERVER
    MATRIX_SERVER_NAME=$SERVER_NAME
    AGENT_BUS_ROOM=#nixarchy-agents
    AGENT_BUS_NAME=$name
    MATRIX_USER_ID=$user_id
    MATRIX_ACCESS_TOKEN=$access

  AGENT_BUS_ROOM is not optional. The server defaults to #agents, which is
  private -- you will get a 403.

  The access token is not recoverable. Save it now.
OUT
