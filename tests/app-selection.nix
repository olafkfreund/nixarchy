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
  appRemove = testLib.vmPackage "nixarchy-app-remove";
  catalogueDiff = testLib.vmPackage "nixarchy-catalogue-diff";
  pkgAdd = testLib.vmPackage "nixarchy-pkg-add";
  pkgRemove = testLib.vmPackage "nixarchy-pkg-remove";
  apply = testLib.vmPackage "nixarchy-apply";
  defaultInstall = testLib.vmPackage "nixarchy-default-install";
  search = testLib.vmPackage "nixarchy-search";
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-app-selection"
  {
    nativeBuildInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      jq
      nix
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
    remove=${appRemove}/bin/nixarchy-app-remove
    diff=${catalogueDiff}/bin/nixarchy-catalogue-diff
    pkgadd=${pkgAdd}/bin/nixarchy-pkg-add
    pkgremove=${pkgRemove}/bin/nixarchy-pkg-remove
    apply=${apply}/bin/nixarchy-apply
    definstall=${defaultInstall}/bin/nixarchy-default-install

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
    # --add writes rows as programs.nixarchy.apps.<id>; enable and disable
    # must both recognise that form (#1276 review).
    "$enable" brave >/dev/null 2>&1 || bad 'enable failed on a full-path row'
    grep -qE '^[[:space:]]*programs\.nixarchy\.apps\.brave\.enable = true' "$file" ||
      bad "enable did not turn on a full-path row: $(grep brave "$file")"
    "$disable" brave >/dev/null 2>&1 || bad 'disable failed on a full-path row'
    grep -qE '^[[:space:]]*#[[:space:]]*programs\.nixarchy\.apps\.brave\.enable' "$file" ||
      bad "disable left a full-path row on: $(grep brave "$file")"
    printf '%s\n' '{ ... }: {' > "$file"
    rc=0; "$diff" --add > refuse.out 2>&1 || rc=$?
    test "$rc" -ne 0 || bad 'catalogue-diff reported success after refusing a file'
    grep -q 'no closing brace' refuse.out || bad "catalogue-diff refused without saying why: $(cat refuse.out)"

    # Every name redirected to a curated app is an unsuccessful pkg-add.
    printf '%s\n' '{ ... }: {' '}' > "$file"
    rc=0; "$pkgadd" brave > pkgadd.out 2>&1 || rc=$?
    test "$rc" -ne 0 || bad 'pkg-add reported success for a redirected name'
    grep -q 'curated' pkgadd.out || bad "pkg-add failed for some other reason: $(cat pkgadd.out)"

    hypetpl=$PWD/hype-templates
    mkdir -p "$hypetpl"
    printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' '    # hype.enable = false;  #@ hype  # on by default' '    # brave.enable = true;  #@ brave' '  };' '}' > "$hypetpl/apps-template.nix"
    hypeoff='^[[:space:]]*(programs\.nixarchy\.apps\.)?hype\.enable[[:space:]]*=[[:space:]]*false'
    # A full-path row sits outside the block, where catalogue-diff --add writes it.
    start() { printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' "    $1" '  };' "  $2" '}' > "$file"; }
    offcase() {
      NIXARCHY_TEMPLATES=$hypetpl "$disable" hype >/dev/null || bad "disable hype failed from: $1"
      grep -qE "$hypeoff" "$file" || bad "disable hype left no live false from: $1"
      nix-instantiate --parse "$file" >/dev/null || bad "disable hype broke the file from: $1"
    }
    start 'hype.enable = true;  #@ hype' ""; offcase 'live true'
    start '# hype.enable = true;  #@ hype' ""; offcase 'old commented row'
    start '# hype.enable = false;  #@ hype  # on by default' ""; offcase 'new commented row'
    start "" 'programs.nixarchy.apps.hype.enable = true;  #@ hype'; offcase 'full-path row'
    start "" ""; offcase 'absent row'

    fzf() { cat > "$PWD/offered"; }
    export -f fzf
    start '# hype.enable = false;  #@ hype  # on by default' ""
    : > offered; PATH=${appDisable}/bin:$PATH "$remove" >/dev/null || bad 'remove failed on commented hype'
    grep -qP '^app\thype$' offered || bad 'remove did not offer default-on hype'
    NIXARCHY_TEMPLATES=$hypetpl "$disable" hype >/dev/null || bad 'disable hype before remove failed'
    : > offered; PATH=${appDisable}/bin:$PATH "$remove" >/dev/null || bad 'remove failed on disabled hype'
    if grep -qP '^app\thype$' offered; then bad 'remove offered disabled hype'; fi

    printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' '    hype.enable = false;  #@ hype' '    omacut.enable = true;  #@ omacut' '    # signed.enable = true;  #@ signed' '  };' '  programs.nixarchy.apps.brave.enable = true;  #@ brave' '}' > "$file"
    NIXARCHY_TEMPLATES=$hypetpl "$disable" omacut > disable.out || bad 'disable omacut failed'
    grep -qF '(1 still enabled)' disable.out || bad 'disable count included hype or missed full-path brave'
    "$enable" signed > enable.out || bad 'enable signed failed'
    grep -qF '(2 queued)' enable.out || bad 'enable count included hype or missed full-path brave'

    sed -n '/^mark_live() {/,/^}/p' ${search}/bin/nixarchy-search > mark-live-function
    grep -q 'mark_live()' mark-live-function || { echo 'mark_live function extraction failed' >&2; exit 1; }
    source mark-live-function
    start 'hype.enable = false;  #@ hype' ""
    mark_live "$file" app > live.out
    if grep -q hype live.out; then bad 'mark_live selected a false row'; fi
    start 'hype.enable = true;  #@ hype' ""
    mark_live "$file" app > live.out
    grep -qP '^app\thype$' live.out || bad 'mark_live missed a true row'

    export NIX_STATE_DIR=$PWD/nix-state NIX_LOG_DIR=$PWD/nix-state
    mkdir -p nix-state
    start "" ""
    sed -i -e '1s/{ \.\.\. }/{ pkgs, ... }/' -e '/^}$/i\  # keep me' "$file"
    "$pkgadd" kdePackages.kdenlive >/dev/null || bad 'pkg-add kdenlive failed'
    grep -qF 'kdePackages.kdenlive  #@pkg kdePackages.kdenlive' "$file" || bad 'pkg-add did not write kdenlive'
    nix-instantiate --parse "$file" >/dev/null || bad 'pkg-add wrote invalid Nix'
    "$pkgremove" kdePackages.kdenlive >/dev/null || bad 'pkg-remove kdenlive failed'
    if grep -qF '#@pkg kdePackages.kdenlive' "$file"; then bad 'pkg-remove left kdenlive'; fi
    grep -qF '# keep me' "$file" || bad 'pkg-remove changed an unrelated line'

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

    # A --yes run (the panel's detached unit) must not wait on another apply,
    # which may be sitting at a prompt with nobody there.
    flock "$XDG_STATE_HOME/nixarchy/applied/lock" sleep 30 &
    holder=$!
    sleep 1
    rc=0; NIXARCHY_FLAKE=$PWD/flake timeout 10 "$apply" --yes --no-preview > lock.out 2>&1 || rc=$?
    kill "$holder" 2>/dev/null || true
    test "$rc" -eq 1 && grep -q 'another apply is running' lock.out ||
      bad "a --yes apply waited on (or ignored) a held lock: rc=$rc $(cat lock.out)"

    # ---- nixarchy-default-install (#1623) ---------------------------------
    defbin=$PWD/defbin
    mkdir -p "$defbin"
    ln -s "$enable" "$defbin/nixarchy-app-enable"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo apply >> "$APPLY_CALLS"' > "$defbin/nixarchy-apply"
    chmod +x "$defbin/nixarchy-apply"
    export APPLY_CALLS=$PWD/apply.calls

    def_row() {
      case "$1:$2" in
        browser:chrome) echo chrome ;;
        browser:brave) echo brave ;;
        browser:edge) echo edge ;;
        browser:firefox) echo firefox ;;
        browser:zen) echo zen ;;
        editor:code) echo vscode ;;
        editor:cursor) echo cursor ;;
        editor:zed) echo zed ;;
        editor:helix) echo helix ;;
        editor:vim) echo vim ;;
        editor:emacs) echo emacs ;;
        *) echo "" ;;
      esac
    }
    def_refused() {
      case "$1:$2" in
        browser:brave-origin | browser:chromium | editor:sublime_text | editor:nvim) return 0 ;;
        *) return 1 ;;
      esac
    }

    printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' \
      '    # chrome.enable = true;  #@ chrome' \
      '    # brave.enable = true;  #@ brave' \
      '    # edge.enable = true;  #@ edge' \
      '    # firefox.enable = true;  #@ firefox' \
      '    # zen.enable = true;  #@ zen' \
      '    # vscode.enable = true;  #@ vscode' \
      '    # cursor.enable = true;  #@ cursor' \
      '    # zed.enable = true;  #@ zed' \
      '    # helix.enable = true;  #@ helix' \
      '    # vim.enable = true;  #@ vim' \
      '    # emacs.enable = true;  #@ emacs' \
      '  };' '}' > "$templates/apps-template.nix"

    for kind in browser editor; do
      setter=${shipped}/share/omarchy/bin/omarchy-default-$kind
      args=$(sed -n 's/^# omarchy:args=\[\(.*\)\]$/\1/p' "$setter" | tr '|' ' ')
      test -n "$args" || { echo "omarchy-default-$kind has no omarchy:args line" >&2; exit 1; }
      for sel in $args; do
        if def_refused "$kind" "$sel"; then
          continue
        fi
        row=$(def_row "$kind" "$sel")
        if [ -z "$row" ]; then
          bad "omarchy-default-$kind omarchy:args names '$sel', which is in neither the map nor the refused list"
          continue
        fi
        cp "$templates/apps-template.nix" "$file"
        rm -rf "$XDG_STATE_HOME/nixarchy"
        : > "$APPLY_CALLS"
        cmd="cmd-$sel"
        rc=0; PATH=$defbin:$PATH "$definstall" "$kind" "$sel" "$cmd" > def.out 2>&1 || rc=$?
        test "$rc" -eq 0 || bad "default-install $kind $sel exited $rc: $(cat def.out)"
        grep -qE "^[[:space:]]*$row\.enable = true;  #@ $row" "$file" ||
          bad "default-install $kind $sel did not enable $row"
        pending=$XDG_STATE_HOME/nixarchy/pending-default-$kind
        test -f "$pending" && test "$(cat "$pending")" = "$(printf '%s\n%s' "$sel" "$cmd")" ||
          bad "default-install $kind $sel did not write pending-default-$kind"
        test "$(wc -l < "$APPLY_CALLS")" -eq 1 ||
          bad "default-install $kind $sel did not exec nixarchy-apply once"
      done
    done

    refuse_case() {
      local script=$1 kind=$2 sel=$3 reason=$4
      cp "$templates/apps-template.nix" "$file"
      rm -rf "$XDG_STATE_HOME/nixarchy"
      : > "$APPLY_CALLS"
      local before rc=0
      before=$(sha256sum < "$file")
      PATH=$defbin:$PATH "$script" "$kind" "$sel" "cmd-$sel" > refuse.out 2>&1 || rc=$?
      test "$rc" -eq 1 || bad "default-install $kind $sel exited $rc (want 1)"
      grep -qF "$reason" refuse.out || bad "default-install $kind $sel did not print '$reason': $(cat refuse.out)"
      test "$(sha256sum < "$file")" = "$before" || bad "default-install $kind $sel changed apps.nix on refusal"
      test ! -e "$XDG_STATE_HOME/nixarchy/pending-default-$kind" || bad "default-install $kind $sel wrote pending file on refusal"
      test ! -s "$APPLY_CALLS" || bad "default-install $kind $sel called nixarchy-apply on refusal"
    }

    refuse_case "$definstall" browser brave-origin "AUR-only"
    refuse_case "$definstall" editor sublime_text "sublimetext4 broken"
    refuse_case "$definstall" browser chromium "already ships in the session"
    refuse_case "$definstall" editor nvim "already ships in the session"

    sed 's/allowunfree=true/allowunfree=false/' "$definstall" > "$PWD/definstall-nofree"
    chmod +x "$PWD/definstall-nofree"
    refuse_case "$PWD/definstall-nofree" browser chrome "needs programs.nixarchy.allowUnfree = true"
    refuse_case "$PWD/definstall-nofree" editor code "needs programs.nixarchy.allowUnfree = true"

    # --settle: command present and setter succeeds -> file gone (the setter removes it).
    settlebin=$PWD/settlebin
    mkdir -p "$settlebin"
    for kind in browser editor; do
      printf '%s\n' '#!${pkgs.bash}/bin/bash' \
        'echo "'"$kind"' $*" >> "$SETTLE_CALLS"' \
        'if [ "''${SETTLE_FAIL:-0}" = 1 ]; then exit 1; fi' \
        'rm -f "$XDG_STATE_HOME/nixarchy/pending-default-'"$kind"'"' \
        > "$settlebin/omarchy-default-$kind"
      chmod +x "$settlebin/omarchy-default-$kind"
    done
    export SETTLE_CALLS=$PWD/settle.calls

    mkdir -p "$XDG_STATE_HOME/nixarchy"
    printf '%s\n' firefox firefox > "$XDG_STATE_HOME/nixarchy/pending-default-browser"
    printf '%s\n' helix helix > "$XDG_STATE_HOME/nixarchy/pending-default-editor"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$settlebin/firefox"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$settlebin/hx"
    chmod +x "$settlebin/firefox" "$settlebin/hx"
    : > "$SETTLE_CALLS"
    rc=0; PATH=$settlebin:$PATH "$definstall" --settle > settle.out 2>&1 || rc=$?
    test "$rc" -eq 0 &&
      test ! -e "$XDG_STATE_HOME/nixarchy/pending-default-browser" &&
      test ! -e "$XDG_STATE_HOME/nixarchy/pending-default-editor" &&
      grep -qFx 'browser firefox' "$SETTLE_CALLS" &&
      grep -qFx 'editor helix' "$SETTLE_CALLS" ||
      bad "--settle with commands present did not settle both defaults: rc=$rc $(cat settle.out) calls=$(cat "$SETTLE_CALLS")"

    # Setter exits 1 -> file stays, says so, rc 1.
    printf '%s\n' firefox firefox > "$XDG_STATE_HOME/nixarchy/pending-default-browser"
    : > "$SETTLE_CALLS"
    rc=0; SETTLE_FAIL=1 PATH=$settlebin:$PATH "$definstall" --settle > settle.out 2>&1 || rc=$?
    test "$rc" -eq 1 &&
      test -f "$XDG_STATE_HOME/nixarchy/pending-default-browser" &&
      grep -qF 'remains pending' settle.out ||
      bad "--settle when setter fails did not keep file and exit 1: rc=$rc $(cat settle.out)"

    # Command missing -> setter not called, file gone, rc 0.
    rm -f "$settlebin/firefox" "$settlebin/hx"
    printf '%s\n' firefox firefox > "$XDG_STATE_HOME/nixarchy/pending-default-browser"
    printf '%s\n' helix helix > "$XDG_STATE_HOME/nixarchy/pending-default-editor"
    : > "$SETTLE_CALLS"
    rc=0; PATH=$settlebin:$PATH "$definstall" --settle > settle.out 2>&1 || rc=$?
    test "$rc" -eq 0 &&
      test ! -e "$XDG_STATE_HOME/nixarchy/pending-default-browser" &&
      test ! -e "$XDG_STATE_HOME/nixarchy/pending-default-editor" &&
      test ! -s "$SETTLE_CALLS" &&
      grep -qF 'did not provide firefox' settle.out &&
      grep -qF 'did not provide helix' settle.out ||
      bad "--settle with missing commands called setter or kept file: rc=$rc $(cat settle.out) calls=$(cat "$SETTLE_CALLS")"

    # No file -> silent 0.
    : > "$SETTLE_CALLS"
    rc=0; PATH=$settlebin:$PATH "$definstall" --settle > settle.out 2>&1 || rc=$?
    test "$rc" -eq 0 && test ! -s settle.out && test ! -s "$SETTLE_CALLS" ||
      bad "--settle with no pending file was not silent 0: rc=$rc $(cat settle.out)"

    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1276)" >&2; exit 1; }
    echo "app-selection: every case passed"
    mkdir -p "$out"
  ''
