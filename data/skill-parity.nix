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
  "## When This Skill MUST Be Used" = {
    class = "adapted";
    upstream = "c4b249c56563";
    anchor = "- Installing packages or changing system configuration — use the `nixos` skill";
    reason = "Upstream's exclusion is Omarchy source development. Here the routing decision that matters first is packages-and-system versus desktop, because on NixOS those are different files with different lifetimes, so the exclusion names the `nixos` skill before it names source development.";
  };

  "## Topic Guides" = {
    class = "adapted";
    upstream = "85358cfcd451";
    anchor = "reporting Nixarchy and Omarchy bugs";
    reason = "Same six guides, one line changed: contributing.md here routes a bug between this port and upstream first, rather than assuming every bug is Omarchy's.";
  };

  "## Critical Safety Rules" = {
    class = "adapted";
    upstream = "a99ca335d725";
    anchor = "read-only `/nix/store` path";
    reason = "Upstream's rule is that /usr/share/omarchy is overwritten on update. Here the path is a store path mounted read-only, so the rule is stronger and stated as such: a write does not lose later, it fails now.";
  };

  "## Privilege Escalation" = {
    class = "adapted";
    upstream = "d4ded906a1a4";
    anchor = "Use `pkexec` only when the caller cannot interact with a terminal";
    reason = "The sudo/pkexec split is upstream's and kept. The sentence about Omarchy granting passwordless sudo to particular commands is dropped: that is an Arch packaging arrangement this port does not make.";
  };

  "## System Architecture" = {
    class = "adapted";
    upstream = "087c2f1646b5";
    anchor = "Two config systems coexist and the boundary matters";
    reason = "The component table gains the flake as the base OS row and the generated menu, and the section states the boundary that has no upstream equivalent: ~/.config is yours and imperative, the flake half is declarative and needs a rebuild.";
  };

  "## Command Discovery" = {
    class = "adapted";
    upstream = "d45ca4a1fa32";
    anchor = "omarchy commands --json";
    reason = "The discovery commands are upstream's. What changes is where a command's source is read from -- $OMARCHY_PATH rather than /usr/share/omarchy -- because the store path is the only correct spelling here.";
  };

  "### Command Groups" = {
    class = "adapted";
    upstream = "ac64c63b62d2";
    anchor = "Run `omarchy --help` for the full list. The most common groups:";
    reason = "The table is upstream's with three purpose cells rewritten; each of those is its own row below, so this row covers the table's frame rather than its contents.";
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
    upstream = "ce587d348b8d";
    anchor = "| `omarchy toggle` | Toggle feature on/off |";
  };

  "group: omarchy theme" = {
    class = "preserved";
    upstream = "5192b6f42133";
    anchor = "| `omarchy theme` | Theme management |";
  };

  "group: omarchy bar" = {
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
    upstream = "25b0b6e33af6";
    anchor = "| `omarchy capture` | Screenshots and recordings |";
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
    class = "adapted";
    upstream = "12f7f777e610";
    anchor = "| `omarchy update` | `nix flake update` + `nixos-rebuild switch` |";
    reason = "\"System updates\" is true of both and useful in neither. Naming the two commands tells the reader that the update moves the flake lock and rebuilds, which is what decides whether it is safe to run now.";
  };

  "## Configuration Locations" = {
    class = "preserved";
    upstream = "dddbfc7f586a";
    anchor = "The Omarchy shell (bar, notifications, plugins, idle) is configured in";
  };

  "### Terminals" = {
    class = "preserved";
    upstream = "7255894c8ce9";
    anchor = "~/.config/ghostty/config";
  };

  "### Other Configs" = {
    class = "adapted";
    upstream = "ad42e6e43311";
    anchor = "Note that `/etc` on NixOS is generated from the system configuration.";
    reason = "The table is upstream's. The paragraph after it is new: one of its rows points into /etc, which on NixOS may be a store symlink, and editing it is the mistake that looks like it worked.";
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
    upstream = "0e08895d8c64";
    anchor = "omarchy update                  # nix flake update + nixos-rebuild switch";
    reason = "The command list is upstream's; the comment on `omarchy update` names what it runs here, for the same reason the command-group row does.";
  };

  "## Troubleshooting" = {
    class = "adapted";
    upstream = "f1b9b329a7d8";
    anchor = "**`omarchy reinstall` exists but cannot finish here.**";
    reason = "Upstream's debug and refresh commands are kept. What is added is the one command that is present and cannot complete: `omarchy reinstall` starts with a pacman transaction the shim refuses, and an agent needs to know that before it recommends it.";
  };

  "## Decision Framework" = {
    class = "adapted";
    upstream = "4cbd9cd66fc8";
    anchor = "Use the `nixos` skill.** Do not run `omarchy pkg add` expecting an install";
    reason = "Upstream's numbered ladder gains the question this port exists to answer: a package install, or anything outside ~/.config, leaves this skill entirely.";
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
    upstream = "b7553b92485c";
    anchor = "\"My change disappeared after a reboot\"";
    reason = "Upstream's examples are kept where the answer is the same command. Three are replaced by the two mistakes that only happen here -- asking this skill to install something, and an imperative change that does not survive a reboot -- because an example is how an agent learns the boundary.";
  };
}
