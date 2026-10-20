---
status: approved
issue: 1385
author: olafkfreund
---

# Intent: Omarchy's passwordless-sudo toggle is hidden everywhere on nixarchy

## Problem

On edge, the top panel shows quattro's `PasswordlessSudo` indicator by
default (`shell/plugins/bar/widgets/Indicators.qml:11`,
`defaultIndicatorEntries`). Clicking it opens a terminal running
`omarchy-sudo-passwordless`. Nixarchy replaces that command with a stub
(`pkgs/omarchy/nix-bin/omarchy-sudo-passwordless`, bin-ledger `replace`)
that explains the feature cannot work on NixOS and exits 1, so the user
sees a wall of text and `Failed (exit code 1)`.

The feature cannot work here as upstream built it: it grants access by
writing `/etc/sudoers.d`, which NixOS's sudo does not read. Nixarchy
decided long ago not to offer passwordless root one click away
(`docs/manual/security.md`, #1280), and the owner confirmed on 2026-10-20
that the answer is to **hide it completely, not port it**.

Where it is still visible:

| where | today |
|---|---|
| Edge, menu *Setup > Security > Passwordless Sudo* | hidden (`modules/apps.nix`, `when = "false"`, #1280) |
| **Edge, the bar indicator** | **shown by default**; clicking runs the stub, which fails. Its `--active` probe also runs at shell start and on every indicator refresh, against a stub that knows no flags |
| **Edge, Settings > bar > indicators** | `PasswordlessSudo` is offered as a choice (`Indicators.manifest.json:30`) |
| **Stable 4.0.6, the menu row** | **shown**; it runs the stub, which fails |

## Proposed outcome

- **No nixarchy user sees passwordless sudo anywhere:** not in the bar,
  not in the menu, and not among the indicators settings offers, on
  stable or edge.
- A user who already has `PasswordlessSudo` in a saved indicator list
  sees nothing and gets no error. The shell logs no QML error, which
  `checks.session` asserts.
- `omarchy-sudo-passwordless`, run by hand, still prints the NixOS
  explanation. The stub stays: it is the one place someone typing the
  command learns what to declare instead.
- `docs/manual/security.md` says the toggle is hidden and why. The
  declarative option it already documents stays.

## Affected users and systems

- Edge: quattro's bar indicator and the settings manifest, in
  `pkgs/omarchy/default.nix` (edge-candidate).
- Stable: the menu row, in `modules/apps.nix` on `main`.
- `docs/manual/security.md`.

## Constraints

- **Hide; do not delete a file another file loads.** Removing
  `PasswordlessSudo.qml` would turn a saved indicator name into a QML
  load error. The indicator must resolve and simply never show.
- **The stub must not be run by the shell at all.** The `--active` probe
  at startup and refresh must not spawn it.
- **`--replace-fail` and `--fuzz=0` as usual,** so the next quattro
  change to these files fails the build instead of quietly bringing the
  icon back.
- **§1:** a check fails if the indicator is in the shipped defaults or
  manifest, and the session check sees no QML error from a configuration
  that names it.
- Edge carries its own diff here, so the change goes where `main` and
  `edge` agree, proved by a trial merge.

## Open questions

- None. The owner chose "hide in full" over porting the feature.
