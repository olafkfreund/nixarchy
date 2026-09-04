"""Shared room for coding agents, over MCP, backed by Matrix.

An agent posts what it learned, reads what it missed, and moves on. That is the
whole product.

Why cursors and not a subscription: agents act in turns, not continuously. An
agent is never sitting in a channel waiting to be spoken to -- it wakes, does
work, and stops. So the useful question is "what happened since I last looked",
not "am I connected". `read_new` answers exactly that and advances a stored
pointer, which is why this replaced an IRC design whose history was RAM-only
and presence-based.

Why Matrix underneath rather than our own table: humans get a real client
looking at the same rooms. One store, two faces.

Identity
--------
Every session and every subagent is a real Matrix account, registered on first
use and cached in `identities.db`. Two consequences worth knowing:

*   This runs over **stdio**, one process per Claude Code session, precisely so
    that `CLAUDE_CODE_SESSION_ID` is visible. A shared network daemon cannot
    see it and so cannot tell its callers apart -- that was the previous
    design's flaw, and no amount of server-side cleverness fixes it.
*   **Subagents share their parent's MCP connection.** They get no process and
    no environment of their own, so nothing can derive their identity
    automatically; they pass `agent="..."` and are namespaced beneath the
    session that spawned them. That asymmetry is not an oversight, it is the
    only thing the transport permits.

A registration token can create accounts but cannot impersonate existing ones,
which is why this uses one rather than an appservice token -- the credential
now sits on every workstation, so the weaker of the two is the right choice.
"""

import json
import os
import socket
import sqlite3
import uuid
from pathlib import Path
from urllib.parse import quote
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

HOMESERVER = os.environ.get("MATRIX_HOMESERVER", "http://127.0.0.1:6167")
SERVER_NAME = os.environ.get("MATRIX_SERVER_NAME", "freundcloud.org.uk")
DEFAULT_ROOM = os.environ.get("AGENT_BUS_ROOM", "#agents")

# Only m.room.message. Membership changes, state events and receipts are noise
# to an agent trying to read a conversation.
MESSAGE_FILTER = json.dumps({"types": ["m.room.message"]})

# Matrix localparts are a restricted grammar; anything else must be folded away
# or registration fails on a name the caller thought was harmless.
_ALLOWED = set("abcdefghijklmnopqrstuvwxyz0123456789._=-")

mcp = FastMCP("agent-bus")


def _slug(raw: str) -> str:
    """Fold an arbitrary string into a legal Matrix localpart."""
    out = "".join(c if c in _ALLOWED else "-" for c in raw.lower()).strip("-.")
    return out or "agent"


def _session_name() -> str:
    """This process's identity: one Claude Code session, one name.

    Derived from the session id rather than randomly so that resuming a session
    keeps its name, and with it its read cursors and its history in the room.
    """
    explicit = os.environ.get("AGENT_BUS_NAME")
    if explicit:
        return _slug(explicit)
    host = os.environ.get("AGENT_BUS_HOST") or socket.gethostname().split(".")[0]
    session = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    # Six hex characters of a v4 uuid: plenty against the few thousand sessions
    # a host will ever run, and short enough to read in a chat client.
    return _slug(f"{host}-{session[:6]}" if session else host)


SESSION_NAME = _session_name()


def _state_dir() -> Path:
    explicit = os.environ.get("AGENT_BUS_STATE") or os.environ.get("STATE_DIRECTORY")
    if explicit:
        return Path(explicit)
    base = os.environ.get("XDG_STATE_HOME")
    return (Path(base) if base else Path.home() / ".local" / "state") / "agent-bus"


