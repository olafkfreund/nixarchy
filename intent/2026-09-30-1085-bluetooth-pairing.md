---
status: approved
issue: 1085
author: olafkfreund
---

# Intent: Bound Bluetooth pairing exposure

## Problem

`modules/nixos.nix` starts a `NoInputNoOutput` Bluetooth agent for the whole graphical session. That agent can accept pairing without user confirmation. The adjacent comment assumes the adapter is pairable only while the Bluetooth panel scans, but the pinned panel starts discovery without changing pairability and this repository sets no pairing timeout. The owner's `Pairable: yes` observation shows a possible exposure, although it may have been made during a scan. A successful unwanted pairing or HID injection has not been reproduced.

## Proposed outcome

An untrusted nearby device cannot pair through the desktop's unattended agent outside a deliberate, bounded pairing action. Normal user-initiated Bluetooth pairing still works.

## Affected users and systems

Nixarchy desktop sessions with a Bluetooth adapter, especially users who leave the session running near untrusted devices. The `bt-agent` user unit and Bluetooth service configuration are involved; radio-free VMs cannot prove pairing behavior.

## Constraints

- Keep an existing NixOS user's Bluetooth choices intact when Nixarchy is disabled.
- Verify the actual panel and BlueZ pairing flow before choosing a timeout or agent lifecycle.
- Add a check that fails when the exposure is reintroduced; live pairing behavior needs a hardware check because the session VM has no radio.
- Do not make pairing silently unavailable to users who explicitly open the Bluetooth panel.

## Open questions

None. The owner chose a visible pairing window of about two minutes without per-pairing confirmation: the adapter is not pairable by default and becomes pairable only while the user pairs from the panel. The pinned panel currently controls discovery, not pairability.
