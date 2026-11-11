{ pkgs, omarchy }:
# #1736: the agents panel runs `omarchy-agent-local use --detach <model>` with no
# terminal. When the preflight fails (no podman, no memlock limit, no CDI spec)
# the patched script must open a terminal showing the error, and hand it the
# arguments quoted exactly once, without --detach, so the terminal run is the
# interactive one. Exiting 1 there instead is what the panel used to do: silently.
#
# The script is upstream's and unwrapped, so PATH stubs are reached
# (tests/AGENTS.md, "A PATH stub loses to runtimeInputs").
let
  isEdge = if pkgs.lib.hasPrefix "edge-" omarchy.version then "1" else "";
in
pkgs.runCommand "nixarchy-agent-local-detach" { inherit isEdge; } ''
  set -euo pipefail
  script=${omarchy}/bin/omarchy-agent-local
  # main's tag ships no omarchy-agent-local (#1752); when it does, drop this branch.
  if [ -z "$isEdge" ]; then
    [ ! -e "$script" ] || { echo "the tag now ships $script: drop the pin gate (#1752)" >&2; exit 1; }
    touch $out
    exit 0
  fi
  [ -f "$script" ] || { echo "missing $script" >&2; exit 1; }
  work=$PWD/work
  mkdir -p "$work/stubs" "$work/with-podman"
  stub() {
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "$2" > "$1"
    chmod +x "$1"
  }
  stub "$work/stubs/systemctl" 'printf "%s\n" infinity'
  stub "$work/stubs/omarchy-local-ai" 'printf "%s\n" "$*" >> "$WORK/local-ai.log"'
  stub "$work/stubs/omarchy-launch-floating-terminal-with-presentation" 'printf "%s\n" "$1" >> "$WORK/launcher.log"'
  stub "$work/with-podman/podman" 'exit 0'
  export WORK=$work

  fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
  reset() { : > "$work/local-ai.log"; : > "$work/launcher.log"; }
  # No podman on PATH: the preflight fails.
  run_without() { PATH=$work/stubs "$script" "$@" 2>/dev/null; }

  for args in "use --detach m" "use m --detach"; do
    reset
    run_without $args || fail "$args: the failing detached run exited instead of opening a terminal"
    logged=$(<"$work/launcher.log")
    [ "$logged" = "omarchy-agent-local 'use' 'm'" ] || fail "$args: launcher got [$logged]"
    [ ! -s "$work/local-ai.log" ] || fail "$args: reached omarchy-local-ai"
  done

  reset
  run_without use --detach "a b" || fail "quoted: the failing detached run exited instead of opening a terminal"
  logged=$(<"$work/launcher.log")
  [ "$logged" = "omarchy-agent-local 'use' 'a b'" ] || fail "quoted: launcher got [$logged]"
  eval "set -- ''${logged#omarchy-agent-local }"
  [ "$#" = 2 ] && [ "$1" = use ] && [ "$2" = "a b" ] || fail "re-parse gave $# args, second [$2]"

  reset
  if run_without use m; then fail "interactive failing run exited 0"; fi
  [ ! -s "$work/launcher.log" ] && [ ! -s "$work/local-ai.log" ] || fail "interactive failure ran something"

  # A passing preflight needs a host without an NVIDIA driver in /proc.
  if [ -e /proc/driver/nvidia ]; then
    echo "SKIP passing case: /proc/driver/nvidia exists here"
  else
    reset
    PATH=$work/stubs:$work/with-podman "$script" use --detach m || fail "passing run exited non-zero"
    [ "$(<"$work/local-ai.log")" = "use --detach m" ] || fail "passing run: omarchy-local-ai got [$(<"$work/local-ai.log")]"
    [ ! -s "$work/launcher.log" ] || fail "passing run opened a launcher"
  fi
  touch $out
''