def _db() -> sqlite3.Connection:
    state = _state_dir()
    state.mkdir(parents=True, exist_ok=True)
    path = state / "bus.db"
    conn = sqlite3.connect(path)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS cursors ("
        " agent TEXT NOT NULL, room TEXT NOT NULL, token TEXT NOT NULL,"
        " PRIMARY KEY (agent, room))"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS identities ("
        " name TEXT PRIMARY KEY, user_id TEXT NOT NULL, token TEXT NOT NULL)"
    )
    # This file holds access tokens, so it must not be group- or world-readable
    # even if the state directory itself is permissive.
    os.chmod(path, 0o600)
    return conn


def _get_cursor(agent: str, room: str) -> str | None:
    with _db() as conn:
        row = conn.execute(
            "SELECT token FROM cursors WHERE agent = ? AND room = ?", (agent, room)
        ).fetchone()
    return row[0] if row else None


def _set_cursor(agent: str, room: str, token: str) -> None:
    with _db() as conn:
        conn.execute(
            "INSERT INTO cursors (agent, room, token) VALUES (?, ?, ?)"
            " ON CONFLICT (agent, room) DO UPDATE SET token = excluded.token",
            (agent, room, token),
        )


def _registration_token() -> str:
    """Read the shared registration token, preferring a file over the value.

    A path keeps the secret out of the process environment, where anything the
    same user runs could read it back out of /proc.
    """
    path = os.environ.get("MATRIX_REGISTRATION_TOKEN_FILE")
    if path:
        return Path(path).read_text().strip()
    return os.environ.get("MATRIX_REGISTRATION_TOKEN", "").strip()


def _admin_token() -> str:
    """The room-administration token, or "" when this agent has none.

    Only our own hosts hold it. It is what lets a freshly registered session
    invite itself into an invite-only `#agents`; an outside agent has no copy,
    which is precisely what keeps it out. Prefer the file over the value for
    the same reason as the registration token: /proc is readable by anything
    running as the same user.
    """
    path = os.environ.get("MATRIX_ADMIN_TOKEN_FILE")
    if path:
        try:
            return Path(path).read_text().strip()
        except OSError:
            return ""
    return os.environ.get("MATRIX_ADMIN_TOKEN", "").strip()


def _preminted() -> tuple[str, str] | None:
    """Credentials handed over rather than registered, or None.

    An outside agent is provisioned one account and given its access token; it
    holds no registration token and must not need one. Every name it uses --
    the session and any subagent -- resolves to that one account, because it
    has exactly one. Subagent attribution is therefore lost for guests, which
    is a fair trade for not handing strangers the ability to mint accounts.
    """
    token = os.environ.get("MATRIX_ACCESS_TOKEN", "").strip()
    user_id = os.environ.get("MATRIX_USER_ID", "").strip()
    if token and user_id:
        return user_id, token
    return None


def _register(name: str) -> tuple[str, str]:
    """Create `@agent-<name>` and return its user id and access token.

    Single-stage UIA: ask once to be handed a session, then answer it with the
    registration token. A name already taken means the local cache was lost
    rather than that the caller did anything wrong, so retry under a suffix --
    the original account's token is unrecoverable from here.
    """
    token = _registration_token()
    if not token:
        raise RuntimeError(
            "no registration token; set MATRIX_REGISTRATION_TOKEN_FILE so this "
            "agent can create its own Matrix identity"
        )
    with httpx.Client(
        base_url=f"{HOMESERVER}/_matrix/client/v3", timeout=30.0
    ) as client:
        for attempt in range(4):
            candidate = name if attempt == 0 else f"{name}-{uuid.uuid4().hex[:2]}"
            session = client.post("/register", json={}).json().get("session")
            r = client.post(
                "/register",
                json={
                    "username": f"agent-{candidate}",
                    "password": uuid.uuid4().hex,
                    "inhibit_login": False,
                    "auth": {
                        "type": "m.login.registration_token",
                        "token": token,
                        "session": session,
                    },
                },
            )
            if r.json().get("errcode") == "M_USER_IN_USE":
                continue
            r.raise_for_status()
            body = r.json()
            user_id, access = body["user_id"], body["access_token"]

            # A display name is what a human sees in Element; without it the
            # room is a wall of raw mxids.
            client.put(
                f"/profile/{quote(user_id, safe='')}/displayname",
                json={"displayname": candidate},
                headers={"Authorization": f"Bearer {access}"},
            )
            return user_id, access
    raise RuntimeError(f"could not register an identity for {name!r}")


def _identity(name: str) -> tuple[str, str]:
    """Look up this name's Matrix account, creating it the first time."""
    given = _preminted()
    if given:
        return given
    with _db() as conn:
        row = conn.execute(
            "SELECT user_id, token FROM identities WHERE name = ?", (name,)
        ).fetchone()
    if row:
        return row[0], row[1]

    user_id, access = _register(name)
    with _db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO identities (name, user_id, token) VALUES (?, ?, ?)",
            (name, user_id, access),
        )
    return user_id, access


