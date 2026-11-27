# Every section of upstream's own SKILL.md, and what this port did with it.
#
# pkgs/omarchy/default.nix renames upstream's `omarchy` skill to `nixarchy` and
# copies ours over the top, so upstream's SKILL.md -- 13 KB, 19 headings, 14
# command groups -- is replaced wholesale. That replacement is deliberate and
# stays: docs/manual/ai.md says why, under "The skills are rewritten, because
# upstream's would lie". An Arch-shaped instruction handed to an agent on NixOS
# is worse than no instruction.
#
# What was missing is the record of WHAT was replaced. Every other guard we
# have on the skills is about names and counts -- readme-counts.sh asserts the
# skill count and a row per skill, build.yml asserts skill-set equality and
# frontmatter. A section appearing inside upstream's SKILL.md, or the body of
# one being rewritten, trips none of them.
#
# ## The rule that keeps this file honest
#
# .github/scripts/check-skill-parity.py fails in BOTH directions -- an upstream
# section with no row is unclassified, a row upstream no longer has is stale --
# and it pins a digest of upstream's text per row, so a bump cannot rewrite a
# section under us either. None of that can be satisfied by editing this file:
# the upstream side is read from inputs.omarchy, the same source pkgs/omarchy
# vendors.
#
# ## The classes
#
#   preserved  the section is here under the same heading, saying the same
#              thing. `anchor` proves it.
#   adapted    the section is here and was rewritten for NixOS. `anchor` is a
#              string from OUR version, so the claim is checked rather than
#              asserted, and `reason` says what moved.
#   omitted    the section is not here at all. `reason` is required, and an
#              anchor is refused -- there is nothing to point at.
#
# ## When upstream bumps
#
# The check names each section whose digest moved. Read the new text, decide
# again, then update `upstream` -- `check-skill-parity.py --report` prints the
# current digests. Updating a digest is the act of having decided; that is why
# it is a hand edit and not a derived file.
#
# The idea, and the anchor-proof shape, come from zicochaos/omarchy-nix's
# skills/omarchy/skill-parity.json (MIT). The code here is ours.
{

  "## Topic Guides" = {
    class = "adapted";
    upstream = "2a25cb15a898";
    tag_upstream = "85358cfcd451";
    anchor = "reporting Nixarchy and Omarchy bugs";
    reason = "The existing guides remain, with contributing.md routing bugs between this port and upstream. Quattro 2eb7eb3 adds apps.md and system.md; both are ported here for NixOS. Our plugins.md link resolves to upstream's renamed shell.md in the built tree. The four omarchy-make-* skills and omarchy-contribute remain separate skills (#1847, #1882).";
  };

  "## Critical Safety Rules" = {
    class = "adapted";
    upstream = "355acc3bad25";
    tag_upstream = "a99ca335d725";
    anchor = "read-only `/nix/store` path";
    reason = "Upstream's rule is that /usr/share/omarchy is overwritten on update. Here the path is a store path mounted read-only, so the rule is stronger and stated as such: a write does not lose later, it fails now. Quattro also asks for a reason on pkexec's dialog; this port does not carry that yet (see Privilege Escalation).";
  };

  "## Privilege Escalation" = {
    class = "adapted";
    upstream = "092eba3f21f2";
    tag_upstream = "d4ded906a1a4";
    anchor = "Use `pkexec` only when the caller cannot interact with a terminal";
    reason = "The sudo/pkexec split is upstream's and kept. Omarchy's new exception for installing curated Arch packages does not apply: Nixarchy installs packages declaratively, omarchy-pkg-add-curated only delegates to omarchy-pkg-add here, and the earlier passwordless-sudo arrangement is not made. Quattro's advice to give pkexec's dialog a reason through `omarchy-shell -q omarchy.polkit expect` is not carried: main's v4.5.0 tag has no such call, though quattro's shell here does.";
  };

  "## System Architecture" = {
    class = "adapted";
    upstream = "2e1d666f4723";
    tag_upstream = "087c2f1646b5";
    anchor = "Two config systems coexist and the boundary matters";
    reason = "The component table gains the flake as the base OS row and the generated menu, and states the boundary between imperative ~/.config and declarative system changes. Quattro's OSD is listed here; dock configuration stays in the linked shell guide, UWSM's env.d is covered in system.md, and default apps in apps.md. This table does not name foot as the default terminal or give UWSM its own row (#1847, #1882).";
  };

  "## Command Discovery" = {
    class = "adapted";
    upstream = "7a68ba28af0a";
    tag_upstream = "d45ca4a1fa32";
    anchor = "omarchy commands --json";
    reason = "The discovery commands are upstream's. What changes is where a command's source is read from -- $OMARCHY_PATH rather than /usr/share/omarchy -- because the store path is the only correct spelling here. Upstream's exception (run omarchy-debug directly, #1823) is for a package install whose router cannot see omarchy-debug; here every omarchy-* is a sibling in one bin/, so `omarchy debug` resolves and the port keeps it.";
  };

  "### Command Groups" = {
    class = "adapted";
    upstream = "f960d4c003ee";
    tag_upstream = "ac64c63b62d2";
    anchor = "Run `omarchy --help` for the full list. The most common groups:";
    reason = "The table keeps upstream's frame while rewriting NixOS-specific purpose cells. Quattro's default, font/icons, dock, hyprland, display, device, remove, webapp/tui, language/region, powerprofiles, agent and snapshot groups are now listed; individual tracked groups have their own rows below (#1847, #1882).";
  };

  "group: omarchy refresh" = {
    class = "preserved";
    upstream = "059222c5d912";
    anchor = "| `omarchy refresh` | Reset config to defaults (backs up first) |";
  };

  "group: omarchy restart" = {
    class = "preserved";
    upstream = "84629bb0b1f4";
    anchor = "| `omarchy restart` | Restart a service/app |";
  };

  "group: omarchy toggle" = {
    class = "preserved";
    upstream = "cb2a5f3ebc93";
    tag_upstream = "ce587d348b8d";
    anchor = "| `omarchy toggle` | Toggle feature on/off |";
    reason = "Quattro 2eb7eb3 changes its example to `omarchy toggle idle`; the group is the same (#1847, #1882).";
  };

  "group: omarchy theme" = {
    class = "preserved";
    upstream = "a849bcce0afa";
    tag_upstream = "5192b6f42133";
    anchor = "| `omarchy theme` | Theme management |";
    reason = "Quattro 2eb7eb3 rewords it to 'Theme and background'; the group and its command are the same (#1847, #1882).";
  };

  "group: omarchy bar" = {
    edge = "absent";
    class = "preserved";
    upstream = "3ca199b05468";
    anchor = "| `omarchy bar` | Bar layout and widgets |";
  };

  "group: omarchy plugin" = {
    class = "preserved";
    upstream = "586c77079ba7";
    anchor = "| `omarchy plugin` | Manage/clone shell plugins |";
  };

  "group: omarchy hook" = {
    class = "preserved";
    upstream = "e848ce440eac";
    anchor = "| `omarchy hook` | Install automation hooks |";
  };

  "group: omarchy install" = {
    edge = "absent";
    class = "adapted";
    upstream = "20c177d0ea7c";
    anchor = "Queue an app into the Nix selection";
    reason = "Upstream installs optional software with pacman. Here the verb queues the app into the declarative selection instead, so the purpose cell says what it does rather than what it is called.";
  };

  "group: omarchy launch" = {
    class = "preserved";
    upstream = "0548e5830525";
    anchor = "| `omarchy launch` | Launch apps |";
  };

  "group: omarchy capture" = {
    class = "preserved";
    upstream = "b1c53310a4be";
    tag_upstream = "25b0b6e33af6";
    anchor = "| `omarchy capture` | Screenshots and recordings |";
    reason = "Quattro 2eb7eb3 rewords it to cover OCR and QR; the group and its command are the same (#1847, #1882).";
  };

  "group: omarchy reminder" = {
    class = "preserved";
    upstream = "bf2d6226790f";
    anchor = "| `omarchy reminder` | Desktop notification reminders |";
  };

  "group: omarchy pkg" = {
    class = "adapted";
    upstream = "4c54b363d4be";
    anchor = "**Explains the declarative route; installs nothing**";
    reason = "`omarchy pkg add` is a pacman transaction upstream. The command still exists here and deliberately installs nothing, so the cell has to say so -- an agent reading upstream's wording would run it and report an install that never happened.";
  };

  "group: omarchy setup" = {
    class = "preserved";
    upstream = "18fd0a0973a9";
    anchor = "| `omarchy setup` | Interactive setup wizards |";
  };

  "group: omarchy update" = {
    edge = "absent";
    class = "adapted";
    upstream = "12f7f777e610";
    anchor = "| `omarchy update` | `nix flake update` + `nixos-rebuild switch` |";
    reason = "\"System updates\" is true of both and useful in neither. Naming the two commands tells the reader that the update moves the flake lock and rebuilds, which is what decides whether it is safe to run now.";
  };

  "## Configuration Locations" = {
    class = "preserved";
    upstream = "48644f18eb53";
    tag_upstream = "dddbfc7f586a";
    anchor = "The Omarchy shell (bar, notifications, plugins, idle) is configured in";
    reason = "Quattro 2eb7eb3 adds tmux, shell aliases, uwsm env.d and mimeapps rows; all four are now listed under Other Configs (#1847, #1882).";
  };

  "### Terminals" = {
    class = "preserved";
    upstream = "7255894c8ce9";
    anchor = "~/.config/ghostty/config";
  };

  "### Other Configs" = {
    class = "adapted";
    upstream = "84d7f4ed43b1";
    tag_upstream = "ad42e6e43311";
    anchor = "Note that `/etc` on NixOS is generated from the system configuration.";
    reason = "The table includes quattro's tmux, shell aliases, desktop environment variables and mimeapps rows. The paragraph after it explains that /etc on NixOS can point into the store and must be changed through the flake (#1847, #1882).";
  };

  "## Safe Customization Patterns" = {
    class = "preserved";
    upstream = "e3b0c44298fc";
    anchor = "## Safe Customization Patterns";
  };

  "### Edit User Config Directly" = {
    class = "adapted";
    upstream = "98d4f7d16e60";
    anchor = "None of this needs a rebuild. That is the point of the boundary";
    reason = "The edit-backup-apply loop is upstream's. The menu line is replaced because the jsonc is generated here, and the closing paragraph says the desktop half needs no rebuild -- the question a reader arriving from the nixos skill will have.";
  };

  "### Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING" = {
    class = "preserved";
    upstream = "897cd8e0fb74";
    anchor = "omarchy refresh hyprland";
  };

  "## System Commands" = {
    class = "adapted";
    upstream = "45c566024503";
    tag_upstream = "0e08895d8c64";
    anchor = "omarchy update                  # nix flake update + nixos-rebuild switch";
    reason = "The command list is upstream's; the comment on `omarchy update` names what it runs here, for the same reason the command-group row does. Quattro 2eb7eb3 adds `omarchy system logout` and `firmware`, and splits reinstall into `reinstall configs` and the full one; not carried here yet (#1847, #1882).";
  };

  "## Troubleshooting" = {
    class = "adapted";
    upstream = "30f46f1f336f";
    tag_upstream = "f1b9b329a7d8";
    anchor = "**`omarchy reinstall` exists but cannot finish here.**";
    reason = "Upstream's debug and refresh commands are kept. What is added is the one command that is present and cannot complete: `omarchy reinstall` starts with a pacman transaction the shim refuses, and an agent needs to know that before it recommends it. Quattro 2eb7eb3 rewords the reinstall commands; the one this port adds, that `omarchy reinstall` cannot finish here, still holds (#1847, #1882).";
  };

  "## Decision Framework" = {
    class = "adapted";
    upstream = "225d90a0c8b8";
    tag_upstream = "4cbd9cd66fc8";
    anchor = "Use the `nixos` skill.** Do not run `omarchy pkg add` expecting an install";
    reason = "Upstream's numbered ladder gains the NixOS boundary: package installs and changes outside ~/.config use the nixos skill. Quattro's default-app and environment-variable decisions are now included; shell code still points at plugins.md, which links to upstream's shell.md in the built tree (#1847, #1882).";
  };

  "### Reminder Requests" = {
    class = "preserved";
    upstream = "7da70548cd70";
    anchor = "omarchy reminder 15 \"Pickup Jack\"";
  };

  "## Out of Scope" = {
    class = "adapted";
    upstream = "6cb63bb9d8ed";
    anchor = "which is read-only anyway";
    reason = "Same exclusions, re-pathed: /usr/share/omarchy becomes $OMARCHY_PATH, `omarchy dev` is dropped because it is not shipped, and package installation is added as the exclusion that sends the reader to the nixos skill.";
  };

  "## Example Requests" = {
    class = "adapted";
    upstream = "47238d122cf6";
    tag_upstream = "fd34bada703c";
    anchor = "\"My change disappeared after a reboot\"";
    reason = "Upstream's examples are kept where the answer is the same command. The NixOS-specific install and persistence examples teach the declarative boundary. The monitor example keeps the monitors.lua edit that works on both pins. Quattro's default browser, terminal, web app, bar, idle, keyboard layout, environment-variable and text-size examples are now included; bug reports still route through contributing.md rather than omarchy-contribute (#1847, #1882).";
  };

  "group: omarchy agent" = {
    edge = "only";
    class = "adapted";
    upstream = "0c343da3f199";
    anchor = "| `omarchy agent` | Coding agents and accounts; local models (quattro) |";
    reason = "Quattro's coding agents, accounts and local models group is listed with NixOS wording (#1847, #1882).";
  };

  "group: omarchy default" = {
    edge = "only";
    class = "preserved";
    upstream = "8008b5f3e179";
    anchor = "| `omarchy default` | Default browser, terminal, editor, dictation, agent |";
    reason = "Quattro's default browser, terminal, editor, dictation and agent group is now listed (#1847, #1882).";
  };

  "group: omarchy device" = {
    edge = "only";
    class = "adapted";
    upstream = "57c394790b73";
    anchor = "| `omarchy device` | Touchpad and touchscreen toggles (quattro) |";
    reason = "Quattro's device group is listed with the touchpad and touchscreen toggles; the table does not claim its keyboard top-row command (#1847, #1882).";
  };

  "group: omarchy display" = {
    edge = "only";
    class = "preserved";
    upstream = "df22eb721f18";
    anchor = "| `omarchy display` | Text scaling everywhere |";
    reason = "Quattro's text-scaling group is now listed (#1847, #1882).";
  };

  "group: omarchy hyprland" = {
    edge = "only";
    class = "preserved";
    upstream = "772ff24a69ef";
    anchor = "| `omarchy hyprland` | Windows, monitors, layouts |";
    reason = "Quattro's windows, monitors and layouts group is now listed (#1847, #1882).";
  };

  "group: omarchy powerprofiles" = {
    edge = "only";
    class = "preserved";
    upstream = "a9e55875cd65";
    anchor = "| `omarchy powerprofiles` | Power profile per power source |";
    reason = "Quattro's power profile group is now listed (#1847, #1882).";
  };
}
