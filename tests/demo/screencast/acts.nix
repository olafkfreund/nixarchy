# What each acting beat DOES, and how it puts the machine back (#930).
#
# "Show how the plugins work" (owner, 2026-09-23) means a viewer sees a
# container start and a box open, not a panel holding still. That makes the
# recording machine the subject rather than the stage, so every act here is:
#
#   * demo-scoped -- `demo-*` names only, so nothing of the owner's is touched
#     and a leftover is recognisable at a glance;
#   * self-cleaning -- `after` undoes `before`, and the recorder's trap runs
#     `sweep` as well, for a take that dies between the two;
#   * idempotent -- every `before` tolerates the object already existing, since
#     a previous take may have died after creating it.
#
# docs/AGENTS.md already asks for exactly this shape: "Before recording, create
# demo-* containers, boxes and VMs, and keep the panels that cannot be faked
# (herdr) out of shot."
#
# Two things are deliberately NOT acted on:
#
#   * Apply. A real rebuild takes minutes and changes the machine (owner
#     excluded it). The Install beat shows the line arriving in apps.nix and
#     the Rebuild panel opening, which is the honest depiction of "nothing is
#     built until you apply" anyway.
#   * herdr's real sessions. herdr-sessions has a demo mode written by its own
#     author for this exact problem, and tests/demo/default.nix:691 already
#     uses it. Real session names are somebody's work in progress and do not
#     belong in a public video.
{
  # id -> { before, after } shell fragments. Absent means the panel is opened
  # and read, with nothing created.
  acts = {
    "nixarchy.podman" = {
      before = ''
        podman rm -f demo-web >/dev/null 2>&1 || true
        podman run -d --name demo-web -p 18080:80 docker.io/library/nginx:alpine >/dev/null 2>&1 || true
      '';
      after = ''
        podman rm -f demo-web >/dev/null 2>&1 || true
      '';
    };

    "nixarchy.distrobox" = {
      # A box that already exists, because pulling an image mid-take is minutes
      # of black screen. Created once here and removed after; if the image is
      # not local the create is skipped rather than stalling the recording.
      before = ''
        if podman image exists docker.io/library/archlinux:latest 2>/dev/null; then
          distrobox create --yes --name demo-box --image docker.io/library/archlinux:latest >/dev/null 2>&1 || true
        else
          echo "  (archlinux image not local -- the Boxes panel will show whatever is there)" >&2
        fi
      '';
      after = ''
        distrobox rm --force demo-box >/dev/null 2>&1 || true
      '';
    };

    "nixarchy.devenv" = {
      before = ''
        mkdir -p ~/demo-project && (cd ~/demo-project && nixarchy dev init python >/dev/null 2>&1 || true)
      '';
      after = ''
        rm -rf ~/demo-project
      '';
    };

    "nixarchy.microvm" = {
      # `create` writes a declaration; it does not build. Building a guest
      # mid-take is minutes, and the panel's own list is what the beat shows.
      before = ''
        nixarchy vm create demo-vm --template shell >/dev/null 2>&1 || true
      '';
      after = ''
        nixarchy vm rm demo-vm >/dev/null 2>&1 || true
      '';
    };

    "nixarchy.herdr" = {
      before = ''
        herdr-sessions demo on >/dev/null 2>&1 || echo "  (herdr demo mode unavailable -- skipping)" >&2
      '';
      after = ''
        herdr-sessions demo off >/dev/null 2>&1 || true
      '';
    };
  };

  # Run unconditionally by the recorder's trap, so a take killed between
  # `before` and `after` still leaves nothing behind. Every name is demo-*;
  # nothing here can touch something the owner made.
  sweep = ''
    podman rm -f demo-web >/dev/null 2>&1 || true
    distrobox rm --force demo-box >/dev/null 2>&1 || true
    nixarchy vm rm demo-vm >/dev/null 2>&1 || true
    herdr-sessions demo off >/dev/null 2>&1 || true
    rm -rf ~/demo-project
  '';
}
