# Omarchy's local model runner (omacom/omarchy-local-ai): rootless Podman
# containers that need the GPU, a raised memlock limit and, on NVIDIA, a CDI
# spec. Bundled because none of that is one upstream line. Takes `inputs` for
# the same reason microvm.nix does: the engine package comes from the overlay.
inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.agent-local;
  inherit (cfg) user;

  # Exactly nixpkgs' own condition for hardware.nvidia-container-toolkit
  # (nvidia-container-toolkit/default.nix), so enabling it never trips its assertion.
  nvidiaDeclared =
    lib.elem "nvidia" config.services.xserver.videoDrivers || config.hardware.nvidia.datacenter.enable;
in
{
  options.programs.nixarchy.services.agent-local.enable = lib.mkEnableOption ''
    Omarchy's local model runner: rootless Podman with the GPU reachable, the
    render and video groups for the desktop user, memlock raised for them, the
    NVIDIA container toolkit when an NVIDIA driver is declared, and the
    `omarchy-local-ai` engine. The catalog's models need a large GPU (the
    smallest wants 38 GiB of GPU memory); for small cards use
    `programs.nixarchy.localAi` (Ollama)
  '';

  config = lib.mkIf (cfg.enable && svc.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = user != null;
            message = ''
              programs.nixarchy.services.agent-local is enabled but no user is set.
              Set programs.nixarchy.user: the render and video groups and the memlock
              limit are granted to that user.
            '';
          }
        ];

        virtualisation.podman.enable = lib.mkDefault true;

        # lowPrio: a user's own copy wins any binary it shares (#1167).
        environment.systemPackages = [
          (lib.lowPrio (pkgs.extend inputs.self.overlays.default).nixarchy-apps.omarchy-local-ai)
        ];

        hardware.nvidia-container-toolkit.enable = lib.mkIf nvidiaDeclared (lib.mkDefault true);

        warnings = lib.optional (nvidiaDeclared && !config.hardware.nvidia-container-toolkit.enable) ''
          programs.nixarchy.services.agent-local is enabled with an NVIDIA driver, but
          hardware.nvidia-container-toolkit.enable is off, so NVIDIA models cannot start.
          Remove that override or turn the toolkit back on.
        '';
      }
      (lib.mkIf (user != null) {
        users.users.${user}.extraGroups = [
          "render"
          "video"
        ];
        security.pam.loginLimits = [
          {
            domain = user;
            item = "memlock";
            type = "-";
            value = "unlimited";
          }
        ];
      })
    ]
  );
}
