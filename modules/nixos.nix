inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;

  # Omarchy's session, launched from its own hyprland.lua in the store rather
  # than from ~/.config/hypr/hyprland.lua. Hyprland's --config takes the entry
  # point; the modules it requires still resolve through $HOME/.config, which
  # is where the Home Manager seed puts them.
  #
  # Through start-hyprland rather than the Hyprland binary. Booting this on a
  # real laptop logged
  #
  #   WARNING: Hyprland is being launched without start-hyprland.
  #   This is highly advised against.
  #
  # start-hyprland is the watchdog Hyprland 0.56 wants supervising it, and it
  # is what nixpkgs' own hyprland.desktop execs. Everything after its `--` is
  # passed through to Hyprland, so --config still arrives where it was going.
  # The VM never complained because a warning is not a failure -- it took
  # somebody reading the journal on a machine that had actually logged in.
  omarchySessionLauncher = pkgs.writeShellScript "omarchy-session" ''
    export OMARCHY_PATH=${cfg.package}/share/omarchy
    exec ${pkgs.uwsm}/bin/uwsm start -N Omarchy -D Hyprland -- \
      ${config.programs.hyprland.package}/bin/start-hyprland -- \
      --config ${cfg.package}/share/omarchy/config/hypr/hyprland.lua
  '';

  # Whether fcitx5 is the input method actually in force, which is both what
  # the unit below can start and what the environment variables would be true
  # about. Read back out of the option rather than assumed, because the
  # defaults this module sets for it are mkDefault.
  usingFcitx5 = config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5";

  # providedSessions has to match the .desktop basename or NixOS refuses it.
  #
  # The label is Nixarchy and the id stays `omarchy`, which is not an
  # oversight. `Name=` is what a greeter prints; the basename is what it
  # *remembers* -- SDDM, GDM and greetd all persist the last session by file
  # id, so renaming the file would log everyone who already picked this
  # session into whatever the greeter falls back to, once, with no
  # explanation. A label costs nothing to change and an id costs a support
  # thread.
  omarchySession =
    (pkgs.writeTextFile {
      name = "omarchy-wayland-session";
      destination = "/share/wayland-sessions/omarchy.desktop";
      text = ''
        [Desktop Entry]
        Name=Nixarchy
        Comment=Omarchy on NixOS, through Hyprland
        Exec=${omarchySessionLauncher}
        Type=Application
        DesktopNames=Hyprland
      '';
    }).overrideAttrs
      (_: {
        passthru.providedSessions = [ "omarchy" ];
      });
