---
status: approved
issue: 1085
intent: intent/2026-09-30-1085-bluetooth-pairing.md
---

# Spec: Register the auto-accept agent only during panel pairing

## Design

The review of draft PR #1101 invalidated its permanent-agent design. In pinned BlueZ 5.87, registering the first agent or requesting a default agent calls `adapter_set_io_capability` ([agent.c:126-171](https://github.com/bluez/bluez/blob/5.87/src/agent.c#L126-L171), [agent.c:268-281](https://github.com/bluez/bluez/blob/5.87/src/agent.c#L268-L281), [agent.c:1004-1033](https://github.com/bluez/bluez/blob/5.87/src/agent.c#L1004-L1033)). With `AlwaysPairable` at its default `false` ([main.conf:16-24](https://github.com/bluez/bluez/blob/5.87/src/main.conf#L16-L24)), that function turns on `MGMT_OP_SET_BONDABLE` while an agent is registered and requests turning it off when the last default agent disappears ([adapter.c:9151-9173](https://github.com/bluez/bluez/blob/5.87/src/adapter.c#L9151-L9173)). Adapter setup's explicit turn-on also requires `AlwaysPairable` ([adapter.c:10520-10525](https://github.com/bluez/bluez/blob/5.87/src/adapter.c#L10520-L10525)). The last-agent-off and hotplug/restart conclusions follow from these source paths; they have **not** been measured on hardware. The prior `ExecStartPre` ran before agent registration, so the permanent agent could reopen pairability immediately.

BlueZ's `PairableTimeout` calls `MGMT_OP_SET_BONDABLE` with zero when it expires ([adapter.c:870-895](https://github.com/bluez/bluez/blob/5.87/src/adapter.c#L870-L895)). That can prevent a lasting outgoing bond: Linux BR/EDR forces a non-bonding authentication value if `HCI_BONDABLE` is clear ([hci_event.c:5248-5279](https://github.com/torvalds/linux/blob/v6.17/net/bluetooth/hci_event.c#L5248-L5279)), and Linux LE clears `SMP_AUTH_BONDING` in that state ([smp.c:650-664](https://github.com/torvalds/linux/blob/v6.17/net/bluetooth/smp.c#L650-L664)). Therefore this design **does not set `PairableTimeout`**. The pairing command's process lifetime bounds the exposure instead.

1. Remove the permanent `bt-agent` user unit from `modules/nixos.nix:1675-1704`, including the draft PR's `ExecStartPre`, and remove its `hardware.bluetooth.settings.General.PairableTimeout` addition at `modules/nixos.nix:1847`. Leave `AlwaysPairable` unset. Update `modules/AGENTS.md`'s user-unit explanation and `tests/options.nix:3650-3667`, which currently require `bt-agent.service`, to assert its absence while retaining the other units. The already-filtered `pkgs/omarchy/enable-user-units.sh:29-42` skips the absent unit at first run; its upstream-name guard in `pkgs/omarchy/default.nix:1540-1549` can remain because it checks the upstream source, not the installed service.
2. Patch the pinned Omarchy `bin/omarchy-bluetooth-device` in `pkgs/omarchy/default.nix` with `--replace-fail`, changing only its `pair)` branch (`basecamp/omarchy@c668141`, [lines 35-41](https://github.com/basecamp/omarchy/blob/c668141e9c42b13c80c9ca4ea108e11708c5e8a5/bin/omarchy-bluetooth-device#L35-L41)). After `power_on`, start `bt-agent -c NoInputNoOutput` for that invocation, wait until it is registered and the adapter is pairable, then run the existing pair/trust/connect sequence. Track the agent PID and stop and reap **that PID** on normal exit or interruption; never kill by process name. If registration fails or times out, do not attempt pairing. Other script actions remain unchanged. Add `bluez-tools` to the package's explicit `runtimeDeps` in `pkgs/omarchy/default.nix:185-239`, since `bt-agent` is currently supplied only by the removed service's store path.
3. Replace `tests/bluetooth-pairing.nix`'s now-invalid guard/timeout assertions with a cheap check of the evaluated module and the patched package: no permanent `bt-agent` unit or pairable timeout, temporary agent registration in the pair branch, PID-scoped cleanup, and no agent start in connect/disconnect/forget. Prove it fails with the persistent unit restored and with the temporary agent removed from the pair branch, using copies outside the worktree and restoring with `cp`. Update `pkgs/verify.sh:444-476` to report the live agent and pairability without calling the short, intentional pairing window a fault. Keep `flake.nix` check registration.

## Alternatives rejected

- Permanent agent with `ExecStartPre` setting `Pairable: no`: registering the default agent turns bonding back on in BlueZ 5.87, so startup ordering defeats the guard.
- Permanent agent with `Pairable: no` plus a 120-second timeout: the timeout can clear bondability during outgoing pairing. It is neither a safe fallback nor needed when the agent lives only for the pair command.
- A panel-wide pairing window or per-pair confirmation: the owner chose the existing `NoInputNoOutput` flow only while the user initiates a pair, with no confirmation prompt. Patching the panel would add lifecycle and multi-monitor state that the pair command already scopes.
- Relying on discovery as a pairing boundary: the pinned panel controls `discovering`, not bondability.

## Risks

- BlueZ may retain bondability after the temporary agent exits, or another agent may remain registered. The source suggests the last-agent exit clears it; hardware must prove this at idle, after adapter power cycling, and after reboot.
- Pairing may fail if the agent has not registered before `bluetoothctl pair`, or if the command is interrupted without cleanup. The readiness wait, PID-scoped trap, and a negative check cover those paths.
- Without a permanent agent, service authorization can be refused for a bonded device that is not trusted. The pair action marks new devices trusted; this affects older untrusted pairings. Reconnect one device paired before this change during the hardware check.
- A process timeout that cuts off the agent before the pairing command finishes can leave an unbonded device. Do not add a separate pairable timeout; bound the agent to the pair command's own lifetime.
- Existing users may have `bt-agent.service` enabled from a prior generation. Removing the declarative unit must be checked against systemd's generated user-unit state so it does not persist as an active service after rebuild and login.

## Verification

- No builds or VM runs at this revised-spec gate. The approved plan is superseded and must be revised and re-approved before code edits. During implementation, run the cheap check against both deliberate breaks, capture the red diagnostics, restore source copies with `cp`, and show a green run. Run `nix fmt`, statix, deadnix, shell syntax, and the applicable module assertions. `checks.options` is left to CI because it needs about 11.5 GB RSS; no local VM checks.
- On hardware after deployment, confirm `bluetoothctl show` reports `Pairable: no` at idle after login and after an adapter power cycle. Reconnect a device paired before this change and check whether it was trusted. Initiate a new pair from the panel, confirm the device bonds and is trusted, then confirm the agent exits and `Pairable: no` returns. **Reboot**, confirm the new device reconnects, and confirm `Pairable: no` again. These are owner checks; the radio-free VM cannot prove them.
