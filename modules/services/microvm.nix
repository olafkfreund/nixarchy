# Declarative sandboxes: permanent MicroVMs that come up at boot.
#
# The other half of #221's "two halves, both wanted". The user-scoped half
# (create/destroy freely, no root, `~/.local/state/nixarchy/microvm/<name>/`)
# is `nixarchy-vm`, #224's CLI over the templates data/microvm-templates.nix
# already builds. This is the half for a machine you keep: declare it here,
# rebuild, and it autostarts under systemd with a state directory root owns.
#
# ## Why this earns a module (data/services.nix's own bar)
#
# Turning a machine on is not one upstream line. It needs the template
# resolved to a module (a typo has to fail at evaluation, not at boot), the
# `kvm` group granted to whoever should be allowed to touch it, and the port
# a declarative machine forwards compiled into that machine's own closure
# rather than passed at launch -- #221's argument for why SSH exists only
# here.
#
# ## The inertness gate, measured rather than assumed
#
# `inputs.microvm.nixosModules.host` sets `microvm.host.enable = true` the
# moment it is imported. This module imports it unconditionally below --
# the same way `modules/services/default.nix` carries `inputs.sops-nix
# .nixosModules.sops` into every nixarchy machine, always present and inert
# until used -- so every effect of that default (the `microvm` system user,
# `/var/lib/microvms` tmpfiles rule, memlock login limits, the `tap`/
# `vhost_net` kernel modules, the setuid `qemu-bridge-helper`,
# `hardware.ksm.enable`, and the `microvm` CLI that drags Nix into the host
# closure) lives inside upstream's own
# `config = lib.mkIf config.microvm.host.enable { ... }`
# (nixos-modules/host/default.nix in the pinned commit) -- so one line, set
# OUTSIDE this module's own `mkIf`, is the entire gate. `machines != { }` on
# top of the service being wanted: a user who turns the service on but
# declares no machine gets nothing running, same as never having asked.
inputs:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.microvm;

  # data/microvm-templates.nix's own bar is "exactly a NixOS module" -- so
  # resolving `template` to `.module` is the whole translation this needs.
  templates = import ../../data/microvm-templates.nix;

  wanted = cfg.enable && svc.enable;
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  options.programs.nixarchy.services.microvm = {
    enable = lib.mkEnableOption ''
      declarative MicroVM sandboxes: permanent, template-built NixOS guests
      that come up at boot under systemd, with a forwarded SSH port and state
      under /var/lib/microvms.

      Off by default, and off leaves nothing behind -- no `microvm` system
      user, no tap/vhost_net kernel modules, no qemu-bridge-helper wrapper,
      no `microvm` CLI in the closure. Every one of those is upstream's own
      `microvm.host.enable`, which this module turns on for you only once you
      declare a machine below.

      For a throwaway machine you create and destroy on a whim, `nixarchy-vm`
      needs none of this -- it never touches the host at all. This option is
      for the machine you want to keep.
    '';

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.user;
      defaultText = lib.literalExpression "config.programs.nixarchy.user";
      description = ''
        Who joins the `kvm` group. Defaults to `programs.nixarchy.user`
        rather than `lib.mkDefault`, so a definition of your own outranks it
        the way `programs.nixarchy.services.hypr-rdp.user` does.

        Null skips the group grant entirely -- there is no session to infer a
        user from any more than hypr-rdp's module can.
      '';
    };

    machines = lib.mkOption {
      default = { };
      description = ''
        Permanent MicroVMs, keyed by name. Each becomes a
        `microvm@<name>.service`, wanted by `microvms.target` when
        `autostart` is true, with state under `/var/lib/microvms/<name>`.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            template = lib.mkOption {
              type = lib.types.enum (builtins.attrNames templates);
              example = "shell";
              description = ''
                Which entry of data/microvm-templates.nix this machine boots.
                An enum drawn from that catalogue, so naming a template that
                does not exist fails the rebuild at evaluation rather than
                leaving a machine that will not start.
              '';
            };

            autostart = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this machine is wanted by microvms.target and comes up at boot.";
            };

            sshPort = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              example = 2222;
              description = ''
                Host port forwarded to the guest's port 22, and the only
                door in besides the console. Null means console only --
                `microvm -s <name>` shells into it (#224's CLI), and nothing
                listens.

                Compiled into this machine's own closure, not passed at
                launch: #221's argument for why SSH belongs to the
                declarative half and not the disposable templates, which
                share one closure across every VM of a template and so
                cannot each carry a different port.
              '';
            };

            memory = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1024;
              description = "Guest RAM in MiB, `microvm.mem` on the guest.";
            };

            cores = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1;
              description = "Guest vCPUs, `microvm.vcpu` on the guest.";
            };

            shares = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule (
                  { config, ... }:
                  {
                    options = {
                      source = lib.mkOption {
                        type = lib.types.str;
                        description = "Host path to share.";
                      };
                      mountPoint = lib.mkOption {
                        type = lib.types.str;
                        description = "Where it appears inside the guest.";
                      };
                      tag = lib.mkOption {
                        type = lib.types.str;
                        default = baseNameOf config.mountPoint;
                        description = "virtiofs tag. Defaults to the mount point's basename, which is unique unless two shares share one.";
                      };
                    };
                  }
                )
              );
              default = [ ];
              description = ''
                Extra host directories to share, beyond the read-only store
                and the per-VM state directory modules/microvm/guest.nix
                already mounts. Appended to `microvm.shares` -- a list, so
                plain assignment, per modules/services/default.nix's rule.
              '';
            };

            modules = lib.mkOption {
              type = lib.types.listOf lib.types.deferredModule;
              default = [ ];
              description = ''
                Extra NixOS modules for this machine, evaluated alongside its
                template. A machine grows in NixOS vocabulary this way,
                rather than nixarchy inventing a second one.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkMerge [
    {
      # See the module header: everything upstream's host module adds lives
      # inside ITS OWN `mkIf config.microvm.host.enable`, so this is the
      # entire gate and it has to sit outside ours.
      microvm.host.enable = lib.mkDefault (wanted && svc.machines != { });
    }

    (lib.mkIf wanted {
      users.users = lib.optionalAttrs (svc.user != null) {
        ${svc.user}.extraGroups = [ "kvm" ];
      };

      microvm.vms = lib.mapAttrs (_: m: {
        inherit (m) autostart;
        config = {
          imports = [
            templates.${m.template}.module
            ../microvm/guest.nix
          ]
          ++ m.modules;

          microvm = {
            mem = m.memory;
            vcpu = m.cores;
            # A list on both sides, so plain assignment merges rather than
            # replaces: modules/microvm/guest.nix's ro-store and hostdir
            # shares survive alongside whatever a machine adds here.
            inherit (m) shares;
            # SLiRP (modules/microvm/guest.nix's `type = "user"` interface)
            # forwards ports without any host network surgery -- upstream's
            # own option docs say so ("When using the SLiRP user networking
            # (default), this option allows to forward ports"). No tap
            # interface is needed for this alone; `boot.kernelModules`
            # gaining `tap`/`vhost_net` is upstream's host module reacting to
            # `host.enable`, not to this machine's own interface type.
            forwardPorts = lib.optional (m.sshPort != null) {
              from = "host";
              host.port = m.sshPort;
              guest.port = 22;
            };
          };

          # Only worth anything with a port to reach it on -- modules/
          # microvm/guest.nix's `dev` user has a blank password and no other
          # way in, so this is scoped to sshPort rather than always on.
          services.openssh.enable = m.sshPort != null;
        };
      }) svc.machines;
    })
  ];
}
