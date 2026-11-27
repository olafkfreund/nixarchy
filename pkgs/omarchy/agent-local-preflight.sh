# nixarchy: programs.nixarchy.services.agent-local provides podman, the memlock
# limit and the NVIDIA CDI spec. Check them before any download; on detached
# failure, open a terminal to show the error instead of exiting silently.
agent_local_fail() {
  echo "omarchy-agent-local: $1" >&2
  echo "Turn on programs.nixarchy.services.agent-local.enable and rebuild." >&2
  [[ -z ${2:-} ]] || echo "$2" >&2
}

agent_local_preflight() {
  command -v podman >/dev/null 2>&1 || { agent_local_fail "podman is not on PATH."; return 1; }
  if [[ $(systemctl --user show -P DefaultLimitMEMLOCK 2>/dev/null) != infinity ]]; then
    agent_local_fail "the user manager does not allow unlimited locked memory (DefaultLimitMEMLOCK is not infinity)." \
      "After a rebuild, log out and in again so the limit reaches your session."
    return 1
  fi
  if [[ -e /proc/driver/nvidia ]]; then
    agent_local_cdi=0
    for agent_local_spec in /var/run/cdi/*; do
      [[ -f $agent_local_spec && $(<"$agent_local_spec") == *nvidia.com/gpu* ]] && agent_local_cdi=1
    done
    if [[ $agent_local_cdi != 1 ]]; then
      agent_local_fail "no NVIDIA CDI spec in /var/run/cdi (nvidia.com/gpu), so containers cannot reach the GPU." \
        "The spec is written at boot: reboot, or run sudo systemctl start nvidia-container-toolkit-cdi-generator."
      return 1
    fi
  fi
  return 0
}

if [[ ${1:-} == "use" ]] && ! agent_local_preflight; then
  if [[ " $* " == *" --detach "* ]]; then
    agent_local_args=()
    for a in "$@"; do [[ $a == --detach ]] || agent_local_args+=("$a"); done
    run=(omarchy-launch-floating-terminal-with-presentation "omarchy-agent-local ${agent_local_args[*]@Q}")
  else
    exit 1
  fi
fi
