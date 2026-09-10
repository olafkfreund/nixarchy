{ inputs, pkgs }:
# The previewVariant module (#487): a nixarchy config previewed with
# `nixos-rebuild build-vm` gets the software-GL fallbacks and the VM sizing
# that make its desktop actually render, and gets them ONLY there.
#
# `virtualisation.vmVariant` is the same config re-evaluated with qemu-vm.nix
# layered on, so it can be asked at evaluation time -- no VM boots here.
# Three machines, because the module makes three claims:
#
#   on        enabling nixarchy fills the vmVariant in;
#   off       Mode A -- an inert import leaves the vmVariant exactly as
#             nixpkgs would have it, measured against a baseline WITHOUT the
#             module rather than against remembered nixpkgs defaults, which
#             would go stale the day nixpkgs changes one;
#   override  everything scalar is mkDefault, so a user's plain assignment
#             in their own vmVariant wins without mkForce -- and the
#             forwardPorts list MERGES with their addition rather than
#             being dropped by it.
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  hardware = {
    boot.loader.grub.device = "/dev/sda";
    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
    system.stateVersion = "25.05";
  };

  machine =
    modules:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = modules ++ [ hardware ];
    }).config.virtualisation.vmVariant;

  on = machine [
    inputs.self.nixosModules.nixarchy
    { programs.nixarchy.enable = true; }
  ];

  off = machine [
    inputs.self.nixosModules.nixarchy
    { programs.nixarchy.enable = false; }
  ];

  # No nixarchy module at all: what nixpkgs gives a vmVariant on its own.
  # The off machine must be indistinguishable from this one in everything
  # the preview module touches.
  baseline = machine [ ];

  overridden = machine [
    inputs.self.nixosModules.nixarchy
    {
      programs.nixarchy.enable = true;
      virtualisation.vmVariant = {
        environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE = "0";
        virtualisation = {
          memorySize = 4096;
          cores = 2;
          forwardPorts = [
            {
              from = "host";
              host.port = 8080;
              guest.port = 80;
            }
          ];
        };
      };
    }
  ];

  glVars = [
    "WLR_RENDERER_ALLOW_SOFTWARE"
    "WLR_NO_HARDWARE_CURSORS"
    "LIBGL_ALWAYS_SOFTWARE"
  ];

  hostPorts = cfg: map (p: p.host.port) cfg.virtualisation.forwardPorts;

  cases = {
    # ---- on: the black-screen fix is present in the VM ----
    on-sets-software-gl = builtins.all (
      v: (on.environment.sessionVariables.${v} or null) == "1"
    ) glVars;
    on-sizes-the-guest = on.virtualisation.memorySize == 8192 && on.virtualisation.cores == 4;
    # 2223, not 2222: qemu cannot bind a host port twice, and 2222 belongs to
    # `nix run .#vm`. The map of every guest's port is in modules/preview.nix
    # beside the forward. Asserting the NUMBER rather than "some forward exists"
    # is the point -- a collision is a wrong number, not a missing one.
    on-forwards-ssh = builtins.elem 2223 (hostPorts on);

    # ---- off: Mode A, indistinguishable from no module at all ----
    off-adds-no-variables = builtins.all (
      v: (off.environment.sessionVariables ? ${v}) == (baseline.environment.sessionVariables ? ${v})
    ) glVars;
    off-leaves-sizing-alone =
      off.virtualisation.memorySize == baseline.virtualisation.memorySize
      && off.virtualisation.cores == baseline.virtualisation.cores;
    off-forwards-nothing = hostPorts off == hostPorts baseline;

    # ---- override: a plain assignment beats every default here ----
    override-wins-variables = overridden.environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE == "0";
    override-wins-sizing =
      overridden.virtualisation.memorySize == 4096 && overridden.virtualisation.cores == 2;
    # And the list is the other way round on purpose: their port arrives
    # AND ours survives. If ours vanished, forwardPorts was mkDefault'd and
    # the module has the merging-type trap the services header warns about.
    override-merges-forwards =
      builtins.elem 8080 (hostPorts overridden) && builtins.elem 2223 (hostPorts overridden);
  };

  broken = lib.filterAttrs (_: ok: !ok) cases;
in
pkgs.runCommand "nixarchy-preview-variant"
  {
    report = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: ok: "  ${name}: ${if ok then "ok" else "BROKEN"}") cases
    );
    checked = toString (builtins.length (builtins.attrNames cases));
    bad = lib.concatStringsSep " " (builtins.attrNames broken);
  }
  (
    if broken == { } then
      ''
        echo "the preview vmVariant, in three states:"
        printf '%s\n' "$report"

        # A floor, so an emptied cases set cannot pass having asked nothing.
        test "$checked" -ge 9

        echo "on fills it in, off leaves nixpkgs' own, a plain assignment wins"
        touch $out
      ''
    else
      ''
        printf '%s\n' "$report"
        echo "these preview-variant claims do not hold: $bad" >&2
        echo "a preview whose desktop cannot render is a VM that boots to a" >&2
        echo "black screen -- see modules/preview.nix and #487." >&2
        exit 1
      ''
  )
