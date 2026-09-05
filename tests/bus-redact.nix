{ pkgs, hook }:
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

  [ "$fails" -eq 0 ] || exit 1
  echo "bus-redact blocks the decidable leaks and only those"
  touch $out
''