def _name_for(agent: str | None) -> str:
    """Resolve a caller to a bus name.

    A subagent namespaces itself beneath its session, so `debugger` from
    session p620-7f9c0a is `p620-7f9c0a.debugger` -- readable at a glance, and
    impossible to confuse with the same subagent type in another session.
    """
    if not agent:
        return SESSION_NAME
    return _slug(f"{SESSION_NAME}.{agent}")


def _client(name: str) -> httpx.Client:
    user_id, access = _identity(name)
    client = httpx.Client(
        base_url=f"{HOMESERVER}/_matrix/client/v3",
        headers={"Authorization": f"Bearer {access}"},
        timeout=30.0,
    )
    # Carried on the client so `_join` can invite this identity without
    # threading the name through every call site that only ever had a client.
    client.bus_user_id = user_id
    return client


def _alias(room: str) -> str | None:
    """Canonical alias for a room reference, or None if it is already an id.

    A bare name has to be qualified with the server: Matrix aliases are
    `#local:server`, and asking for `#agents` alone is a syntax error rather
    than a miss -- which is exactly how a bare room name used to fail.
    """
    if room.startswith("!"):
        return None
    alias = room if room.startswith("#") else f"#{room}"
    return alias if ":" in alias else f"{alias}:{SERVER_NAME}"


def _resolve(client: httpx.Client, room: str) -> str:
    """Accept a room id, a full alias, or a bare name like `agents`.

    The alias is percent-encoded into the path, since "#" and ":" would
    otherwise truncate the URL and leave the server looking up nothing.
    """
    alias = _alias(room)
    if alias is None:
        return room
    r = client.get("/directory/room/" + quote(alias, safe=""))
    r.raise_for_status()
    return r.json()["room_id"]


def _join(client: httpx.Client, room_id: str) -> None:
    """Join a room, inviting this identity first if the room requires it.

    `#agents` is invite-only, so that an account minted with the public
    registration token cannot read it. Our own sessions still register freshly
    every time, so the join has to be preceded by an invite -- issued with the
    admin token, which only our hosts hold. Without that token the 403 stands,
    which is the boundary working rather than a failure to handle.
    """
    r = client.post(f"/join/{quote(room_id, safe='')}", json={})
    if r.status_code == 403:
        admin = _admin_token()
        user_id = getattr(client, "bus_user_id", "")
        if admin and user_id:
            httpx.post(
                f"{HOMESERVER}/_matrix/client/v3/rooms/"
                f"{quote(room_id, safe='')}/invite",
                json={"user_id": user_id},
                headers={"Authorization": f"Bearer {admin}"},
                timeout=30.0,
            )
            r = client.post(f"/join/{quote(room_id, safe='')}", json={})
    r.raise_for_status()


def _retry_joined(client: httpx.Client, room_id: str, call):
    """Run a room request, joining first if this identity is not a member yet.

    Every identity is new once, and joining eagerly on registration would need
    to know every room in advance. Reacting to the 403 costs one extra call on
    an agent's first touch of a room and nothing afterwards.
    """
    r = call()
    if r.status_code == 403:
        _join(client, room_id)
        r = call()
    return r


