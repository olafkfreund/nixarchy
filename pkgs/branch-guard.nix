# One answer to "may this checkout be rebuilt?", shared by nixarchy-apply,
# omarchy-update and autoUpdate so the three cannot disagree (#1037).
# Why: pkgs/AGENTS.md#a-rebuild-built-whatever-branch-the-checkout-was-on
{
  writeShellApplication,
  git,
  coreutils,
}:
writeShellApplication {
  name = "nixarchy-branch-guard";
  runtimeInputs = [
    git
    coreutils
  ];
  text = ''
    ref=''${1:?usage: nixarchy-branch-guard <flake>}
    dir=''${ref%%#*}
    dir=''${dir#path:}

    # Not a local checkout (github:, a missing path): nothing to guard.
    [ -d "$dir" ] || exit 0
    # Read-only. modules/nixos.nix already trusts programs.nixarchy.flake for
    # root; -c covers a NIXARCHY_FLAKE pointed elsewhere, for these calls only.
    g() { git -c safe.directory="$dir" -C "$dir" "$@"; }
    [ "$(g rev-parse --is-inside-work-tree 2>/dev/null || true)" = true ] || exit 0
    [ "''${ALLOW_BRANCH_DEPLOY:-}" = 1 ] && exit 0
    # No remote: nobody else's branch to protect against.
    [ -n "$(g remote)" ] || exit 0

    guessed=
    default=$(g symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
    default=''${default#origin/}
    [ -n "$default" ] || { default=main guessed=1; }

    branch=$(g branch --show-current)
    [ "$branch" = "$default" ] && exit 0
    # Detached exactly at origin/<default> counts, as in nixos_config#2056.
    if [ -z "$branch" ]; then
      tip=$(g rev-parse -q --verify "refs/remotes/origin/$default" || true)
      [ -n "$tip" ] && [ "$(g rev-parse HEAD)" = "$tip" ] && exit 0
    fi

    rev=$(g rev-parse --short HEAD 2>/dev/null || echo "no commits")
    {
      printf "nixarchy: refusing to rebuild from '%s' (%s), not %s.\n" "''${branch:-detached HEAD}" "$rev" "$default"
      printf '  %s is the flake this machine builds; building a branch deploys it.\n' "$dir"
      printf '  switch back:      git -C %s switch %s\n' "$dir" "$default"
      printf '  build it anyway:  ALLOW_BRANCH_DEPLOY=1 <the command you ran>\n'
      if [ -n "$guessed" ]; then
        printf '  (%s is a guess: origin/HEAD is unset. If the default branch is not\n' "$default"
        printf '   %s, run: git -C %s remote set-head origin -a)\n' "$default" "$dir"
      fi
    } >&2
    exit 1
  '';
}
