# The CID script, the autoconfirm loop and the guest wiring of the
# `hyprland-ai-mirror` template, plus its `hyprland` half (Lua config,
# start-hyprland, Chromium's Wayland flag).
# Boots nothing: no CI check boots a guest (#929 wedged twice), so the MCP round
# trip over vsock is proven live, not here. See tests/AGENTS.md. #1504, #1508,
# #1509, #1510.
{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  tpl = ../modules/microvm/templates;
  system = pkgs.stdenv.hostPlatform.system;

  # Built from the template's own file, so ShellCheck runs on it too; used only
  # for the refusal cases, the template's own extraArgsScript covers the rest.
  vsockCid = pkgs.writeShellApplication {
    name = "nixarchy-vsock-cid";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile (tpl + "/vsock-cid.sh");
  };

  # ai-mirror stubbed: `control confirm <id>` appends the id to $CONFIRM_LOG,
  # anything else does nothing.
  stub = pkgs.writeShellScriptBin "ai-mirror" ''
    case "$1" in
      control) [ "$2" = confirm ] && printf '%s\n' "$3" >> "$CONFIRM_LOG" ;;
    esac
  '';

  noCtx = builtins.unsafeDiscardStringContext;

  # Evaluated guest facts, as values: a .drv path in the environment would make
  # nix build the guest (tests/AGENTS.md).
  cfg =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        inputs.microvm.nixosModules.microvm
        ../modules/microvm/guest.nix
        (tpl + "/hyprland-ai-mirror.nix")
      ];
    }).config;
  units = cfg.systemd.user.services;
  chromium = lib.findFirst (
    p: (p.pname or "") == "chromium"
  ) (throw "no chromium in the hyprland template's systemPackages") cfg.environment.systemPackages;
in
pkgs.runCommand "microvm-ai-mirror"
  {
    cidOption = if cfg.microvm.vsock.cid == null then "null" else toString cfg.microvm.vsock.cid;
    hasExtraArgs = lib.boolToString (cfg.microvm.extraArgsScript != null);
    listenExec = noCtx units.ai-mirror-vsock.serviceConfig.ExecStart;
    confirmPath = noCtx (toString units.ai-mirror-autoconfirm.path);
    listenPath = noCtx (toString units.ai-mirror-vsock.path);
    confirmWanted = toString units.ai-mirror-autoconfirm.wantedBy;
    listenWanted = toString units.ai-mirror-vsock.wantedBy;
    autoconfirmScript = noCtx units.ai-mirror-autoconfirm.script;
    luaText = cfg.environment.etc."hypr/hyprland.lua".text or "";
    hasConf = lib.boolToString (cfg.environment.etc ? "hypr/hyprland.conf");
    hyprExec = noCtx units.hyprland.serviceConfig.ExecStart;
    chromiumCmd = noCtx chromium.buildCommand;
  }
  ''
    fail() { echo "FAIL: $*" >&2; exit 1; }

    # (c) guest wiring
    [ "$cidOption" = null ] || fail "microvm.vsock.cid is $cidOption; the CID must come from extraArgsScript"
    [ "$hasExtraArgs" = true ] || fail "extraArgsScript is not set"
    [[ $listenExec == *VSOCK-LISTEN:7000* ]] || fail "listener runs '$listenExec'"
    for p in "$confirmPath" "$listenPath"; do
      [[ " $p " == *" /run/current-system/sw "* ]] || fail "a unit's path lacks /run/current-system/sw: '$p'"
    done
    for w in "$confirmWanted" "$listenWanted"; do
      [[ " $w " == *" default.target "* ]] || fail "a unit is not wanted by default.target: '$w'"
    done

    # (d) hyprland Lua config
    [ "$hasConf" = false ] || fail "the hyprland template still writes hyprland.conf"
    hd=$(mktemp -d)
    printf '%s' "$luaText" > "$hd/hyprland.lua"
    verify=$(env -i HOME="$hd" XDG_RUNTIME_DIR="$hd" ${pkgs.hyprland}/bin/Hyprland --verify-config --config "$hd/hyprland.lua" 2>&1) || fail "Hyprland rejects the template's Lua: $verify"
    [[ $verify == *"config ok"* ]] || fail "Hyprland did not say config ok: $verify"
    for k in Virtual-1 1920x1080 disable_splash_rendering enable_stdout_logs; do
      [[ $luaText == *"$k"* ]] || fail "the hyprland Lua lacks $k"
    done

    # (e) hyprland wiring
    [[ $hyprExec == */bin/start-hyprland\ --path\ /nix/store/*/bin/Hyprland\ --\ --config\ /etc/hypr/hyprland.lua ]] || fail "hyprland unit runs '$hyprExec', not start-hyprland --path <Hyprland> with the Lua config"
    for f in --ozone-platform=wayland --force-renderer-accessibility; do
      [[ $chromiumCmd == *"$f"* ]] || fail "Chromium's wrapper lacks $f"
    done

    # (a) vsock CID: chosen once, then stable
    d=$(mktemp -d)
    cd "$d"
    first=$(${cfg.microvm.extraArgsScript}) || fail "the CID script failed on its first run"
    second=$(${cfg.microvm.extraArgsScript}) || fail "the CID script failed on its second run: was the CID kept?"
    [ "$first" = "$second" ] || fail "CID changed between runs: $first / $second"
    cid=''${first#-device vhost-vsock-pci,guest-cid=}
    [ "$first" = "-device vhost-vsock-pci,guest-cid=$cid" ] || fail "bad line: $first"
    [ "$cid" -ge 3 ] && [ "$cid" -le 4294967294 ] || fail "CID $cid out of range"
    [ "$(cat vsock-cid)" = "$cid" ] || fail "vsock-cid file does not hold $cid"
    # A second VM's directory must get its own CID: the point of #1508.
    other=$(mkdir other && cd other && ${cfg.microvm.extraArgsScript}) || fail "the CID script failed in a second directory"
    [ "$other" != "$first" ] || fail "two VM directories got the same CID: $first"

    mkdir bad
    (cd bad && printf '3+4\n' > vsock-cid && ${vsockCid}/bin/nixarchy-vsock-cid) \
      && fail "accepted arithmetic in vsock-cid"
    mkdir long
    (cd long && printf '18446744073709551619\n' > vsock-cid && ${vsockCid}/bin/nixarchy-vsock-cid) \
      && fail "accepted a 20-digit vsock-cid that wraps to 3"
    mkdir link
    (cd link && ln -s "$d/vsock-cid" vsock-cid && ${vsockCid}/bin/nixarchy-vsock-cid) \
      && fail "accepted a symlinked vsock-cid"

    # (b) autoconfirm: confirm a pending request, and only a pending one
    export CONFIRM_LOG="$d/confirms" XDG_RUNTIME_DIR="$d/run"
    mkdir -p "$XDG_RUNTIME_DIR/ai-mirror"
    state="$XDG_RUNTIME_DIR/ai-mirror/state.json"
    run_for() {
      : > "$CONFIRM_LOG"
      PATH=${stub}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin timeout "$1" ${pkgs.bash}/bin/bash -c "$autoconfirmScript" || true
    }
    printf '%s\n' '{"owner":"pending","request":{"id":"abc"}}' > "$state"
    run_for 3
    [ "$(sort -u "$CONFIRM_LOG")" = abc ] || fail "pending was not confirmed with its id"
    for o in off agent; do
      printf '{"owner":"%s","request":{"id":"abc"}}\n' "$o" > "$state"
      run_for 2
      [ ! -s "$CONFIRM_LOG" ] || fail "owner $o was confirmed"
    done

    touch $out
  ''
