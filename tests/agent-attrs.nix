{ pkgs }:
# Every attr_for() arm in omarchy-default-agent names a nixpkgs attribute that
# exists and installs the command its id names (#1452).
# Failures are collected and reported by the build, never thrown: an eval error
# would abort every check built beside this one (CLAUDE.md §13).
let
  inherit (pkgs) lib;
  script = builtins.readFile ../pkgs/omarchy/nix-bin/omarchy-default-agent;
  # Anchored to a line start: elsewhere_attr_for() also ends in "attr_for() {".
  parts = lib.splitString "\nattr_for() {\n" script;
  body =
    if lib.length parts < 2 then
      ""
    else
      builtins.head (lib.splitString "\n}\n" (builtins.elemAt parts 1));
  arms = lib.filter (m: m != null) (
    map (builtins.match " +([a-z0-9-]+)\\) +echo ([a-z0-9-]+) ;;") (lib.splitString "\n" body)
  );
  problem =
    arm:
    let
      id = builtins.elemAt arm 0;
      attr = builtins.elemAt arm 1;
      main = builtins.tryEval (pkgs.${attr}.meta.mainProgram or null);
    in
    if !(pkgs ? ${attr}) then
      "${id}: no pkgs.${attr}"
    else if !main.success || main.value != id then
      "${id}: pkgs.${attr} installs ${
        if main.success then toString main.value else "<throws>"
      }, not ${id}"
    else
      null;
  # A parse that matched almost nothing would pass having checked nothing.
  problems =
    lib.optional (
      lib.length arms < 5
    ) "attr_for: parsed ${toString (lib.length arms)} arms; the parse must have moved"
    ++ lib.filter (p: p != null) (map problem arms);
in
pkgs.runCommand "nixarchy-agent-attrs" { problems = lib.concatStringsSep "\n" problems; } ''
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems" >&2
    exit 1
  fi
  echo "${toString (lib.length arms)} attr_for arms resolve to the command they name" > $out
''
