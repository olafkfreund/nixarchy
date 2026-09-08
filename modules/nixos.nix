inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;

  # Where the resolved-path half of the flake's safe.directory entry lives.
  #
  # Under /var/lib rather than /etc: /etc/gitconfig is a store symlink that
  # nothing can append to, and this value is not knowable until the machine
  # it describes exists. Root-owned and root-writable only, because git reads
  # it as configuration for whoever loads it -- a file a normal user could
  # write would be a way to hand root arbitrary git settings.
  safeDirInclude = "/var/lib/nixarchy/gitconfig-flake";

  # Why: modules/AGENTS.md#omarchys-session-launched-from-its-own-hyprland-lu
  omarchySessionLauncher = pkgs.writeShellScript "omarchy-session" ''
    export OMARCHY_PATH=${cfg.tree}
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
    ./fleet.nix
    (import ./services inputs)
    ./flatpaks.nix
    inputs.nix-flatpak.nixosModules.nix-flatpak

    # Declarative secrets, for the bundled services that need one. Imported
    # unconditionally and INERT: upstream gates its whole config on
    # `sops.secrets != {}` and `sops.templates != {}`, so a machine that
    # declares neither -- every Mode A machine, and every machine today --
    # gains no unit, no activation script and no package from this line.
    # nixarchy sets no sops option of its own; the host-key identity is
    # already upstream's default. tests/options.nix asserts both halves.
    inputs.sops-nix.nixosModules.sops
  ];

  options.programs.nixarchy = {
    enable = lib.mkEnableOption "Nixarchy, the Omarchy desktop vendored for NixOS";

    # Why: modules/AGENTS.md#nixarchy-wrote-this-machine-as-a-property-of-the-c
    installerManaged = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
      description = ''
        Whether this configuration descends from the host module the Nixarchy
        installer generates. Set by installer/host.nix and by nothing else.

        Surfaced to shell tools as /etc/nixarchy/managed, which is the single
        predicate every armed command gates on: nixarchy commits, pushes and
        rewrites configuration only on a machine it wrote.
      '';
    };

    tree = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.package}/share/omarchy";
      internal = true;
      description = ''
        What OMARCHY_PATH points at: Omarchy's tree, with the files nixarchy
        generates for THIS machine in it. modules/apps.nix sets it to a mirror
        of the package whose default/omarchy/omarchy-menu.jsonc carries the
        Install-row rewrites, which is what keeps that menu off pacman without
        taking the extension file upstream documents as the user's -- #210.

        Not readOnly, and defaulted to the package's own tree: a configuration
        with the apps module inert still has to resolve to something.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      # Why: modules/AGENTS.md#built-from-your-nixpkgs-through-this-flakes-overla
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

    flatpaks = {
      uninstallUnmanaged = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Remove Flatpaks that this configuration does not declare, including
          ones installed by hand with `flatpak install`.

          On, the file is the truth: the machine's Flatpaks are exactly what
          your configuration lists, and anything else is gone at the next
          rebuild. That is the same promise nixarchy already makes about
          packages, and it is the reason someone would want this.

          Off by default, and the default is the point. Removing software a
          person installed themselves is the one thing this project has said
          it will not do -- the README puts it as "deselecting is the only
          removal nixarchy is allowed to perform. An app that arrived from
          your own configuration is not this menu's to take away." Turning
          this on crosses that line, deliberately, on a machine where you have
          decided the configuration is the only truth.

          Neither answer is wrong. What would be wrong is deleting somebody's
          software without their having asked.
        '';
      };
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

    defaultAgent = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "claude"
          "codex"
          "opencode"
          "crush"
          "gemini"
          "copilot"
          "grok"
        ]
      );
      default = null;
      example = "opencode";
      description = ''
        Which coding agent this machine's Omarchy menu treats as the default:
        the one `omarchy-agent` launches, and the one the Ask menu's whole
        group is gated on.

        Setting this installs the agent and records the choice, so it survives
        a rebuild and travels to the next machine installed from this flake.
        Without it the choice exists only in
        `~/.config/omarchy/defaults/agent`, written by the menu at runtime --
        which is the one thing this project exists to replace.

        The menu still works and still writes that file, so a machine can be
        changed at a prompt. This option is authoritative on the next
        activation: the configuration is the source of truth, and a menu click
        that outlived a rebuild would be a second, invisible one.

        The ids match `omarchy-default-agent`'s. Absent from the list are `pi`,
        `omp` and `antigravity`, which nixpkgs has no package for -- that
        command falls back to mise for those, and an imperative install is not
        something an option should promise to reproduce.
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
        What to do about nixarchy's Plymouth boot splash.

        The theme DIRECTORY is called `omarchy`, and stays called that:
        `boot.plymouth.theme` names a directory, so renaming it means moving
        `themePackages` in the same breath. What is inside it is ours -- every
        image `omarchy.script` draws is drawn by `pkgs/omarchy/nixarchy-logo.py`
        and `nixarchy-plymouth-chrome.py`, and the theme's own `Name=` is
        nixarchy. `checks.options` asserts that, for this splash and for the
        live image's.

        `defer` sets it at `mkDefault`, so anything that names a theme of its
        own keeps it -- stylix does, which is why a stylix machine boots to the
        stylix splash with nixarchy installed. This is the default because a
        boot splash is a taste, and one already chosen should survive.

        `force` takes nixarchy's instead. Both `boot.plymouth.theme` and
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
        # versionAtLeast, not string >=: Nix compares strings lexicographically,
        # so "0.100.0" >= "0.55" is false and the day Hyprland reaches 0.100
        # this assertion would fire wrongly on every machine at once.
        assertion = lib.versionAtLeast (config.programs.hyprland.package.version or "0") "0.55";
        message = ''
          Nixarchy needs Hyprland >= 0.55 for the Lua config API that
          Omarchy 4.x is written against (hl.bind / hl.window_rule / hl.on).
          Use inputs.hyprland's package, not nixpkgs'.
        '';
      }
    ];

    # Why: modules/AGENTS.md#most-of-what-the-install-menu-offers-is-unfree
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
      # Why: modules/AGENTS.md#etc-nixos-belongs-to-the-installed-user-installer-
      git = {
        enable = lib.mkDefault true;
        config = {
          safe.directory = [ cfg.flake ];

          # Why: modules/AGENTS.md#the-literal-path-above-is-not-always-enough-becaus
          include.path = safeDirInclude;
        };
      };

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

      # Why: modules/AGENTS.md#mise-is-in-omarchys-base-packages-and-its-dev-env-
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

    # The resolved half of the flake's safe.directory entry -- see the
    # programs.git block above for why it cannot be written at evaluation
    # time. Writes a real path only when it differs from the configured one,
    # so on the normal case (a real directory at /etc/nixos) this leaves an
    # empty file and changes nothing.
    #
    # Always writes, never appends: the file is derived state, and a stale
    # entry left behind after somebody repoints programs.nixarchy.flake would
    # keep exempting a directory nobody asked about.
    system.activationScripts.nixarchyFlakeSafeDirectory = ''
      install -d -m 0755 -o root -g root /var/lib/nixarchy

      # readlink -f, not realpath: coreutils is guaranteed here and this runs
      # before much else. A flake directory that does not exist yet resolves
      # to nothing, which is the empty-file case and correct -- the machine
      # simply has no flake to exempt.
      nixarchy_flake_resolved=$(${pkgs.coreutils}/bin/readlink -f ${lib.escapeShellArg cfg.flake} 2>/dev/null || true)

      {
        echo "# Written by programs.nixarchy. Do not edit; see modules/nixos.nix."
        if [ -n "$nixarchy_flake_resolved" ] &&
           [ "$nixarchy_flake_resolved" != ${lib.escapeShellArg cfg.flake} ]; then
          echo "[safe]"
          echo "	directory = $nixarchy_flake_resolved"
        fi
      } > ${safeDirInclude}.tmp

      chmod 0644 ${safeDirInclude}.tmp
      chown root:root ${safeDirInclude}.tmp
      mv -f ${safeDirInclude}.tmp ${safeDirInclude}
    '';

    environment = {
      # The single indirection point. bin/, shell/, themes/, the Hyprland Lua
      # defaults and the menu's defaults file are all resolved relative to
      # this. It is the package's own tree unless the apps module has
      # generated one for this machine -- see programs.nixarchy.tree.
      sessionVariables = {
        OMARCHY_PATH = cfg.tree;

        # omarchy-capture-screenshot defaults this to tensaku-edit, which is an
        # Arch package and is not in nixpkgs, so the Edit on every screenshot
        # notification did nothing (#204). satty-edit is the wrapper the
        # omarchy package puts around satty -- already installed on every
        # machine here, and named by nothing until now. mkDefault so a machine
        # that does package tensaku, or wants gimp, just says so.
        OMARCHY_SCREENSHOT_EDITOR = lib.mkDefault "satty-edit";

        # The replacement omarchy-update reads this. It is a plain script
        # inside the package with no way to see module options, and it is
        # reached from the shell's bar widget and notifications as well as the
        # menu.
        NIXARCHY_FLAKE = cfg.flake;
      };

      # Omarchy's scripts are unwrapped by design (wrapping breaks the CLI's
      # metadata scan), so their dependencies have to be on the session PATH.
      systemPackages = [
        cfg.package
      ]
      # Why: modules/AGENTS.md#minus-hyprland-itself
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

        # Why: modules/AGENTS.md#config-hypr-xdph-conf-which-the-package-seeds-into
        hyprland-preview-share-picker

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
      # Why: modules/AGENTS.md#passed-straight-through
      flatpak.uninstallUnmanaged = lib.mkDefault cfg.flatpaks.uninstallUnmanaged;

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

      # Why: modules/AGENTS.md#cups-avahi-and-nss-mdns-are-all-in-base-packages
      printing.enable = lib.mkDefault true;
      printing.browsed.enable = lib.mkDefault false;
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

    # Why: modules/AGENTS.md#the-ownership-marker-for-the-shell-tools-that-cann
    environment.etc."nixarchy/managed" = lib.mkIf cfg.installerManaged {
      text = ''
        This machine's configuration descends from the host module the Nixarchy
        installer generates (installer/host.nix), so nixarchy commands that
        commit, push or rewrite configuration will act on it.

        Written declaratively by programs.nixarchy.installerManaged and renewed
        by every rebuild. Deleting it changes nothing until the next switch.

        nixarchy ${cfg.package.version}
      '';
    };

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

        # Why: modules/AGENTS.md#the-other-half-of-that-script-which-this-module-le
        allowedTCPPorts = [ 53317 ];
        allowedUDPPorts = [ 53317 ];
      };
      networkmanager.enable = lib.mkDefault true;
    };

    # Why: modules/AGENTS.md#install-config-lockscreen-pam-sh-whose-one-line-is
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

      # Why: modules/AGENTS.md#omarchy-path-default-systemd-user-which-upstream-i
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
          environment.OMARCHY_PATH = cfg.tree;
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

      # Why: modules/AGENTS.md#default-systemd-user-app-slice-d-10-oomd-conf
      user.units."app.slice" = {
        overrideStrategy = "asDropin";
        text = ''
          [Slice]
          ManagedOOMMemoryPressure=kill
          ManagedOOMSwap=kill
        '';
      };
    };

    # Compressed swap in RAM, because there is otherwise none at all.
    #
    # installer/disk-config.nix lays down @, @home, @nix, @log and the snapshot
    # subvolumes and no swap of any kind -- no partition, no file, no zram. A
    # tester asked why, which is the right question: a machine with no swap has
    # no headroom, and the first thing that notices is a big rebuild.
    #
    # What it costs today, on a machine with none:
    #
    #   systemd-oomd is enabled here and its per-slice policy is
    #   ManagedOOMSwap=kill -- a rule about swap pressure, on a system where
    #   swap pressure cannot happen. It falls back to memory pressure, which
    #   fires later and kills more.
    #
    #   A `nixos-rebuild` that evaluates a large closure is exactly the
    #   workload that wants to page out something idle, and cannot.
    #
    # zram rather than a swap file, and the reason is btrfs. A file on btrfs
    # needs its own nodatacow subvolume and the right attributes set before a
    # single byte is written; get it wrong and the kernel refuses to swapon,
    # usually on somebody else's machine. zram needs no disk layout at all, so
    # it works identically on an existing install and a fresh one -- and this
    # module is imported by machines whose partitioning nixarchy never chose.
    #
    # What it deliberately does NOT buy: hibernation. Suspend-to-disk needs
    # real swap at least the size of RAM, and zram cannot provide it -- see
    # docs/manual/troubleshooting.md for the swap file that can.
    #
    # 50% of RAM is the NixOS default and stays. It is a ceiling on the
    # COMPRESSED size, so at a typical 2-3x ratio it buys more than it reserves,
    # and the pages it holds are ones the machine was not touching.
    #
    # mkDefault, so an adopter who has real swap, or who hibernates, turns it
    # off in one line.
    zramSwap.enable = lib.mkDefault true;

    hardware = {
      # bin/omarchy-brightness-display-ddc talks to monitors over i2c
      i2c.enable = lib.mkDefault true;

      # Why: modules/AGENTS.md#bluez-bluez-tools-and-bluez-utils-are-all-in
      bluetooth.enable = lib.mkDefault true;

      # The CPU microcode, for whichever vendor this machine has.
      #
      # Same argument as the firmware below, and the same trap:
      # nixos-generate-config.pl:328-329 emits exactly these two lines, and
      # emits them only inside `if ($virt eq "none")`. So a real machine asks
      # for microcode and no VM ever does -- which meant the REFERENCE hosts
      # baked onto the image did not have it and every installed machine did.
      #
      # That difference is the drift tests/install.nix warns about: the seeded
      # system and the installed one must match, or the install has to build
      # what the medium cannot supply. It surfaced as an offline install
      # walking backwards into the texinfo bootstrap trying to compile
      # microcode-intel with no compiler -- a bare-metal report we had and
      # could not place.
      #
      # Setting it here rather than leaving it to the generated config is what
      # makes them match: reference and installed now agree by construction,
      # on metal and in a VM alike. nixpkgs ignores the vendor that is not
      # present, so naming both costs nothing.
      cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      # Wireless, Bluetooth and most graphics need a firmware blob, and this is
      # the option that puts one on the machine.
      #
      # It reads as belonging in hardware-configuration.nix, and nominally it is:
      # nixos-generate-config imports installer/scan/not-detected.nix, whose
      # entire content is `enableRedistributableFirmware = lib.mkDefault true`.
      # But it imports it only inside `if ($virt eq "none")` -- bare metal only,
      # nixos-generate-config.pl:321. So the installed system's firmware depends
      # on a generated import, and the generated import depends on a virt probe.
      #
      # That is untestable here by construction. Every guest we install into
      # reports a virt type, so every VM check takes the branch where this is
      # FALSE and no test can ever exercise the branch real users are on. The ISO
      # sets it (installation-device.nix), which is worse rather than better: the
      # installer has wifi and the machine it installs may not, and the report
      # that arrives is "it worked during the install".
      #
      # Redistributable, not All: this needs no allowUnfree and is what a desktop
      # wants. hardware.enableAllFirmware adds b43, brcm, facetimehd and the Xbox
      # dongles for ~2 MB more and does need it, so the doctor's Wireless section
      # names it per-card instead of it being turned on for everyone.
      #
      # mkDefault, so an adopter who has a reason to ship no blobs still wins.
      enableRedistributableFirmware = lib.mkDefault true;
    };

    # Why: modules/AGENTS.md#our-own-splash-in-the-theme-directory-upstreams-oc
    users.users = lib.optionalAttrs (cfg.user != null) {
      ${cfg.user}.extraGroups = [
        "input"
      ]
      # Why: modules/AGENTS.md#docker-is-enabled-above-at-mkdefault-for-every-mac
      ++ lib.optional config.virtualisation.docker.enable "docker";
    };

    # The newest kernel nixpkgs has, not the release default.
    #
    # This is a laptop distribution. NixOS defaults to an older, longer-lived
    # kernel because it also has to serve machines that have been running for
    # two years; nixarchy's problem is the opposite one, a machine bought last
    # month whose graphics or wifi has no driver in a kernel from last spring.
    #
    # Concretely, and the reason this changed: Dell, Intel and Omarchy shipped
    # `linux-ptl` for Panther Lake XPS machines -- roughly twenty backports
    # taken from Linux 7.0 release candidates, carried on Omarchy's own mirror
    # "until Linux 7.0 drops". nixarchy was shipping 6.18, older than the
    # kernel they had to work around, on hardware that needed 7.0-rc.
    #
    # Porting those backports would be the wrong answer. Linux 7.0 dropped;
    # nixpkgs carries 7.2 and will carry whatever is newest at the moment an
    # image is built, so tracking `linuxPackages_latest` gets the same fixes
    # from upstream with no patch set to maintain and nothing to forget to
    # retire. That is the NixOS-shaped version of what linux-ptl did.
    #
    # mkDefault, so an adopter who needs an LTS -- an out-of-tree module that
    # lags, a machine that is happy where it is -- sets boot.kernelPackages
    # and wins without touching this file.
    #
    # The two known hazards were measured rather than assumed: nothing in this
    # tree references ZFS, and the NVIDIA open driver evaluates against the
    # newest kernel in the current pin. When a future pin breaks that, it
    # breaks at evaluation with the package named, which is a better failure
    # than a machine that cannot see its screen.
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

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

    # Why: modules/AGENTS.md#default-fontconfig-conf-avail-50-omarchy-conf-whic
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

    # Why: modules/AGENTS.md#default-environment-d-10-omarchy-fcitx-conf-plus-t
    i18n.inputMethod = {
      enable = lib.mkOverride 1250 true;
      type = lib.mkOverride 1250 "fcitx5";
    };

    # Why: modules/AGENTS.md#fcitx5-says-this-itself-in-a-notification-on-every
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
