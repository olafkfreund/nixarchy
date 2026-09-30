---
status: approved
issue: 1085
intent: intent/2026-09-30-1085-bluetooth-pairing.md
---

# Spec: Disable unattended incoming Bluetooth pairing

## Design

The pinned Omarchy source is `basecamp/omarchy` revision `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` (`flake.nix:81-82`, `flake.lock`). Its [Bluetooth panel](https://github.com/basecamp/omarchy/blob/c668141e9c42b13c80c9ca4ea108e11708c5e8a5/shell/plugins/panels/bluetooth/Panel.qml#L504-L559) starts discovery while open and stops it after closing. `Panel.qml:408-420` handles opening, and `Panel.qml:276-280` delegates pairing to `bin/omarchy-bluetooth-device:35-41`. Neither file changes `Pairable`; discovery is not a pairing gate. The assertion at `modules/nixos.nix:1692-1694` is therefore false. [BlueZ's Adapter API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst) says `Pairable` defaults to true, affects incoming requests, and has a disabled timeout by default.

1. In `modules/nixos.nix:1675-1698`, make the existing agent refuse to start until it has set the default adapter non-pairable, and keep its restart behavior so a temporarily unavailable adapter is retried. Set `hardware.bluetooth.settings.General.PairableTimeout = 120` beside `hardware.bluetooth.enable` at `modules/nixos.nix:1842` as a fallback if another client enables incoming pairing. These definitions remain inside the `programs.nixarchy` enabled configuration, leaving Mode A untouched. Replace the incorrect safety comment. A timeout alone would leave BlueZ's default `Pairable: yes` window open.
2. Leave the pinned panel unchanged. Its `Panel.qml:276-280` initiates outgoing pairing through `bin/omarchy-bluetooth-device:35-41`. [BlueZ's Adapter API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst) says `Pairable` affects incoming pairing requests only, so outgoing panel pairing should work with `Pairable: no`; confirm that on hardware before considering the change complete. Device-initiated pairing is an accepted loss.
3. Add one cheap check under `tests/`, wired through `flake.nix`, that reads the **evaluated enabled module's** Bluetooth settings and generated agent unit. Assert that the agent gates startup on pairability being turned off and the timeout is 120 seconds. Also assert the disabled module adds none of these settings. The check must fail when the module guard or timeout is removed, then pass when restored. Copy files aside and restore them after each deliberate break; capture the failing outputs for the PR.
4. Extend `pkgs/verify.sh:444-458` to report actual adapter pairability and agent state on real hardware, without claiming that the radio-free `tests/session.nix:1145-1167` VM tested pairing. A manual hardware check must cover idle, panel open, panel close, adapter power cycle, and a user-initiated outgoing pair while `Pairable: no`. This is the only layer that can prove the runtime boundary.

## Alternatives rejected

- `PairableTimeout = 120` alone: [BlueZ defaults to pairable](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst), so a timeout without an explicit off state does not establish an idle boundary.
- Stop the permanent agent only: this removes unattended acceptance but does not make the adapter non-pairable by default.
- Open a short incoming pairing window from the panel: the owner chose no incoming window and accepted the loss of device-initiated pairing. It would also require a downstream patch to the pinned panel.
- Per-pairing confirmation: the owner chose to preserve unattended agent handling for outgoing pairing instead.
- Treat discovery as pairability: the pinned panel changes `discovering` only, and BlueZ exposes `Pairable` separately.

## Risks

- BlueZ may bring an adapter back as pairable after power cycling or when a new adapter appears. The hardware check must catch that; if it does, the implementation needs a way to restore the off state before completion.
- If the startup off operation races adapter creation, the agent must fail closed and retry; pairing may be temporarily unavailable.
- Other Bluetooth clients can alter the global `Pairable` property. The two-minute timeout limits exposure but does not replace the idle-state check.

## Verification

- During implementation, run the cheap check against a deliberately removed module guard, then against a removed timeout; capture each failure, restore from file copies, and show a green run. Run formatter and static Nix checks. No builds or VM runs occur at this spec gate.
- On hardware, `bluetoothctl show` reports `Pairable: no` at idle, while the panel is open and after power cycling; deliberate outgoing pairing from the panel still works. If another client enables pairing, it returns to `Pairable: no` within two minutes. `nixarchy-verify` reports the observed state.
- The radio-free session VM checks only that Bluetooth is configured, not the pairing boundary.
