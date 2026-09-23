# The shot list, as data (#930).
#
# One file drives three things, so they cannot drift from each other:
#   * screencast-drive performs `action` and holds for `hold` seconds;
#   * verify-beats samples the recording at the OBSERVED time of each beat and
#     requires `expect` to be readable there;
#   * screencast-edit places `caption` over the same beat in the social cut.
#
# A caption that claims something the beat does not show is therefore a beat
# the gate fails, rather than a subtitle nobody checked. That distinction is
# load-bearing: a review pointed out that running the gate AFTER editing would
# let a caption satisfy its own expectation, so the gate runs on the raw
# master and refuses a file that already carries captions.
#
# ALL TWELVE shipped plugins appear. Stated rather than left implicit, because
# a reviewer counted the montage alone and concluded nine:
#
#   named beats  nixarchy.pkg (search), plugin-browser (audit),
#                nixarchy.rebuild (apply)
#   montage      microvm, podman, distrobox, devenv, github-actions,
#                gitlab-pipelines, herdr, flatsnap, ai-mirror
#
# Three plus nine.
#
# RUNTIME:
#
#   spine   2 + 3 + 4 + 5 + 4 + 5 + 6       = 29.0
#   theme   3 + 2.5 + 3 + 2.5               = 11.0
#   montage 9 x 2.4                         = 21.6
#   tail    5 + 4                           =  9.0
#                                             ------
#                                             70.6
#
# That is over the 60-second brief, and deliberately so. The brief is 60
# seconds for the CUT, and screencast-edit speeds the whole master to
# SCREENCAST_TARGET_SECONDS -- so a hold here buys screen time at the cost of
# pace everywhere, rather than at the cost of another beat. The owner said as
# much when asking for the acting beats: "if this takes more time that is fine
# we can speed up the recording to catch up".
#
# The montage is still at the floor of what a person can read, and nothing
# below 2.4 there is worth recording.
let
  # Each montage entry is one panel, opened on its own keybinding.
  montage =
    map
      # `action` is per-entry so a plugin that has no panel can say so.
      # ai-mirror is the one: kinds=bar-widget, nothing for nixarchy-plugin to
      # open, and two takes failed on it before this override existed.
      (p: {
        label = "montage-${p.short}";
        action = p.action or "plugin";
        inherit (p) id expect;
        hold = 2.4;
        caption = p.name;
      })
      [
        {
          short = "microvm";
          id = "nixarchy.microvm";
          name = "MicroVMs — disposable NixOS, in seconds";
          expect = "MicroVM|Sandbox|VM";
        }
        {
          short = "podman";
          id = "nixarchy.podman";
          name = "Podman";
          expect = "Podman|container";
        }
        {
          short = "boxes";
          id = "nixarchy.distrobox";
          name = "Boxes";
          expect = "Distrobox|box";
        }
        {
          short = "devenv";
          id = "nixarchy.devenv";
          name = "Dev environments";
          expect = "devenv|environment";
        }
        {
          short = "github";
          id = "olafkfreund.github-actions";
          name = "GitHub Actions";
          expect = "GitHub|workflow|run";
        }
        {
          short = "gitlab";
          id = "olafkfreund.gitlab-pipelines";
          name = "GitLab pipelines";
          expect = "GitLab|pipeline";
        }
        {
          short = "herdr";
          id = "nixarchy.herdr";
          name = "Your agents, across machines";
          expect = "Herdr|session|agent";
        }
        {
          short = "flatsnap";
          id = "nixarchy.flatsnap";
          name = "Flatpak & Snap — declaratively";
          expect = "Flat|Snap";
        }
        {
          # ai-mirror is kinds=bar-widget ONLY. There is no panel for
          # nixarchy-plugin to open, and two takes failed on exactly that --
          # the driver's own assertion caught it both times. So this beat
          # holds on the desktop with the bar in shot, which is what the
          # plugin actually is: an indicator, not a panel.
          short = "aimirror";
          id = "olafkfreund.ai-mirror";
          action = "settle";
          name = "An agent can drive this desktop — and Super+Shift+Escape stops it";
          expect = null;
        }
      ];
