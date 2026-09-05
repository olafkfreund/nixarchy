{
  pkgs,
  hook,
  peekHook,
  registerScript,
}:
# The redaction hook, driven with the payloads it will actually meet (#272).
#
# AGENTS.md §1 applies with unusual force here: a security hook that passes
# everything looks identical to a working one. So this proves both halves --
# that it blocks what it claims to block, and that it passes the traffic the
# issue predicts will occur on the bus every day: version numbers shaped like
# IPv4, base16 colours shaped like hex secrets, nix store hashes.
#
# And one property that is not about matching at all: the refusal must not
# echo the secret. A guard whose error message is a searchable archive of
# everything an agent nearly leaked is worse than no guard.
pkgs.runCommand "nixarchy-bus-redact" { nativeBuildInputs = [ pkgs.jq ]; } ''
  cp ${hook} hook.sh
  chmod +x hook.sh

  fails=0
  # t <want> <name> <room> <text>; an empty room means the key is absent, the
  # case where the server default applies.
  t() {
    want=$1 name=$2 room=$3 text=$4
    if [ -n "$room" ]; then
      jq -n --arg t "$text" --arg r "$room" \
        '{tool_name:"mcp__agent-bus__post",tool_input:{text:$t,room:$r}}' > payload.json
    else
      jq -n --arg t "$text" \
        '{tool_name:"mcp__agent-bus__post",tool_input:{text:$t}}' > payload.json
    fi
    if bash hook.sh < payload.json > out 2>&1; then got=allow; else
      rc=$?
      got=block
      [ "$rc" = 2 ] || { echo "  FAILED  $name: blocked with exit $rc, not 2"; fails=$((fails+1)); }
    fi
    if [ "$got" = "$want" ]; then
      echo "  ok      $name ($got)"
    else
      echo "  FAILED  $name: wanted $want, got $got"
      sed 's/^/            /' out
      fails=$((fails + 1))
    fi
  }

  TOKEN=ghp_0123456789abcdefghijABCDEFGHIJ01234567
  PUB="#nixarchy-agents"
  PRIV="#agents"

  # Credential shapes block in every room, and the refusal names the class.
  t block "GitHub token, public room"   "$PUB"  "the fix was export GH_TOKEN=$TOKEN"
  grep -qi 'GitHub token' out || { echo "  FAILED  refusal does not name the class"; fails=$((fails+1)); }
  # The no-archive property: the refusal must not contain the secret itself.
  ! grep -q "$TOKEN" out || { echo "  FAILED  the refusal echoes the token"; fails=$((fails+1)); }
  t block "GitHub token, private room"  "$PRIV" "token: $TOKEN"
  t block "Matrix token"                "$PRIV" "auth failed with syt_YWJjZGVmZ2hpamts_xyz"
  t block "private key block"           "$PUB"  "-----BEGIN OPENSSH PRIVATE KEY-----"
  t block "JWT"                         "$PUB"  "header eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r"

  # Network identity blocks in the public room...
  t block "private IPv4, public room"   "$PUB"  "it binds to 192.168.1.34:8080"
  # No-archive again: the class ("192.168.0.0/16") may appear, the address
  # itself must not.
  ! grep -q '192\.168\.1\.34' out || { echo "  FAILED  the refusal echoes the address"; fails=$((fails+1)); }
  t block "tailnet IPv4, public room"   "$PUB"  "reach it on 100.101.102.103"
  t block "MAC address, public room"    "$PUB"  "the NIC is aa:bb:cc:dd:ee:f0"
  # ...and the SAME message passes in #agents, where the announce rule
  # requires naming hosts and the room is private.
  t allow "private IPv4, #agents"       "$PRIV" "it binds to 192.168.1.34:8080"
  t allow "MAC address, #agents"        "$PRIV" "the NIC is aa:bb:cc:dd:ee:f0"

  # The regressions the issue predicts will actually happen: versions shaped
  # like IPv4, colours shaped like hex secrets, store hashes full of entropy.
  t allow "version number"              "$PUB"  "continuwuity 26.8.1 fixed it, nixpkgs 25.05 has not"
  t allow "four-part public version"    "$PUB"  "the fix landed in 1.2.3.4"
  t allow "base16 colour"               "$PUB"  "set the border to #a3b2c1 and the text to #1e1e2e"
  t allow "loopback and doc addresses"  "$PUB"  "bind 127.0.0.1 or 0.0.0.0, docs use 203.0.113.7"
  t allow "nix store hash"              "$PUB"  "/nix/store/v3xi7xb3n38a48psm23lcf2nfyjk6jsk-obs-studio-32.2.1 failed"
  t allow "ordinary lesson"             "$PUB"  "systemd EnvironmentFile needs the - marker and RuntimeDirectory="

  # A missing room means the server default applies, resolved as the server
  # resolves it: AGENT_BUS_ROOM, then #agents.
  t allow "no room, no env -> #agents rules"  "" "host 192.168.1.34 is fine here"
  AGENT_BUS_ROOM="#nixarchy-agents" \
    t block "no room, env says public -> strict" "" "host 192.168.1.34 leaks here"

  # Fail open: a hook that crashes must not take the bus down with it.
  if echo 'not json at all' | bash hook.sh >out 2>&1; then
    echo "  ok      malformed payload (allow)"
  else
    echo "  FAILED  malformed payload blocked or crashed"; sed 's/^/            /' out
    fails=$((fails+1))
  fi

  # ------------------------------------------------------------------------
  # bus-peek.sh (#268): the Stop hook that decides exit 0 (let the turn end)
  # vs exit 2 (hand pending messages back), from a JSON payload and its
  # peek command's exit code -- and until now had no test at all. Same
  # doctrine as above: the real script, driven by stubs that lie.
  # ------------------------------------------------------------------------
  cp ${peekHook} peek.sh
  chmod +x peek.sh

  # The stub peek command AGENT_BUS_CMD points at: rc and output from env.
  cat > stubpeek.sh <<'EOF'
  #!/bin/sh
  printf '%s\n' "''${PEEK_OUT:-}"
  exit "''${PEEK_RC:-0}"
  EOF
  chmod +x stubpeek.sh
  export AGENT_BUS_CMD=$PWD/stubpeek.sh

  pt() {
    want=$1 name=$2 payload=$3
    if printf '%s' "$payload" | bash peek.sh >out 2>err; then got=0; else got=$?; fi
    if [ "$got" = "$want" ]; then
      echo "  ok      $name (exit $got)"
    else
      echo "  FAILED  $name: wanted exit $want, got $got"
      sed 's/^/            /' err
      fails=$((fails + 1))
    fi
  }

  # A Stop hook that fires while already continuing from a Stop hook is a
  # loop; the payload says so and the hook must let the turn end, pending
  # messages or not.
  MATRIX_ACCESS_TOKEN=syt_test PEEK_RC=1 PEEK_OUT="you have mail"     pt 0 "stop_hook_active short-circuits" '{"stop_hook_active":true}'

  # No token means not on the bus: get out of the way, never nag.
  MATRIX_ACCESS_TOKEN= PEEK_RC=1 PEEK_OUT="you have mail"     pt 0 "no token, no wake" '{}'

  # Nothing pending: the turn ends.
  MATRIX_ACCESS_TOKEN=syt_test PEEK_RC=0     pt 0 "peek quiet" '{}'

  # Something pending: exit 2, and the MESSAGE plus the reply guidance are
  # what comes back -- an exit 2 with an empty stderr wakes an agent with
  # nothing to act on.
  MATRIX_ACCESS_TOKEN=syt_test PEEK_RC=1 PEEK_OUT="agent-x: are the boxes up?"     pt 2 "pending message wakes the agent" '{}'
  grep -q "are the boxes up" err || { echo "  FAILED  the wake does not carry the message"; fails=$((fails+1)); }
  grep -q "post(thread=" err || { echo "  FAILED  the wake does not say how to reply"; fails=$((fails+1)); }

  # Garbage payload: jq errors, the case matches nothing, and the hook
  # continues on its other gates rather than crashing the Stop.
  MATRIX_ACCESS_TOKEN= PEEK_RC=0     pt 0 "malformed payload falls through" 'not json'

  [ "$fails" -eq 0 ] || exit 1
  echo "bus-redact blocks the decidable leaks and only those; bus-peek wakes exactly when something is pending"
  # register.sh's consent gate (#270): connecting is the user's decision, so
  # the disclosure is enforced at the connect moment -- and the refusal must
  # happen BEFORE any network. A curl that records being called is the
  # tripwire: a gate that refuses after the first request already sent
  # something.
  # ------------------------------------------------------------------------
  cp ${registerScript} register.sh
  chmod +x register.sh
  cat > curl <<'EOF'
  #!/bin/sh
  touch curl-called
  echo '{}'
  EOF
  chmod +x curl
  export PATH=$PWD:$PATH

  # Unattended, no consent: refuse, say how to consent, touch nothing.
  if ro=$(printf "" | AGENT_BUS_CONSENT= bash register.sh some-agent 2>&1); then
    echo "  FAILED  register.sh proceeded without consent"; fails=$((fails+1))
  else
    echo "  ok      no consent -> refused"
  fi
  echo "$ro" | grep -q "AGENT_BUS_CONSENT=public" || { echo "  FAILED  the refusal does not say how to consent"; fails=$((fails+1)); }
  echo "$ro" | grep -qi "PUBLIC" || { echo "  FAILED  the refusal does not carry the disclosure"; fails=$((fails+1)); }
  [ ! -e curl-called ] || { echo "  FAILED  the gate let a network request out before refusing"; fails=$((fails+1)); }

  # Consent given: the gate opens, and the run proceeds to the next real
  # requirement (the registration token), proving the refusal above was the
  # gate and not something downstream.
  if ro=$(printf "" | AGENT_BUS_CONSENT=public bash register.sh some-agent 2>&1); then
    echo "  FAILED  register.sh succeeded with no token?"; fails=$((fails+1))
  else
    echo "$ro" | grep -q "no registration token" \
      && echo "  ok      consent -> proceeds to the token check" \
      || { echo "  FAILED  with consent, the failure is not the token check:"; echo "$ro" | sed 's/^/            /'; fails=$((fails+1)); }
  fi

  [ "$fails" -eq 0 ] || exit 1
  echo "bus-redact blocks the decidable leaks and only those; the consent gate holds the door"
  touch $out
''
