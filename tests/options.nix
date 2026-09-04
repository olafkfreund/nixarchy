{ inputs, pkgs }:
# The options that add or remove something, checked both ways.
#
# An option nobody turns off is an option nobody knows is broken. Each of
# these is on by default and covered in that state by some other check, so
# what is untested is the half a user reaches for when they do not want the
# default -- and that half is exactly what a refactor breaks quietly.
#
# Evaluated rather than booted. Every option here does its work by putting a
# package in a list or a line in a file, so evaluation is where the answer is;
# booting a VM to look would be slower and prove no more. That is not the case
# generally -- see tests/integration.nix for the bugs that only a build finds.
let
  system = pkgs.stdenv.hostPlatform.system;

  configWith =
    settings:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        {
          programs.nixarchy = {
            enable = true;
          }
          // settings;
        }
        {
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;

  # A host where some other module already has an opinion, so what is being
  # measured is whose definition survives -- not what nixarchy asks for alone.
  configBeside =
    extra:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        { programs.nixarchy.enable = true; }
        extra
        {
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;

  sessionNames =
    cfg: map (p: p.passthru.providedSessions or [ ]) cfg.services.displayManager.sessionPackages;

  hasOmarchySession = cfg: builtins.elem "omarchy" (pkgs.lib.flatten (sessionNames cfg));

  # Each case is (what it should look like on, what it should look like off).
  cases = {
    session = {
      on = hasOmarchySession (configWith {
        session = true;
      });
      off = hasOmarchySession (configWith {
        session = false;
      });
    };

    displayManager = {
      on = (configWith { displayManager = true; }).services.displayManager.sddm.enable;
      off = (configWith { displayManager = false; }).services.displayManager.sddm.enable;
    };

    binaryCaches = {
      on =
        builtins.elem "https://nixarchy.cachix.org"
          (configWith { binaryCaches = true; }).nix.settings.substituters;
      off =
        builtins.elem "https://nixarchy.cachix.org"
          (configWith { binaryCaches = false; }).nix.settings.substituters;
    };

    preinstalls = {
      # "Pinta", capitalised -- its pname is not the attribute name, and
      # matching the attribute name found nothing in either direction, which
      # this check reported as the option being broken. It was the probe.
      on =
        builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstalls = true; }).environment.systemPackages;
      off =
        builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstalls = false; }).environment.systemPackages;
    };

    # The unit itself, both ways. "off" is the half that matters: a nixarchy
    # machine that never asked for remote desktop must have no RDP daemon
    # declared for any user.
    hyprRdpUnit = {
      on = rdpOn.systemd.user.services ? hypr-rdp;
      off = rdpOff.systemd.user.services ? hypr-rdp;
    };

    # And the sops template. Off, nothing renders -- which also keeps the
    # sops-nix inertness the block above asserts true for everyone else.
    hyprRdpTemplate = {
      on = rdpOn.sops.templates ? "hypr-rdp.toml";
      off = rdpOff.sops.templates ? "hypr-rdp.toml";
    };

    # openFirewall is its own decision and defaults to false, so enabling the
    # service must NOT open 3389. "off" here is the whole promise of the
    # option: the promoted path is the tailnet, which needs no firewall change.
    hyprRdpFirewall = {
      on = builtins.elem 3389 rdpFirewall.networking.firewall.allowedTCPPorts;
      off = builtins.elem 3389 rdpOn.networking.firewall.allowedTCPPorts;
    };

    # The evaluation-time refusal, both ways. Without the "off" half this
    # would pass just as well against an assertion that always fires.
    hyprRdpAssertion = {
      on = mentions "passwordSecret" (failedAssertions rdpNoSecret);
      off = mentions "passwordSecret" (failedAssertions rdpOn);
    };

    # ---- microvm: #221's inertness table, each row with a real off state --
    #
    # This is the check the PR body's "break it, watch it fail" argument is
    # built on. Deleting the `microvm.host.enable` line in
    # modules/services/microvm.nix (leaving the import) makes every case in
    # this group fail at once, because every one of them is a consequence of
    # that single gate rather than of anything they individually configure.
    microvmHostUser = {
      on = mvOn.users.users ? microvm;
      off = mvOff.users.users ? microvm;
    };

    microvmStateDir = {
      on = mvOn.systemd.tmpfiles.settings ? "10-microvm";
      off = mvOff.systemd.tmpfiles.settings ? "10-microvm";
    };

    microvmUnits =
      let
        has =
          cfg:
          cfg.systemd.services ? "microvm-tap-interfaces@"
          && cfg.systemd.services ? "microvm-virtiofsd@"
          && cfg.systemd.targets ? microvms;
      in
      {
        on = has mvOn;
        off = has mvOff;
      };

    microvmCommand =
      let
        has = cfg: builtins.any (p: pkgs.lib.getName p == "microvm") cfg.environment.systemPackages;
      in
      {
        on = has mvOn;
        off = has mvOff;
      };

    # kvm is not in extraGroups today (modules/nixos.nix grants input and,
    # conditionally, docker -- never kvm), so this is a real pair: the group
    # is a capability nobody asked for on a machine that never declared a
    # sandbox, the same argument modules/nixos.nix already makes for docker.
    microvmKvmGroup = {
      on = builtins.elem "kvm" (mvOn.users.users.someone.extraGroups or [ ]);
      off = builtins.elem "kvm" (mvOff.users.users.someone.extraGroups or [ ]);
    };

    # Every field below compares the "sandbox" machine, which set the field
    # explicitly, against "plain", which left it at its default -- both from
    # the SAME evaluation of mvOn, so what is measured is that the value
    # actually follows what was declared rather than a hardcoded default
    # that happens to read true once.
    microvmAutostart = {
      on = mvOn.microvm.vms.sandbox.autostart == false;
      off = mvOn.microvm.vms.plain.autostart == false;
    };

    microvmMemory = {
      on = (mvVm mvOn "sandbox").microvm.mem == 4096;
      off = (mvVm mvOn "plain").microvm.mem == 4096;
    };

    microvmCores = {
      on = (mvVm mvOn "sandbox").microvm.vcpu == 3;
      off = (mvVm mvOn "plain").microvm.vcpu == 3;
    };

    microvmShare = {
      on = builtins.elem "extra" (map (s: s.tag) (mvVm mvOn "sandbox").microvm.shares);
      off = builtins.elem "extra" (map (s: s.tag) (mvVm mvOn "plain").microvm.shares);
    };

    # A typo in `template` has to fail the rebuild, not produce a machine
    # that never boots -- data/microvm-templates.nix's own catalogue is
    # exactly the enum modules/services/microvm.nix draws from.
    microvmTemplate = {
      on = mvTemplateOk.success;
      off = mvTemplateBad.success;
    };

    # preinstallsExclude is the per-application half of preinstalls, and the
    # only removal path for an app the selection does not carry. Both ways:
    # Pinta is there by default and gone when named.
    preinstallsExclude = {
      on =
        !(builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstallsExclude = [ "pinta" ]; }).environment.systemPackages
        );
      off =
        !(builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstallsExclude = [ ]; }).environment.systemPackages
        );
    };

    # bootSplash, which is three-valued rather than a switch. The half that
    # matters is `force`: it has to beat a theme set at normal priority, which
    # is what stylix does and what sends people reaching for mkForce on
    # boot.plymouth.theme alone -- a build failure, because themePackages then
    # does not contain what the name points at.
    bootSplash = {
      on = (configWith { bootSplash = "force"; }).boot.plymouth.theme == "omarchy";
      off = (configWith { bootSplash = "off"; }).boot.plymouth.theme == "omarchy";
    };

    # The input method, which is not an option of ours but a default we set on
    # someone else's. GNOME's desktop-manager module sets the same option to
    # "ibus" at mkDefault; when this module matched that priority the two tied
    # and a host running both failed to evaluate at all -- not a wrong value, no
    # value. So the assertion is that another module's mkDefault wins outright,
    # and that fcitx5 still lands on a host with no other opinion.
    inputMethod = {
      on = (configWith { }).i18n.inputMethod.type == "fcitx5";
      off =
        (configBeside {
          i18n.inputMethod.type = pkgs.lib.mkDefault "ibus";
        }).i18n.inputMethod.type == "fcitx5";
    };

    # nixarchy allows unfree because most of the Install menu is unfree. The
    # half worth testing is the other one: a user who wants nixpkgs' own policy
    # back must be able to have it.
    #
    # This case exists because the first attempt did not work at all. mkDefault
    # on nixpkgs.config.allowUnfree never resolves -- nixpkgs.config is a
    # free-form attribute set, so the override attrset is stored verbatim and
    # nixpkgs receives a set where it wants a bool. Nothing else would have
    # caught that; the module still evaluated.
    allowUnfree = {
      on = (configWith { }).nixpkgs.config.allowUnfree or false;
      off = (configWith { allowUnfree = false; }).nixpkgs.config.allowUnfree or false;
    };

    browserThemeUser = {
      # null is the default, so this one reads the other way round: the rules
      # appear when a user is named.
      on =
        builtins.any (r: pkgs.lib.hasInfix "chromium/policies" r)
          (configWith { browserThemeUser = "someone"; }).systemd.tmpfiles.rules;
      off =
        builtins.any (r: pkgs.lib.hasInfix "chromium/policies" r)
          (configWith { browserThemeUser = null; }).systemd.tmpfiles.rules;
    };

    # sops-nix is imported by every nixarchy machine and must do nothing
    # until a secret is declared. See sopsOff/sopsOn below for why this is
    # asserted rather than assumed.
    sops = {
      on = hasSops sopsOn;
      off = hasSops sopsOff;
    };
  };

  # Every Install row upstream offers, checked against what the selection
  # covers -- so a row added by an Omarchy bump cannot quietly go unmapped.
  #
  # The exceptions are listed rather than counted, because "how many are
  # unmapped" is a number that drifts silently and "which ones, and why" is
  # a decision someone made. Each of these is either not an application at
  # all, or a known gap the README names.
  # The menu file. Parsed in the builder rather than here: stripping JSONC
  # comments with string functions in Nix got the indented ones wrong and fed
  # builtins.fromJSON something that was still commented. Python has a parser;
  # this file does not need a second one.
  menuFile = "${(pkgs.extend inputs.self.overlays.default).omarchy}/share/omarchy/default/omarchy/omarchy-menu.jsonc";

  # An upstream Install row is "mapped" if data/apps.nix answers for it OR
  # data/services.nix does. Both are now real answers: tailscale moved from
  # one to the other when it gained a module, and the row went with it. A
  # check that knew only about apps would have called that unmapped and been
  # wrong -- the row is wired, just not by the file it used to be wired by.
  mappedRows =
    pkgs.lib.mapAttrsToList (_: a: a.menuId) (
      pkgs.lib.filterAttrs (_: a: a ? menuId) (import ../data/apps.nix)
    )
    ++ pkgs.lib.mapAttrsToList (_: s: s.menuId) (pkgs.lib.filterAttrs (_: s: s ? menuId) services);

  # Rows that are actions rather than applications, plus the gaps the README
  # names. Fonts go through omarchy-install-font and the Arch-name map; the
  # four gaming rows and three frameworks are documented as needing a hand.
  notApps = [
    "install.aur"
    "install.package"
    "install.preinstalls"
    "install.style.background"
    "install.style.theme"
    "install.tui"
    "install.webapp"
    "install.windows"
    "install.service.chromium-account"
    "install.style.font.bitstream"
    "install.style.font.cascadia"
    "install.style.font.fira"
    "install.style.font.iosevka"
    "install.style.font.meslo"
    "install.style.font.victor"
    "install.ai.ollama"
    "install.gaming.battlenet"
    "install.gaming.geforce-now"
    "install.gaming.retro-launcher"
    "install.gaming.xbox-cloud"
    "install.development.docker-dbs"
    "install.development.elixir.phoenix"
    "install.development.php.laravel"
    "install.development.rails"
  ];

  # The built reference machine, for the things that are facts about a system
  # rather than about an option.
  vm = inputs.self.nixosConfigurations.vm.config.system.build.toplevel;

  # ---- the boot splash is ours ------------------------------------------
  #
  # #46's acceptance, in the one place that can hold it: "no Omarchy artwork
  # is reachable from the ISO or the installed boot splash". That issue was
  # closed once on the strength of a claim that it was not, while five
  # upstream assets still were -- so this reads the built theme directory
  # rather than the source that produces it.
  #
  # Two directories, because they are two code paths and the acceptance names
  # both: modules/nixos.nix puts the omarchy package in
  # boot.plymouth.themePackages, installer/cd.nix puts nixarchy-plymouth
  # there. Each is resolved through the plymouth module's own themesEnv --
  # environment.etc."plymouth/themes" is the same buildEnv the initrd theme
  # directory is copied out of, so this is what boots, not what was asked for.
  #
  # pkgs/omarchy/default.nix already fails the BUILD if a branded asset comes
  # out byte-identical to upstream's. This is the other half of the same
  # promise and it cannot be answered there: a theme whose every file is ours
  # proves nothing if the machine is pointed at a different theme, and the ISO
  # spent this entire issue pointed at no theme at all.
  #
  # Guarded on `enable`, because environment.etc."plymouth/themes" does not
  # exist when the plymouth module is off -- and a splash that is off is
  # exactly the state this issue sat in for the live image, so it has to reach
  # the message below rather than die in evaluation with a missing attribute.
  splashPaths =
    cfg:
    if cfg.boot.plymouth.enable then
      "${cfg.environment.etc."plymouth/themes".source}/${cfg.boot.plymouth.theme}"
    else
      "/plymouth-is-not-enabled";

  installedSplash = configWith { };
  isoSplash = inputs.self.nixosConfigurations.iso.config;

  # ---- nixarchy does not delete software somebody installed ----
  #
  # uninstallUnmanaged removes every Flatpak the configuration does not
  # declare, including ones installed by hand. It is a real thing to want and
  # it must never arrive by accident, so the default is asserted rather than
  # trusted: this is precisely the kind of default that gets flipped later by
  # someone tidying up who does not know what it costs.
  #
  # Both ends. The nixarchy option is what a person sets; the upstream option
  # is what actually decides, and a passthrough that silently stopped passing
  # would leave the first reading false while the second did the deleting.
  flatpakDefaults = {
    ours = (configWith { }).programs.nixarchy.flatpaks.uninstallUnmanaged;
    theirs = (configWith { }).services.flatpak.uninstallUnmanaged;
    # And that asking for it works, or the option is decoration.
    onWhenAsked =
      (configWith { flatpaks.uninstallUnmanaged = true; }).services.flatpak.uninstallUnmanaged;
  };

  # ---- the fleet option, both ways --------------------------------------
  #
  # Both ends again. What a person sets is programs.nixarchy.fleet; what
  # decides is system.autoUpgrade, and a passthrough that quietly stopped
  # passing would leave a fleet that reads as enabled and never pulls.
  #
  # The off case is the one that matters most here: this is the only option in
  # nixarchy that can revert somebody's unpushed work, so a machine that did
  # not ask for it must not acquire a timer.
  fleet = rec {
    offByDefault = (configWith { }).system.autoUpgrade.enable;
    on = configWith {
      fleet = {
        enable = true;
        url = "github:me/config";
      };
    };
    onWhenAsked = on.system.autoUpgrade.enable;
    url = on.system.autoUpgrade.flake;
    # A laptop asleep at 03:00 never catches up without this.
    persistent = on.system.autoUpgrade.persistent;
    # The whole reason the option exists rather than raw autoUpgrade: an
    # upgrade that starts failing must leave a mark, or the fleet stops
    # converging and looks exactly like a fleet that is up to date.
    onFailure = on.systemd.services.nixos-upgrade.unitConfig.OnFailure or "";
  };

  # ---- devenv, both halves --------------------------------------------
  #
  # The half that breaks quietly is "off". devenv is a package plus a line in
  # three shell rcs plus a substituter, and each of those three arrives through
  # a different mechanism -- so "it did not turn on" is loud, and "it turned on
  # for someone who never asked" is silent. Mode A is the case: importing
  # nixosModules.nixarchy must add no devenv, no hook line in any shell, and
  # above all no substituter, because a substituter is trust granted without a
  # conflict to warn anyone.
  #
  # zsh and fish are enabled explicitly here because the module gates their
  # hooks on the shell actually existing. Without that, the on case would read
  # the same as the off case for two of the three shells and prove nothing.
  devenvOff = configWith { };

  devenvOn = configBeside {
    programs = {
      nixarchy.services.devenv.enable = true;
      zsh.enable = true;
      fish.enable = true;
    };
  };

  # The cache is a separate decision from the package. Someone who set
  # binaryCaches = false said something about whose builds they run, and
  # enabling devenv must not walk that back.
  devenvNoCache = configBeside {
    programs.nixarchy = {
      binaryCaches = false;
      services.devenv.enable = true;
    };
  };

  hasDevenv = cfg: builtins.any (p: (p.pname or "") == "devenv") cfg.environment.systemPackages;
  hasCache = cfg: builtins.elem "https://devenv.cachix.org" cfg.nix.settings.substituters;
  hookIn = text: pkgs.lib.hasInfix "devenv hook" text;

  # ---- boxes, both halves (#257) --------------------------------------
  #
  # More reaches across than devenv does: turning services.boxes.enable on
  # crosses into Home Manager, which nothing else in this file evaluates.
  # Every effect the option has, measured both ways -- the shape #221 set
  # for microvm.host.enable:
  #
  #   | | enable = false | enable = true, one machine |
  #   |---|---|---|
  #   | virtualisation.podman.enable | false | true |
  #   | programs.distrobox.containers | { } | populated |
  #   | distrobox-home-manager systemd unit | absent | absent (forced off) |
  #   | distrobox in environment.systemPackages | absent | present |
  #   | distrobox in home.packages | absent | absent (package = null) |
  #
  # The systemd-unit row is the one that matters most: Home Manager's own
  # default for enableSystemdUnit is `containers != { } && package != null`,
  # which is true the moment a machine is declared -- so "on" has to prove
  # the unit is STILL absent, not just that "off" is quiet.
  boxesUser = "tester";

  boxesConfig =
    enable:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        {
          programs.nixarchy = {
            enable = true;
            services.boxes = {
              inherit enable;
            }
            // pkgs.lib.optionalAttrs enable {
              machines.dev.image = "archlinux:latest";
            };
          };
          users.users.${boxesUser}.isNormalUser = true;
          home-manager.users.${boxesUser} = {
            imports = [ inputs.self.homeManagerModules.nixarchy ];
            home.stateVersion = "25.05";
            programs.nixarchy.enable = true;
          };
        }
        {
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;

  boxesOff = boxesConfig false;
  boxesOn = boxesConfig true;

  homeOfBoxes = cfg: cfg.home-manager.users.${boxesUser};
  hasDistrobox = list: builtins.any (p: (p.pname or "") == "distrobox") list;

  # ---- sops-nix, imported by everyone and doing nothing --------------
  #
  # #155 adopted a declarative secrets mechanism for one concrete reason:
  # hypr-rdp reads its password only from an inline string in its TOML or
  # from `-p`, so something has to render a config file at runtime. That
  # decision put an upstream module into EVERY nixarchy machine, including
  # every Mode A machine that will never declare a secret -- so what has to
  # be asserted is that the module is inert, not that it works.
  #
  # Inertness here is upstream's promise, not ours: sops-nix gates both
  # halves of its config on `sops.secrets != {}` and `sops.templates != {}`.
  # A promise made by someone else's module is exactly the kind a version
  # bump can withdraw quietly, and the failure would be silent -- an
  # activation script and a systemd unit appearing on machines that never
  # asked for secrets. Nothing else in this repo would notice.
  sopsOff = configWith { };

  # The other half, so that the case above measures inertness rather than an
  # import that never worked. validateSopsFiles is off because there is no
  # encrypted file here to validate, and a key source is named so this reads
  # as a machine someone actually configured.
  sopsOn = configBeside {
    sops = {
      validateSopsFiles = false;
      age.keyFile = "/var/lib/sops-nix/key.txt";
      defaultSopsFile = ./options.nix;
      secrets.a-secret = { };
    };
  };

  # Which of the two activation paths upstream picks depends on whether the
  # machine uses systemd-sysusers or userborn, so asking for one of them by
  # name would assert the wrong thing on the other kind of machine.
  hasSops =
    cfg: (cfg.systemd.services ? sops-install-secrets) || (cfg.system.activationScripts ? setupSecrets);

  # ---- hypr-rdp, whose module is the only thing that refuses ----------
  #
  # hypr-rdp FAILS OPEN. v0.1.5, src/config.rs:187-197, resolves the password
  # with `unwrap_or_default()` and then, finding it empty, logs two warnings
  # and serves the session anyway -- and src/server/mod.rs:123 builds no
  # credentials at all when username and password are both empty. There is no
  # `bail!` and no exit anywhere on that path.
  #
  # So every case below is measuring a refusal rather than a feature, and the
  # halves that break quietly are the "off" ones: a unit that appears on a
  # machine nobody enabled it on is an RDP daemon somebody did not ask for.
  rdpSops = {
    validateSopsFiles = false;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    defaultSopsFile = ./options.nix;
    secrets.rdp-password = { };
  };

  rdpOff = configBeside {
    programs.nixarchy.user = "someone";
    sops = rdpSops;
  };

  rdpOn = configBeside {
    programs.nixarchy = {
      user = "someone";
      services.hypr-rdp = {
        enable = true;
        passwordSecret = "rdp-password";
      };
    };
    sops = rdpSops;
  };

  rdpFirewall = configBeside {
    programs.nixarchy = {
      user = "someone";
      services.hypr-rdp = {
        enable = true;
        passwordSecret = "rdp-password";
        openFirewall = true;
      };
    };
    sops = rdpSops;
  };

  # Enabled with no secret named. Read as a list of failed assertions rather
  # than by forcing system.build.toplevel: the point is that THIS assertion
  # fires, and a config that fails to build for some unrelated reason would
  # look identical from outside.
  rdpNoSecret = configBeside {
    programs.nixarchy = {
      user = "someone";
      services.hypr-rdp.enable = true;
    };
    sops = rdpSops;
  };

  failedAssertions = cfg: map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);

  mentions = needle: msgs: builtins.any (m: pkgs.lib.hasInfix needle m) msgs;

  rdpUnitOf = cfg: cfg.systemd.user.services.hypr-rdp.serviceConfig or { };

  # ---- microvm, whose whole promise is that "off" leaves nothing --------
  #
  # #221 measured `inputs.microvm.nixosModules.host` against `main` before
  # designing anything: `microvm.host.enable = true` the instant it is
  # imported, and with it a system user, memlock limits, the tap/vhost_net
  # kernel modules, a setuid qemu-bridge-helper, KSM and a `microvm` CLI that
  # drags Nix into the closure. modules/services/default.nix imports it
  # unconditionally (the same way sops-nix is always present and inert), so
  # every one of those has to come from `machines != {}` alone.
  #
  # mvOff never enables the service at all -- the state most nixarchy
  # machines are actually in, and where every row of #221's table must read
  # "false".
  mvOff = configWith { user = "someone"; };

  # mvOn declares two machines rather than one, so the per-machine cases
  # below can prove a passthrough varies with its input instead of merely
  # being present: "sandbox" sets every field explicitly, "plain" leaves
  # them at their defaults, and "off" for those cases is the plain machine
  # reading back the default rather than a second full evaluation.
  mvOn = configWith {
    user = "someone";
    services.microvm = {
      enable = true;
      machines = {
        sandbox = {
          template = "shell";
          autostart = false;
          memory = 4096;
          cores = 3;
          sshPort = 2222;
          shares = [
            {
              source = "/tmp/nixarchy-options-test-share";
              mountPoint = "/mnt/extra";
              tag = "extra";
            }
          ];
        };
        plain = {
          template = "shell";
        };
      };
    };
  };

  mvVm = cfg: name: cfg.microvm.vms.${name}.config.config;

  # The enum in modules/services/microvm.nix's `template` option is the
  # whole claim that a typo fails at evaluation rather than at boot. Forcing
  # the guest's own toplevel is what actually walks through
  # `templates.${m.template}.module`, so a name the catalogue does not have
  # throws here rather than merely constructing a lazy, never-forced value.
  mvTemplateOk =
    builtins.tryEval
      (mvVm (configWith {
        services.microvm.enable = true;
        services.microvm.machines.x.template = "shell";
      }) "x").system.build.toplevel.outPath;
  mvTemplateBad =
    builtins.tryEval
      (mvVm (configWith {
        services.microvm.enable = true;
        services.microvm.machines.x.template = "not-a-real-template";
      }) "x").system.build.toplevel.outPath;

  # The cache promise, stated where it can be measured (#221): the guest
  # closure served to `microvm -c <name>` has to be the same closure CI
  # already pushed, or "the first launch is a download" is hopeful rather
  # than true. Same NAME and template in both evaluations -- upstream's own
  # eval-config sets `networking.hostName = lib.mkDefault name;`
  # (nixos-modules/host/options.nix in the pinned commit), and that name
  # becomes part of `system.build.toplevel`'s own derivation name, so two
  # DIFFERENTLY-named machines would never share an outPath regardless of
  # this invariant -- that would be measuring the name, not the promise.
  # What varies here is deliberately only memory, cores and share SOURCE --
  # same share tag and mount point, since varying those would be a genuine
  # guest config change (nixos-modules/microvm/mounts.nix keys the generated
  # mount unit on `tag`, never on `source`).
  mvInvariantOf =
    memCfg:
    mvVm (configWith {
      services.microvm.enable = true;
      services.microvm.machines.vm = {
        template = "shell";
      }
      // memCfg;
    }) "vm";

  mvInvariantSmall = mvInvariantOf {
    memory = 512;
    cores = 1;
    shares = [
      {
        source = "/tmp/nixarchy-options-invariant-a";
        mountPoint = "/mnt/extra";
        tag = "extra";
      }
    ];
  };

  mvInvariantBig = mvInvariantOf {
    memory = 8192;
    cores = 8;
    shares = [
      {
        source = "/tmp/nixarchy-options-invariant-b-a-very-different-path";
        mountPoint = "/mnt/extra";
        tag = "extra";
      }
    ];
  };

  microvmProblems =
    pkgs.lib.optional
      (mvInvariantSmall.system.build.toplevel.outPath != mvInvariantBig.system.build.toplevel.outPath)
      ''
        the guest toplevel changed with memory, cores or share source:
          small (512MiB, 1 core): ${mvInvariantSmall.system.build.toplevel.outPath}
          big (8192MiB, 8 cores): ${mvInvariantBig.system.build.toplevel.outPath}
        the cache promise ("the first launch is a download") does not hold.''
    ++ pkgs.lib.optional mvInvariantSmall.microvm.storeOnDisk "microvm.vms.vm.config.microvm.storeOnDisk is true at 512MiB; the host's /nix/store share should make an image build unnecessary."
    ++ pkgs.lib.optional mvInvariantBig.microvm.storeOnDisk "microvm.vms.vm.config.microvm.storeOnDisk is true at 8192MiB; the host's /nix/store share should make an image build unnecessary.";

  # ---- a bundled service yields to a user who already configured it ----
  #
  # This is the Mode A hazard in one assertion. Someone adds nixarchy to a
  # machine they already run and already configure; if a module here sets a
  # scalar at plain priority, they get "conflicting definition values" and
  # their only escape is mkForce on their OWN configuration -- the burden
  # backwards, and exactly what disko #441 and home-manager #5870 are.
  #
  # Evaluating at all is most of the proof: a priority clash is an evaluation
  # error, so a regression here does not produce a wrong value, it produces a
  # configuration that will not build. Reading the value back checks the other
  # half, that ours yielded rather than merely tying.
  syncthingBeside = configBeside {
    programs.nixarchy = {
      user = "someone";
      services.syncthing.enable = true;
    };
    # What the user already had, at ordinary priority.
    services.syncthing.dataDir = "/srv/sync";
  };

  # The same hazard for the module that bundles Ollama (#96). Worth its own
  # case rather than trusting the syncthing one: local-ai sets four upstream
  # scalars, and the two options it deliberately leaves at plain priority --
  # loadModels and environmentVariables -- merge, so a well-meant mkDefault
  # there would drop our contribution the moment the user names one of their
  # own. Reading the port back proves the scalars yield; reading the resolved
  # endpoint proves the agents follow the server to the port that won, rather
  # than dialling the one we asked for and nobody is listening on.
  ollamaBeside = configBeside {
    programs.nixarchy.localAi = {
      enable = true;
      allowCpu = true;
    };
    # What the user already had, at ordinary priority.
    services.ollama.port = 21434;
  };

  # And the group the desktop user gets, which is the other half of #92: docker
  # is enabled for every machine at nixos.nix:705 and was usable only on
  # machines the installer built.
  dockerGroups =
    (configBeside { programs.nixarchy.user = "someone"; }).users.users.someone.extraGroups;

  # ---- "nixarchy wrote this machine", both ways -------------------------
  #
  # The armed commands -- nixarchy-config-repo, and the post-boot hook that
  # offers it -- commit a configuration, choose whether it is public and push
  # it somewhere. On a machine nixarchy built that is the whole point. On a
  # machine where somebody imported nixosModules.nixarchy into a configuration
  # of their own, it is nixarchy publishing a repository it does not own.
  #
  # The predicate is /etc/nixarchy/managed, written only where
  # programs.nixarchy.installerManaged is set, which is only in
  # installer/host.nix. So the off case is a plain nixosSystem importing the
  # module -- Mode A, exactly the machine that must not get it -- and the on
  # case is the reference host, which imports that file.
  #
  # The off case is the one that breaks quietly: a marker that arrives for
  # everybody makes every gate below it read as passing, and nothing says so.
  managedModeA = (configWith { }).environment.etc ? "nixarchy/managed";

  # ---- and the factory-reset unit, the same question in its sharpest form ---
  #
  # nixarchy-factory-reset.service renames a person's entire home directory.
  # It lives in installer/host.nix rather than in the module precisely so that
  # a Mode A machine cannot have it -- there is no @factory on a disk nixarchy
  # did not lay out, and a unit that goes looking for one on somebody else's
  # filesystem is the worst thing in this repository to get wrong.
  #
  # Structural, not conditional: the off case here is not "the option is
  # false", it is "the module does not define the unit at all". That is what
  # this asserts, because a later refactor that moved the unit into
  # modules/nixos.nix behind an `installerManaged` mkIf would still read as
  # correct in review and would be one typo away from arming every machine.
  factoryUnitModeA = (configWith { }).systemd.services ? nixarchy-factory-reset;

  # ---- enabling a custom remote must not remove Flathub ----
  #
  # nix-flatpak's `remotes` defaults to a list holding only Flathub, and it is
  # a plain default: setting it REPLACES that list rather than adding to it.
  # GeForce NOW comes from NVIDIA's own repository, so enabling it sets the
  # option -- and a module that wrote `remotes = [ nvidia ]` would take
  # Flathub off the machine.
  #
  # Nothing would say so. Flatpaks already installed from Flathub keep
  # working, and the next one simply cannot be found. That is why this is a
  # check and not a comment.
  flatpakRemotes =
    let
      c = configWith { flatpaks.apps.geforce-now.enable = true; };
    in
    map (r: r.name) c.services.flatpak.remotes;

  # ---- the flatpak catalogue, same discipline ----
  flatpaks = import ../data/flatpaks.nix;

  flatpakProblems = pkgs.lib.flatten (
    pkgs.lib.mapAttrsToList (
      id: fp:
      let
        need = field: cond: pkgs.lib.optional (!cond) "  ${id}: ${field}";
      in
      [
        (need "no label" (fp ? label && fp.label != ""))
        (need "no category" (fp ? category && fp.category != ""))
        (need "no appId" (fp ? appId && fp.appId != ""))
        # The predictable mistake is writing a package name where an
        # application id belongs -- `bottles` instead of
        # `com.usebottles.bottles`. It fails at install time on the user's
        # machine, which is the wrong place to find out, and the shape is
        # cheap to check: Flathub ids are reverse-DNS and always contain a dot.
        (need "appId is not reverse-DNS (needs at least two dots)" (
          (fp.appId or "") == "" || builtins.length (pkgs.lib.splitString "." (fp.appId or "")) >= 3
        ))
        # Every entry has to answer "why can nixpkgs not carry this", because
        # that question is the whole reason the file exists. An entry without
        # a note has not been asked it.
        (need "no note saying why nixpkgs cannot carry it" (fp ? note && fp.note != ""))
        # A remote is a name AND a location. Half of one silently means the
        # app is looked for on Flathub, which for an entry that named a remote
        # is exactly where it is not -- and the failure lands on the user's
        # machine at install time rather than here.
        (need "remote needs both name and location" (
          !(fp ? remote) || ((fp.remote ? name) && (fp.remote ? location))
        ))
        (need "remote location must be a .flatpakrepo URL" (
          !(fp ? remote)
          || (
            pkgs.lib.hasPrefix "https://" (fp.remote.location or "")
            && pkgs.lib.hasSuffix ".flatpakrepo" (fp.remote.location or "")
          )
        ))
      ]
    ) flatpaks
  );

  # ---- the services catalogue is shaped the way the generator expects ----
  #
  # data/apps.nix has no schema check at all: it is read with `app ? field`
  # and a missing field simply produces a row nobody notices is wrong. That is
  # tolerable for a file one person edits rarely and not for a catalogue meant
  # to grow, so this one is checked.
  #
  # What is NOT checked here: that a bundled entry has a module in
  # modules/services/. Those modules do not exist yet, and an assertion that
  # fails until they do would mean this file cannot land before them.
  services = import ../data/services.nix;

  serviceProblems = pkgs.lib.flatten (
    pkgs.lib.mapAttrsToList (
      id: svc:
      let
        need = field: cond: pkgs.lib.optional (!cond) "  ${id}: ${field}";
      in
      [
        (need "no label" (svc ? label && svc.label != ""))
        (need "no category" (svc ? category && svc.category != ""))
        (need "kind must be \"plain\" or \"bundled\"" (
          svc ? kind
          && builtins.elem svc.kind [
            "plain"
            "bundled"
          ]
        ))
        # A plain entry IS its option path -- the whole point is that the real
        # upstream line lands in the user's file rather than an alias. Without
        # the path there is no line to write.
        (need "kind=plain needs an option path" (
          (svc.kind or "") != "plain" || (svc ? option && svc.option != [ ])
        ))
        # And a bundled entry must not carry one, because its module decides
        # what to set. A stray path here reads as though it were honoured.
        (need "kind=bundled must not set option; its module decides" (
          (svc.kind or "") != "bundled" || !(svc ? option)
        ))
        # The note is where the teaching happens. An entry without one is a
        # row that says what a thing is called and nothing about what turning
        # it on costs.
        (need "no note" (svc ? note && svc.note != ""))
        # #91 could not assert this: modules/services/ did not exist. It does
        # now, and without this a bundled entry generates a template line for
        # an option nobody declared -- which fails only when a user uncomments
        # it, which is the worst moment to find out.
        (need "kind=bundled needs modules/services/${id}.nix" (
          (svc.kind or "") != "bundled" || builtins.pathExists ../modules/services/${id}.nix
        ))
      ]
    ) services
  );

  broken = pkgs.lib.filterAttrs (_: c: !(c.on && !c.off)) cases;

  report = pkgs.lib.concatStringsSep "\n" (
    pkgs.lib.mapAttrsToList (
      name: c: "  ${name}: on=${builtins.toString c.on} off=${builtins.toString c.off}"
    ) cases
  );
