---
status: draft
issue: 1120
author: olafkfreund
---

# Intent: Offer only available installer console keymaps

## Problem

The installer wizard offers Arabic (`ara`) and Thai (`th-tis`) in
`installer/brand/keymaps.txt`, but neither name exists under the pinned
`kbd` 2.9.0 `share/keymaps`. All other 42 entries resolve to a keymap file.
`ask_keymap` ignores a failed `loadkeys`, then writes the selected name into
the generated host's `console.keyMap`. NixOS compiles that keymap with
`loadkeys` during the system build, so these choices can fail after the user
has already answered the wizard. The issue's missing-file claim holds; its
later build failure follows from the pinned NixOS module, but has not been
reproduced by building an installer image.

The pinned upstream Omarchy keyboard menu does not offer Arabic or Thai.
Its menu chooses a Linux console keymap; Omarchy's Hyprland XKB layout is
configured separately. A Latin console layout is usable for installation,
but must not be labelled Arabic or Thai.

## Proposed outcome

Every keyboard choice the installer offers resolves to a real keymap in
the pinned `kbd` package. Users who need Arabic or Thai text can select an
available console layout during installation and configure the desktop's
XKB input layout separately afterwards. A check catches a missing menu
keymap when `kbd` or the list changes.

## Affected users and systems

People choosing a keyboard in the interactive installer, especially those
choosing Arabic or Thai; installed hosts whose generated flake sets
`console.keyMap`; and the installer check suite.

## Constraints

- Use the installer-rendered pinned `kbd` tree, not the developer host's
  keyboard database or an XKB layout name, to establish console support.
- Preserve valid choices and the answers-file ability to specify any real
  pinned console keymap.
- Do not silently map an Arabic or Thai label to a Latin layout. Console
  setup and Hyprland/XKB input are different settings.
- Prove a new check fails when a menu entry names a missing keymap, then
  passes with the corrected list. No builds or implementation at this gate.

## Open questions

1. Should Arabic and Thai be mapped, dropped, or retained with a fallback?
   **Recommend dropping both menu rows.** The pinned `kbd` offers neither
   map, upstream Omarchy omits both, and a hidden Latin fallback would
   misrepresent the selected layout. Users can select a real console layout
   and set their desktop XKB layout separately.
2. Should an automated check cover the whole menu against the pinned `kbd`?
   **Recommend yes.** Compare every tab-separated map name with the actual
   pinned package tree (including symlinked `.map.gz` files), and break-prove
   it with one deliberately missing row. This keeps all 42 remaining names
   honest as the package changes.