in
{
  # The spine is the repository's own copy rather than something written for a
  # video. README.md, above the Install menu section:
  #   "Omarchy's Install menu runs `pacman -S`. Here it edits a file you own."
  beats = [
    {
      label = "desktop";
      action = "settle";
      hold = 2;
      expect = null; # a wallpaper says nothing; this beat is a breath
      caption = "nixarchy — the Omarchy desktop, on NixOS";
    }
    {
      label = "menu";
      action = "menu";
      # `root` is the LAUNCHER -- "What would you like to do?", with
      # Applications, Clipboard History and Calculator. The Omarchy menu, the
      # one this beat is about, is a row inside it. There is no route that
      # lands on it directly: a route is an item id, and summoning an id opens
      # that item's own submenu rather than the list it sits in.
      #
      # Worse, an unknown route falls back to root SILENTLY -- `menu`,
      # `omarchy`, `omarchy.menu` and `main` were each tried live and each
      # produced a byte-identical launcher screenshot. So a wrong guess here
      # does not fail; it records the launcher under a caption about the menu,
      # which is exactly what the first four takes did.
      #
      # The honest route is the one a person takes: open root, arrow down one,
      # enter. That is what `keys` is for.
      route = "root";
      keys = "Down Return";
      hold = 3;
      expect = "Install";
      caption = "One menu. Every change.";
    }
    {
      label = "install-pick";
      action = "menu";
      route = "install";
      hold = 4;
      expect = "Packages|Search|Flatpak";
      caption = "Omarchy's Install menu runs pacman -S.";
    }
    {
      label = "apps-nix";
      action = "term";
      # The file a pick writes to. The whole argument, in one frame.
      command = "grep -n -m3 -B1 '#@' ~/.config/nixarchy/apps.nix | head -12; sleep 5";
      hold = 5;
      expect = "apps\\.nix|#@";
      caption = "Here it edits a file you own.";
    }
    {
      label = "rebuild";
      action = "plugin";
      id = "nixarchy.rebuild";
      hold = 4;
      expect = "Rebuild|Apply";
      caption = "Nothing is built until you apply.";
    }
    {
      label = "search";
      action = "plugin";
      id = "nixarchy.pkg";
      hold = 5;
      # What the panel actually prints, read off a frame of take 4 rather than
      # guessed: a filter box over the tabs `Apps Services Selection Options
      # Drafts Flakes`. The first three expectations here were "Packages",
      # "Search" and "nixpkgs" -- all three plausible, none of them words this
      # picker puts on screen, so the gate failed a beat that was perfect.
      expect = "Apps|Services|Flakes|filter";
      caption = "Every package and every NixOS option, in one picker.";
    }
    {
      label = "plugin-browser";
      action = "plugin";
      id = "io.github.olafkfreund.nixarchy-plugin-browser";
      hold = 6;
      expect = "Plugin|audit|Security";
      # The strongest differentiator: upstream's Add Plugin only asks for a
      # Git URL. This one sandboxes the plugin and reports two verdicts
      # before anything reaches the shell.
      caption = "Marketplace plugins, audited in a sandbox before they touch your shell.";
    }
    # ---- the theme block (owner, 2026-09-23: "show that we can change themes
    # and background and that the plugin follow that as well") --------------
    #
    # Four beats rather than one, because each is separately verifiable. A
    # single beat that opened the switcher AND applied a theme would have its
    # picker on screen at the start and a repainted desktop at the end, and
    # whichever of the two the gate sampled, the other would be unchecked.
    #
    # It sits here, before the montage, on purpose: everything after it is
    # recorded in the new theme, so "the plugins follow" is shown nine more
    # times rather than claimed once.
    {
      label = "theme";
      action = "menu";
      route = "style.theme";
      # The switcher is a coverflow carousel (namespace omarchy-image-selector)
      # -- screenshots of each theme, with ONE name under the centred one.
      # Arrowing is therefore both the nicest footage in the take and the only
      # way the beat shows more than a single theme. No Return: the beat is
      # about browsing, and theme-apply below commits a known one, so the take
      # does not depend on where the carousel happened to land.
      keys = "Right Right";
      hold = 3;
      # Exactly ONE of these is on screen at a time, which is why it is the
      # whole list rather than the two we expect to pass. The first version
      # named five themes the carousel had not reached and would have failed
      # against a perfect frame -- the same mistake this file's `search` beat
      # made. Taken from `omarchy-theme-list` on the recording machine.
      expect = "Osaka Jade|Tokyo Night|Kanagawa|Nord|Gruvbox|Everforest|Catppuccin|Rose Pine|Matte Black|Ristretto|Lumon|Miasma";
      caption = "Twenty themes, in the same menu.";
    }
    {
      label = "theme-apply";
      action = "exec";
      # Set by name rather than driven through the switcher: the picker filters
      # as you type, so a keystroke sequence would depend on the list order and
      # on nothing else having a similar name. The switcher is what the beat
      # above shows; this is what it does.
      command = "omarchy-theme-set 'Tokyo Night'";
      hold = 2.5;
      expect = null; # a repainted desktop carries no text of its own
      caption = "Change it once.";
    }
    {
      label = "theme-follows";
      action = "plugin";
      id = "nixarchy.pkg";
      hold = 3;
      expect = "Apps|Services|Flakes|filter";
      # The claim the owner asked for, and the reason this beat reopens a panel
      # the viewer has already seen in the old theme rather than a new one:
      # the comparison is the point.
      caption = "Every plugin follows.";
    }
    {
      label = "background";
      action = "exec";
      command = "omarchy-theme-bg-next";
      hold = 2.5;
      expect = null;
      caption = "Backgrounds too.";
    }
  ]
  ++ montage
  ++ [
    {
      label = "rollback";
      action = "menu";
      route = "system.recovery";
      hold = 5;
      expect = "Roll back|recovery|snapshot";
      caption = "Every rebuild is a generation. One rollback away.";
    }
    {
      label = "endcard";
      action = "settle";
      hold = 4;
      expect = null;
      # Only what is true. ai-mirror -- the plugin that lets an agent drive a
      # desktop -- reaches a different host than the one being recorded, so
      # "made with a nixarchy plugin" would be a false claim on a public
      # video. This says what actually happened.
      caption = "Recorded on NixOS. Driven end to end by an AI agent.";
    }
  ];
}
