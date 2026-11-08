# Omarchy's Neovim configuration, which on Arch arrives as the `omarchy-nvim`
# package from Omarchy's own pacman repository.
#
# That package has no published source. It is not basecamp/omarchy-nvim, it is
# not anywhere else in the basecamp org, and the repository it is served from
# publishes binaries rather than PKGBUILDs -- so unlike every other app here,
# there is nothing to follow.
#
# What there is: Omarchy carried this configuration in-tree, as `config/nvim`,
# until v3.0.2, and dropped it in v4.0.0 when the package was split out. The
# unchanged files here are that tree, byte for byte, at v3.0.2. The package
# remains under the same MIT licence.
#
# Two files were taken from Omarchy's binary package on 2026-11-08 so the
# seeded config and the user-file migration carry the 4.5 transparency update:
# https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.9.21-5-any.pkg.tar.zst
# Archive sha256: b46d41973cacfcf2d8be371351336a3f689e2eb7b9bacdb7ca81939354cbcbc9
# In-archive paths:
# usr/share/omarchy-nvim/config/lua/plugins/lualine-transparent.lua
# usr/share/omarchy-nvim/config/plugin/after/transparency.lua
# This package has no published source, so these files were extracted once;
# there is no fetch at build time.
#
# It is a handful of files, because it is not a Neovim
# distribution: it is LazyVim, plus the handful of things Omarchy changes about
# it. LazyVim itself is not vendored and must not be -- it resolves and locks
# its own plugins at runtime into ~/.local/share/nvim, exactly as it does on
# Arch, and freezing that into the store would replace upstream's arrangement
# rather than carry it.
#
# `lua/plugins/theme.lua` is deliberately NOT here. Upstream ships it, but on a
# running machine it is a symlink to the current theme's neovim.lua -- see
# migrations/1785002349.sh -- so the file is overwritten the moment a theme is
# applied. modules/home.nix makes that link; shipping a stub that is always
# immediately replaced would only mislead whoever reads this next.
{
  lib,
  stdenvNoCC,
  # No default, deliberately.
  #
  # It was `? "4.0.2"`, and by 4.0.3 that was a version literal two releases
  # stale -- the nightly review flagged it as "one of the three copies is
  # stale". It never actually applied, because flake.nix passes the real
  # version, so it was inert AND wrong: the worst combination, since nothing
  # could ever catch it drifting.
  #
  # Required instead. A caller that forgets now fails at evaluation rather than
  # silently producing a package labelled with whatever release happened to be
  # current when this line was written.
  omarchyVersion,
}:
stdenvNoCC.mkDerivation {
  pname = "omarchy-nvim-config";
  version = omarchyVersion;

  src = ./config;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/omarchy-nvim"
    cp -R ./. "$out/share/omarchy-nvim/"
    runHook postInstall
  '';

  meta = {
    description = "Omarchy's LazyVim configuration, from v3.0.2 with two 4.5 transparency files";
    longDescription = ''
      The contents of Omarchy's `omarchy-nvim` package: a LazyVim extras
      selection, plugin overrides, and the 4.5 transparency highlight and
      lualine scripts.
      Seeded into ~/.config/nvim by programs.nixarchy.neovim, and only when
      there is nothing there already.
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