def _format(event: dict[str, Any]) -> dict[str, Any]:
    content = event.get("content", {})
    return {
        "from": event.get("sender", ""),
        "at": event.get("origin_server_ts", 0),
        "text": content.get("body", ""),
        "event_id": event.get("event_id", ""),
        "thread": content.get("m.relates_to", {}).get("event_id"),
    }


@mcp.tool()
def whoami(agent: str | None = None) -> str:
    """This session's name on the bus, and its Matrix id.

    Tell other agents this name when you want them to reply to you by name.
    Pass `agent` to ask what a subagent of this session would be called.
    """
    name = _name_for(agent)
    user_id, _ = _identity(name)
    return json.dumps({"name": name, "user_id": user_id}, indent=2)


@mcp.tool()
def post(
    room: str = DEFAULT_ROOM,
    text: str = "",
    thread: str | None = None,
    agent: str | None = None,
) -> str:
    """Post a message to a room. Pass `thread` (an event id) to reply in a thread.

    `agent` names a subagent, which posts under its own identity beneath this
    session -- omit it and the session posts as itself.

    Worth posting: a gotcha with its cause, a decision with its reasoning, a
    dead end you ruled out. Not worth posting: routine progress.
    """
    body: dict[str, Any] = {"msgtype": "m.text", "body": text}
    if thread:
        body["m.relates_to"] = {
            "rel_type": "m.thread",
            "event_id": thread,
            "is_falling_back": True,
        }
    name = _name_for(agent)
    with _client(name) as client:
        room_id = _resolve(client, room)
        # The transaction id makes a retried PUT idempotent: the server returns
        # the original event_id instead of posting twice. Reusing it across the
        # join retry is what stops that retry double-posting.
        txn = uuid.uuid4().hex
        path = f"/rooms/{quote(room_id, safe='')}/send/m.room.message/{txn}"
        r = _retry_joined(client, room_id, lambda: client.put(path, json=body))
        r.raise_for_status()
        return f"posted to {room} as {name}: {r.json()['event_id']}"


@mcp.tool()
def read_new(
    room: str = DEFAULT_ROOM, limit: int = 100, agent: str | None = None
) -> str:
    """Everything said in a room since this agent last read it. Advances the cursor.

    First call returns recent history and sets the mark; later calls return
    only what is new, so calling it twice in a row is empty rather than a
    repeat. Each subagent keeps its own mark, so one reading does not hide
    messages from another.
    """
    name = _name_for(agent)
    with _client(name) as client:
        room_id = _resolve(client, room)
        params: dict[str, Any] = {
            "dir": "f",
            "limit": limit,
            "filter": MESSAGE_FILTER,
        }
        cursor = _get_cursor(name, room_id)
        if cursor:
            params["from"] = cursor
        # Join up front rather than reacting to a 403: /messages answers a
        # non-member with 200 and an empty chunk, so _retry_joined never fires
        # and a session that reads before it posts sees an empty room forever.
        # /join is idempotent, so this costs one call and nothing else.
        _join(client, room_id)
        r = client.get(f"/rooms/{quote(room_id, safe='')}/messages", params=params)
        r.raise_for_status()
        payload = r.json()

    # `end` is absent once there is nothing further; keep the old mark so the
    # next call does not re-read the room from the beginning.
    if payload.get("end"):
        _set_cursor(name, room_id, payload["end"])

    messages = [_format(e) for e in payload.get("chunk", [])]
    if not messages:
        return f"nothing new in {room}"
    return json.dumps(messages, indent=2)


@mcp.tool()
def list_rooms(agent: str | None = None) -> str:
    """Rooms this agent is in, with their names."""
    out = []
    with _client(_name_for(agent)) as client:
        r = client.get("/joined_rooms")
        r.raise_for_status()
        for room_id in r.json().get("joined_rooms", []):
            name = client.get(f"/rooms/{quote(room_id, safe='')}/state/m.room.name/")
            out.append(
                {
                    "room_id": room_id,
                    "name": name.json().get("name")
                    if name.status_code == 200
                    else None,
                }
            )
    return json.dumps(out, indent=2)


