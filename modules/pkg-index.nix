# The package half of nixarchy-search's index: every derivation `nix search`
# would show, plus the meta that `nix search --json` does not carry --
# homepage, licence, unfree, broken (#493). Verified against Nix 2.34: its
# JSON is pname/version/description and nothing else, so the walk has to be
# ours. It follows the same rule nix search does -- descend into attrsets
# only where recurseForDerivations says to -- and produces the identical row
# set (112,755 attrs on the nixpkgs it was written against, both ways).
#
# Evaluated by the built nixarchy-search script, once per system generation,
# via `nix-instantiate --eval --strict --json --arg nixpkgs <path>`. Never
# per keystroke: the picker inlines everything in the row for that reason.
#
# Every meta access sits under tryEval because a broken meta on one package
# must cost that one row, not the index.
{
  nixpkgs,
}:
let
  pkgs = import nixpkgs {
    # Show everything and say what it is, rather than hide it: the picker
    # marks unfree and broken instead of pretending they do not exist.
    # Nothing here decides licence policy; that stays with the rebuild.
    config = {
      allowUnfree = true;
      allowBroken = true;
      allowInsecurePredicate = _: true;
      allowUnsupportedSystem = true;
    };
  };
  inherit (pkgs) lib;

  try =
    v: d:
    let
      r = builtins.tryEval v;
    in
    if r.success then r.value else d;

  asList = l: if builtins.isList l then l else [ l ];

  licNames =
    m:
    let
      one = l: if builtins.isAttrs l then (l.shortName or l.spdxId or "?") else builtins.toString l;
    in
    if m ? license then builtins.concatStringsSep ", " (map one (asList m.license)) else "";

  # The same question nixarchy-pkg-add asks: any licence that is not
  # `free = true` makes the package unfree.
  isUnfree =
    m:
    m ? license
    && !(builtins.all (l: if builtins.isAttrs l then (l.free or true) else true) (asList m.license));

  row = path: v: {
    attr = path;
    version = try (v.version or "") "";
    description = try (v.meta.description or "") "";
    homepage =
      let
        h = try (v.meta.homepage or "") "";
      in
      if builtins.isList h then (if h == [ ] then "" else builtins.head h) else builtins.toString h;
    license = try (licNames (try v.meta { })) "";
    unfree = try (isUnfree (try v.meta { })) false;
    broken = try (v.meta.broken or false) false;
  };

  go =
    prefix: set:
    builtins.concatLists (
      map (
        n:
        let
          r = builtins.tryEval (builtins.getAttr n set);
          v = r.value;
        in
        if !r.success then
          [ ]
        else if try (lib.isDerivation v) false then
          [ (builtins.tryEval (row (prefix + n) v)) ]
        else if try (builtins.isAttrs v && (v.recurseForDerivations or false)) false then
          go (prefix + n + ".") v
        else
          [ ]
      ) (builtins.attrNames set)
    );
in
map (r: r.value) (builtins.filter (r: r.success) (go "" pkgs))
