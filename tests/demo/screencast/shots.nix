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
# RUNTIME, because the brief is 60 seconds and the first draft came to 71:
#
#   spine   2 + 3 + 4 + 5 + 4 + 5 + 6   = 29.0
#   montage 9 x 2.4                     = 21.6
#   tail    5 + 4                       =  9.0
#                                         ------
#                                         59.6
#
# Every hold is arithmetic rather than preference: lengthening one means
# shortening another, and the montage is already at the floor of what a person
# can read. The owner chose the full twelve-plugin tour knowing that, against
# the advice that one transformation persuades better than a tour.
let
  # Each montage entry is one panel, opened on its own keybinding.
  montage =
    map
      (p: {
        label = "montage-${p.short}";
        action = "plugin";
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
          short = "aimirror";
          id = "olafkfreund.ai-mirror";
          name = "An agent can drive this desktop — and you can stop it";
          expect = "mirror|agent|control";
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
      route = "";
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
      expect = "Packages|Search|nixpkgs";
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
