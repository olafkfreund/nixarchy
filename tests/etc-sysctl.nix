{
  pkgs,
  reference,
  upstream,
}:
# Upstream's sysctl.d, value for value, against the file a machine reads.
# Why: tests/AGENTS.md#etc-sysctl-compares-values-every-other-native-row-is-still-a-name
let
  inherit (pkgs) lib;

  rows = lib.filterAttrs (name: _: lib.hasPrefix "sysctl.d/" name) (import ../data/etc-overlay.nix);

  parse =
    text:
    let
      lines = builtins.filter (l: l != "" && !lib.hasPrefix "#" l) (
        map lib.trim (lib.splitString "\n" text)
      );
      fields = builtins.match "([^=]+)=(.*)";
    in
    {
      malformed = builtins.filter (l: fields l == null) lines;
      # reverseList: listToAttrs keeps the first definition, sysctl the last.
      values = builtins.listToAttrs (
        lib.reverseList (
          map (
            l:
            lib.nameValuePair (lib.trim (builtins.elemAt (fields l) 0)) (
              lib.trim (builtins.elemAt (fields l) 1)
            )
          ) (builtins.filter (l: fields l != null) lines)
        )
      );
    };

  # What the machine reads, so no value coercion is reimplemented here.
  configured = (parse reference.config.environment.etc."sysctl.d/60-nixos.conf".text).values;

  files = lib.mapAttrs (
    name: row:
    let
      path = "${upstream}/etc/${name}";
      exists = builtins.pathExists path;
      parsed = parse (if exists then builtins.readFile path else "");
    in
    {
      inherit name exists;
      inherit (parsed) malformed values;
      inherit (row) class;
      differs = row.differs or { };
    }
  ) rows;

  keyProblems =
    file:
    lib.mapAttrsToList (
      key: want:
      let
        have = configured.${key} or null;
        decision = file.differs.${key} or null;
      in
      if decision == null then
        lib.optional (have != want)
          "${key}: upstream's ${file.name} says ${want}, this configuration says ${
            if have == null then "nothing" else have
          }. Set it in modules/nixos.nix, or record differs.\"${key}\" on that row of data/etc-overlay.nix."
      else if decision.upstream != want then
        [
          "${key}: the decision in data/etc-overlay.nix was about upstream's ${decision.upstream}, and upstream now says ${want}. Decide again."
        ]
      else if have == want then
        [
          "${key}: data/etc-overlay.nix records a difference, but this configuration now matches upstream. Delete the entry."
        ]
      else if (decision.reason or "") == "" then
        [ "${key}: the differs entry in data/etc-overlay.nix has no reason." ]
      else
        [ ]
    ) file.values;

  staleDecisions =
    file:
    map (
      key: "${key}: data/etc-overlay.nix records a difference, and ${file.name} no longer sets it."
    ) (builtins.filter (key: !(file.values ? ${key})) (builtins.attrNames file.differs));

  fileProblems =
    file:
    lib.optional (
      !file.exists
    ) "${file.name}: has a row in data/etc-overlay.nix, and upstream does not ship it."
    ++ map (l: "${file.name}: not a key=value line: ${l}") file.malformed
    ++ lib.flatten (keyProblems file)
    ++ staleDecisions file;

  allKeys = lib.concatMap (file: builtins.attrNames file.values) (builtins.attrValues files);

  # covered rows are excluded: a user's mkDefault on those ties with nixpkgs, not us.
  nativeKeys = lib.concatMap (
    file: lib.optionals (file.class == "native") (builtins.attrNames file.values)
  ) (builtins.attrValues files);

  swept =
    (reference.extendModules {
      modules = [ { boot.kernel.sysctl = lib.genAttrs nativeKeys (_: lib.mkDefault "sentinel"); } ];
    }).config.boot.kernel.sysctl;

  # A tie is a throw, which tryEval catches, so this names the key and doesn't abort.
  lost = builtins.filter (
    key:
    let
      got = builtins.tryEval swept.${key};
    in
    !(got.success && got.value == "sentinel")
  ) nativeKeys;

  # An empty list passes everything, so too few keys is itself a failure.
  floor = 10;

  problems =
    lib.concatMap fileProblems (builtins.attrValues files)
    ++ map (
      key:
      "${key}: a user's own mkDefault does not survive. Its priority in modules/nixos.nix must stay weaker than 1000."
    ) lost
    ++
      lib.optional (builtins.length allKeys < floor)
        "found only ${toString (builtins.length allKeys)} keys, below the floor of ${toString floor}: the path moved, or the parser stopped reading.";
in
pkgs.runCommand "nixarchy-etc-sysctl"
  {
    problems = lib.concatStringsSep "\n" problems;
    passAsFile = [ "problems" ];
    found = builtins.length allKeys;
  }
  ''
    if [ -s "$problemsPath" ]; then
      sed 's/^/etc-sysctl: FAIL /' "$problemsPath" >&2
      exit 1
    fi
    echo "etc-sysctl: all $found keys match upstream or carry a decision"
    touch "$out"
  ''
