# The CID script, the autoconfirm loop and the guest wiring of the
# `hyprland-ai-mirror` template.
# Boots nothing: no CI check boots a guest (#929 wedged twice), so the MCP round
# trip over vsock is proven live, not here. See tests/AGENTS.md. #1504, #1508.
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

    mkdir bad
    (cd bad && printf 'abc\n' > vsock-cid && ${vsockCid}/bin/nixarchy-vsock-cid) \
      && fail "accepted a non-numeric vsock-cid"
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
