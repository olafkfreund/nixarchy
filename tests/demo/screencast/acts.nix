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

    # devenv's project is made in PREP, not here. razer has no devenv projects
    # at all, so the panel would open on an empty list -- and scaffolding one
    # inside its own 2.4s beat means recording a spinner. Prepared ahead, the
    # panel has something real to show the moment it opens.

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

    # herdr has no demo mode here. The binary is `herdr`, not
    # `herdr-sessions`, and `herdr session` offers only list/attach/stop --
    # tests/demo/default.nix's `demo on` is a verb this build does not have.
    #
    # So the panel shows the machine's real sessions, on the owner's decision
    # (2026-09-23): they are machine names rather than anything private. That
    # is a judgement about THIS machine, and anyone reusing this harness should
    # look at `herdr session list` before recording rather than assume it.
  };

  # Run by prep, so the take starts from something real rather than
  # scaffolding it on camera.
  stage = ''
    mkdir -p ~/demo-project
    if [ ! -f ~/demo-project/devenv.nix ]; then
      (cd ~/demo-project && nixarchy dev init python >/dev/null 2>&1) ||
        echo "  (could not scaffold ~/demo-project -- the devenv panel may be empty)" >&2
    fi
  '';

  # Run unconditionally by the recorder's trap, so a take killed between a
  # beat's `before` and `after` still leaves nothing behind. Every name is
  # demo-*; nothing here can touch something the owner made.
  sweep = ''
    rm -rf ~/demo-project
    podman rm -f demo-web >/dev/null 2>&1 || true
    distrobox rm --force demo-box >/dev/null 2>&1 || true
    nixarchy vm rm demo-vm >/dev/null 2>&1 || true
  '';
}
