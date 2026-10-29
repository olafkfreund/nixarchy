---
status: draft
issue: 1509
author: x
---

# Intent: the hyprland template uses Lua config, and its Chromium opens a window

Covers #1509 and #1510. Both are defects in one file,
`modules/microvm/templates/hyprland.nix`, which `hyprland-ai-mirror` imports
(#1513's `nixarchy-desktop` does not). One branch, so the file is edited and
re-measured once.

## Problem

1. **#1510: the compositor config uses a format Hyprland is removing.** The
   template writes `/etc/hypr/hyprland.conf` in hyprlang. The guest's Hyprland
   0.56.2 shows a toast on every boot saying `.conf` support goes in 0.57,
   plus a second warning that it "was started without start-hyprland". Both
   land in every screenshot an agent takes of the sandbox. When nixpkgs
   reaches 0.57, the monitor rule stops applying, the output stops being
   1920x1080, and every capture taken against that size is wrong.
2. **#1509: Chromium opens no window.** The template ships Chromium for
   accessibility testing (#821), but started with no flags it waits 80 s and
   shows nothing. It defaults to X11, and the guest has no Xwayland and no
   `NIXOS_OZONE_WL`. With `--ozone-platform=wayland` it renders in about 11 s
   and `a11y_find` sees its controls (measured on p620, 2026-10-29).

## Proposed outcome

- The guest's Hyprland reads a Lua config with the same four settings: the
  `Virtual-1` 1920x1080 monitor rule, no logo, no splash, and logs on stdout.
  It starts the way Hyprland wants to be started, so neither toast appears.
- A plain `chromium` started in the guest (from ai-mirror's `launch`, a
  terminal or a script) opens a Wayland window, with the accessibility tree
  still exposed.
- A check that boots nothing can see both: no `.conf` and the Lua settings
  present, and Chromium's wrapper carrying the Wayland flag. A live boot shows
  no toast in a screenshot and a Chromium window in `windows`.

## Affected users and systems

- `modules/microvm/templates/hyprland.nix`, its note in
  `data/microvm-templates.nix` if that mentions the config path,
  `modules/microvm/AGENTS.md` if it names `hyprland.conf`, and a check
  (likely an extension of `tests/microvm-ai-mirror.nix` or a sibling).
- Users of the `hyprland` and `hyprland-ai-mirror` templates. Guest
  behaviour only; nothing on the host changes. Mode A is untouched, since a
  template is opt-in.

## Constraints

- One closure per template, as now. No host GL (#1506).
- Every one of the four settings stays load-bearing (modules/microvm/AGENTS.md):
  dropping one gives the same `CBackend::create() failed!`, so the live boot
  must show each still applies (output size, logs in the journal).
- The fix for Chromium must reach a process started by a systemd user
  service with no login, which is how ai-mirror's `launch` starts things. A
  session variable may not reach it (#1509's note), so this is measured, not
  assumed.
- The owner asked for agy and Codex on the team. Neither can build, so they
  implement or review, and this session runs every check and the live boot.

## Open questions

1. Is `start-hyprland` right under a systemd user service, or does it expect
   a login session? Default: try it; if it does not fit, keep `Hyprland` and
   suppress only the start-hyprland warning if that's possible. The spec
   decides after reading `start-hyprland`.
2. Chromium flag in the wrapper (`commandLineArgs`) or `NIXOS_OZONE_WL`?
   Default: the wrapper flag, because it reaches every caller regardless of
   environment.
