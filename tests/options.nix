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
    flatpakOurs = pkgs.lib.boolToString flatpakDefaults.ours;
    flatpakTheirs = pkgs.lib.boolToString flatpakDefaults.theirs;
    flatpakOn = pkgs.lib.boolToString flatpakDefaults.onWhenAsked;
    syncthingDataDir = syncthingBeside.services.syncthing.dataDir;
    ollamaPort = builtins.toString ollamaBeside.services.ollama.port;
    ollamaEndpoint = ollamaBeside.programs.nixarchy.localAi.resolved.endpoint;
    dockerGroups = pkgs.lib.concatStringsSep " " dockerGroups;
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