in
pkgs.runCommand "nixarchy-options"
  {
    inherit report;
    inherit menuFile vm;
    omarchyPath = "${(pkgs.extend inputs.self.overlays.default).omarchy}/share/omarchy";
    # The menu the shell actually renders on this machine, which is NOT the
    # package's own: modules/apps.nix rewrites the rows that would run pacman
    # and points OMARCHY_PATH at a mirrored tree carrying the result (#210).
    # Every row nixarchy adds -- Search, Roll back, Back up configuration, the
    # two home-backup rows, App removal -- exists only in this file, so a
    # command check pointed at the package's menu could never see one of them.
    treeMenu = "${inputs.self.nixosConfigurations.vm.config.programs.nixarchy.tree}/default/omarchy/omarchy-menu.jsonc";
    mapped = pkgs.lib.concatStringsSep " " mappedRows;
    serviceProblems = pkgs.lib.concatStringsSep "\n" serviceProblems;
    flatpakProblems = pkgs.lib.concatStringsSep "\n" flatpakProblems;
    microvmProblems = pkgs.lib.concatStringsSep "\n" microvmProblems;
    flatpakCount = builtins.toString (builtins.length (builtins.attrNames flatpaks));
    flatpakRemotes = pkgs.lib.concatStringsSep " " flatpakRemotes;
    fleetOff = pkgs.lib.boolToString fleet.offByDefault;
    fleetOn = pkgs.lib.boolToString fleet.onWhenAsked;
    fleetUrl = fleet.url;
    fleetPersistent = pkgs.lib.boolToString fleet.persistent;
    fleetOnFailure = fleet.onFailure;
    flatpakOurs = pkgs.lib.boolToString flatpakDefaults.ours;
    flatpakTheirs = pkgs.lib.boolToString flatpakDefaults.theirs;
    flatpakOn = pkgs.lib.boolToString flatpakDefaults.onWhenAsked;
    # The two strings the unit is made of. Both carry store-path context, so
    # naming them here is what makes the guard derivation an input of this
    # check and therefore something the script below can actually run.
    rdpGuard = (rdpUnitOf rdpOn).ExecStartPre or "";
    rdpExecStart = (rdpUnitOf rdpOn).ExecStart;
    rdpConditionUser = rdpOn.systemd.user.services.hypr-rdp.unitConfig.ConditionUser;
    # The template as it exists in the store -- the file a `grep -r password`
    # over everything nixarchy generated would find.
    rdpTemplateFile = rdpOn.sops.templates."hypr-rdp.toml".file;
    syncthingDataDir = syncthingBeside.services.syncthing.dataDir;
    ollamaPort = builtins.toString ollamaBeside.services.ollama.port;
    ollamaEndpoint = ollamaBeside.programs.nixarchy.localAi.resolved.endpoint;
    dockerGroups = pkgs.lib.concatStringsSep " " dockerGroups;
    managedModeA = pkgs.lib.boolToString managedModeA;
    factoryUnitModeA = pkgs.lib.boolToString factoryUnitModeA;
    # The factory-reset script, run rather than read. Every branch of it is
    # reachable from here -- see the block that uses it for why that needed a
    # fake `btrfs` and what it buys.
    factoryReset = "${(pkgs.extend inputs.self.overlays.default).omarchy}/bin/omarchy-system-factory-reset";
    devenvOffPackage = pkgs.lib.boolToString (hasDevenv devenvOff);
    devenvOffBash = pkgs.lib.boolToString (hookIn devenvOff.programs.bash.interactiveShellInit);
    devenvOffZsh = pkgs.lib.boolToString (hookIn devenvOff.programs.zsh.interactiveShellInit);
    devenvOffFish = pkgs.lib.boolToString (hookIn devenvOff.programs.fish.interactiveShellInit);
    devenvOffCache = pkgs.lib.boolToString (hasCache devenvOff);
    devenvOnPackage = pkgs.lib.boolToString (hasDevenv devenvOn);
    devenvOnBash = pkgs.lib.boolToString (hookIn devenvOn.programs.bash.interactiveShellInit);
    devenvOnZsh = pkgs.lib.boolToString (hookIn devenvOn.programs.zsh.interactiveShellInit);
    devenvOnFish = pkgs.lib.boolToString (hookIn devenvOn.programs.fish.interactiveShellInit);
    devenvOnCache = pkgs.lib.boolToString (hasCache devenvOn);
    devenvOnKey = pkgs.lib.boolToString (
      builtins.elem "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=" devenvOn.nix.settings.trusted-public-keys
    );
    # The Omarchy rc chain still has to be there beside ours -- programs.bash
    # .interactiveShellInit is a merging type, and a mkDefault on it would drop
    # one of the two silently.
    devenvOnOmarchyChain = pkgs.lib.boolToString (
      pkgs.lib.hasInfix "default/bash/rc" devenvOn.programs.bash.interactiveShellInit
    );
    sopsOffUnit = pkgs.lib.boolToString (sopsOff.systemd.services ? sops-install-secrets);
    sopsOffActivation = pkgs.lib.boolToString (sopsOff.system.activationScripts ? setupSecrets);
    sopsOffSecrets = pkgs.lib.boolToString (sopsOff.sops.secrets == { });
    sopsOffTemplates = pkgs.lib.boolToString (sopsOff.sops.templates == { });
    sopsOnActive = pkgs.lib.boolToString (hasSops sopsOn);
    devenvNoCacheCache = pkgs.lib.boolToString (hasCache devenvNoCache);
    devenvNoCachePackage = pkgs.lib.boolToString (hasDevenv devenvNoCache);
    boxesOffPodman = pkgs.lib.boolToString boxesOff.virtualisation.podman.enable;
    boxesOffContainers = pkgs.lib.boolToString (
      (homeOfBoxes boxesOff).programs.distrobox.containers == { }
    );
    boxesOffUnit = pkgs.lib.boolToString (
      (homeOfBoxes boxesOff).systemd.user.services ? distrobox-home-manager
    );
    boxesOffSystemPkg = pkgs.lib.boolToString (hasDistrobox boxesOff.environment.systemPackages);
    boxesOffHomePkg = pkgs.lib.boolToString (hasDistrobox (homeOfBoxes boxesOff).home.packages);
    boxesOnPodman = pkgs.lib.boolToString boxesOn.virtualisation.podman.enable;
    boxesOnContainers = pkgs.lib.boolToString (
      (homeOfBoxes boxesOn).programs.distrobox.containers ? dev
    );
    boxesOnImage = (homeOfBoxes boxesOn).programs.distrobox.containers.dev.image or "";
    boxesOnUnit = pkgs.lib.boolToString (
      (homeOfBoxes boxesOn).systemd.user.services ? distrobox-home-manager
    );
    boxesOnSystemPkg = pkgs.lib.boolToString (hasDistrobox boxesOn.environment.systemPackages);
    boxesOnHomePkg = pkgs.lib.boolToString (hasDistrobox (homeOfBoxes boxesOn).home.packages);
    # The home-backup script, run rather than read. Its gate and its allowlist
    # are the two things this issue actually promises, and both are answerable
    # by executing it -- --check and --list exist partly for that reason and
    # partly because the menu rows' `when:` calls the first of them.
    homeBackup = "${(pkgs.extend inputs.self.overlays.default).omarchy}/bin/nixarchy-home-backup";
    splashInstalledDir = splashPaths installedSplash;
    splashInstalledOn = pkgs.lib.boolToString installedSplash.boot.plymouth.enable;
    splashInstalledTheme = installedSplash.boot.plymouth.theme;
    splashIsoDir = splashPaths isoSplash;
    splashIsoOn = pkgs.lib.boolToString isoSplash.boot.plymouth.enable;
    splashIsoTheme = isoSplash.boot.plymouth.theme;
    # What the assets are measured against. The vendored tree, at the version
    # this flake pins -- so a bump that changes an asset changes what "still
    # upstream's" means, which is the point.
    splashUpstream = "${(pkgs.extend inputs.self.overlays.default).omarchy.src}/default/plymouth";
    serviceCount = builtins.toString (builtins.length (builtins.attrNames services));
    notApps = pkgs.lib.concatStringsSep " " notApps;
    nativeBuildInputs = [ pkgs.python3 ];
  }
  (
    if flatpakProblems != [ ] then
      ''
        echo "data/flatpaks.nix has entries the generator cannot use:" >&2
        echo "$flatpakProblems" >&2
        exit 1
      ''
    else if serviceProblems != [ ] then
      ''
        echo "data/services.nix has entries the generator cannot use:" >&2
        echo "$serviceProblems" >&2
        exit 1
      ''
    else if microvmProblems != [ ] then
      ''
        echo "the microvm closure invariant does not hold:" >&2
        echo "$microvmProblems" >&2
        exit 1
      ''
    else if broken == { } then
      ''
          echo "$report"
          echo "the services catalogue is well formed ($serviceCount entries)"
          echo "the flatpak catalogue is well formed ($flatpakCount entries)"

          # ---- Flathub survives a custom remote ---------------------------
          case " $flatpakRemotes " in
            *" flathub "*) ;;
            *) echo "enabling a flatpak from another remote removed flathub:" >&2
               echo "  remotes = $flatpakRemotes" >&2
               echo "nix-flatpak's remotes option replaces rather than appends." >&2
               exit 1 ;;
          esac
          case " $flatpakRemotes " in
            *" GeForceNOW "*) ;;
            *) echo "the entry's own remote was not declared: $flatpakRemotes" >&2
               exit 1 ;;
          esac
          echo "a flatpak from another remote keeps flathub ($flatpakRemotes)"

          # ---- flatpaks are not removed unless asked ---------------------
          if [ "$flatpakOurs" != "false" ] || [ "$flatpakTheirs" != "false" ]; then
            echo "uninstallUnmanaged defaults to on." >&2
            echo "  programs.nixarchy.flatpaks.uninstallUnmanaged = $flatpakOurs" >&2
            echo "  services.flatpak.uninstallUnmanaged          = $flatpakTheirs" >&2
            echo "That deletes Flatpaks a person installed themselves." >&2
            exit 1
          fi
          [ "$flatpakOn" = "true" ] || {
            echo "asking for uninstallUnmanaged does not turn it on" >&2
            exit 1
          }
          echo "flatpaks are left alone unless the machine's owner asks"

          # ---- hypr-rdp refuses, at both layers -------------------------
          #
          # Upstream does not refuse: given an empty password it logs a
          # warning and serves the desktop. Everything here is checking that
          # this repo does instead.

          # 1. The password is never on a command line. /proc/*/cmdline is
          #    world-readable, so `-p` would hand it to every process on the
          #    machine -- which is exactly why the config file exists.
          case "$rdpExecStart" in
            *" -p "*|*"--password"*)
              echo "the RDP password is passed on the command line:" >&2
              echo "  $rdpExecStart" >&2
              echo "/proc/*/cmdline is world-readable. Render it into the" >&2
              echo "config file instead." >&2
              exit 1 ;;
          esac
          case "$rdpExecStart" in
            *"--config "*) ;;
            *) echo "hypr-rdp is not pointed at the rendered config:" >&2
               echo "  $rdpExecStart" >&2
               echo "Without --config it reads ~/.config/hypr-rdp/config.toml," >&2
               echo "tolerates its absence, and serves unauthenticated." >&2
               exit 1 ;;
          esac
          echo "hypr-rdp is given a config file and never a password argument"

          # 2. No cleartext in the store. The template is a store file; what
          #    belongs in it is sops-nix's placeholder, which is replaced at
          #    activation into /run.
          grep -q '^password = "<SOPS:' "$rdpTemplateFile" || {
            echo "the rendered template does not carry a sops placeholder:" >&2
            sed 's/^password = .*/password = <REDACTED BY THIS CHECK>/' \
              "$rdpTemplateFile" >&2
            echo "Whatever is in the password field is in the world-readable" >&2
            echo "Nix store." >&2
            exit 1
          }
          echo "the config template holds a sops placeholder, not a password"

          # 3. The unit belongs to one user. systemd.user.services is declared
          #    for everybody; the rendered file is 0400 to one account.
          [ "$rdpConditionUser" = "someone" ] || {
            echo "the RDP unit is not conditioned on its user:" >&2
            echo "  ConditionUser = $rdpConditionUser" >&2
            exit 1
          }

          # 4. The runtime refusal, RUN rather than read. This is the layer an
          #    assertion cannot reach: a secret that exists and renders empty,
          #    or a template sops-nix failed to write, both evaluate fine and
          #    would otherwise start a daemon that answers.
          guard=''${rdpGuard%% *}
          test -n "$guard" || {
            echo "the RDP unit has no ExecStartPre." >&2
            echo "Nothing checks the rendered config before hypr-rdp reads it," >&2
            echo "and hypr-rdp itself does not check: an empty password gets a" >&2
            echo "warning in the journal and a desktop on the network." >&2
            exit 1
          }
          test -x "$guard" || { echo "no guard at $guard" >&2; exit 1; }

          good=$PWD/good.toml
          printf 'bind = "127.0.0.1:3389"\nusername = "nixarchy"\npassword = "s3cret"\n' > "$good"
          "$guard" "$good" || {
            echo "the guard rejected a config that has a password." >&2
            echo "A guard that refuses everything is a service nobody can run." >&2
            exit 1
          }

          empty=$PWD/empty-password.toml
          printf 'bind = "127.0.0.1:3389"\nusername = "nixarchy"\npassword = ""\n' > "$empty"
          if "$guard" "$empty" 2>/dev/null; then
            echo "the guard accepted an EMPTY password." >&2
            echo "That is the exact state upstream turns into an" >&2
            echo "unauthenticated remote desktop: config.rs unwrap_or_default()" >&2
            echo "warns and serves." >&2
            exit 1
          fi

          nouser=$PWD/no-username.toml
          printf 'bind = "127.0.0.1:3389"\npassword = "s3cret"\n' > "$nouser"
          if "$guard" "$nouser" 2>/dev/null; then
            echo "the guard accepted a config with no username." >&2
            exit 1
          fi

          if "$guard" "$PWD/not-here.toml" 2>/dev/null; then
            echo "the guard accepted a config file that does not exist." >&2
            echo "An unrendered template must fail the unit, not start it." >&2
            exit 1
          fi
          echo "the RDP unit refuses to start without a password in its config"

          # ---- composition: the user's definition wins -------------------
          [ "$syncthingDataDir" = "/srv/sync" ] || {
            echo "a bundled service overrode a value the user had already set:" >&2
            echo "  services.syncthing.dataDir is $syncthingDataDir, not /srv/sync" >&2
            echo "every scalar a service module sets must be lib.mkDefault." >&2
            exit 1
          }
          echo "a bundled service yields to configuration the user already had"

          [ "$ollamaPort" = "21434" ] || {
            echo "local-ai overrode a port the user had already set:" >&2
            echo "  services.ollama.port is $ollamaPort, not 21434" >&2
            echo "enable, package, host and port must all be lib.mkDefault." >&2
            exit 1
          }
          [ "$ollamaEndpoint" = "http://127.0.0.1:21434/v1" ] || {
            echo "the agents were pointed somewhere the server is not:" >&2
            echo "  endpoint is $ollamaEndpoint, not http://127.0.0.1:21434/v1" >&2
            exit 1
          }
          echo "local-ai yields the Ollama port and the agents follow it"

          case " $dockerGroups " in
            *" docker "*) echo "the desktop user can reach the docker socket" ;;
            *) echo "docker is enabled but the desktop user is not in its group" >&2
               echo "groups: $dockerGroups" >&2
               exit 1 ;;
          esac

          # ---- no Omarchy artwork on either boot splash -------------------
          #
          # The list of images is read out of omarchy.script rather than
          # written down here. What the acceptance is about is what is DRAWN,
          # and a written list cannot notice an upstream bump that starts
          # drawing a sixth file -- which is precisely how this regresses,
          # since every branded asset is a copy of a file upstream also ships.
          #
          # logos/oma.png is the one file left as upstream's, because nothing
          # draws it. That is not asserted separately: if a bump ever draws it,
          # it joins this list and fails here.
          splash_is_ours() {
            where=$1
            dir=$2
            enabled=$3
            theme=$4

            [ "$enabled" = "true" ] || {
              echo "$where: boot.plymouth.enable is $enabled" >&2
              echo "  the splash this issue is about is not on." >&2
              exit 1
            }
            [ "$theme" = "omarchy" ] || {
              echo "$where: boot.plymouth.theme is '$theme', not omarchy" >&2
              echo "  the machine boots a theme this repo does not draw." >&2
              exit 1
            }
            grep -qx 'Name=nixarchy' "$dir/omarchy.plymouth" || {
              echo "$where: the theme still calls itself:" >&2
              grep -h '^Name=' "$dir/omarchy.plymouth" >&2
              echo "  plymouth-set-default-theme --list and omarchy-plymouth-current" >&2
              echo "  both report this name." >&2
              exit 1
            }

            drawn=$(sed -n 's/.*Image("\([^"]*\)").*/\1/p' "$dir/omarchy.script" | sort -u)
            [ -n "$drawn" ] || {
              echo "$where: omarchy.script draws no images at all" >&2
              echo "  either the script changed shape or this check stopped" >&2
              echo "  being able to see what it draws -- which is worse." >&2
              exit 1
            }

            n=0
            for img in $drawn; do
              n=$((n + 1))
              test -e "$dir/$img" || {
                echo "$where: the splash draws $img and the theme has no such file" >&2
                exit 1
              }
              if cmp -s "$dir/$img" "$splashUpstream/$img"; then
                echo "$where: $img is byte-for-byte upstream's file" >&2
                echo "  #46's acceptance is that no Omarchy artwork is reachable" >&2
                echo "  from the ISO or the installed boot splash. This is." >&2
                echo "  It is drawn by $dir/omarchy.script." >&2
                exit 1
              fi
            done
            # The animation is invisible to the scrape above: the script names
            # its frames by building the string, Image("frame-" + i + ".png"),
            # so sed sees nothing to pull out and 33 files could go missing
            # without a word. What the script declares and what the theme ships
            # are checked against each other instead.
            frames=$(sed -n 's/^global\.frame_count = \([0-9]*\);.*/\1/p' \
              "$dir/omarchy.script")
            case "$frames" in
              "" | 0)
                echo "$where: the splash script declares no animation frames" >&2
                echo "  global.frame_count is what it plays; without it the" >&2
                echo "  wordmark is a still again." >&2
                exit 1
                ;;
            esac
            # ls rather than find: $dir is a symlink into the theme package, and
            # find does not descend one unless told to.
            shipped=$(ls "$dir"/frame-*.png 2>/dev/null | wc -l)
            [ "$shipped" = "$frames" ] || {
              echo "$where: the script plays $frames frames, the theme ships $shipped" >&2
              echo "  a missing frame is a blank sprite mid-animation." >&2
              exit 1
            }

            echo "$where: splash is nixarchy's, all $n images it draws are ours,"
            echo "$where: and its $frames animation frames are all present"
          }

          splash_is_ours installed "$splashInstalledDir" \
            "$splashInstalledOn" "$splashInstalledTheme"
          splash_is_ours iso "$splashIsoDir" "$splashIsoOn" "$splashIsoTheme"

          # ---- nixarchy only commits a configuration it wrote --------------
          #
          # Three assertions, and the first is the one that matters. A Mode A
          # machine -- somebody's own configuration, with nixosModules.nixarchy
          # imported into it -- must not carry the marker, because everything
          # downstream reads its presence as permission to commit and push
          # /etc/nixos to a remote of nixarchy's choosing.
          [ "$managedModeA" = "false" ] || {
            echo "importing nixosModules.nixarchy wrote /etc/nixarchy/managed." >&2
            echo "  That file means 'nixarchy wrote this machine', and it is what" >&2
            echo "  nixarchy-config-repo and the post-boot nudge gate on. On a" >&2
            echo "  configuration somebody else wrote, it makes nixarchy offer to" >&2
            echo "  commit and push a repository that is not its to publish." >&2
            echo "  Only installer/host.nix may set programs.nixarchy.installerManaged." >&2
            exit 1
          }

          # And the other way: the reference host imports installer/host.nix,
          # so it must. A gate nothing ever passes is a command nobody can run.
          test -e "$vm/etc/nixarchy/managed" || {
            echo "the installed reference host has no /etc/nixarchy/managed" >&2
            echo "  installer/host.nix sets programs.nixarchy.installerManaged;" >&2
            echo "  without the file every armed command refuses the machines" >&2
            echo "  nixarchy itself built." >&2
            exit 1
          }
          echo "the ownership marker reaches the installed host and no one else"

          # The coupling, which neither of the above can see: the marker could
          # be perfect and the command could still never look at it. Both the
          # refusal and the --check the post-boot hook calls are in this one
          # script, so this is where a missing gate would show.
          #
          # Comments stripped first. The path is named in the prose above the
          # gate as well as in the gate, and a check that a file mentions
          # something in a comment is not a check.
          grep -v '^[[:space:]]*#' "$vm/sw/bin/nixarchy-config-repo" \
            | grep -q '/etc/nixarchy/managed' || {
            echo "nixarchy-config-repo does not consult /etc/nixarchy/managed" >&2
            echo "  Its only gate would then be consent, not ownership." >&2
            exit 1
          }

          # Run it. The build sandbox has no /etc/nixarchy/managed, which makes
          # it exactly the unowned machine, and the refusal has to be an exit
          # code as well as a paragraph -- the post-boot hook reads --check's
          # status and nothing else.
          if "$vm/sw/bin/nixarchy-config-repo" >refusal 2>&1; then
            echo "nixarchy-config-repo succeeded on a machine nixarchy did not write:" >&2
            cat refusal >&2
            exit 1
          fi
          grep -qi "not one Nixarchy wrote" refusal || {
            echo "the refusal does not say why it refused:" >&2
            cat refusal >&2
            exit 1
          }
          grep -q "nixos-config-repo" refusal || {
            echo "the refusal names no way for the user to do it themselves" >&2
            cat refusal >&2
            exit 1
          }
          if "$vm/sw/bin/nixarchy-config-repo" --check >check 2>&1; then
            echo "--check asked for a nudge on a machine nixarchy did not write" >&2
            cat check >&2
            exit 1
          fi
          test ! -s check || {
            echo "--check is documented as printing nothing; it printed:" >&2
            cat check >&2
            exit 1
          }
          echo "on an unowned machine it refuses, says why, and nudges nobody"

          # ---- and a way to reach it that is not a notification ------------
          #
          # The command was reachable by nudge or by knowing its name, which
          # makes "I changed things, is that backed up?" a question with no
          # answer in the interface. The row is also the drift path's front
          # door: running it on an armed repository is what commits and pushes
          # what has piled up since.
          row=$(sed -n '/"system.backup"/,/^  }/p' "$vm/etc/nixarchy/omarchy-menu.jsonc")
          test -n "$row" || {
            echo "the menu has no System > Back up configuration row" >&2
            echo "  nixarchy-config-repo is then reachable only by acting on a" >&2
            echo "  notification, or by knowing the command's name." >&2
            exit 1
          }
          case "$row" in
            *nixarchy-config-repo*) ;;
            *) echo "the backup row does not call nixarchy-config-repo:" >&2
               echo "$row" >&2; exit 1 ;;
          esac
          # Same predicate as the command's own, or the row draws on machines
          # where choosing it can only produce the refusal above.
          case "$row" in
            */etc/nixarchy/managed*) ;;
            *) echo "the backup row is not gated on ownership:" >&2
               echo "$row" >&2
               echo "  on a machine nixarchy did not write it would render, and" >&2
               echo "  clicking it would only ever print a refusal." >&2
               exit 1 ;;
          esac
          echo "the menu reaches it, on the machines where it can work"

          # ---- devenv: nothing at all until it is asked for ---------------
          for pair in "package:$devenvOffPackage" "bash hook:$devenvOffBash" \
            "zsh hook:$devenvOffZsh" "fish hook:$devenvOffFish" \
            "substituter:$devenvOffCache"; do
            if [ "''${pair#*:}" != "false" ]; then
              echo "devenv is off, but its ''${pair%%:*} is on the machine anyway." >&2
              echo "A configuration that never selects devenv must gain nothing." >&2
              exit 1
            fi
          done
          echo "devenv adds no package, no hook and no substituter until selected"

          # ---- and everything once it is ----------------------------------
          for pair in "package:$devenvOnPackage" "bash hook:$devenvOnBash" \
            "zsh hook:$devenvOnZsh" "fish hook:$devenvOnFish" \
            "substituter:$devenvOnCache" "public key:$devenvOnKey"; do
            if [ "''${pair#*:}" != "true" ]; then
              echo "devenv is enabled but its ''${pair%%:*} is missing." >&2
              exit 1
            fi
          done
          echo "devenv installs, hooks bash, zsh and fish, and trusts its cache"

          # A merging type, so ours composes rather than replaces. If this
          # fails the machine lost Omarchy's aliases and functions the moment
          # devenv was selected, and nothing else would have said so.
          [ "$devenvOnOmarchyChain" = "true" ] || {
            echo "selecting devenv displaced Omarchy's bash chain from /etc/bashrc" >&2
            exit 1
          }
          echo "the devenv hook composes with the shell chain rather than replacing it"

          # ---- declining caches is not undone by selecting devenv ---------
          [ "$devenvNoCacheCache" = "false" ] || {
            echo "binaryCaches = false, yet devenv added devenv.cachix.org." >&2
            echo "A substituter is trust, and it merges into the list with no" >&2
            echo "conflict and no warning -- which is why it must be asked for." >&2
            exit 1
          }
          [ "$devenvNoCachePackage" = "true" ] || {
            echo "declining the cache also removed devenv itself" >&2
            exit 1
          }
          echo "devenv respects binaryCaches = false and still installs"

          # ---- boxes: off adds nothing, anywhere ---------------------------
          for pair in "podman:$boxesOffPodman" "distrobox containers:$boxesOffContainers" \
            "distrobox unit:$boxesOffUnit" "distrobox in systemPackages:$boxesOffSystemPkg" \
            "distrobox in home.packages:$boxesOffHomePkg"; do
            case "''${pair%%:*}" in
              "distrobox containers") want=true ;;
              *) want=false ;;
            esac
            if [ "''${pair#*:}" != "$want" ]; then
              echo "services.boxes is off, but its ''${pair%%:*} says otherwise on the machine anyway." >&2
              echo "A configuration that never selects boxes must gain nothing -- neither on the" >&2
              echo "NixOS side (podman, distrobox in systemPackages) nor across into Home Manager" >&2
              echo "(distrobox.containers, its systemd unit, or a second copy in home.packages)." >&2
              exit 1
            fi
          done
          echo "boxes adds no podman, no distrobox and nothing in Home Manager until selected"

          # ---- boxes: on reaches Home Manager, and still refuses the unit --
          for pair in "podman:$boxesOnPodman" "distrobox containers:$boxesOnContainers" \
            "distrobox in systemPackages:$boxesOnSystemPkg"; do
            if [ "''${pair#*:}" != "true" ]; then
              echo "services.boxes is enabled with a machine declared, but its ''${pair%%:*} is missing." >&2
              exit 1
            fi
          done
          [ "$boxesOnImage" = "archlinux:latest" ] || {
            echo "the declared machine's image did not reach programs.distrobox.containers.dev:" >&2
            echo "got '$boxesOnImage'" >&2
            exit 1
          }
          echo "boxes on with one machine: podman, the package, and the container all land"

          # This is the row that matters most. Home Manager's OWN default for
          # enableSystemdUnit is `containers != { } && package != null` -- true
          # the instant a machine is declared -- so this has to prove the unit
          # is STILL absent, not merely that "off" produced nothing. Its
          # ExecStart bakes a literal /nix/store/... path
          # (the distrobox package's own /bin/distrobox-assemble) straight
          # into the unit file, the same
          # GC-survival hazard nixpkgs#478154 describes and modules/services/
          # boxes.nix already refuses for distrobox itself.
          for pair in "distrobox unit:$boxesOnUnit" "distrobox in home.packages:$boxesOnHomePkg"; do
            if [ "''${pair#*:}" != "false" ]; then
              echo "services.boxes is enabled, but its ''${pair%%:*} is present anyway." >&2
              echo "enableSystemdUnit must stay refused: its ExecStart bakes a literal" >&2
              echo "/nix/store/... path into the unit, the same hazard distrobox itself is" >&2
              echo "never allowed to be reached through (nixpkgs#478154)." >&2
              exit 1
            fi
          done
          echo "boxes on still refuses Home Manager's own systemd unit, and installs distrobox once"

          # ---- sops-nix: imported by everyone, inert until asked --------
          for pair in "systemd unit:$sopsOffUnit" "activation script:$sopsOffActivation"; do
            if [ "''${pair#*:}" != "false" ]; then
              echo "no secret is declared, yet sops-nix put a ''${pair%%:*} on the machine." >&2
              echo "Importing the module must cost a Mode A machine nothing. If an" >&2
              echo "upstream bump stopped gating on sops.secrets/sops.templates, this" >&2
              echo "is where that shows up -- do not fix it by removing the check." >&2
              exit 1
            fi
          done
          [ "$sopsOffSecrets" = "true" ] && [ "$sopsOffTemplates" = "true" ] || {
            echo "nixarchy declared a sops secret or template of its own." >&2
            echo "It must declare neither: the mechanism exists for the modules" >&2
            echo "that opt into it, not for every machine that imports nixarchy." >&2
            exit 1
          }
          [ "$sopsOnActive" = "true" ] || {
            echo "declaring a sops secret produced no activation path at all," >&2
            echo "so the inertness checked above is an import that never worked." >&2
            exit 1
          }
          echo "sops-nix is imported, declares nothing, and works when asked"

          echo "every option adds what it should and removes it again"

          python3 ${./coverage.py}

        # ---- the lock screen has a PAM stack ------------------------------
        # Omarchy 4.x's lock screen is quickshell-native and reads
        # /etc/pam.d/omarchy-lock-password. This module used to declare
        # security.pam.services.hyprlock instead -- PAM for a program the
        # desktop no longer runs -- so `omarchy-shell lock lock` answered
        # "missing-pam" and the screen stayed unlocked, on a real laptop,
        # through the keybinding, the menu, idle, lid close and suspend.
        test -e "$vm/etc/pam.d/omarchy-lock-password" || {
          echo "no /etc/pam.d/omarchy-lock-password: the lock screen cannot authenticate" >&2
          exit 1
        }
        grep -q 'pam_unix.so' "$vm/etc/pam.d/omarchy-lock-password" || {
          echo "the lock PAM stack has no pam_unix auth" >&2; exit 1; }
        if [ -e "$vm/etc/pam.d/hyprlock" ]; then
          echo "still declaring PAM for hyprlock, which Omarchy 4 does not run" >&2
          exit 1
        fi
        echo "the lock screen has a PAM stack"

        # ---- printing is on, cups-browsed is not --------------------------
        # 4.0.2 dropped cups-browsed from base.packages and from the services
        # it enables -- "Harden CUPS printer discovery and administration".
        # NixOS defaults services.printing.browsed.enable to
        # services.avahi.enable, which this module sets, so the daemon
        # upstream removed kept running here by inheritance: as root, with no
        # hardening, creating queues from mDNS announcements. Asserted rather
        # than trusted, because the coupling lives in nixpkgs and a bump can
        # bring it back without touching a line of this repo.
        if [ -e "$vm/etc/systemd/system/cups-browsed.service" ]; then
          echo "cups-browsed is on the machine again -- upstream removed it in 4.0.2." >&2
          echo "It comes back through services.printing.browsed.enable, which" >&2
          echo "nixpkgs defaults to services.avahi.enable." >&2
          exit 1
        fi
        test -e "$vm/etc/systemd/system/cups.service" || {
          echo "printing is off entirely: browsed was meant to go, not CUPS" >&2
          exit 1
        }
        echo "printing is on and cups-browsed is not"

        # ---- the user units exist and name store paths --------------------
        # Upstream ships these under default/systemd/user, which is not a
        # systemd search path, so nothing ever loaded them: no lock before
        # suspend, no Bluetooth pairing agent, no crash watcher. Their
        # ExecStart lines are all /usr/bin/..., so declaring them is only half
        # the job -- the paths have to be real too.
        for unit in bt-agent omarchy-sleep-lock omarchy-crash-watch \
          omarchy-recover-internal-monitor; do
          test -e "$vm/etc/systemd/user/$unit.service" || {
            echo "$unit.service is not installed where systemd looks" >&2; exit 1; }
        done
        if grep -rl '/usr/bin/' "$vm/etc/systemd/user/"*.service >/dev/null 2>&1; then
          echo "a user unit still points at /usr/bin, which does not exist here:" >&2
          grep -rl '/usr/bin/' "$vm/etc/systemd/user/"*.service >&2
          exit 1
        fi
        test -e "$vm/etc/systemd/user/graphical-session.target.wants/omarchy-sleep-lock.service" || {
          echo "omarchy-sleep-lock is installed but never started" >&2; exit 1; }
        echo "the user units are installed, wanted, and name store paths"

        # ---- logind gives sleep-lock time to work -------------------------
        grep -q 'HandlePowerKey=ignore' "$vm/etc/systemd/logind.conf" || {
          echo "the power button still hard-poweroffs instead of opening the menu" >&2
          exit 1
        }
        grep -q 'InhibitDelayMaxSec=15' "$vm/etc/systemd/logind.conf" || {
          echo "no inhibit delay: sleep-lock may not secure the screen before suspend" >&2
          exit 1
        }
        echo "logind defers the power key and allows an inhibit delay"

        # ---- fonts resolve to Omarchy's, not nixpkgs' ---------------------
        grep -q 'JetBrainsMono Nerd Font' "$vm/etc/fonts/local.conf" 2>/dev/null || {
          echo "fontconfig does not pin Omarchy's monospace; fc-match answers Adwaita Mono" >&2
          exit 1
        }
        echo "fontconfig pins Omarchy's font choices"

        # ---- the two images are tellable apart -----------------------------
        #
        # Interpolated rather than grepped, because reading these forces the
        # ISO configurations to evaluate -- which is what makes the volumeID
        # assertions in installer/cd.nix fire at PR time. Nothing else here
        # evaluates them, and a release build finding it is a release too
        # late.
        #
        # They were identical once: same filename, same label, for a 5.6 GB
        # image and a 1.5 GB one.
        isoName=${inputs.self.nixosConfigurations.iso.config.image.baseName}
        netName=${inputs.self.nixosConfigurations.iso-net.config.image.baseName}
        isoLabel=${inputs.self.nixosConfigurations.iso.config.isoImage.volumeID}
        netLabel=${inputs.self.nixosConfigurations.iso-net.config.isoImage.volumeID}
        test "$isoName" != "$netName" || {
          echo "both ISOs build to the same filename ($isoName): copy them out and they collide" >&2
          exit 1
        }
        test "$isoLabel" != "$netLabel" || {
          echo "both ISOs carry the same volume label ($isoLabel): two sticks, one name" >&2
          exit 1
        }
        case "$isoName" in
          *${inputs.self.packages.${system}.omarchy.version}*) ;;
          *) echo "the ISO filename does not carry the version: $isoName" >&2; exit 1 ;;
        esac
        echo "the two images are tellable apart by name and label ($isoLabel / $netLabel)"

        # ---- a flatpak is pickable, by the tooling that already exists ------
        #
        # The whole reason flatpaks went into services.nix rather than a fourth
        # file is that nixarchy-service-enable then handles them unchanged --
        # same #@ markers, and its "is the marked line live?" test is the one
        # that works for a line not beginning with the id.
        #
        # That makes two things silently coupled: the row has to be IN the
        # services template, and the menu row has to call service-enable. Move
        # flatpaks to their own file and the menu still renders, still looks
        # right, and answers "no service 'geforce-now'" when clicked. So assert
        # the coupling rather than trusting it.
        for id in ${toString (builtins.attrNames (import ../data/flatpaks.nix))}; do
          grep -qE "#@ $id([[:space:]]|$)" "$vm/etc/nixarchy/services-template.nix" || {
            echo "flatpak '$id' has no marked row in the services template:" >&2
            echo "  nixarchy-service-enable $id will fail, and the menu row calls exactly that" >&2
            exit 1
          }
          # And commented out to begin with -- a catalogue that installs itself
          # is not a catalogue.
          grep -qE "^[[:space:]]*#.*#@ $id([[:space:]]|$)" "$vm/etc/nixarchy/services-template.nix" || {
            echo "flatpak '$id' is live in the template: it would install unasked" >&2
            exit 1
          }
        done
        echo "every flatpak has a commented, marked row the existing tooling can enable"

        # ---- the picker's flatpak rows are ONE line each ---------------------
        #
        # The index is tab-separated, five fields, one row per line. The preview
        # field is prose and carries its newlines escaped for exactly that
        # reason. Write a real newline into it and the row silently becomes
        # several rows -- which the picker renders without complaint, as
        # unselectable nonsense between the real entries. That shipped once
        # during development and nothing but reading the file caught it.
        rows=$(sed -n 's/.*flatpakrows=\(\/nix\/store[^ ]*\).*/\1/p' "$vm/sw/bin/nixarchy-search" | head -1)
        test -n "$rows" || { echo "nixarchy-search names no flatpak rows file" >&2; exit 1; }
        bad=$(awk -F'\t' 'NF != 5 {print NR": "NF" fields"}' "$rows")
        if [ -n "$bad" ]; then
          echo "the picker's flatpak rows are not all five tab-separated fields:" >&2
          echo "$bad" >&2
          echo "  a real newline in the preview field splits one row into several" >&2
          exit 1
        fi
        awk -F'\t' '$1 != "flatpak" {print; exit 1}' "$rows" >/dev/null || {
          echo "a flatpak row does not carry the flatpak kind, so routing will miss it" >&2
          exit 1
        }
        echo "the picker's flatpak rows are $(wc -l < "$rows") well-formed lines"

        # ---- machines pull only when asked ---------------------------------
        test "$fleetOff" = false || {
          echo "system.autoUpgrade is on without programs.nixarchy.fleet.enable" >&2
          echo "  a machine that did not ask for a fleet must not acquire a timer:" >&2
          echo "  the next pull reverts anything under /etc/nixos that was not pushed" >&2
          exit 1
        }
        test "$fleetOn" = true || {
          echo "fleet.enable does not reach system.autoUpgrade; nothing would pull" >&2; exit 1; }
        test "$fleetUrl" = "github:me/config" || {
          echo "fleet.url did not reach system.autoUpgrade.flake: got '$fleetUrl'" >&2; exit 1; }
        test "$fleetPersistent" = true || {
          echo "the upgrade timer is not persistent; a laptop asleep at the hour never catches up" >&2
          exit 1
        }
        case "$fleetOnFailure" in
          *nixarchy-upgrade-failed*) ;;
          *)
            echo "nixos-upgrade has no OnFailure hook (got '$fleetOnFailure')" >&2
            echo "  an upgrade that starts failing stops delivering configuration and" >&2
            echo "  says nothing -- which is what this option exists to survive" >&2
            exit 1
            ;;
        esac
        echo "the fleet timer is off unless asked, and leaves a mark when it fails"

        # ---- the home half is backed up by an allowlist, and only on our own
        #      machines -------------------------------------------------------
        #
        # Everything a person customises about this desktop -- the bar layout,
        # the keybindings, the themes they made -- is seeded with `cp -rn` and
        # therefore lives outside every generation, outside Home Manager's
        # rollback and outside /etc/nixos. nixarchy-home-backup is the only
        # thing on the machine that gets it off the disk.

        test -e "$vm/sw/bin/nixarchy-home-backup" || {
          echo "nixarchy-home-backup is not on PATH; the menu rows call a command that is not there" >&2
          exit 1
        }

        # `cmp` decides, on restore, whether a file differs from the backup and
        # therefore whether the user's version is saved alongside. It comes
        # from diffutils, which is NOT in the omarchy package's runtimeDeps --
        # it is on PATH only because NixOS puts it in requiredPackages. Assert
        # that rather than trust it: without cmp every restore reports every
        # file as changed and litters $HOME with .bak copies of files that
        # never differed.
        test -e "$vm/sw/bin/cmp" || {
          echo "no cmp on the system path: nixarchy-home-backup restore cannot tell a changed file from an identical one" >&2
          exit 1
        }

        # ---- the ownership gate, both ways --------------------------------
        #
        # The epic's third done-criterion: every command refuses on a machine
        # nixarchy did not install. .nixarchy-url is written by
        # installer/mkFlake.nix and by nothing else, so its absence is
        # "somebody imported nixosModules.nixarchy into a config they own".
        gateHome=$TMPDIR/gate-home
        gateFlake=$TMPDIR/gate-flake
        mkdir -p "$gateHome" "$gateFlake"

        if HOME=$gateHome NIXARCHY_FLAKE=$gateFlake "$homeBackup" --check; then
          echo "nixarchy-home-backup --check passes with no .nixarchy-url in the flake" >&2
          echo "  the menu rows would appear, and the command would run, on a machine" >&2
          echo "  whose owner never asked nixarchy to manage their home directory" >&2
          exit 1
        fi
        if HOME=$gateHome NIXARCHY_FLAKE=$gateFlake "$homeBackup" >/dev/null 2>&1; then
          echo "nixarchy-home-backup ran on a machine with no ownership marker" >&2
          exit 1
        fi

        touch "$gateFlake/.nixarchy-url"
        HOME=$gateHome NIXARCHY_FLAKE=$gateFlake "$homeBackup" --check || {
          echo "nixarchy-home-backup --check refuses on a machine nixarchy DID install" >&2
          echo "  both menu rows would be permanently hidden" >&2
          exit 1
        }
        echo "nixarchy-home-backup refuses without the ownership marker, and runs with it"

        # ---- the allowlist is an allowlist ---------------------------------
        #
        # ~/.config holds gh's token, the agent credential files
        # nixarchy-config-repo's own agent_ready enumerates, and live browser
        # sessions. The entire design is "never ~/.config wholesale", and that
        # is one line away from being untrue at any time.
        allowlist=$(HOME=$gateHome NIXARCHY_FLAKE=$gateFlake "$homeBackup" --list)

        for want in .config/omarchy/shell.json .config/hypr/ \
          .config/omarchy/themes/ .local/state/omarchy/ \
          .config/omarchy/backup.list; do
          echo "$allowlist" | grep -qxF "$want" || {
            echo "the shipped allowlist no longer covers $want" >&2
            echo "$allowlist" >&2
            exit 1
          }
        done

        wholesale=$(echo "$allowlist" | grep -xE '\.|\.config/?|\.local/?|\.local/share/?|\.local/state/?' || true)
        if [ -n "$wholesale" ]; then
          echo "the allowlist has grown a wholesale home-directory entry:" >&2
          echo "$wholesale" >&2
          echo "  that is where the tokens are. The allowlist exists to not do this." >&2
          exit 1
        fi

        # The three things inside an allowlisted directory that must not
        # travel. clipboard-history.json is the sharpest: password managers
        # paste through the clipboard, and it sits inside
        # ~/.local/state/omarchy, which the epic asks for by name.
        for never in .local/state/omarchy/clipboard-history.json \
          .local/state/omarchy/current/theme/ \
          .local/state/omarchy/done/; do
          echo "$allowlist" | grep -qxF "!$never" || {
            echo "the allowlist no longer excludes $never" >&2
            exit 1
          }
        done
        echo "the allowlist names $(echo "$allowlist" | grep -cv '^!') paths and excludes $(echo "$allowlist" | grep -c '^!')"

        # ---- the menu rows exist, and are gated the same way ----------------
        #
        # A row whose `when` does not match the script's own gate is a row that
        # appears on a machine where clicking it prints a refusal.

        # ---- the factory baseline, and the reset that returns to it --------
        #
        # #172. The destructive half is a systemd unit that renames @home
        # before /home is mounted. Everything about it that can be established
        # without a btrfs filesystem is established here; that the restore
        # actually restores is proven in checks.install, on a real disk.

        # The ownership question, in its sharpest form. A Mode A machine must
        # not carry the unit AT ALL -- not disabled, not conditioned, absent.
        [ "$factoryUnitModeA" = "false" ] || {
          echo "importing nixosModules.nixarchy defined nixarchy-factory-reset.service." >&2
          echo "  That unit renames the whole of @home. A machine nixarchy did not" >&2
          echo "  install has no @factory to return to and no business carrying a" >&2
          echo "  unit that goes looking for one on somebody else's filesystem." >&2
          echo "  It belongs in installer/host.nix, which only generated flakes import." >&2
          exit 1
        }

        # And the other way: the reference host imports installer/host.nix, so
        # it must have it. Without the unit the reset stages a request file
        # nothing ever reads and reboots into an unchanged machine -- which
        # looks exactly like a reset that decided not to.
        unit=$vm/etc/systemd/system/nixarchy-factory-reset.service
        test -e "$unit" || {
          echo "the installed reference host has no nixarchy-factory-reset.service" >&2
          exit 1
        }

        # The two lines the whole design rests on.
        #
        # ConditionPathExists is the only thing between a booting machine and
        # a home-directory rename: without it the unit runs on every boot.
        grep -qx 'ConditionPathExists=/var/lib/nixarchy/factory-reset.request' "$unit" || {
          echo "nixarchy-factory-reset.service is not gated on the request file:" >&2
          grep -n 'Condition' "$unit" >&2 || echo "  (no Condition= at all)" >&2
          exit 1
        }

        # Before=home.mount BY NAME. Ordering against local-fs.target is not
        # enough and looks identical in review: home.mount is itself before
        # that target, and systemd leaves the order between two units that are
        # both Before= the same target unspecified. A restore that lands after
        # the mount renames a subvolume the kernel already holds open -- the
        # rename succeeds, the boot keeps showing the old /home, and the user
        # sees a reset that did nothing.
        sed -n 's/^Before=//p' "$unit" | tr ' ' '\n' | grep -qxF 'home.mount' || {
          echo "nixarchy-factory-reset.service is not ordered before home.mount:" >&2
          grep -n '^Before=' "$unit" >&2 || echo "  (no Before= at all)" >&2
          echo "  Before=local-fs.target is NOT the same claim." >&2
          exit 1
        }

        # The script asks `btrfs subvolume list -r` whether there is a
        # baseline. With no btrfs on PATH that question answers "no" on every
        # machine, including the ones that do have one -- a refusal that reads
        # exactly like the honest pre-#172 refusal and is a lie.
        test -e "$vm/sw/bin/btrfs" || {
          echo "no btrfs on the system path: omarchy-system-factory-reset cannot" >&2
          echo "  tell a machine with a baseline from one without, and answers" >&2
          echo "  'there is no factory snapshot' to both." >&2
          exit 1
        }

        # ---- every branch of the script, run --------------------------------
        #
        # The seam is NIXARCHY_BTRFS, which says which binary to ask. That is
        # a seam and not a test-only code path: the parsing, the requirement
        # that BOTH subvolumes are present, and the requirement that they are
        # read-only (the real script passes -r, and the fake only ever prints
        # what -r would) are the shipped ones. The alternative is a btrfs
        # filesystem, which means a VM, which means this could only be asked
        # in the 25-minute install check and only in the single state that
        # machine happens to be in.
        fr=$TMPDIR/factory
        mkdir -p "$fr/bin" "$fr/var"
        printf '#!/bin/sh\ncat "$FAKE_SUBVOLUMES"\n' >"$fr/bin/btrfs"
        chmod +x "$fr/bin/btrfs"

        marker=$fr/managed
        request=$fr/var/factory-reset.request
        subvols=$fr/subvols
        : >"$subvols"

        # 1. No ownership marker: refuse, whatever is on the disk.
        printf 'ID 256 gen 9 top level 5 path @factory\nID 257 gen 9 top level 5 path @factory-home\n' >"$subvols"
        if reset_out=$(env NIXARCHY_MANAGED_MARKER="$fr/absent" NIXARCHY_FACTORY_REQUEST="$request" \
                     NIXARCHY_BTRFS="$fr/bin/btrfs" FAKE_SUBVOLUMES="$subvols" \
                     "$factoryReset" --force 2>&1); then
          echo "omarchy-system-factory-reset ran on a machine with no ownership marker" >&2
          echo "  A full baseline was on the disk, which is exactly the case where" >&2
          echo "  forgetting the gate does something rather than nothing." >&2
          exit 1
        fi
        case "$reset_out" in
          *"was not written by nixarchy"*) ;;
          *) echo "the unowned refusal does not say why:" >&2; echo "$reset_out" >&2; exit 1 ;;
        esac
        test ! -e "$request" || { echo "a reset was staged on an unowned machine" >&2; exit 1; }

        touch "$marker"

        # 2. Ours, but no baseline: every machine installed before #172.
        : >"$subvols"
        if reset_out=$(env NIXARCHY_MANAGED_MARKER="$marker" NIXARCHY_FACTORY_REQUEST="$request" \
                     NIXARCHY_BTRFS="$fr/bin/btrfs" FAKE_SUBVOLUMES="$subvols" \
                     "$factoryReset" --force 2>&1); then
          echo "a factory reset was staged on a machine with no factory baseline" >&2
          exit 1
        fi
        case "$reset_out" in
          *"no factory snapshot on this machine"*) ;;
          *) echo "the no-baseline refusal lost its explanation:" >&2; echo "$reset_out" >&2; exit 1 ;;
        esac
        test ! -e "$request" || { echo "a reset was staged with no baseline to restore" >&2; exit 1; }

        # 3. Half a baseline is not a baseline. This is the #171 shape and the
        #    installer deletes the survivor rather than leave it -- but if it
        #    ever did not, restoring /home from @factory-home while /var/lib
        #    had nothing to come from would be worse than refusing.
        printf 'ID 256 gen 9 top level 5 path @factory-home\n' >"$subvols"
        if env NIXARCHY_MANAGED_MARKER="$marker" NIXARCHY_FACTORY_REQUEST="$request" \
               NIXARCHY_BTRFS="$fr/bin/btrfs" FAKE_SUBVOLUMES="$subvols" \
               "$factoryReset" --force >/dev/null 2>&1; then
          echo "half a baseline (@factory-home alone) was accepted as a baseline" >&2
          exit 1
        fi
        test ! -e "$request" || { echo "a reset was staged from half a baseline" >&2; exit 1; }

        # 4. Both, read-only: staged, and staged is ALL it does. Nothing this
        #    script runs may touch the disk -- the request file is the entire
        #    output, and the unit above is what acts on it.
        printf 'ID 256 gen 9 top level 5 path @factory\nID 257 gen 9 top level 5 path @factory-home\n' >"$subvols"
        env NIXARCHY_MANAGED_MARKER="$marker" NIXARCHY_FACTORY_REQUEST="$request" \
            NIXARCHY_BTRFS="$fr/bin/btrfs" FAKE_SUBVOLUMES="$subvols" \
            "$factoryReset" --force >/dev/null 2>&1 || {
          echo "the reset refused a machine that has a complete, read-only baseline" >&2
          exit 1
        }
        test -e "$request" || {
          echo "the reset reported success and staged nothing: the request file" >&2
          echo "  is what nixarchy-factory-reset.service conditions on, so the" >&2
          echo "  next boot would do nothing at all." >&2
          exit 1
        }

        # 5. --check answers the same question, silently -- it is what a menu
        #    row would gate on, and a row that disagrees with the command
        #    behind it is a row that prints a refusal when clicked.
        env NIXARCHY_MANAGED_MARKER="$marker" NIXARCHY_BTRFS="$fr/bin/btrfs" \
            FAKE_SUBVOLUMES="$subvols" "$factoryReset" --check || {
          echo "--check refuses a machine that has a baseline" >&2
          exit 1
        }
        if env NIXARCHY_MANAGED_MARKER="$fr/absent" NIXARCHY_BTRFS="$fr/bin/btrfs" \
               FAKE_SUBVOLUMES="$subvols" "$factoryReset" --check; then
          echo "--check passes on a machine nixarchy did not install" >&2
          exit 1
        fi
        echo "the factory reset refuses without ownership, without a baseline and on half of one"

        python3 ${./home-backup-menu.py} "$vm/etc/nixarchy/omarchy-menu.jsonc"

          touch $out
      ''
    else
      ''
        echo "$report"
        echo "these options do not take effect both ways: ${pkgs.lib.concatStringsSep " " (builtins.attrNames broken)}" >&2
        echo "an option that cannot be turned off is not an option." >&2
        exit 1
      ''
  )
