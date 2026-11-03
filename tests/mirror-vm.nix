{ pkgs }:
pkgs.runCommand "nixarchy-mirror-vm"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.jq
    ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1 HOME="$TMPDIR"
    mkdir -p "$HOME/.local/state/nixarchy/microvm/test" fakebin
    printf '%s\n' 3 > "$HOME/.local/state/nixarchy/microvm/test/vsock-cid"
    cp ${./mirror-vm-fake-socat.py} fakebin/socat
    chmod +x fakebin/socat
    # The sandbox has no /usr/bin/env: without this the exec fails and
    # mirror-vm reports "socat is not installed" for every case.
    patchShebangs fakebin
    export PATH="$PWD/fakebin:$PATH"
    script=${../pkgs/omarchy/skills/ai-mirror/mirror-vm}
    failures=0

    fail() { echo "FAIL: $case_name: $*"; failures=$((failures + 1)); }
    run() {
      case_name="$1"
      expected="$2"
      error="$3"
      printf '%s\n' "$4" > scenario.json
      printf '%s\n' "$5" > steps.json
      : > calls.jsonl
      export FAKE_SCENARIO="$PWD/scenario.json" FAKE_LOG="$PWD/calls.jsonl"
      if python3 "$script" test steps.json --out "$PWD/shots" > stdout.txt 2> stderr.txt; then
        actual=0
      else
        actual=$?
      fi
      if [ "$actual" -ne "$expected" ]; then fail "exit $actual, expected $expected"; fi
      if [ -n "$error" ]; then
        if ! grep -Fxq -- "$error" stderr.txt; then
          fail "expected stderr: $error; got: $(cat stderr.txt)"
        fi
      elif [ -s stderr.txt ]; then
        fail "unexpected stderr: $(cat stderr.txt)"
      fi
      if ! jq -se '.[-1] == {"name":"control","arguments":{"mode":"off"}}' calls.jsonl > /dev/null; then
        fail "last call was not control off"
      fi
    }
    calls() {
      if ! jq -se "$1" calls.jsonl > /dev/null; then
        fail "calls did not satisfy: $1"
      fi
    }

    run 1 0 "" '{"launch":[{"window":"0x1"}]}' '[{"tool":"launch","args":{"generation":"@generation"}},{"tool":"input","args":{"generation":"@generation","window":"@window"}}]'
    calls '[.[] | select(.name=="launch" or .name=="input")] == [{"name":"launch","arguments":{"generation":7}},{"name":"input","arguments":{"generation":7,"window":"0x1"}}]'

    run 2 1 'step 1: "@window" before any launch' '{}' '[{"tool":"input","args":{"window":"@window"}}]'
    calls '[.[] | select(.name=="input")] == []'

    run 3 1 'step 3: "@window" after a launch that did not return exactly one window' '{"launch":[{"window":"0x1"},{"candidates":["0x2","0x3"]}]}' '[{"tool":"launch"},{"tool":"launch"},{"tool":"input","args":{"window":"@window"}}]'
    calls '[.[] | select(.name=="launch")] | length == 2'
    calls '[.[] | select(.name=="input")] == []'

    for body in '{"note":"started"}' '{"window":""}' '{"window":"  "}'; do
      run 4 1 'step 2: "@window" after a launch that did not return exactly one window' "{\"launch\":[$body]}" '[{"tool":"launch"},{"tool":"input","args":{"window":"@window"}}]'
      calls '[.[] | select(.name=="input")] == []'
    done

    run 5 1 'step 3: "@window" after that window was closed' '{"launch":[{"window":"0x1"}]}' '[{"tool":"launch"},{"tool":"window","args":{"action":"close","address":"0x1"}},{"tool":"input","args":{"window":"@window"}}]'
    calls '[.[] | select(.name=="window")] == [{"name":"window","arguments":{"action":"close","address":"0x1"}}]'
    calls '[.[] | select(.name=="input")] == []'
    run 5-other 0 "" '{"launch":[{"window":"0x1"}]}' '[{"tool":"launch"},{"tool":"window","args":{"action":"close","address":"0x2"}},{"tool":"input","args":{"window":"@window"}}]'
    calls '[.[] | select(.name=="input")][0].arguments.window == "0x1"'

    run 6 0 "" '{}' '[{"tool":"input","args":{"generation":5,"window":"0xabc"}}]'
    calls '[.[] | select(.name=="input")][0].arguments == {"generation":5,"window":"0xabc"}'

    run 7 0 "" '{}' '[{"tool":"input","args":{"generation":5}}]'
    calls '[.[] | select(.name=="input")][0].arguments == {"generation":5}'

    run 8-shot 0 "" '{"screenshot":[{"frame":"f1","generation":9}]}' '[{"tool":"screenshot"},{"tool":"input","args":{"generation":"@generation"}}]'
    calls '[.[] | select(.name=="input")][0].arguments.generation == 9'
    run 8-control 0 "" '{"control":[{"ok":true},{"generation":11}]}' '[{"tool":"control","args":{"mode":"agent"}},{"tool":"input","args":{"generation":"@generation"}}]'
    calls '[.[] | select(.name=="input")][0].arguments.generation == 11'

    for body in '{"owner":"agent"}' '{"owner":"agent","generation":true}'; do
      run 9 1 'step 1: "@generation" no generation seen yet' "{\"status\":[$body]}" '[{"tool":"input","args":{"generation":"@generation"}}]'
      calls '[.[] | select(.name=="input")] == []'
    done

    run 10-after 0 "" '{}' '[{"tool":"screenshot"},{"tool":"input","args":{"frame":"@last"}}]'
    calls '[.[] | select(.name=="input")][0].arguments.frame == "f1"'
    run 10-before 1 'step 1: "@last" before any screenshot' '{}' '[{"tool":"input","args":{"frame":"@last"}}]'
    calls '[.[] | select(.name=="input")] == []'

    if [ "$failures" -ne 0 ]; then
      echo "mirror-vm: $failures failed assertions"
      exit 1
    fi
    echo 'mirror-vm: all 10 cases passed'
    touch "$out"
  ''
