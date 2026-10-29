# ai-mirror inside a microvm guest, so an MCP agent on the host drives a
# disposable desktop instead of the real one. Not a template on its own:
# hyprland-ai-mirror (#1504) and nixarchy-desktop (#1513) import it.
#
# Why each piece is here (measured 2026-10-29, see the spec):
# - Control is granted without asking: starting the VM is the consent, so a
#   user service confirms every pending request through the guest's own CLI.
#   It is a polling loop, not a path unit -- a path unit missed the first
#   request after a cold boot, before Hyprland was up.
# - The host reaches the guest over vsock only, port 7000. There is no SSH.
#   The CID is per VM, chosen at run time by vsock-cid.sh and kept in the VM's
#   directory, so several of these can run at once. #1508.
# - The listener's `path` is /run/current-system/sw: without it `launch`
#   cannot find the guest's apps.
{ pkgs, inputs, ... }:
let
  am = inputs.ai-mirror.packages.${pkgs.stdenv.hostPlatform.system};
  path = [ "/run/current-system/sw" ];
  vsockCid = pkgs.writeShellApplication {
    name = "nixarchy-vsock-cid";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./vsock-cid.sh;
  };
in
{
  microvm.extraArgsScript = "${vsockCid}/bin/nixarchy-vsock-cid";
  environment.systemPackages = [
    am.ai-mirror
    am.ai-mirror-input
    pkgs.jq
  ];
  systemd.user.services.ai-mirror-autoconfirm = {
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "dev";
    inherit path;
    script = ''
      while sleep 0.5; do
        id=$(jq -r 'select(.owner == "pending") | .request.id // empty' "$XDG_RUNTIME_DIR/ai-mirror/state.json" 2>/dev/null || true)
        [ -z "$id" ] || ai-mirror control confirm "$id" || true
      done
    '';
    serviceConfig.Restart = "always";
  };
  systemd.user.services.ai-mirror-vsock = {
    wantedBy = [ "default.target" ];
    after = [
      "hyprland.service"
      "ai-mirror-autoconfirm.service"
    ];
    wants = [ "ai-mirror-autoconfirm.service" ];
    unitConfig.ConditionUser = "dev";
    inherit path;
    serviceConfig.ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:7000,fork EXEC:'ai-mirror mcp'";
  };
}