in
{
  imports = [
    inputs.hyprland.nixosModules.default
    (import ./apps.nix inputs)
    ./local-ai.nix
    ./services
  ];

  options.programs.nixarchy = {
    enable = lib.mkEnableOption "Nixarchy, the Omarchy desktop vendored for NixOS";

    package = lib.mkOption {
      type = lib.types.package;
      # Built from *your* nixpkgs through this flake's overlay, not from
      # inputs.self.packages -- which is built from nixarchy's own nixpkgs.
      #
      # Those look identical and are not: every one of the ~80 runtime
      # dependencies would come from a different nixpkgs instance than the
      # rest of your system, and the first one you also install yourself makes
      # buildEnv refuse the profile --
      #
      #   two given paths contain a conflicting subpath:
      #     .../tesseract-5.5.3/bin/tesseract and .../tesseract-5.5.3/bin/tesseract
      #
      # -- two builds of the same version, which reads like a bug in nix until
      # you notice the hashes differ. Found by building a real config that had
      # tesseract of its own.
      default = (pkgs.extend inputs.self.overlays.default).omarchy;
      defaultText = lib.literalExpression "pkgs.extend nixarchy.overlays.default).omarchy";
      description = "The vendored Omarchy tree providing OMARCHY_PATH.";
    };

    session = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register "Nixarchy" as its own entry in wayland-sessions, so any
        greeter can offer it alongside whatever else the machine runs. The
        session id stays `omarchy`, so a greeter that already remembers this
        session keeps remembering it.

        This is what makes nixarchy coexist with an existing Hyprland setup.
        The session names Omarchy's own hyprland.lua with Hyprland's --config,
        so it does not need to own ~/.config/hypr/hyprland.lua -- yours keeps
        serving your session, and this one keeps serving Omarchy's.

        The two still share ~/.config/hypr/{monitors,input,bindings,looknfeel,
        autostart}.lua, because Omarchy's bootstrap builds Hyprland's Lua
        module path from $HOME/.config and nothing else. Editing those changes
        both sessions.
      '';
    };

    displayManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable SDDM with Omarchy's greeter. Turn it off on a machine that
        already has one: GDM, greetd, LightDM and ly all launch Omarchy's
        session out of wayland-sessions perfectly well, and you lose the
        branded greeter rather than the desktop. Two display managers at once
        is not a working configuration -- NixOS gets two definitions of
        displayManager.generic.execCmd and refuses to build.

        This is an option rather than something derived from whether another
        greeter is enabled, because deriving it does not work: NixOS computes
        parts of the display-manager machinery *from* sddm.enable, so reading
        gdm.enable or greetd.enable back out of the config closes a loop and
        evaluation dies with "infinite recursion". Asking outright cannot.
      '';
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        The user who runs the desktop.

        Set this and nixarchy can do the few things that need to name someone.
        Today that is the `input` group: upstream's installer runs
        `usermod -aG input`, and without it the dictation tools and game
        controllers Omarchy offers cannot read their devices. There is no way
        to infer it -- a NixOS machine has many users and the module cannot
        guess which one logs into Omarchy -- so leaving this unset simply skips
        that step rather than picking someone.

        `browserThemeUser` is deliberately *not* inherited from this. Naming
        the desktop user should not also hand them the browsers' policy
        directories, which on a shared machine means policy for everyone; set
        that one separately if you want it.
      '';
    };

    browserThemeUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # Not `cfg.user`: naming the desktop user should not silently hand them
      # the browsers' policy directories. See the description below for why
      # that is a decision to make on purpose.
      default = null;
      example = "alice";
      description = ''
        Let this user's theme switches set the Chromium/Chrome/Edge/Brave
        accent colour, by creating the browsers' policy directories and giving
        them to that user.

        Off by default, and worth understanding before turning on. Chromium
        reads policy only from /etc/<browser>/policies/managed -- there is no
        per-user equivalent, by design, because policy is an administrator
        control. Making that directory writable by a user therefore lets them
        set policy for *every* user of the machine: proxies, forced
        extensions, the lot. On a single-user desktop that is a distinction
        without a difference; on a shared machine it is a real one.

        What it buys is the accent colour alone. Light and dark already follow
        the theme without this, through the settings portal rather than a
        policy file -- so the browser is themed either way, just not tinted.
      '';
    };

    allowUnfree = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Allow unfree packages.

        Most of what the Install menu offers is unfree -- the browsers, the
        editors, Steam, the AI clients. Leaving licence policy to the consumer
        sounded principled and in practice meant picking an app, running
        nixarchy-apply, and watching the rebuild die on a licence error with
        nothing on screen explaining that the fix was a line in a file you had
        never opened.

        Set this to false for nixpkgs' own default instead. Turn it off HERE
        rather than by writing nixpkgs.config.allowUnfree = false yourself:
        nixpkgs.config is a free-form attribute set, so two definitions of the
        same key do not resolve by priority the way a normal option does, and
        yours would not win -- not even with mkForce.
      '';
    };

    binaryCaches = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add nixarchy.cachix.org and hyprland.cachix.org as substituters.
        Without them, enabling nixarchy means compiling a compositor.

        This is the one thing here that changes a machine without any chance
        of a conflict to warn you: substituters and trusted-public-keys are
        lists, so they merge silently into whatever you already trust. Set
        this to false if that is not a decision you want made for you --
        everything still builds, it just builds locally.
      '';
    };

    preinstalls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the desktop applications Omarchy ships preinstalled -- the set
        omarchy-install-preinstalls restores and Remove > Preinstalls takes
        away. Upstream has these on a fresh machine, so they are on here too.

        Six of upstream's thirteen cannot be here: obsidian is unfree, so it
        would abort the whole rebuild rather than fail on its own -- enable
        `apps.obsidian` for it instead -- and aether, omacut, omacalc and
        omawrite are Omarchy's own applications, not packaged in nixpkgs.
        cliamp is, and is included: it arrived after this was first written.
        lazydocker is already a runtime dependency.

        Turning this off is the declarative Remove > Preinstalls.
      '';
    };

    bootSplash = lib.mkOption {
      type = lib.types.enum [
        "defer"
        "force"
        "off"
      ];
      default = "defer";
      description = ''
        What to do about Omarchy's Plymouth boot splash.

        `defer` sets it at `mkDefault`, so anything that names a theme of its
        own keeps it -- stylix does, which is why a stylix machine boots to the
        stylix splash with nixarchy installed. This is the default because a
        boot splash is a taste, and one already chosen should survive.

        `force` takes Omarchy's instead. Both `boot.plymouth.theme` and
        `boot.plymouth.themePackages` are forced together, because forcing only
        the name leaves NixOS asserting a theme that is not in the package list
        and failing the build -- which is exactly what someone reaching for
        `lib.mkForce` on the theme alone runs into.

        `off` leaves `boot.plymouth` untouched, including `enable`.
      '';
    };

    preinstallsExclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "pinta" ];
      description = ''
        Preinstalled applications to leave out, by nixpkgs attribute name.

        `preinstalls` is all-or-nothing, which is the one thing the Remove menu
        cannot express: an app in the selection can be deselected on its own,
        but the preinstalled set could only be taken away whole. This is the
        per-application half of it -- the declarative equivalent of removing
        one app rather than the group.

        Names that match nothing are an error rather than a typo you find by
        noticing the app is still installed.
      '';
    };

    shellIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Source Omarchy's shell chain into interactive zsh, when zsh is
        enabled. Upstream ships bash and nothing else, so this is the same
        aliases and functions -- compress, dip, hdl, iso2sd, the tmux layouts
        -- reaching a shell that had none of them.

        Three of upstream's five rc files are portable and are sourced as-is.
        The two that are genuinely bash (shopt and BASH_COMPLETION internals;
        `mise activate bash`, `starship init bash`, fzf's bash key bindings)
        are done against the same tools' zsh support instead. bash-specific
        completions and the readline inputrc are left alone: zsh has compinit
        and ZLE, and a half-ported version of either is worse than neither.

        See programs.nixarchy.bashIntegration for bash.
      '';
    };

    bashIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Source Omarchy's bash rc chain -- default/bash/{envs,shell,aliases,
        functions,init,inputrc} plus every file in default/bash/fns -- into
        interactive bash. This is what provides the shell functions the manual
        documents (compress, dip, hdl, tdl, iso2sd, worktree and tmux
        helpers), and it needs no patching here because every path in that
        chain resolves through OMARCHY_PATH, which this module already
        exports.

        Nothing in the desktop depends on it: the menus and bin/ call the
        omarchy-* executables directly, not these functions. It is on by
        default because it is a real part of Omarchy, but it is opinionated --
        it aliases `ls` to eza, `cd` to zoxide, `g` to git, and sets EDITOR
        and BROWSER -- so it is worth turning off if you bring your own shell
        config. It loads from /etc/bashrc, i.e. before ~/.bashrc, so anything
        you define yourself still wins.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # removeAttrs ignores a name that is not there, so a typo would leave
        # the app installed and the user hunting for why. Named here instead.
        assertion =
          let
            known = [
              "pinta"
              "libreoffice"
              "xournalpp"
              "obs-studio"
              "moonlight-qt"
              "kdenlive"
              "gnome-disk-utility"
              "sushi"
              "cliamp"
            ];
          in
          lib.all (n: builtins.elem n known) cfg.preinstallsExclude;
        message =
          "programs.nixarchy.preinstallsExclude names something that is not a "
          + "preinstalled application: "
          + lib.concatStringsSep " " (
            lib.subtractLists [
              "pinta"
              "libreoffice"
              "xournalpp"
              "obs-studio"
              "moonlight-qt"
              "kdenlive"
              "gnome-disk-utility"
              "sushi"
              "cliamp"
            ] cfg.preinstallsExclude
          )
          + ". The set is: pinta libreoffice xournalpp obs-studio moonlight-qt "
          + "kdenlive gnome-disk-utility sushi cliamp.";
      }
      {
        assertion = config.programs.hyprland.package.version or "0" >= "0.55";
        message = ''
          Nixarchy needs Hyprland >= 0.55 for the Lua config API that
          Omarchy 4.x is written against (hl.bind / hl.window_rule / hl.on).
          Use inputs.hyprland's package, not nixpkgs'.
        '';
      }
    ];

    # Most of what the Install menu offers is unfree: the browsers, the editors,
    # Steam, the AI clients, several of the fonts. Leaving licence policy to the
    # consumer sounded principled and in practice meant a new user picked an app,
    # ran nixarchy-apply, and watched a rebuild die on a licence error partway
    # through -- with nothing on screen explaining that the fix was a line in a
    # file they had never opened.
    #
    # Behind an option rather than mkDefault, because mkDefault does not work
    # here: nixpkgs.config is a free-form attribute set, so `mkDefault true` on
    # one of its keys is stored as the override attrset itself and nixpkgs is
    # handed { _type = "override"; ... } where it expects a bool. mkDefault on
    # the whole set does resolve, but then any other nixpkgs.config key a user
    # sets replaces our definition wholesale and unfree silently goes away.
    #
    # mkIf so that turning the option off removes the definition entirely rather
    # than asserting false, and mkDefault so that ours is the one that yields
    # wherever something else already owns nixpkgs.config. That is not
    # hypothetical: a NixOS VM test takes its pkgs from outside and imports
    # misc/nixpkgs/read-only.nix, which defines nixpkgs.config as a unique
    # option -- so any definition of ours, at any priority above default, makes
    # every runNixOSTest node fail to evaluate.
    #
    # The cost is that priorities filter before merging: a user who sets any
    # other nixpkgs.config key, say permittedInsecurePackages, outranks this
    # default and drops it, and unfree goes off again. That case is not silent,
    # which is the only reason it is acceptable -- modules/apps.nix warns at
    # evaluation time when an enabled app is unfree and allowUnfree is off, and
    # names the fix.
    nixpkgs.config = lib.mkIf cfg.allowUnfree (lib.mkDefault { allowUnfree = true; });

    nix.settings = {
      # nixarchy-apply runs `nh os switch <flake>`, so flakes are not
      # optional here. mkDefault leaves a user free to manage this themselves.
      experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
      ];

      # hyprland.cachix.org covers Hyprland when the pinned commit is one
      # hyprwm built; nixarchy.cachix.org covers it when it is not, plus the
      # vendored Omarchy tree and the packages this flake builds itself.
      #
      # Behind an option rather than mkForce: these are lists, so they merge
      # into a user's existing trust with no conflict and no warning, which
      # makes them the only thing in this module that can change a machine
      # silently. See programs.nixarchy.binaryCaches.
      substituters = lib.mkIf cfg.binaryCaches [
        "https://nixarchy.cachix.org"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = lib.mkIf cfg.binaryCaches [
        "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
      ];
    };

    # One `programs` block rather than three scattered assignments: statix
    # flags a repeated top-level key, and it is right that they read better
    # together.
    programs = {
      hyprland = {
        # This block is deliberately NOT mkDefault, unlike everything else
        # here. Omarchy *is* Hyprland, so enabling nixarchy while disabling it
        # is a contradiction rather than a preference -- and NixOS' own
        # hyprland module already defines `package` at mkDefault priority, so
        # matching that priority does not yield to the user, it ties with
        # nixpkgs and fails with "defined multiple times". Overriding these
        # means lib.mkForce, which is the honest signal for replacing the
        # compositor an entire desktop is written against.
        enable = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage =
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        # Omarchy's session and its user units are started through uwsm.
        withUWSM = true;
      };

      # mise is in Omarchy's base packages and its dev-env installers lean on
      # it heavily. It downloads prebuilt runtimes, which cannot run against
      # NixOS' non-standard loader, so it detects NixOS and falls back to
      # compiling from source -- which then fails, because there is no compiler
      # on the session PATH. mise's own message names the fix:
      #
      #   "The automatic all_compile=true default on NixOS caused python to
      #    compile from source. Enable nix-ld to use precompiled binaries"
      #
      # This is what makes `omarchy install dev-env` work rather than print a
      # wall of build errors.
      nix-ld.enable = lib.mkDefault true;

      # See programs.nixarchy.bashIntegration. This lands in /etc/bashrc, which
      # bash sources BEFORE ~/.bashrc, so a user's own aliases still win.
      #
      # The chain needs no patching: `default/bash/rc` resolves everything
      # through OMARCHY_PATH, exported above, and the two /usr paths it does
      # mention -- Arch's env-bootstrap and bash_completion -- are both behind
      # `[ -r ... ]` guards, and their jobs are already done by this module and
      # by NixOS respectively.
      bash.interactiveShellInit = lib.mkIf cfg.bashIntegration ''
        source ${cfg.package}/share/omarchy/default/bash/rc
      '';

      # The same for zsh, which upstream does not ship. Only when zsh is
      # actually enabled: programs.zsh.interactiveShellInit on a machine with
      # no zsh writes an rc nothing reads, and turning zsh on for someone who
      # did not ask is not this module's business.
      zsh.interactiveShellInit = lib.mkIf (cfg.shellIntegration && config.programs.zsh.enable) ''
        source ${cfg.package}/share/omarchy/default/zsh/rc
      '';

      # fish, same condition. Its rc derives everything from the same bash
      # files rather than translating them, so it tracks upstream the way the
      # other two do.
      fish.interactiveShellInit = lib.mkIf (cfg.shellIntegration && config.programs.fish.enable) ''
        source ${cfg.package}/share/omarchy/default/fish/rc
      '';
    };

    environment = {
      # The single indirection point. bin/, shell/, themes/ and the Hyprland
      # Lua defaults are all resolved relative to this.
      sessionVariables.OMARCHY_PATH = "${cfg.package}/share/omarchy";

      # The replacement omarchy-update reads this. It is a plain script inside
      # the package with no way to see module options, and it is reached from
      # the shell's bar widget and notifications as well as the menu.
      sessionVariables.NIXARCHY_FLAKE = cfg.flake;

      # Omarchy's scripts are unwrapped by design (wrapping breaks the CLI's
      # metadata scan), so their dependencies have to be on the session PATH.
      systemPackages = [
        cfg.package
      ]
      # Minus Hyprland itself.
      #
      # The package carries the compositor its Lua config is written against as
      # a runtime dependency, and putting that in systemPackages made it the
      # Hyprland on PATH -- so on a machine that already ran Hyprland, enabling
      # nixarchy silently swapped the compositor behind the user's *existing*
      # sessions. Its share/wayland-sessions/hyprland.desktop won the buildEnv
      # collision too, so `hyprland.desktop` pointed at nixarchy's build rather
      # than theirs. Found by building this against a real configuration; the
      # doctor tells people to keep their own Hyprland, and this quietly did
      # the opposite.
      #
      # programs.hyprland already puts the right one on PATH -- ours when
      # nixarchy sets the option, theirs when they mkForce it -- so dropping it
      # here changes nothing on a clean machine and stops overriding anyone
      # else's. omarchy-session still runs the Lua config through
      # config.programs.hyprland.package, which is the same binary either way.
      ++ builtins.filter (d: !(lib.hasPrefix "hyprland-" (d.name or ""))) cfg.package.passthru.runtimeDeps
      # sessionPackages alone does not populate
      # /run/current-system/sw/share/wayland-sessions, and that is where greetd
      # greeters actually look -- so the session package goes here as well.
      ++ lib.optional cfg.session omarchySession
      ++ (with pkgs; [
        # omarchy-theme-set-gnome applies the light/dark half of every theme
        # with `gsettings set org.gnome.desktop.interface`, and on Arch the
        # schemas it writes arrive as transitive dependencies. Nothing pulls
        # them into a NixOS system profile, so gsettings answered "No schemas
        # installed" and every one of those writes was a no-op -- which is why
        # a dark theme left GTK apps and Chromium in light mode.
        glib
        gsettings-desktop-schemas

        # install/omarchy-base.packages:46. GTK 3 has no Adwaita-dark of its
        # own; gnome-themes-extra is the package that supplies it, and it is
        # the exact name gsettings gets set to.
        gnome-themes-extra

        # install/omarchy-base.packages:147. Every theme's icons.theme names a
        # Yaru variant -- Yaru-magenta, Yaru-sage, Yaru-olive and so on -- so
        # without this the icon theme is set to something that does not exist.
        yaru-theme
        # Yaru inherits from Adwaita for anything it does not draw itself.
        adwaita-icon-theme

        # Omarchy sets a cursor size but never a cursor theme -- on Arch one
        # comes with the desktop packages. NixOS ships none, so Hyprland used
        # its own built-in pointer. Bibata is here rather than Yaru or Adwaita
        # because those ship a single cursor each, and the point is to follow
        # the theme: Ice is white for dark themes, Classic black for light.
        bibata-cursors
      ])
      ++ lib.optionals cfg.preinstalls (
        # Filtered by attribute name rather than by pname: the name someone
        # writes in preinstallsExclude is the one they would look up on
        # search.nixos.org, and pname disagrees with it often enough to matter
        # -- pinta's is "Pinta", capitalised.
        lib.attrValues (
          lib.removeAttrs {
            # omarchy-install-preinstalls, minus the six that cannot be here.
            inherit (pkgs)
              pinta
              libreoffice
              xournalpp
              obs-studio
              moonlight-qt
              ;
            inherit (pkgs.kdePackages) kdenlive;

            # install/omarchy-base.packages. The GUIs manual sends people to
            # Disks for formatting and SMART, and sushi is what makes Space
            # preview a file in Nautilus without opening it.
            inherit (pkgs) gnome-disk-utility sushi;

            # Omarchy's own music TUI, bound to SUPER + SHIFT + ALT + M. The
            # text above said it was not in nixpkgs; it arrived after that was
            # written, so the keybinding had been failing on a package that was
            # available the whole time.
            inherit (pkgs) cliamp;
          } cfg.preinstallsExclude
        )
      );
    };

    # install/config/*.sh and install/config/enable-services.sh, expressed as
    # options instead of the imperative scripts upstream runs once at install.
    # Every enable here is mkDefault. Nixarchy is a desktop, but it is a
    # NixOS module before it is a distribution, and someone adding it to a
    # machine they already run should not have to fight it: without mkDefault,
    # a laptop on TLP, a GNOME user on GDM, a podman user, anyone on
    # systemd-networkd or PulseAudio got an evaluation failure and had to
    # mkForce their way out one option at a time. Their setting wins now, and
    # they lose only the feature that depended on it.
    services = {
      # See programs.nixarchy.displayManager for why this is an option of our
      # own rather than a look at whether another greeter is already enabled.
      displayManager.sddm = {
        enable = lib.mkIf cfg.displayManager (lib.mkDefault true);
        wayland.enable = lib.mkDefault true;

        # etc/sddm.conf.d/10-theme.conf. The theme itself rides in the package
        # at share/sddm/themes/omarchy, and /share/sddm is already one of the
        # paths linked into the system profile, so naming it here is enough.
        # Without this SDDM uses its own stock theme -- a blue gradient with a
        # placeholder avatar -- as the first screen of an Omarchy machine.
        theme = lib.mkDefault "omarchy";
      };

      # Left at mkDefault true rather than derived from services.pulseaudio:
      # NixOS' own graphical-desktop.nix already turns PipeWire on for any
      # graphical session, so deriving `false` here fights nixpkgs instead of
      # yielding to the user, and conflicts with that definition. A PulseAudio
      # user hits nixpkgs' assertion with or without nixarchy; that one is not
      # ours to resolve.
      pipewire = {
        enable = lib.mkDefault true;
        alsa.enable = lib.mkDefault true;
        alsa.support32Bit = lib.mkDefault true;
        pulse.enable = lib.mkDefault true;
        jack.enable = lib.mkDefault true;
      };

      # install/config/locate.sh
      locate.enable = lib.mkDefault true;

      # cups, cups-browsed, avahi and nss-mdns are all in base.packages
      printing.enable = lib.mkDefault true;
      avahi = {
        enable = lib.mkDefault true;
        nssmdns4 = lib.mkDefault true;
        openFirewall = lib.mkDefault true;
      };

      # gnome-keyring + libsecret, and the gvfs backends nautilus needs
      gnome.gnome-keyring.enable = lib.mkDefault true;
      gvfs.enable = lib.mkDefault true;
      udisks2.enable = lib.mkDefault true;

      # power-profiles-daemon is in base.packages, and NixOS asserts that it
      # and TLP cannot both be on. Same reasoning as pipewire above: a laptop
      # already running TLP never sets this, so mkDefault alone left the
      # assertion firing. omarchy-powerprofiles-set stops working, which is
      # the honest consequence of choosing the other power daemon.
      power-profiles-daemon.enable = lib.mkDefault (!config.services.tlp.enable);

      # The bar's battery widget and the power panel both read UPower over
      # DBus, and omarchy-powerprofiles-set autodetect gates on its OnBattery
      # property. That read is `2>/dev/null` with a fallback, so without the
      # daemon it does not fail -- it silently concludes you are on AC and
      # never switches to power-saver.
      upower.enable = lib.mkDefault true;

      # etc/systemd/logind.conf.d/, both files.
      logind.settings.Login = {
        # Omarchy binds the power button to its own power menu. NixOS' default
        # of "poweroff" got there first, so the button shut the machine down
        # and the menu was unreachable.
        HandlePowerKey = lib.mkDefault "ignore";

        # omarchy-sleep-lock holds a delay inhibitor while the shell secures
        # the screen, and a delay inhibitor is a timer rather than a promise:
        # logind suspends anyway when it expires. Upstream's own comment says
        # five seconds -- logind's default -- is not enough when closing the
        # lid also reconfigures displays, because Quickshell waits for the
        # screen set to settle before it can secure. This costs nothing when
        # locking works; a healthy lock releases in well under a second.
        InhibitDelayMaxSec = lib.mkDefault 15;
      };
    };

    # An Omarchy entry of its own in wayland-sessions. Without it the only way
    # to reach the desktop is for Omarchy to own ~/.config/hypr/hyprland.lua,
    # which a machine that already runs Hyprland cannot give it.
    #
    # DesktopNames stays "Hyprland" rather than "omarchy":
    # xdg-desktop-portal-hyprland declares UseIn=wlroots;Hyprland;... and would
    # not bind for any other name, which silently breaks ScreenCast and
    # Screenshot inside the session.
    services.displayManager.sessionPackages = lib.mkIf cfg.session [ omarchySession ];

    # The anchor ~/.XCompose includes. That file is written once at first
    # login and never rewritten, so it cannot name a store path: this one is
    # regenerated with the system and always points at the current package.
    environment.etc."omarchy/xcompose".source = "${cfg.package}/share/omarchy/default/xcompose";

    # glib looks for compiled schemas in $XDG_DATA_DIRS/glib-2.0/schemas, but
    # nixpkgs' glib setup hook relocates them to
    # share/gsettings-schemas/<name>/glib-2.0/schemas so that two packages
    # shipping schemas cannot collide -- and environment.pathsToLink does not
    # carry that path into the system profile at all. Installing the package is
    # therefore not enough to make it readable: without this, gsettings answers
    # "No schemas installed" and omarchy-theme-set-gnome writes nothing.
    environment.sessionVariables.XDG_DATA_DIRS = [
      "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
    ];

    # install/config/docker.sh
    virtualisation.docker.enable = lib.mkDefault true;

    networking = {
      # install/config/firewall.sh (upstream uses ufw)
      firewall = {
        enable = lib.mkDefault true;

        # The other half of that script, which this module left behind.
        # Upstream's is not merely "turn the firewall on":
        #
        #     ufw default deny incoming
        #     ufw allow 53317/udp
        #     ufw allow 53317/tcp   # "Allow ports for LocalSend."
        #
        # Porting only the deny half enables a firewall that blocks the one
        # service Omarchy's manual promises works out of the box: "Omarchy's
        # firewall is closed by default except for LocalSend's port, so this
        # works out of the box on a fresh install." On a machine taking this
        # module's firewall default it did not -- Share > Receive listened on
        # 53317 and nothing on the network could reach it.
        #
        # Discovery was never the missing part: services.avahi above already
        # opens 5353. Only LocalSend's own transfer port was closed.
        #
        # Not mkDefault: these are list options, so they merge with whatever
        # the user opens rather than replacing it. A mkDefault list would be
        # dropped whole the moment they opened a port of their own.
        allowedTCPPorts = [ 53317 ];
        allowedUDPPorts = [ 53317 ];
      };
      networkmanager.enable = lib.mkDefault true;
    };

    # install/config/lockscreen-pam.sh, whose one line is `omarchy-apply-lock`
    # -- and that writes /etc/pam.d/omarchy-lock-password. Omarchy 4's lock
    # screen is the Quickshell one, which names that stack itself
    # (shell/plugins/lock/Service.qml: `config: "omarchy-lock-password"`), and
    # watches the file's existence to decide whether locking is possible at
    # all. hyprlock appears nowhere in the tree except omarchy-upgrade-to-
    # quattro, which *removes* it -- so what was declared here was PAM for a
    # program the desktop no longer runs. On a live session:
    #
    #   /etc/pam.d/omarchy-lock-password  ->  No such file or directory
    #   omarchy-shell lock lock           ->  missing-pam, screen stayed up
    #
    # Five paths reach that no-op: SUPER + CTRL + L, Menu > System > Lock, the
    # idle timeout, lid close, and suspend.
    #
    # An empty attrset is the whole fix. NixOS' generated stack is pam_unix
    # auth plus an account section, which is upstream's file with faillock and
    # pam_systemd_home taken out. faillock is deliberately not reproduced:
    # NixOS' only handle on it is `logFailures`, which emits pam_faillock with
    # no preauth/authfail/authsucc arguments, so nothing ever resets the
    # counter -- three bad unlocks would lock a user out of their own screen
    # for good. Upstream's deny=10 needs the raw `rules` interface, and a
    # lockout is a worse failure than the logging it would buy.
    security.pam.services = {
      omarchy-lock-password = { };
    }
    # Upstream writes omarchy-lock-fingerprint only when fprintd-list reports
    # enrolled fingers, and the shell gates on that same pair (the file plus
    # fprintd-list). optionalAttrs rather than mkIf because mkIf on an
    # attrsOf entry still defines the service, and the service NixOS would
    # then generate with fprintAuth false is a pam_unix stack -- a
    # "fingerprint" method that silently waits for a password nothing asks for.
    // lib.optionalAttrs config.services.fprintd.enable {
      # pam_fprintd alone, as upstream: fprintAuth already defaults to
      # services.fprintd.enable, and unixAuth off keeps the fingerprint stack
      # from falling back to a password prompt the lock screen never renders.
      omarchy-lock-fingerprint.unixAuth = false;
    };

    systemd = {
      # omarchy-theme-set-browser writes {"BrowserThemeColor": ...} into each
      # browser's policy directory on every theme switch, and skips any that
      # does not exist -- which on NixOS is all of them, so the accent silently
      # never applied. Creating them is all that is needed; the script is
      # upstream's and works unchanged once it has somewhere to write.
      tmpfiles.rules = lib.mkIf (cfg.browserThemeUser != null) (
        map (dir: "d ${dir} 0755 ${cfg.browserThemeUser} users - -") [
          "/etc/chromium/policies"
          "/etc/chromium/policies/managed"
          "/etc/opt/chrome/policies"
          "/etc/opt/chrome/policies/managed"
          "/etc/opt/edge/policies"
          "/etc/opt/edge/policies/managed"
          "/etc/brave/policies"
          "/etc/brave/policies/managed"
        ]
      );

      # $OMARCHY_PATH/default/systemd/user/, which upstream installs into
      # /usr/lib/systemd/user and nothing here installed anywhere -- that
      # directory is not a systemd search path. `systemctl --user status
      # bt-agent.service` answered "could not be found" on a live session, and
      # with it went the pairing agent, the crash watcher, the input method, the
      # internal-monitor recovery, and -- the one that matters -- the sleep lock,
      # so suspend did not lock even once the PAM stack above exists.
      #
      # Declared here rather than linked out of the package, because every
      # shipped ExecStart is a /usr/bin path that resolves to nothing on NixOS
      # and the package is not this module's to patch. The bodies are upstream's:
      # same conditions, same ordering, same restart policy, binaries named by
      # store path.
      #
      # omarchy-migrate-notify and omarchy-tailscale-receive are deliberately
      # absent. Their conditions (ConditionPathIsDirectory=/usr/share/omarchy/
      # migrations, ConditionPathExists=/usr/bin/tailscale) can never hold here,
      # and both jobs belong elsewhere on NixOS: migrations arrive with a
      # rebuild, and Taildrop with services.tailscale.
      #
      # Each omarchy-* unit gets /run/current-system/sw on its PATH. NixOS gives
      # every unit a stub PATH of coreutils, findutils, grep, sed and systemd,
      # and unlike the copies upstream drops in ~/.config/systemd/user that stub
      # *overrides* the session PATH uwsm imported -- omarchy-system-sleep-
      # monitor would not find dbus-monitor, and none of them would find the
      # other omarchy-* commands they call. The system profile is where the
      # package's runtimeDeps already live, by the package's own design: bin/ is
      # a symlink farm rather than wrapped programs, so the CLI can still read
      # the `# omarchy:summary=` metadata out of each script.
      #
      # omarchy-speaker-tuning is absent for a different reason: omarchy-audio-
      # tuning installs it itself, by copying the unit into
      # ~/.config/systemd/user and running `systemctl --user enable`. Declaring
      # it would not race that copy -- the user directory outranks /etc -- but
      # `omarchy audio tuning off` disables and deletes it, and `disable` cannot
      # remove an [Install] symlink that lives in a read-only /etc, so the
      # tuning would come back at the next login with the config it needs gone.
      user.services = {
        bt-agent = {
          description = "Bluetooth pairing agent (auto-accept)";
          documentation = [ "man:bt-agent(1)" ];
          unitConfig.ConditionPathIsDirectory = "/sys/class/bluetooth";
          after = [ "dbus.socket" ];
          requires = [ "dbus.socket" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            # Skips cleanly on a machine with no usable adapter instead of
            # entering a restart loop.
            ExecCondition = "${config.systemd.package}/bin/systemctl is-active --quiet bluetooth.service";
            # bt-agent is in bluez-tools, not bluez -- upstream gets it from
            # base.packages, and the package's runtimeDeps carry only bluez
            # because no script in bin/ calls it. Named by store path so it does
            # not need to be on anyone's PATH.
            #
            # NoInputNoOutput auto-accepts pairing requests, which is safe only
            # because bluez is `pairable: true` for as long as the Bluetooth
            # panel is scanning and refuses inbound attempts outside that window.
            ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";
            Restart = "on-failure";
            RestartSec = 2;
          };
        };

        omarchy-sleep-lock = {
          description = "Lock Omarchy before suspend";
          after = [
            "dbus.socket"
            "wayland-session-waitenv.service"
          ];
          requires = [ "dbus.socket" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          path = [ "/run/current-system/sw" ];
          # Upstream also has ConditionEnvironment=OMARCHY_PATH, which checks the
          # user manager's environment -- true here only because uwsm imports
          # what omarchy-session exported. The store path is known at build
          # time, so it is passed in below instead and the condition dropped;
          # WAYLAND_DISPLAY is what actually proves a graphical session.
          unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
          # omarchy-system-sleep-monitor resolves its companion
          # omarchy-system-sleep-lock through $OMARCHY_PATH, not through PATH.
          environment.OMARCHY_PATH = "${cfg.package}/share/omarchy";
          serviceConfig = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/omarchy-system-sleep-monitor";
            Restart = "always";
            RestartSec = 2;
          };
        };

        omarchy-crash-watch = {
          description = "Announce process crashes and offer an AI diagnosis";
          after = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          path = [ "/run/current-system/sw" ];
          unitConfig = {
            ConditionEnvironment = "WAYLAND_DISPLAY";
            # Written by omarchy-toggle-crash-capture. Checked here so a
            # watcher switched off stays off across logins, which matters more
            # on NixOS than on Arch: the unit is declared, so `systemctl --user
            # disable` has nothing it can remove.
            ConditionPathExists = "!%h/.local/state/omarchy/toggles/crash-capture-off";
          };
          serviceConfig = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/omarchy-crash-watch";
            Restart = "always";
            RestartSec = 5;
          };
        };

        omarchy-recover-internal-monitor = {
          description = "Recover the internal monitor toggle when no external display is connected";
          before = [ "graphical-session-pre.target" ];
          wantedBy = [ "graphical-session-pre.target" ];
          path = [ "/run/current-system/sw" ];
          unitConfig.ConditionPathExists = "%h/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${cfg.package}/bin/omarchy-hw-recover-internal-monitor";
          };
        };
      }
      # fcitx5 is what turns the CapsLock compose sequences in ~/.XCompose into
      # text -- the file is seeded correctly by the Home Manager module, and
      # nothing was ever running to interpret it. Skipped entirely if someone
      # chose a different input method, since ExecStart would then name a binary
      # that package does not ship.
      // lib.optionalAttrs usingFcitx5 {
        omarchy-fcitx5 = {
          description = "Fcitx5 input method (XCompose sequences)";
          after = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          # After= is ordering only. An `omarchy update` over SSH has a live user
          # manager and no compositor, and a fcitx5 started there owns the bus
          # name with no WAYLAND_DISPLAY -- the later graphical login then finds
          # the unit already active and never starts a working one.
          unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
          serviceConfig = {
            Type = "simple";
            # notificationitem duplicates the tray entry Omarchy renders itself.
            ExecStart = "${config.i18n.inputMethod.package}/bin/fcitx5 --disable notificationitem";
            # always, not on-failure: fcitx5 exits 0 when another instance owns
            # its bus name, and a clean exit still leaves no input method.
            Restart = "always";
            RestartSec = 2;
          };
        };
      };

      # default/systemd/user/app.slice.d/10-oomd.conf. systemd-oomd is on by
      # default in NixOS, and with no slice marked as a candidate it has nothing
      # it is allowed to kill. Marking app.slice -- where uwsm-app puts every
      # launched application -- leaves the compositor structurally ineligible:
      # Hyprland runs in session.slice, so oomd takes the browser or terminal
      # that caused the pressure and the session survives to report it.
      #
      # Deliberately not systemd.oomd.enableUserSlices, which is the obvious
      # switch and the wrong one: it sets the same properties on user.slice and
      # on the user manager's own root slice, which puts the compositor back in
      # the candidate pool. asDropin rather than a systemd.user.slices entry so
      # systemd's own app.slice definition is extended, not replaced.
      #
      # Upstream's oomd.conf.d also lowers the global thresholds to 50% over 20s
      # from systemd's 60% over 30s. Not carried over: those are a tuning
      # preference, and the defaults still fire.
      user.units."app.slice" = {
        overrideStrategy = "asDropin";
        text = ''
          [Slice]
          ManagedOOMMemoryPressure=kill
          ManagedOOMSwap=kill
        '';
      };
    };

    # bin/omarchy-brightness-display-ddc talks to monitors over i2c
    hardware.i2c.enable = lib.mkDefault true;

    # bluez, bluez-tools and bluez-utils are all in
    # install/omarchy-base.packages, the bar has a Bluetooth widget, and
    # omarchy-bluetooth-device and omarchy-bluetooth-power are two of the
    # commands the menu offers -- but none of it works without the service,
    # and nothing here was starting it. Every session logged
    #
    #   quickshell.dbus.objectmanager: Failed to create
    #   DBusObjectManagerInterface for "org.bluez" "/"
    #
    # which was written off as a VM artefact for as long as this was in the
    # README's known gaps. It is the same shape as UPower: the tools were
    # installed, the daemon was not.
    hardware.bluetooth.enable = lib.mkDefault true;

    # Omarchy's own splash, which upstream installs by copying into
    # /usr/share/plymouth/themes from omarchy-refresh-plymouth. Nothing was
    # doing that here, so plymouth came up with NixOS' default theme -- the one
    # screen every boot shows, unbranded.
    #
    # Theme and themePackages always move together, at whatever priority
    # bootSplash asks for. NixOS asserts the named theme exists in the package
    # list, so setting one without the other fails the build -- which is what
    # anyone reaching for `lib.mkForce boot.plymouth.theme = "omarchy"` on a
    # stylix machine hits, because stylix sets themePackages at normal priority
    # and wins it.
    # The one thing upstream's installer does that needs a name.
    #
    # install/hardware/input-group.sh runs `usermod -aG input`, and without it
    # the dictation tools and controllers Omarchy offers cannot read their
    # devices. Skipped entirely when programs.nixarchy.user is unset, because
    # the alternative is guessing which of a machine's users logs into the
    # desktop.
    users.users = lib.optionalAttrs (cfg.user != null) {
      ${cfg.user}.extraGroups = [
        "input"
      ]
      # Docker is enabled above, at mkDefault, for every machine. Enabled and
      # unusable, until now: without this group every command wants sudo, and
      # `docker ps` answers "permission denied while trying to connect to the
      # Docker daemon socket" -- which reads like a broken install rather than
      # a missing group.
      #
      # The installer has always put its user in `docker` directly
      # (installer/host.nix), so this was only ever wrong for someone adding
      # nixarchy to a machine they already run: they got the daemon and not
      # the access. Conditioned on the option rather than set unconditionally,
      # so turning Docker off does not leave a group behind that grants root
      # to whatever installs a socket there later.
      ++ lib.optional config.virtualisation.docker.enable "docker";
    };

    boot.plymouth = lib.mkMerge [
      (lib.mkIf (cfg.bootSplash != "off") {
        enable = lib.mkDefault true;
      })
      (lib.mkIf (cfg.bootSplash == "defer") {
        themePackages = lib.mkDefault [ cfg.package ];
        theme = lib.mkDefault "omarchy";
      })
      (lib.mkIf (cfg.bootSplash == "force") {
        themePackages = lib.mkForce [ cfg.package ];
        theme = lib.mkForce "omarchy";
      })
    ];

    # default/fontconfig/conf.avail/50-omarchy.conf, which upstream symlinks
    # into /etc/fonts/conf.d. Without it `fc-match monospace` on a live
    # session answered Adwaita Mono, so every application asking for the
    # generic family got a font Omarchy never chose -- and half the file's
    # rules had nothing to resolve to anyway, because Liberation was not
    # installed (see fonts.packages below).
    #
    # The whole file rather than fonts.fontconfig.defaultFonts, which covers
    # the three generic families and nothing else: this also carries the
    # system-ui / -apple-system / BlinkMacSystemFont aliases that Electron and
    # web apps ask for by name, the emoji and Nerd Font fallback chains, and
    # the Arabic script rules.
    #
    # localConf, not a package in fontconfig's conf.d, for two reasons:
    # fonts.conf includes local.conf last, so these rules win the ties they
    # are meant to win, and it is one mkDefault a user can take back whole.
    # Read from the flake input rather than from cfg.package, because
    # readFile on a derivation output is import-from-derivation and would
    # make this module unevaluatable without building Omarchy first.
    fonts.fontconfig.localConf = lib.mkDefault (
      builtins.readFile "${inputs.omarchy}/default/fontconfig/conf.avail/50-omarchy.conf"
    );

    fonts.packages = [
      # Omarchy's own icon font travels inside the package, at
      # share/fonts/truetype/omarchy.ttf. Without it registered here the menu
      # button's U+E900 draws as tofu -- an empty box in the bar.
      cfg.package
    ]
    ++ (with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      font-awesome

      # What 50-omarchy.conf assigns sans-serif, serif and the system-ui
      # aliases to. On Arch it arrives with the base packages; here its
      # absence made those rules name a family fontconfig could not resolve,
      # so they fell through to whatever was installed.
      liberation_ttf
    ]);

    # default/environment.d/10-omarchy-fcitx.conf, plus the daemon that reads
    # it -- fcitx5 was not installed at all. i18n.inputMethod rather than
    # dropping fcitx5 into systemPackages: it is what builds fcitx5 with its
    # addons, writes the Qt plugin path, and sets XMODIFIERS and the GTK/Qt IM
    # modules. The unit that starts it is above.
    # Priority 1250, which is neither of the two names lib gives you, because
    # this option is squeezed between them. GNOME's desktop-manager module sets
    # type to "ibus" at mkDefault (1000) and two mkDefaults tie rather than
    # yield, so a host running GNOME beside this session failed to evaluate at
    # all -- not the wrong input method, no evaluation. One step lower is not
    # available either: nixpkgs' own module defines type as null at
    # mkOptionDefault (1500) to carry the deprecated `enabled` across, and
    # nullOr refuses to merge null with a value, so matching that ties in the
    # other direction. Sitting between the two loses to anyone with a real
    # opinion and still beats nixpkgs' placeholder, which is exactly the rule
    # this module follows everywhere else: arrive beside what is installed.
    i18n.inputMethod = {
      enable = lib.mkOverride 1250 true;
      type = lib.mkOverride 1250 "fcitx5";
    };

    # fcitx5 says this itself, in a notification on every login:
    #
    #   Wayland Diagnose -- Detect GTK_IM_MODULE being set and Wayland Input
    #   method frontend is working. It is recommended to unset GTK_IM_MODULE.
    #
    # nixpkgs sets GTK_IM_MODULE and QT_IM_MODULE only when waylandFrontend is
    # off, which is its default (i18n/input-method/fcitx5.nix). Those two are
    # the X11-era route: with them set, GTK sends input through the legacy
    # module instead of the Wayland input-method protocol, which is both worse
    # and, in GTK4 and Electron apps, sometimes nothing at all.
    #
    # Nixarchy is Wayland-only -- there is no session here where the X11
    # default is the right one -- so this is set rather than left to the user.
    i18n.inputMethod.fcitx5.waylandFrontend = lib.mkIf usingFcitx5 (lib.mkDefault true);

    # The two of upstream's four that the nixpkgs module does not set. It has
    # no opinion on either, and SDL applications and the older INPUT_METHOD
    # convention read nothing else.
    environment.sessionVariables.INPUT_METHOD = lib.mkIf usingFcitx5 (lib.mkDefault "fcitx");
    environment.sessionVariables.SDL_IM_MODULE = lib.mkIf usingFcitx5 (lib.mkDefault "fcitx");

    xdg.portal = {
      enable = lib.mkDefault true;
      # xdg-desktop-portal-gtk is in upstream's base.packages. A portal is
      # registered, not merely installed, so it belongs here rather than in
      # the package's runtimeDeps. The hyprland portal comes from
      # programs.hyprland.portalPackage above.
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };
  };
}
