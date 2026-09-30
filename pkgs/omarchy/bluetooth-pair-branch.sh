    coproc PAIR_AGENT { exec stdbuf -oL bt-agent -c NoInputNoOutput 2>&1; }
    agent_pid=$PAIR_AGENT_PID
    stop_agent() {
      kill "$agent_pid" 2>/dev/null || true
      wait "$agent_pid" 2>/dev/null || true
    }
    trap stop_agent EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    registered=false
    for attempt in {1..5}; do
      if read -r -t 1 -u "${PAIR_AGENT[0]}" line; then
        if [[ $line == "Default agent requested" ]]; then
          registered=true
          break
        fi
      elif ! kill -0 "$agent_pid" 2>/dev/null; then
        break
      fi
    done
    if [[ $registered != true ]]; then
      echo "Bluetooth pairing agent did not register" >&2
      exit 1
    fi

    pairable=false
    for attempt in {1..25}; do
      if state=$(timeout 2s bluetoothctl show 2>/dev/null) &&
         grep -Eq '^[[:space:]]*Pairable: yes$' <<<"$state"; then
        pairable=true
        break
      fi
      sleep 0.2
    done
    if [[ $pairable != true ]]; then
      echo "Bluetooth adapter did not become pairable" >&2
      exit 1
    fi

    timeout 20s bluetoothctl pair "$address" >/dev/null 2>&1 || true
