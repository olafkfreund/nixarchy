{ inputs, pkgs }:
# The selection writers, against the files they rewrite (#1276): enable,
# disable, catalogue-diff --add, pkg-add, the search picker's Flathub branch,
# and apply's copies into the flake. Each script is the one the vm ships,
# taken by pname, so it cannot drift from what the module builds. Every case
# runs; the failures are counted, so one red run names all of them.
let
  testLib = import ./lib.nix { inherit inputs; };
  appEnable = testLib.vmPackage "nixarchy-app-enable";
  appDisable = testLib.vmPackage "nixarchy-app-disable";
  catalogueDiff = testLib.vmPackage "nixarchy-catalogue-diff";
  pkgAdd = testLib.vmPackage "nixarchy-pkg-add";
  apply = testLib.vmPackage "nixarchy-apply";
  search = testLib.vmPackage "nixarchy-search";
in
pkgs.runCommand "nixarchy-app-selection"
  {
    nativeBuildInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      jq
      util-linux
    ];
  }
  ''
    fails=0
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    export HOME=$PWD/home XDG_CONFIG_HOME=$PWD/home/.config XDG_STATE_HOME=$PWD/home/.local/state
    mkdir -p "$XDG_CONFIG_HOME/nixarchy" "$XDG_STATE_HOME"
    file=$XDG_CONFIG_HOME/nixarchy/apps.nix
    templates=$PWD/templates
    mkdir -p "$templates"
    printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' '    # brave.enable = true;  #@ brave' '  };' '}' > "$templates/apps-template.nix"
    export NIXARCHY_TEMPLATES=$templates
    cp "$templates/apps-template.nix" "$file"
    chmod 640 "$file"
    enable=${appEnable}/bin/nixarchy-app-enable
    disable=${appDisable}/bin/nixarchy-app-disable
    diff=${catalogueDiff}/bin/nixarchy-catalogue-diff
    pkgadd=${pkgAdd}/bin/nixarchy-pkg-add
    apply=${apply}/bin/nixarchy-apply

    # A missing row is inserted, and the file keeps its mode. (Whether that
    # write was a rename is not visible here: enable's own sed -i replaces the
    # inode straight after. The catalogue-diff case below shows the rename.)
    sed -i '/#@ brave/d' "$file"
    inode=$(stat -c %i "$file")
    "$enable" brave >/dev/null || bad 'enable brave failed'
    grep -q 'brave.enable = true' "$file" || bad 'enable did not insert the missing row'
    test "$(stat -c %a "$file")" = 640 && test "$(stat -c %i "$file")" != "$inode" || bad 'enable did not rename a same-directory temp with the original mode'

    # A live false is a selection to turn on, not an already-enabled result.
    sed -i 's/brave.enable = true/brave.enable = false/' "$file"
    "$enable" brave >/dev/null || bad 'enable brave failed'
    grep -q 'brave.enable = true' "$file" || bad 'enable left a false row false'
    before=$(sha256sum < "$file")
    rc=0; "$disable" 'brave.*' >/dev/null 2>&1 || rc=$?
    test "$rc" -eq 2 && test "$(sha256sum < "$file")" = "$before" || bad 'disable accepted an invalid regex id or changed the file'
    "$disable" brave >/dev/null || bad 'disable brave failed'
    grep -q '# brave.enable' "$file" || bad 'disable did not comment the row'

    # catalogue-diff must report a refusal, and a successful --add also renames.
    printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' '  };' '}' > "$file"
    inode=$(stat -c %i "$file")
    "$diff" --add >/dev/null || bad 'catalogue-diff --add failed'
    grep -q '#@ brave' "$file" && test "$(stat -c %i "$file")" != "$inode" &&
      test "$(stat -c %a "$file")" = 640 || bad 'catalogue-diff did not rename with the original mode'
    printf '%s\n' '{ ... }: {' > "$file"
    rc=0; "$diff" --add > refuse.out 2>&1 || rc=$?
    test "$rc" -ne 0 || bad 'catalogue-diff reported success after refusing a file'
    grep -q 'no closing brace' refuse.out || bad "catalogue-diff refused without saying why: $(cat refuse.out)"

    # Every name redirected to a curated app is an unsuccessful pkg-add.
    printf '%s\n' '{ ... }: {' '}' > "$file"
    rc=0; "$pkgadd" brave >/dev/null 2>&1 || rc=$?
    test "$rc" -ne 0 || bad 'pkg-add reported success for a redirected name'

    # Extract the shipped Flathub function. Replace only the terminal read;
    # the query is fixed and fzf/curl stay stubbed, so this needs no network.
    sed -n '/^flathub_search() {/,/^}/p' ${search}/bin/nixarchy-search \
      | sed 's@< /dev/tty@<<<"query"@' > flathub-function
    grep -q 'flathub_search()' flathub-function || { echo 'Flathub function extraction failed' >&2; exit 1; }
    # The runtime's index is tab-separated, including a curated Flathub ID.
    printf 'flatpak\torg.example.App\tExample\t\t\n' > index.tsv
    index=$PWD/index.tsv
    curl() { printf '%s\n' '{"hits":[{"app_id":"org.example.App","name":"Example","summary":"Example"}]}'; }
    fzf() { cat; }
    nixarchy-service-enable() { printf '%s\n' "$1" > enabled-id; }
    source flathub-function
    flathub_search >/dev/null || true
    test "$(cat enabled-id)" = org.example.App || bad 'Flathub exact match did not reach service-enable'

    # Apply must preserve a draft edited in the flake and stop before switch.
    printf '%s\n' '{ ... }: {' '}' > "$file"
    mkdir -p "$XDG_CONFIG_HOME/nixarchy/packages" flake
    printf '%s\n' 'source draft' > "$XDG_CONFIG_HOME/nixarchy/packages/sample.nix"
    nixarchy-branch-guard() { :; }
    nh() {
      flock -n "$XDG_STATE_HOME/nixarchy/applied/lock" true && {
        echo 'apply released its lock before switch' >&2; return 1;
      }
      echo switched > switched
    }
    export -f nixarchy-branch-guard nh
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >/dev/null || bad 'apply failed'
    test -f switched && test -f flake/nixarchy/packages/sample.nix || bad 'apply did not copy the draft and switch'
    inode=$(stat -c %i flake/nixarchy/apps.nix)
    printf '%s\n' '{ ... }: { # changed' '}' > "$file"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >/dev/null || bad 'apply failed'
    test "$(stat -c %i flake/nixarchy/apps.nix)" != "$inode" &&
      test "$(stat -c %a flake/nixarchy/apps.nix)" = "$(stat -c %a "$file")" || bad 'apply did not rename the flake copy with its mode'
    printf '%s\n' 'edited in flake' > flake/nixarchy/packages/sample.nix
    rm switched
    rc=0; NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >/dev/null 2>&1 || rc=$?
    test "$rc" -ne 0 && test ! -f switched && grep -q 'edited in flake' flake/nixarchy/packages/sample.nix || bad 'apply overwrote an edited draft or switched anyway'
    # No record yet (the first apply after the edited-draft check arrived) is
    # not an edit: a draft changed in ~/.config, where drafts live, applies.
    rm -f "$XDG_STATE_HOME"/nixarchy/applied/[0-9a-f]*
    printf '%s\n' 'edited at the source' > "$XDG_CONFIG_HOME/nixarchy/packages/sample.nix"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >/dev/null 2>&1 &&
      grep -q 'edited at the source' flake/nixarchy/packages/sample.nix ||
      bad 'apply refused a draft edited at its source because no record existed yet'

    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1276)" >&2; exit 1; }
    echo "app-selection: every case passed"
    mkdir -p "$out"
  ''
