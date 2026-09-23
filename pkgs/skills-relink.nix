# The agent-skills relink, as a command rather than a block inside home.nix's
# activation (#888).
#
# It was inline, and nothing could run it: an activation script is reachable
# only by activating, so the one thing that decides whether every agent on the
# machine can see its skills had no check at all. AGENTS.md §2 asks for a probe
# at the highest layer that can see the thing; a package is that layer, and
# checks.skills-relink drives this against a stubbed HOME.
#
# Why: modules/AGENTS.md#agent-skills-relinked-on-every-activation
{
  writeShellApplication,
  coreutils,
  findutils,
}:
writeShellApplication {
  name = "nixarchy-skills-relink";
  runtimeInputs = [
    coreutils
    findutils
  ];
  text = ''
    home=''${1:?usage: nixarchy-skills-relink <home> --own <dir> [--guarded <dir>]}
    shift
    own="" guarded=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --own) own=''${2:?--own needs a directory}; shift 2 ;;
        --guarded) guarded=''${2:?--guarded needs a directory}; shift 2 ;;
        *) echo "nixarchy-skills-relink: unknown argument $1" >&2; exit 2 ;;
      esac
    done
    [ -n "$own" ] || { echo "nixarchy-skills-relink: --own is required" >&2; exit 2; }

    # Cleaned in FOUR directories, linked in three. .codex is cleaned because
    # earlier generations planted links there; dropping it from the clean-up
    # too would strand them for good. It is not linked because Codex reads
    # ~/.agents/skills as well and does not merge same-named skills, so both
    # listed every skill twice (#897).
    clean_dirs=".agents/skills .claude/skills .codex/skills .pi/agent/skills"
    link_dirs=".agents/skills .claude/skills .pi/agent/skills"

    # Only links into a skills tree in the store are removed -- both ours and
    # the input's. A skill somebody wrote by hand is a real directory and is
    # never touched.
    for agentdir in $clean_dirs; do
      dest="$home/$agentdir"
      [ -d "$dest" ] || continue
      for link in "$dest"/*; do
        [ -L "$link" ] || continue
        case "$(readlink "$link")" in
          /nix/store/*/agents/skills/* | /nix/store/*/share/nix-skills/*) rm -f "$link" ;;
        esac
      done
    done

    for agentdir in $link_dirs; do
      dest="$home/$agentdir"
      mkdir -p "$dest"

      # Ours win, as they always have: ln -sfn replaces whatever is there.
      find "$own" -mindepth 1 -maxdepth 1 -type d | while read -r skill; do
        ln -sfn "$skill" "$dest/$(basename "$skill")"
      done

      # The input's are guarded. A name already taken -- by one of ours, or by
      # a skill the user wrote, or by their own programs.nix-skills -- is
      # reported and left alone. Linking over it is how two sources of skills
      # silently become one.
      [ -n "$guarded" ] || continue
      find "$guarded" -mindepth 1 -maxdepth 1 -type d | while read -r skill; do
        name=$(basename "$skill")
        if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
          echo "nixarchy: ~/$agentdir/$name is not ours; leaving it"
        else
          ln -sfn "$skill" "$dest/$name"
        fi
      done
    done
  '';
}
