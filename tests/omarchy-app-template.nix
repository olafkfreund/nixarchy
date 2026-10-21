# The omarchy-app skill's templates must build as written (#1406). The skill
# tells an agent to `nix run` a project made from templates.md; nothing else
# ever compiles that Nix, qmake and C++, so a typo in the patch would ship.
#
# package.nix is read twice. At evaluation the patch file is the only copy
# available without importing from a derivation, so its added lines give the
# Nix text that is built (builtins.toFile, then callPackage). At build time the
# SHIPPED templates.md is extracted into a project, and the two copies are
# compared byte for byte. The patch cannot drift from what ships.
#
# The package is built from the extracted project, so it exercises the qmake
# file, the C++ and the resource file as well, and the assertions look for what
# the skill promises the launcher will find.
{
  pkgs,
  omarchy,
  patch,
}:
let
  name = "tally";
  inherit (pkgs) lib;

  # Added and context lines of the patch, with the diff column removed.
  lines = builtins.filter (
    l:
    l != ""
    && builtins.elem (builtins.substring 0 1 l) [
      "+"
      " "
    ]
  ) (lib.splitString "\n" (builtins.readFile patch));
  patched = lib.concatStringsSep "\n" (
    map (l: builtins.substring 1 (builtins.stringLength l) l) lines
  );
  afterHeading = builtins.elemAt (lib.splitString "## `package.nix`\n\n```nix\n" patched) 1;
  packageNix = lib.replaceStrings [ "<name>" ] [ name ] (
    builtins.head (lib.splitString "```" afterHeading)
  );

  project =
    pkgs.runCommand "${name}-project"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 -I ${./omarchy-app-template.py} \
          ${omarchy}/share/omarchy/default/agents/skills/omarchy-app/templates.md $out ${name}
      '';

  package = (pkgs.callPackage (builtins.toFile "package.nix" packageNix) { }).overrideAttrs (_: {
    src = project;
  });
in
pkgs.runCommand "nixarchy-omarchy-app-template" { } ''
  # The shipped template and the text built here are the same bytes.
  printf '%s' ${lib.escapeShellArg packageNix} > expected
  cmp expected ${project}/package.nix

  test -x ${package}/bin/${name}
  test -e ${package}/bin/.${name}-wrapped || { echo "bin/${name} is not wrapped: wrapQtAppsHook did not run"; exit 1; }
  grep -q '^Exec=${name} ' ${package}/share/applications/${name}.desktop
  test -s ${package}/share/icons/hicolor/scalable/apps/${name}.svg
  touch $out
''
