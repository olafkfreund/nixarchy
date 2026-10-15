{ inputs, pkgs }:
# nixarchy-language-select against a services.nix shaped like the template
# (#1289). The script is the vm's own, taken by pname; the registry is a stub
# through its NIXARCHY_LANGUAGE_REGISTRY seam, because the baked one is empty
# on Omarchy v4.0.4. Every case runs and failures are counted.
let
  testLib = import ./lib.nix { inherit inputs; };
  select = testLib.vmPackage "nixarchy-language-select";
in
pkgs.runCommand "nixarchy-language-select"
  {
    nativeBuildInputs = with pkgs; [
      coreutils
      gnugrep
    ];
  }
  ''
    fails=0
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    export XDG_CONFIG_HOME=$PWD/cfg
    mkdir -p "$XDG_CONFIG_HOME/nixarchy"
    file=$XDG_CONFIG_HOME/nixarchy/services.nix
    printf '%s\n' '{"da":{},"fr":{}}' > registry.json
    export NIXARCHY_LANGUAGE_REGISTRY=$PWD/registry.json
    sel=${select}/bin/nixarchy-language-select
    live() { grep -cE '^[[:space:]]*[^#[:space:]].*#@ language([[:space:]]|$)' "$file" || true; }
    fresh() {
      printf '%s\n' '{ ... }:' '{' "$@" '}' > "$file"
      chmod 640 "$file"
    }

    # Insert into a file without the line, keeping the mode.
    fresh '  services.x.enable = true; #@ x'
    "$sel" da >/dev/null || bad 'select da failed'
    grep -qF 'programs.nixarchy.language = "da";' "$file" || bad 'insert did not write the line'
    test "$(live)" = 1 || bad 'insert left other than one live line'
    test "$(stat -c %a "$file")" = 640 || bad 'insert changed the file mode'
    grep -qF '#@ x' "$file" || bad 'insert lost another row'

    # Replace: exactly one live line, with the new code.
    "$sel" fr >/dev/null || bad 'select fr failed'
    test "$(live)" = 1 || bad 'replace left other than one live line'
    grep -qF 'language = "fr";' "$file" && ! grep -qF 'language = "da";' "$file" || bad 'replace did not swap da for fr'
    test "$(stat -c %a "$file")" = 640 || bad 'replace changed the file mode'

    # A live line somewhere else, twice, ends up as one.
    fresh '  services.x.enable = true; #@ x' '  programs.nixarchy.language = "da";  #@ language' '  programs.nixarchy.language = "fr";  #@ language'
    "$sel" da >/dev/null || bad 'select da over two lines failed'
    test "$(live)" = 1 || bad 'two live lines did not collapse to one'

    # null clears the live line and nothing else.
    "$sel" null >/dev/null || bad 'select null failed'
    test "$(live)" = 0 || bad 'null left a live line'
    grep -qF '#@ x' "$file" || bad 'null removed another row'

    # A commented line is not live: it stays, and a live one is added.
    fresh '  # programs.nixarchy.language = "fr";  #@ language'
    "$sel" da >/dev/null || bad 'select da beside a comment failed'
    test "$(live)" = 1 || bad 'a commented line was counted as live'
    grep -qF '# programs.nixarchy.language = "fr";' "$file" || bad 'the commented line was altered'
    "$sel" null >/dev/null
    grep -qF '# programs.nixarchy.language = "fr";' "$file" || bad 'null removed the commented line'

    # Refusals leave the file byte-identical and exit 2.
    fresh '  programs.nixarchy.language = "da";  #@ language'
    before=$(sha256sum < "$file")
    for arg in xx 'a/b' 'd a'; do
      rc=0; "$sel" "$arg" >/dev/null 2>&1 || rc=$?
      test "$rc" -eq 2 || bad "'$arg' exited $rc, not 2"
      test "$(sha256sum < "$file")" = "$before" || bad "'$arg' changed the file"
    done

    test "$fails" -eq 0
    echo "language-select: every case passed"
    touch $out
  ''
