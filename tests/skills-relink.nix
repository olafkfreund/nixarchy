{ pkgs }:
# #888: the agent-skills relink, driven as a command against a fake home.
#
# It used to be a loop inside home.nix's activation, where no check could reach
# it -- so whether every agent on the machine sees its skills was decided by
# code nothing ran. This is that code, as a package, with a HOME it is safe to
# ruin.
#
# The asymmetry these cases pin down: FOUR directories are cleaned, THREE are
# linked. .codex is cleaned because earlier generations planted links there and
# dropping it from the clean-up would strand them; it is not linked because
# Codex reads ~/.agents/skills too and does not merge same-named skills, so
# both listed every skill twice (#897).
let
  relink = pkgs.callPackage ../pkgs/skills-relink.nix { };

  # Real store paths, because the clean-up pattern is anchored at
  # /nix/store. A fixture under $PWD cannot match `/nix/store/*/...`, so one
  # built there would leave case 5 permanently red -- and "fixing" that by
  # relaxing the pattern would weaken the real guard to match any path with
  # those segments in it. Build the shape instead.
  skillTree =
    name: dirs:
    pkgs.runCommand name { } (
      "mkdir -p " + builtins.concatStringsSep " " (map (d: "\"$out/${d}\"") dirs)
    );
  ownTree = skillTree "own-skills" [
    "agents/skills/nixos"
    "agents/skills/devenv"
  ];
  inputTree = skillTree "input-skills" [
    "share/nix-skills/nix-language"
    "share/nix-skills/devenv-project"
    # Same name as one of ours, deliberately: the sharpest collision, and the
    # only one `ln -sfn` would actually silently win, since it replaces a
    # SYMLINK where it merely descends into a real directory.
    "share/nix-skills/nixos"
  ];
in
pkgs.runCommand "nixarchy-skills-relink" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  export HOME=$PWD/home
  mkdir -p "$HOME"
  fails=0
  ok() { echo "  ok      $1"; }
  bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }

  own=${ownTree}/agents/skills
  guarded=${inputTree}/share/nix-skills

  run() { ${relink}/bin/nixarchy-skills-relink "$HOME" "$@"; }

  # ---- 1. own skills reach the three linked directories ------------------
  got=$(run --own "$own" 2>&1)
  linked=0
  for d in .agents/skills .claude/skills .pi/agent/skills; do
    [ -L "$HOME/$d/nixos" ] && [ -L "$HOME/$d/devenv" ] && linked=$((linked + 1))
  done
  if [ "$linked" -eq 3 ]; then
    ok "our own skills are linked in all three agent directories"
  else
    bad "own skills reached $linked of 3 directories: $got"
  fi

  # ---- 2. .codex is cleaned, never linked (#897) -------------------------
  if [ ! -e "$HOME/.codex/skills/nixos" ]; then
    ok ".codex is not linked, so Codex does not list every skill twice"
  else
    bad ".codex/skills/nixos was linked; #897 says Codex reads .agents/skills"
  fi

  # ---- 3. the input's skills are linked where nothing is ------------------
  got=$(run --own "$own" --guarded "$guarded" 2>&1)
  if [ -L "$HOME/.agents/skills/nix-language" ]; then
    ok "a guarded skill is linked where the name is free"
  else
    bad "nix-language was not linked: $got"
  fi

  # ---- 4. a name already taken is reported and left alone -----------------
  # A real directory, as a skill somebody wrote by hand would be. Linking over
  # it is how two sources of skills silently become one.
  rm -f "$HOME/.agents/skills/devenv-project"
  mkdir -p "$HOME/.agents/skills/devenv-project"
  echo mine > "$HOME/.agents/skills/devenv-project/SKILL.md"
  got=$(run --own "$own" --guarded "$guarded" 2>&1)
  if [ -d "$HOME/.agents/skills/devenv-project" ] &&
    [ ! -L "$HOME/.agents/skills/devenv-project" ] &&
    [ "$(cat "$HOME/.agents/skills/devenv-project/SKILL.md")" = mine ]; then
    ok "a name already taken is left alone, not replaced"
  else
    bad "devenv-project was clobbered: $got"
  fi
  <<<"$got" grep -q "is not ours; leaving it" &&
    ok "and it says so, rather than silently skipping" ||
    bad "nothing was printed about the skill it left alone: $got"

  # ---- 4b. ours win a same-name collision --------------------------------
  # The case the guard actually exists for. A real directory survives `ln -sfn`
  # by accident (it is descended into, not replaced), so only a SYMLINK
  # collision measures the guard -- and one of ours is exactly that.
  rm -rf "$HOME/.agents/skills/devenv-project"
  run --own "$own" --guarded "$guarded" >/dev/null 2>&1
  if [ "$(readlink "$HOME/.agents/skills/nixos")" = "$own/nixos" ]; then
    ok "a guarded skill does not take a name one of ours already holds"
  else
    bad "nixos now points at $(readlink "$HOME/.agents/skills/nixos"), not ours"
  fi

  # ---- 5. turning the option off removes the input's links ---------------
  # The clean-up pattern for share/nix-skills is the only thing that makes an
  # off switch actually turn it off.
  rm -rf "$HOME/.agents/skills/devenv-project"
  run --own "$own" --guarded "$guarded" >/dev/null 2>&1
  run --own "$own" >/dev/null 2>&1
  if [ ! -e "$HOME/.agents/skills/nix-language" ] && [ -L "$HOME/.agents/skills/nixos" ]; then
    ok "without --guarded the input's links go and ours stay"
  else
    bad "off left nix-language behind, or took nixos with it"
  fi

  # ---- 6. a link the user made elsewhere is untouched ---------------------
  mkdir -p "$PWD/elsewhere/mine"
  ln -sfn "$PWD/elsewhere/mine" "$HOME/.agents/skills/mine"
  run --own "$own" >/dev/null 2>&1
  if [ -L "$HOME/.agents/skills/mine" ]; then
    ok "a link pointing outside the store is left alone"
  else
    bad "the user's own link was removed"
  fi

  [ "$fails" -eq 0 ] || exit 1
  touch $out
''