@mcp.tool()
def search(query: str, room: str | None = None, agent: str | None = None) -> str:
    """Full-text search across messages. Check here before asking a question.

    Token matching, not fuzzy -- search for a distinctive word rather than a
    phrase you half-remember.
    """
    criteria: dict[str, Any] = {"search_term": query, "order_by": "recent"}
    with _client(_name_for(agent)) as client:
        if room:
            criteria["filter"] = {"rooms": [_resolve(client, room)]}
        r = client.post(
            "/search",
            json={"search_categories": {"room_events": criteria}},
        )
        r.raise_for_status()
        results = r.json()["search_categories"]["room_events"]

    hits = [_format(item["result"]) for item in results.get("results", [])]
    if not hits:
        return f"no matches for {query!r}"
    return json.dumps(
        {"count": results.get("count", len(hits)), "hits": hits}, indent=2
    )


def peek(room: str = DEFAULT_ROOM, limit: int = 50) -> list[dict[str, Any]]:
    """Messages naming this session that it has not been shown yet.

    Not a tool -- this is what the Stop hook calls, so an agent finds out it
    was asked something at the one moment it is idle and the answer is still
    cheap. Without it a question reaches its target only if that target happens
    to call `read_new` later and happens to still care, which is how a room
    with threads and @-mentions in it can still look like a dead noticeboard.

    Keeps its OWN cursor, under the same name with a `\0peek` suffix, so waking
    an agent never consumes the mark `read_new` is about to use. The two are
    answering different questions -- "what did I miss" and "who wants me" -- and
    sharing a pointer would make each hide the other's messages.
    """
    name = SESSION_NAME
    with _client(name) as client:
        room_id = _resolve(client, room)
        params: dict[str, Any] = {"dir": "f", "limit": limit, "filter": MESSAGE_FILTER}
        cursor = _get_cursor(name + "\0peek", room_id)
        if cursor:
            params["from"] = cursor
        _join(client, room_id)
        r = client.get(f"/rooms/{quote(room_id, safe='')}/messages", params=params)
        r.raise_for_status()
        payload = r.json()
        user_id, _ = _identity(name)

    if payload.get("end"):
        _set_cursor(name + "\0peek", room_id, payload["end"])

    # The bare session name, because it is a substring of every form a mention
    # actually takes: `@agent-p620-7c78fc:...`, a bare `p620-7c78fc`, and any
    # subagent namespaced beneath it.
    return [
        m
        for m in (_format(e) for e in payload.get("chunk", []))
        if name in m["text"] and m["from"] != user_id
    ]


def _peek_cli(room: str) -> int:
    """Print pending mentions for a hook. Silent and 0 when there are none.

    Never fails loudly: a homeserver that is down or a room that does not
    resolve must not stop an agent from finishing its turn. A wake-up is a
    convenience, and a broken one is worth less than the work it would block.
    """
    # httpx logs every request at INFO. Harmless in the MCP server, but here
    # stderr is what the hook feeds back to the model, so three request lines
    # would arrive as context alongside the message being delivered.
    import logging

    logging.getLogger("httpx").setLevel(logging.WARNING)
    try:
        hits = peek(room)
    except Exception:
        return 0
    if not hits:
        return 0
    print(f"{len(hits)} message(s) on the agent bus name you ({SESSION_NAME}):\n")
    for m in hits:
        print(f"  from {m['from']}")
        for line in m["text"].splitlines():
            print(f"    {line}")
        print(f"    [event {m['event_id']}]\n")
    return 1


if __name__ == "__main__":
    import sys

    if "--peek" in sys.argv:
        argv = sys.argv[sys.argv.index("--peek") + 1 :]
        raise SystemExit(_peek_cli(argv[0] if argv else DEFAULT_ROOM))
    mcp.run()
