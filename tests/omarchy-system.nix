{ inputs, pkgs, ... }:
# omarchy-system schedules a power action before it closes any window (#1659),
# and on edge keeps --firmware-setup when it does (#1793). On edge it also
# checks the browser-extensions repair: Chrome's policy is environment.etc's,
# so an override counts as current and the repair never writes /etc (#1793).
# Every command the scripts reach is a stub that records its call, so nothing
# here touches the build sandbox's own system.
let
  inherit (pkgs) lib;
  pkg = inputs.self.nixosConfigurations.reference.config.programs.nixarchy.package;
  isEdge = import ../pkgs/omarchy/is-quattro.nix lib pkg.version;
  tree = "${pkg}/share/omarchy";
in
pkgs.runCommand "nixarchy-omarchy-system"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      jq
    ];
  }
  ''
    set +e # stdenv runs with -e; cases read $? themselves
    fails=0
    pass() { echo "PASS  $1"; }
    fail() { echo "FAIL  $1: $2"; fails=$((fails + 1)); }

    stubs=$TMPDIR/stubs
    calls=$TMPDIR/calls
    mkdir -p "$stubs"
    for n in systemctl omarchy-hyprland-window-close-all omarchy-osd omarchy-shell omarchy-state \
      uwsm omarchy-notification-send omarchy-install-chromium-copy-url omarchy-install-chromium-ytdlp \
      omarchy-theme-set-browser pgrep; do
      printf '#!%s\necho "%s $*" >> "%s"\n' "${pkgs.bash}/bin/bash" "$n" "$calls" > "$stubs/$n"
    done
    # systemctl refuses to schedule when asked to.
    printf '#!%s\necho "systemctl $*" >> "%s"\ncase "$* $STUB_SCHEDULE_FAIL" in *--when=*1) exit 1 ;; esac\nexit 0\n' \
      "${pkgs.bash}/bin/bash" "$calls" > "$stubs/systemctl"
    # logind answers the firmware question; STUB_FW_NO makes it say no.
    printf '#!%s\necho "busctl $*" >> "%s"\nif [ -n "$STUB_FW_NO" ]; then echo '"'"'s "no"'"'"'; else echo '"'"'s "yes"'"'"'; fi\n' \
      "${pkgs.bash}/bin/bash" "$calls" > "$stubs/busctl"
    printf '#!%s\necho "$1"\n' "${pkgs.bash}/bin/bash" > "$stubs/omarchy-i18n"
    chmod +x "$stubs"/*
    export PATH=$stubs:$PATH OMARCHY_PATH=${tree} HOME=$TMPDIR/home
    mkdir -p "$HOME"

    # --inhibited runs exit_session directly, for every action.
    run() { : > "$calls"; ${tree}/bin/omarchy-system "$1" --inhibited >/dev/null 2>&1; }
    line() { grep -n -m1 -e "$1" "$calls" | cut -d: -f1; }
    # before <first> <second>: both were called, the first one earlier.
    before() {
      a=$(line "$1"); b=$(line "$2")
      [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
    }

    for action in reboot shutdown; do
      verb=$([ "$action" = shutdown ] && echo poweroff || echo reboot)
      run "$action"
      if before "systemctl $verb --no-wall --when=+5s" omarchy-hyprland-window-close-all; then
        pass "$action is scheduled before any window closes"
      else
        fail "$action is scheduled before any window closes" "$(paste -sd'|' "$calls")"
      fi
    done

    run logout
    if before omarchy-hyprland-window-close-all "uwsm stop"; then pass "logout closes windows, then stops the session"
    else fail "logout closes windows, then stops the session" "$(paste -sd'|' "$calls")"; fi

    ${lib.optionalString isEdge ''
      STUB_FW_NO=1 run firmware; rc=$?
      if [ "$rc" -ne 0 ] && ! grep -q window-close-all "$calls" && ! grep -q -- '--when=' "$calls"; then
        pass "firmware without firmware support closes and schedules nothing"
      else
        fail "firmware without firmware support closes and schedules nothing" "rc=$rc $(paste -sd'|' "$calls")"
      fi

      STUB_SCHEDULE_FAIL=1 run firmware; rc=$?
      if [ "$rc" -ne 0 ] && ! grep -q window-close-all "$calls"; then
        pass "a refused schedule closes nothing"
      else
        fail "a refused schedule closes nothing" "rc=$rc $(paste -sd'|' "$calls")"
      fi

      run firmware
      if before "systemctl reboot --firmware-setup --no-wall --when=+5s" omarchy-hyprland-window-close-all; then
        pass "firmware keeps --firmware-setup and is scheduled first"
      else
        fail "firmware keeps --firmware-setup and is scheduled first" "$(paste -sd'|' "$calls")"
      fi

      # Browser extensions: a copy whose Chrome policy directory is a temp dir, and
      # whose policy helper only records what it is asked to do.
      policy=$TMPDIR/chrome-policy
      helpers=$TMPDIR/browser-policy.sh
      printf '%s\n' \
        'browser_policy_dir_hardened() { echo "browser_policy_dir_hardened" >> "'"$calls"'"; return 1; }' \
        'browser_policy_parents_hardened() { echo "browser_policy_parents_hardened" >> "'"$calls"'"; return 1; }' \
        'browser_policy_setup_dir() { echo "browser_policy_setup_dir $*" >> "'"$calls"'"; }' > "$helpers"
      sed -e "s|/etc/opt/chrome/policies/managed|$policy|" \
        -e "s|source \"\$OMARCHY_PATH/install/helpers/browser-policy.sh\"|source \"$helpers\"|" \
        ${tree}/bin/omarchy-install-browser-extensions > "$TMPDIR/ext"
      chmod +x "$TMPDIR/ext"
      grep -q "$helpers" "$TMPDIR/ext" || { echo "the policy helper is not sourced where expected" >&2; exit 1; }
      hosts=$HOME/.config/google-chrome/NativeMessagingHosts
      mkdir -p "$hosts"
      cp ${tree}/default/chromium/native-messaging-hosts/*.json "$hosts/"

      mkdir -p "$policy"
      echo '{"overridden": true}' > "$policy/omarchy-extensions.json"
      : > "$calls"
      if "$TMPDIR/ext" --check chrome >/dev/null 2>&1; then pass "an overridden declared policy is current"
      else fail "an overridden declared policy is current" "$(paste -sd'|' "$calls")"; fi

      rm "$policy/omarchy-extensions.json"
      if ! "$TMPDIR/ext" --check chrome >/dev/null 2>&1; then pass "a missing policy is not current"
      else fail "a missing policy is not current" "check said current"; fi

      : > "$calls"
      "$TMPDIR/ext" chrome >/dev/null 2>&1; rc=$?
      if [ "$rc" -eq 1 ] && ! grep -q -e browser_policy_setup_dir -e omarchy-theme-set-browser "$calls" \
        && [ -z "$(ls -A "$policy")" ]; then
        pass "the Chrome repair refuses and writes nothing"
      else
        fail "the Chrome repair refuses and writes nothing" "rc=$rc $(paste -sd'|' "$calls") files=$(ls -A "$policy")"
      fi
    ''}

    [ "$fails" -eq 0 ] || exit 1
    touch "$out"
  ''
