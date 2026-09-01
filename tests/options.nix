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

  mappedRows = pkgs.lib.mapAttrsToList (_: a: a.menuId) (
    pkgs.lib.filterAttrs (_: a: a ? menuId) (import ../data/apps.nix)
  );

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
    serviceCount = builtins.toString (builtins.length (builtins.attrNames services));
    notApps = pkgs.lib.concatStringsSep " " notApps;
    nativeBuildInputs = [ pkgs.python3 ];
  }
  (
    if serviceProblems != [ ] then
      ''
        echo "data/services.nix has entries the generator cannot use:" >&2
        echo "$serviceProblems" >&2
        exit 1
      ''
    else if broken == { } then
      ''
          echo "$report"
          echo "the services catalogue is well formed ($serviceCount entries)"
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
