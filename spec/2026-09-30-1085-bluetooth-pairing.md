---
status: draft
issue: 1085
intent: intent/2026-09-30-1085-bluetooth-pairing.md
---

# Spec: Bound unattended Bluetooth pairing to the panel

## Design

The pinned Omarchy source is `basecamp/omarchy` revision `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` (`flake.nix:81-82`, `flake.lock`). Its [Bluetooth panel](https://github.com/basecamp/omarchy/blob/c668141e9c42b13c80c9ca4ea108e11708c5e8a5/shell/plugins/panels/bluetooth/Panel.qml#L504-L559) starts discovery while open and stops it after closing. `Panel.qml:408-420` handles opening, and `Panel.qml:276-280` delegates pairing to `bin/omarchy-bluetooth-device:35-41`. Neither file changes `Pairable`; discovery is not a pairing gate. The assertion at `modules/nixos.nix:1692-1694` is therefore false. [BlueZ's Adapter API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst) says `Pairable` defaults to true, affects incoming requests, and has a disabled timeout by default.

1. In `modules/nixos.nix:1675-1698`, make the existing agent refuse to start until it has set the default adapter non-pairable, and keep its restart behavior so a temporarily unavailable adapter is retried. Set `hardware.bluetooth.settings.General.PairableTimeout = 120` beside `hardware.bluetooth.enable` at `modules/nixos.nix:1842`. These definitions remain inside the `programs.nixarchy` enabled configuration, leaving Mode A untouched. Replace the incorrect safety comment. A timeout alone would leave BlueZ's default `Pairable: yes` window open.
2. In `pkgs/omarchy/default.nix`'s existing shell patch area (around line 1826), patch the pinned `shell/plugins/panels/bluetooth/Panel.qml` with fail-fast substitutions. Use Quickshell's writable adapter `pairable` property: set it true when the user opens the panel for discovery, false on close, and false when an enabled adapter appears while the panel is closed. Keep the panel's existing discovery ownership logic. The installed Quickshell 0.3.1 Bluetooth type exposes writable `pairable` and `pairableTimeout` properties. Its close behavior must account for the existing multiple-monitor handoff (`Panel.qml:424-440`), so one panel cannot turn pairing off while another remains open. The 120-second BlueZ timeout closes the window if the shell exits without cleanup.
3. Add one cheap check under `tests/`, wired through `flake.nix`, that reads the **evaluated enabled module's** Bluetooth settings and generated agent unit plus the built, patched panel. Assert that the agent gates startup on pairability being turned off, the timeout is 120 seconds, and the panel opens and closes pairability with the correct multi-monitor behavior. Also assert the disabled module adds none of these settings. The check must fail when either the module guard or panel patch is removed, then pass when restored. Copy files aside and restore them after each deliberate break; capture both failing outputs for the PR.
4. Extend `pkgs/verify.sh:444-458` to report actual adapter pairability and agent state on real hardware, without claiming that the radio-free `tests/session.nix:1145-1167` VM tested pairing. A manual hardware check must cover idle, panel open, panel close, the two-minute timeout, adapter power cycle, and a user-initiated pair. This is the only layer that can prove the runtime boundary.

## Alternatives rejected

- `PairableTimeout = 120` alone: [BlueZ defaults to pairable](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst), so a timeout without an explicit off state does not establish an idle boundary.
- Stop the permanent agent only: this removes unattended acceptance but does not make the adapter non-pairable by default or specify how panel pairing works.
- Per-pairing confirmation: the owner chose a short visible Just Works window instead.
- Treat discovery as pairability: the pinned panel changes `discovering` only, and BlueZ exposes `Pairable` separately.

## Risks

- BlueZ may bring an adapter back as pairable after power cycling or when a new adapter appears. The panel's adapter-change handling and the hardware check must catch that.
- If the startup off operation races adapter creation, the agent must fail closed and retry; pairing may be temporarily unavailable.
- A panel on another monitor may hold discovery when one closes. Pairability must follow the active panel, not an individual panel instance.
- Other Bluetooth clients can alter the global `Pairable` property. The two-minute timeout limits exposure but does not replace the idle-state check.

## Verification

- During implementation, run the cheap check against a deliberately removed module guard, then against a deliberately removed panel patch; capture each failure, restore from file copies, and show a green run. Run formatter and static Nix checks. No builds or VM runs occur at this spec gate.
- On hardware, `bluetoothctl show` reports `Pairable: no` at idle and after power cycling; opening the panel reports `Pairable: yes`; closing it or waiting at most two minutes reports `Pairable: no`; deliberate pairing from the panel still works. `nixarchy-verify` reports the observed state.
- The radio-free session VM checks only that Bluetooth is configured, not the pairing boundary.
