---
status: draft
issue: 765
author: olafkfreund
---

# Intent: the rebuild runs in the Omarchy shell, and asks for the password through the Omarchy dialog

Closes #765.

## Problem

Enabling an app from the menu is the most common way anyone changes a nixarchy
machine, and it is the least Omarchy-looking thing on the desktop.
`omarchy-launch-floating-terminal-with-presentation nixarchy-apply` opens a
terminal. The terminal asks two `[y/N]` questions, streams nh's build log, and
then `sudo` asks for the password as text inside that terminal. nh
auto-elevates, finds sudo before pkexec, and nothing in the repo sets an
elevation strategy or askpass. The Omarchy polkit dialog
(`shell/plugins/polkit`) is already running on every nixarchy desktop, with no
competing agent, and the rebuild never uses it.

Three smaller things go wrong along the same path:

- **`nixarchy-apply` can only be driven by a person at a tty.** nixarchy-pkg
  feeds it `printf 'n\ny\n'`. The preview question is only asked when
  `nixarchy-preview` is installed (`modules/apps.nix:3307`), so on a machine
  without it the `n` meant for the preview answers "Build and switch now?" and
  the switch is declined.
- **The failure message can be false.** "Nothing changed on this machine"
  (`modules/apps.nix:3331`) prints for every nonzero exit, but nh activates
  first and updates the profile and bootloader afterwards, so it can fail with
  the running system already changed.
- **The bar spinner's click shows the wrong log.** It opens `nix-daemon.service`
  (`pkgs/omarchy/switch-indicator.qml:96`), which misses evaluation errors and
  activation output.

## Proposed outcome

- Choosing Build and switch asks for the password in the Omarchy polkit dialog,
  not in a terminal.
- The rebuild shows in an Omarchy-styled Quickshell panel: the current step,
  elapsed time, the tail of the log, and on failure **Copy log** and **Open full
  log in terminal**. The complete error text is always one click away.
- Closing the panel does not stop the build. Reopening it, or restarting the
  shell, reconnects to the same build.
- `nixarchy-apply` accepts its answers as flags. It keeps the interactive
  prompts for a person at a terminal, and scripts and plugins stop feeding it
  stdin.
- A failed rebuild says it failed and where to read why, without claiming
  whether anything changed.
- The bar spinner opens the rebuild's own log.

## Affected users and systems

Every nixarchy desktop. Affected code: `nixarchy-apply` and its callers
(`modules/apps.nix`, the menu rows, nixarchy-pkg's Apply), nh's elevation
settings, the pkexec wrapper and polkit configuration
(`security.polkit`), the switch indicator, and a new Quickshell panel in the
vendored tree (`pkgs/omarchy/`).

## Constraints

- **Authentication stays required.** No passwordless rule for wheel: switching
  runs activation code from a configuration the user controls, so a
  passwordless switch is passwordless root.
- **Only the rebuild changes.** Other `sudo` uses keep their prompts, including
  SSH and the console. `sudo` is not replaced system-wide.
- **The panel is a viewer, never the owner of the build.** A shell crash must
  not kill a switch halfway through activation.
- **nh itself stays unprivileged**, and only the elevation strategy changes. nh
  refuses to run `os` as root.
- **Mode A:** importing the module with nothing enabled changes nothing
  (`modeAInert`).
- The terminal path stays available: `nixarchy apply` from a shell behaves as it
  does today.
- Every new check is proven to fail first (§1). A new `checks.<name>` needs a
  workflow edit by a human (§4, §11).

## Open questions

- **Scope of the first PR.** Recommended order: pkexec and the `--yes`/
  `--no-preview` flags and the message fix, then the supervised unit, then the
  panel. The first slice fixes the password prompt and nixarchy-pkg's Apply
  without any QML. Or do all three at once?
- **Does the menu still open a terminal at all?** Options: the panel replaces
  the floating terminal for Install > Apply and the per-app rows, or the panel
  is added and the terminal stays the default until the panel has proven
  itself.
