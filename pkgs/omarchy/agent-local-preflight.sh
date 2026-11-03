# nixarchy: nothing is installed on first use. programs.nixarchy.services.agent-local
# provides podman, the memlock limit and the NVIDIA CDI spec, so check them before
# any download starts. Pure bash: no grep -q, and a missing command reads as a failure.
if [[ ${1:-} == "use" ]]; then
  agent_local_fail() {
    echo "omarchy-agent-local: $1" >&2
    echo "Turn on programs.nixarchy.services.agent-local.enable and rebuild." >&2
    [[ -z ${2:-} ]] || echo "$2" >&2
    exit 1
  }
  command -v podman >/dev/null 2>&1 || agent_local_fail "podman is not on PATH."
  if [[ $(systemctl --user show -P DefaultLimitMEMLOCK 2>/dev/null) != infinity ]]; then
    agent_local_fail "the user manager does not allow unlimited locked memory (DefaultLimitMEMLOCK is not infinity)." \
      "After a rebuild, log out and in again so the limit reaches your session."
  fi
  if [[ -e /proc/driver/nvidia ]]; then
    agent_local_cdi=0
    for agent_local_spec in /var/run/cdi/*; do
      [[ -f $agent_local_spec && $(<"$agent_local_spec") == *nvidia.com/gpu* ]] && agent_local_cdi=1
    done
    if [[ $agent_local_cdi != 1 ]]; then
      agent_local_fail "no NVIDIA CDI spec in /var/run/cdi (nvidia.com/gpu), so containers cannot reach the GPU." \
        "The spec is written at boot: reboot, or run sudo systemctl start nvidia-container-toolkit-cdi-generator."
    fi
  fi
fi
