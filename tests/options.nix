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
    mapped = pkgs.lib.concatStringsSep " " mappedRows;
    serviceProblems = pkgs.lib.concatStringsSep "\n" serviceProblems;
    flatpakProblems = pkgs.lib.concatStringsSep "\n" flatpakProblems;
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
    syncthingDataDir = syncthingBeside.services.syncthing.dataDir;
    ollamaPort = builtins.toString ollamaBeside.services.ollama.port;
    ollamaEndpoint = ollamaBeside.programs.nixarchy.localAi.resolved.endpoint;
    dockerGroups = pkgs.lib.concatStringsSep " " dockerGroups;
    managedModeA = pkgs.lib.boolToString managedModeA;
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
    # The home-backup script, run rather than read. Its gate and its allowlist
    # are the two things this issue actually promises, and both are answerable
    # by executing it -- --check and --list exist partly for that reason and
    # partly because the menu rows' `when:` calls the first of them.
    homeBackup = "${(pkgs.extend inputs.self.overlays.default).omarchy}/bin/nixarchy-home-backup";
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
