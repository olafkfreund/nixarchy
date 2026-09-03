inputs:
{
  # Declared with a default: home-manager only passes osConfig when it is used
  # as a NixOS module, and referencing an undefined argument would break every
  # standalone configuration.
  osConfig ? null,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;

  # Why: modules/AGENTS.md#what-omarchy-path-points-at-and-the-source-of-ever
  omarchyPath = osConfig.programs.nixarchy.tree or "${cfg.package}/share/omarchy";

  # Upstream's user menu file, which nixarchy does not write -- named here
  # because the activation below has to undo an older nixarchy having done so.
  menuExtensionPath = "${config.xdg.configHome}/omarchy/extensions/omarchy-menu.jsonc";

  # The local model is configured on the SYSTEM side -- it is a service and a
  # package set -- but its provider files live in a home. Read across rather
  # than declared twice, so the address the server binds and the address the
  # agents dial cannot disagree.
  #
  # `enable = false` when there is no osConfig: a standalone home-manager user
  # has no NixOS module to have turned this on, so every option below it is
  # inert and nothing is written.
  localAi = {
    enable = false;
    agents = [ ];
    model = "";
    contextWindow = 0;
    resolved.endpoint = "";
  }
  // (osConfig.programs.nixarchy.localAi or { });

  # The coding agent the menu treats as default, when the configuration names
  # one. Null on a standalone home-manager user, exactly like localAi above:
  # there is no NixOS module to have set it.
  defaultAgent = osConfig.programs.nixarchy.defaultAgent or null;

  # Same shape as localAi just above: declared on the NixOS side
  # (modules/services/boxes.nix), because `machines` names containers that
  # should exist regardless of which user's home-manager config is reading
  # this file, and applied here because Home Manager's `programs.distrobox`
  # is a per-user option with nowhere else to be set. `enable = false` when
  # there is no osConfig, for the same reason localAi's does: a standalone
  # home-manager user has no NixOS module to have turned this on.
  boxes = {
    enable = false;
    machines = { };
  }
  // (osConfig.programs.nixarchy.services.boxes or { });

  # Through the overlay on *your* nixpkgs, for the same reason cfg.package's
  # default takes that route: inputs.self.packages is built from nixarchy's own
  # nixpkgs, and a second copy of anything in home.packages is a buildEnv
  # collision. This one carries no dependencies, but the rule is the rule and
  # the next person copying this line will be packaging something that does.
  omarchyNvimConfig = (pkgs.extend inputs.self.overlays.default).omarchy-nvim-config;

  # Omarchy's Neovim configuration, appended to the seed activation rather than
  # wrapped around it: this is a string the activation interpolates, so adding
  # it costs the diff it is worth instead of re-indenting three hundred lines
  # of unrelated shell.
  #
  # It runs after the first-run theme, on purpose -- the colourscheme link
  # points into the current theme, and that directory is what omarchy-theme-set
  # has just created.
  nvimActivation =
    let
      nvimDir = "${config.xdg.configHome}/nvim";
      themeLink = "${nvimDir}/lua/plugins/theme.lua";
      themeTarget = "${config.home.homeDirectory}/.local/state/omarchy/current/theme/neovim.lua";
    in
    lib.optionalString (cfg.neovim != "off") (
      ''
        # Seed only into nothing. `seed_dir` would already refuse to clobber a
        # file, but a half-seeded editor config is worse than none: LazyVim
        # reads every .lua under lua/plugins as a plugin spec, so dropping
        # Omarchy's into somebody else's configuration means their setup now
        # loads two specs it never asked for. All or nothing, and "nothing" is
        # the answer whenever the directory exists.
        if [ ! -e "${nvimDir}" ]; then
          run mkdir -p "${nvimDir}"
          run ${pkgs.coreutils}/bin/cp -rn --no-preserve=mode,ownership \
            "${omarchyNvimConfig}/share/omarchy-nvim"/. "${nvimDir}"/ \
            2>/dev/null || true
          echo "nixarchy: seeded Omarchy's Neovim config into ${nvimDir}"
        fi

        # The colourscheme link, which is the whole of Omarchy's Neovim
        # theming: every stock theme ships a neovim.lua and this is what reads
        # it. Upstream's own migrations set this same link, and
        # migrations/1785002349.sh will not touch the path unless it is already
        # a symlink -- so neither does this. A theme.lua somebody wrote is
        # theirs.
        if [ ! -e "${themeLink}" ] || [ -L "${themeLink}" ]; then
          run mkdir -p "$(dirname "${themeLink}")"
          run ln -snf "${themeTarget}" "${themeLink}"
        else
          echo "nixarchy: kept your ${themeLink}, so Omarchy themes will not drive Neovim"
        fi
      ''
      + lib.optionalString (cfg.neovim == "adopt") ''
        # What `adopt` adds: naming the collisions rather than leaving them to
        # be discovered. Both are configurations that work on their own and
        # quietly disagree once the link above exists -- two LazyVim specs
        # setting opts.colorscheme, or a Home-Manager-owned tree where the link
        # cannot be written at all.
        for f in colorscheme.lua colourscheme.lua; do
          if [ -e "${nvimDir}/lua/plugins/$f" ]; then
            echo "nixarchy: ${nvimDir}/lua/plugins/$f also sets a colourscheme; it and the Omarchy theme link will disagree"
          fi
        done
        if [ -L "${nvimDir}/init.lua" ] \
          && case "$(readlink "${nvimDir}/init.lua")" in /nix/store/*) true ;; *) false ;; esac; then
          echo "nixarchy: ${nvimDir} is managed by Home Manager; add the theme link there rather than here"
        fi
      ''
    );

  # Why: modules/AGENTS.md#each-declared-plugin-checked-at-build-time-against
  validatedPlugins = lib.mapAttrs (
    name: plugin:
    pkgs.runCommand "nixarchy-plugin-${name}"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.findutils
        ];
      }
      ''
        src=${plugin.src}
        if [ ! -f "$src/manifest.json" ]; then
          echo "programs.nixarchy.plugins.${name}: no manifest.json in $src." >&2
          echo "An Omarchy plugin is a directory with a manifest.json at its root." >&2
          exit 1
        fi

        # PATH so the script finds the tools it shells out to; OMARCHY_PATH
        # because everything in bin/ resolves through it.
        export OMARCHY_PATH=${omarchyPath}
        export PATH=${
          lib.makeBinPath [
            pkgs.jq
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
          ]
        }:$PATH
        if ! ${omarchyPath}/bin/omarchy-plugin-validate "$src"; then
          echo "" >&2
          echo "programs.nixarchy.plugins.${name} would not load." >&2
          exit 1
        fi

        # Why: modules/AGENTS.md#a-plugin-that-shells-out-to-pacman-fails-the-rebui
        hits=$(
          find "$src" -type f \( -name '*.qml' -o -name '*.js' -o -name '*.sh' -o -name '*.bash' \) -print0 |
            xargs -0 -r grep -nHE '\bpacman\b|\byay\b' |
            grep -vE ':[0-9]+:[[:space:]]*(//|#)' || true
        )
        if [ -n "$hits" ]; then
          echo "" >&2
          echo "programs.nixarchy.plugins.${name} runs pacman or yay:" >&2
          printf '%s\n' "$hits" | sed "s|^$src/|  |" >&2
          echo "" >&2
          echo "Neither exists on NixOS, so this plugin would install, appear in" >&2
          echo "the bar, and fail the first time it is used. Packages come from" >&2
          echo "the Install menu or your configuration here; a plugin cannot" >&2
          echo "install its own." >&2
          echo "" >&2
          echo "If the plugin only MENTIONS them in prose, move that to a" >&2
          echo "whole-line comment -- this ignores those." >&2
          exit 1
        fi

        id=$(jq -r '.id' "$src/manifest.json")
        mkdir -p $out
        echo -n "$id" > $out/id
        ln -s "$src" $out/plugin
      ''
  ) cfg.plugins;
in
{
  # Nixi: the guide that should come with nixarchy -- a live hands-on tour,
  # an offline-first manual search, and an AI tutor grounded in this machine.
  #
  # Imported unconditionally, and TURNED ON for every nixarchy desktop below.
  # Upstream's whole config is `lib.mkIf cfg.enable`, so `false` really does
  # leave nothing behind -- no unit, no timer, no plugin folder, no package,
  # and therefore nothing listening on 8642. That is the half tests/options.nix
  # spends most of its nixi cases on, because with a default of `true` it is
  # the half nobody exercises on purpose.
  #
  # No option of nixarchy's own wrapping it, which is data/services.nix's
  # "plain" rule applied one directory over: `services.nixi.enable = false`
  # is one line, it is the line nixi's own documentation shows, and a
  # `programs.nixarchy.services.nixi` alias would be a second name for one
  # switch plus RFC 42's staleness problem. What a default-on bundle owes the
  # user is not a second option but a findable answer, so the README feature
  # table and docs/manual/getting-started.md both say it is on and both show
  # the line that turns it off.
  #
  # It is also why no row was added to data/services.nix. That catalogue
  # generates ~/.config/nixarchy/services.nix, which is a NixOS file; nixi is
  # a home-manager module and there is no NixOS option for a row to write.
  imports = [ inputs.nixi.homeModules.default ];

  options.programs.nixarchy = {
    enable = lib.mkEnableOption "the Omarchy user session";

    package = lib.mkOption {
      type = lib.types.package;
      # From *your* nixpkgs through this flake's overlay, for the same reason
      # the NixOS module does it: inputs.self.packages is built from
      # nixarchy's own nixpkgs, so its ~80 runtime dependencies are a second
      # copy of packages you may already have. home.packages is exactly where
      # that surfaces -- buildEnv refuses a profile holding two builds of the
      # same tesseract, and says so in a way that looks like a nix bug.
      default = (pkgs.extend inputs.self.overlays.default).omarchy;
      defaultText = lib.literalExpression "(pkgs.extend nixarchy.overlays.default).omarchy";
      description = "The vendored Omarchy tree providing OMARCHY_PATH.";
    };

    neovim = lib.mkOption {
      type = lib.types.enum [
        "theme-only"
        "adopt"
        "off"
      ];
      default = "theme-only";
      description = ''
        What to do about Omarchy's Neovim configuration, which on Arch arrives
        as the `omarchy-nvim` package.

        Neovim itself is installed either way -- it is one of the omarchy
        package's runtime dependencies, as it is one of upstream's base
        packages. This is only about `~/.config/nvim`, which is yours.

        `theme-only` (the default) links Neovim's colourscheme to the Omarchy
        theme, and seeds the rest of the configuration only when there is no
        `~/.config/nvim` at all. On a machine that has never had Neovim
        configured -- a fresh install -- that is the whole Omarchy setup. On a
        machine that already has one, it is one file added and nothing touched.

        `adopt` is the same, except it says out loud what it did not do, so a
        configuration that was kept rather than replaced is visible rather than
        silently ignored.

        `off` leaves `~/.config/nvim` alone entirely, including the theme link.

        Nothing here ever overwrites a file you wrote. There is no setting that
        does: an editor configuration is not this module's to replace.
      '';
    };

    defaultTheme = lib.mkOption {
      type = lib.types.str;
      default = "tokyo-night";
      description = "Theme applied on first login only. Switchable at runtime afterwards.";
    };

    # Why: modules/AGENTS.md#declares-which-plugins-are-present-and-deliberatel
    plugins = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.src = lib.mkOption {
            type = lib.types.path;
            description = ''
              A directory containing the plugin's manifest.json -- a flake
              input, a fetchgit, or a path in your own configuration.
            '';
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          omteleprompt.src = pkgs.fetchgit {
            url = "https://github.com/seyhunak/omteleprompt.git";
            rev = "9a35865220a0c9d65132329e446a84c466545110";
            hash = "sha256-KJM/AC1DnPwob40lo39Rlk9qkyKTI++bss1wPIcGsTs=";
          };
        }
      '';
      description = ''
        Omarchy shell plugins to install declaratively.

        Each is symlinked into ~/.config/omarchy/plugins under the id from its
        own manifest.json, which is the name the shell and every omarchy-plugin-*
        command already use. Validated at build time against the same schema the
        shell enforces, so a broken manifest fails the rebuild rather than
        quietly failing to load after you log in.

        This installs a plugin; it does not enable it. Enable it once from
        Setup > Plugins or with `omarchy plugin enable <id>` and that choice
        persists, because the shell records it in shell.json rather than in the
        plugin folder. `omarchy plugin add` still works alongside this for
        anything you would rather not pin.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    # THE ONE LINE. The guide ships on, and this is where that is decided:
    # `false` here takes it off every nixarchy desktop, and mkDefault means a
    # user's own `services.nixi.enable = false` outranks us without needing
    # mkForce -- which is the whole reason a default-on bundle is allowed to
    # be a default at all.
    #
    # On rather than off is a change to machines that already exist: a desktop
    # that rebuilds after this gains a guide it did not ask for. That is the
    # maintainer's call, taken deliberately -- a guide nobody has to discover
    # is the difference between a beginner's desktop and a desktop for people
    # who already know. What it owes in return is that the answer be findable
    # without reading this file, so the README feature table and
    # docs/manual/getting-started.md both name it and both show the one line
    # above.
    services.nixi.enable = lib.mkDefault true;

    # And the two defaults nixarchy deliberately does NOT change.
    #
    # `barWidget.enable` is true upstream, and stays true here -- which with
    # the default above means every desktop gets the snowflake. It reads like
    # "nixarchy silently puts a button on your bar", and on Arch it would be
    # -- but not on this desktop. All it does is drop a plugin folder into
    # ~/.config/omarchy/plugins/, and an installed plugin is not an enabled
    # one: enablement lives in shell.json, which the running shell owns and
    # nothing here writes. That is the same guarantee programs.nixarchy.plugins
    # above makes, and tests/plugin.nix asserts it against a real session --
    # a declaratively installed plugin comes up listed and NOT enabled, to be
    # turned on once from Setup > Plugins. So the honest description of the
    # default is "the guide is installed and offered", not "a button appeared".
    # Re-defaulting it to false would not save anyone a button; it would hide
    # the widget from the plugin picker and leave a server on 8642 with no way
    # to reach it.
    #
    # `menuEntry.enable` is false upstream and stays false, and #220 does not
    # change that. Nixi declines the Omarchy menu extension because owning it
    # means owning the whole file -- and #220 is nixarchy getting OUT of that
    # file for exactly the same reason, so that upstream's merge and
    # third-party plugins can have it (shell/plugins/README.md tells plugins to
    # write it). Handing it straight to a different Nix-managed writer would
    # spend the freedom the moment it arrived. Today it is worse than
    # unnecessary: nixarchy's own activation still relinks that path, so
    # turning nixi's menu entry on before #220 lands does nothing at all, in
    # silence. Nixi does not need the row either way -- the bar widget is its
    # front door.
    #
    # The default above sharpens this rather than softening it: nixi is now on
    # everywhere, so a future nixi that starts managing menu rows would be
    # managing them on every nixarchy machine. Whoever bumps the pin should
    # re-read this comment, and tests/options.nix fails if that default moves.

    # Why: modules/AGENTS.md#omarchys-desktop-is-its-hyprland-config
    warnings =
      let
        ownsHyprConfig =
          (config.wayland.windowManager.hyprland.enable or false)
          || lib.any (n: lib.hasPrefix "hypr/" n) (lib.attrNames config.xdg.configFile);

        # Why: modules/AGENTS.md#whether-there-is-an-omarchy-session-entry-to-log-i
        hasOmarchySession =
          (osConfig.programs.nixarchy.enable or false) && (osConfig.programs.nixarchy.session or true);
      in
      lib.optional (ownsHyprConfig && !hasOmarchySession) ''
        nixarchy: ~/.config/hypr is already managed by Home Manager
        (wayland.windowManager.hyprland, or an xdg.configFile "hypr/..." entry).

        Omarchy's hyprland.lua is therefore NOT installed -- the seed never
        overwrites a file you own -- so nothing in ~/.config/hypr loads
        Omarchy's bar or its keybindings.

        There is also no "Omarchy" session entry to log into, because
        programs.nixarchy.session is off. Between the two, this configuration
        gets Omarchy's applications and menus but never its desktop.

        Turn programs.nixarchy.session back on. It registers a session that
        runs Hyprland against Omarchy's own hyprland.lua with --config, so it
        needs nothing in ~/.config/hypr, and both desktops work: yours stays
        yours, Omarchy's is Omarchy's.
      '';

    home = {
      # The runtime dependencies go in only when the NixOS module is not
      # already providing them. Listing them in both places is not merely
      # redundant, it is what turns a package you have overridden into a
      # broken rebuild: home.packages and environment.systemPackages are
      # different profiles, and buildEnv refuses a profile holding two builds
      # of the same program. A config carrying its own
      # `pkgs.tesseract.override { ... }` collided with the stock one here,
      # and said so as "two given paths contain a conflicting subpath" naming
      # the same version twice.
      packages = [
        cfg.package
      ]
      ++ lib.optionals (!(osConfig.programs.nixarchy.enable or false)) cfg.package.passthru.runtimeDeps;

      sessionVariables.OMARCHY_PATH = omarchyPath;

      # Same reason as the NixOS module's copy: upstream's default screenshot
      # editor, tensaku-edit, is not in nixpkgs, so the Edit on the screenshot
      # notification was dead (#204). Set here too because this module is also
      # usable standalone, without programs.nixarchy.
      sessionVariables.OMARCHY_SCREENSHOT_EDITOR = lib.mkDefault "satty-edit";

      # Seed, don't manage: these files are copied, never symlinked. Omarchy
      # expects the user to edit ~/.config/hypr/*.lua by hand and rewrites
      # ~/.local/state/omarchy at runtime, both of which Home Manager's
      # read-only store symlinks would break. Existing files are never
      # overwritten.
      activation.nixarchySeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                seed_dir() {
                  local src="$1" dest="$2"
                  [ -d "$src" ] || return 0
                  run mkdir -p "$dest"
                  # --no-clobber: a file the user has edited is theirs, not ours.
                  run ${pkgs.coreutils}/bin/cp -rn --no-preserve=mode,ownership \
                    "$src"/. "$dest"/ 2>/dev/null || true
                }

                # One shipped default, under a name of our choosing. A plain `cp -n` is
                # not enough on its own: the sources are store paths, and a branding
                # file that lands r--r--r-- is one the user cannot edit, which is the
                # entire point of the two of them.
                seed_file() {
                  local src="$1" dest="$2"
                  [ -f "$src" ] || return 0
                  if [ ! -e "$dest" ]; then
                    run mkdir -p "$(dirname "$dest")"
                    run ${pkgs.coreutils}/bin/cp --no-preserve=mode,ownership "$src" "$dest"
                  fi
                }

                # Report what was kept rather than replaced. Without this the seed is
                # silent about the one case that matters -- a hyprland.lua owned by
                # something else, which leaves Omarchy's session files unread.
                note_kept() {
                  local src="$1" dest="$2" f
                  [ -d "$src" ] || return 0
                  for f in "$src"/*; do
                    [ -f "$f" ] || continue
                    if [ -e "$dest/$(basename "$f")" ] \
                      && ! ${pkgs.diffutils}/bin/diff -q \
                        "$f" "$dest/$(basename "$f")" >/dev/null 2>&1; then
                      echo "nixarchy: kept your $dest/$(basename "$f"), not Omarchy's"
                    fi
                  done
                }

                # The whole of config/, not a chosen two of it. Upstream's own docs
                # point at ~/.config/foot/foot.ini and ~/.config/starship.toml, and
                # omarchy-theme-set-foot, btop's color_theme and the tmux keybindings
                # all read from ~/.config -- so seeding only hypr and omarchy left
                # starship on its stock prompt, tmux without Omarchy's prefix and
                # keybindings, and foot and btop unthemed.
                seed_dir "${omarchyPath}/config" "${config.xdg.configHome}"
                note_kept "${omarchyPath}/config/hypr" "${config.xdg.configHome}/hypr"

                # And say, once, which session to pick.
                #
                # The twelve-line warning that used to cover this fired on every
                # rebuild of a machine that was already logging into Omarchy correctly.
                # This is the same fact in one line, printed only when the situation
                # applies: home-manager owns the hypr config, so Omarchy's own is not
                # installed and the session entry is the way in.
                if [ -e "${config.xdg.configHome}/hypr/hyprland.lua" ] \
                  && [ -L "${config.xdg.configHome}/hypr/hyprland.lua" ]; then
                  echo "nixarchy: ~/.config/hypr is yours; log in through the \"Omarchy\" session for Omarchy's desktop"
                fi

                # install/user/theme.sh. btop.conf asks for a theme named "current",
                # and omarchy-theme-set-templates renders btop.theme into the current
                # theme on every switch, so this one symlink is what makes btop follow
                # the theme. Dangling until the first theme is set, which is fine.
                run mkdir -p "${config.xdg.configHome}/btop/themes"
                run ln -snf \
                  "${config.home.homeDirectory}/.local/state/omarchy/current/theme/btop.theme" \
                  "${config.xdg.configHome}/btop/themes/current.theme"

                run mkdir -p "${config.home.homeDirectory}/.local/state/omarchy/current"

                # Why: modules/AGENTS.md#the-hyprland-toggles-tree-and-deliberately-only-fl
                seed_file "${omarchyPath}/default/hypr/toggles/flags.lua" \
                  "${config.home.homeDirectory}/.local/state/omarchy/toggles/hypr/flags.lua"

                # tensaku's shipped default. Nothing reads it yet -- tensaku-edit, the
                # screenshot editor omarchy-capture-screenshot reaches for, is not
                # packaged here -- but it is one of the files upstream's /etc/skel
                # plants, and seeding it now means packaging tensaku later does not need
                # a second pass over $HOME.
                seed_dir "${omarchyPath}/default/tensaku" \
                  "${config.home.homeDirectory}/.local/state/tensaku"

                # omarchy-branding-screensaver writes straight into this directory and
                # never creates it, so editing the screensaver text failed with
                # "E212: Can't open file for writing". Upstream's config skeleton does
                # not ship it either.
                run mkdir -p "${config.xdg.configHome}/omarchy/branding"

                # Why: modules/AGENTS.md#and-the-two-files-that-belong-in-it-which-upstream
                seed_file "${omarchyPath}/icon.txt" \
                  "${config.xdg.configHome}/omarchy/branding/about.txt"
                seed_file "${omarchyPath}/logo.txt" \
                  "${config.xdg.configHome}/omarchy/branding/screensaver.txt"

                # Why: modules/AGENTS.md#the-extensions-directory-and-one-thing-to-undo-in-
                run mkdir -p "${config.xdg.configHome}/omarchy/extensions"
                case "$(readlink "${menuExtensionPath}" 2>/dev/null)" in
                  /etc/nixarchy/*)
                    run rm -f "${menuExtensionPath}"
                    echo "nixarchy: ${menuExtensionPath} is yours now, not a link into /etc"
                    ;;
                esac
                seed_file "${omarchyPath}/config/omarchy/extensions/omarchy-menu.jsonc" \
                  "${menuExtensionPath}"

                # Why: modules/AGENTS.md#agent-skills-relinked-on-every-activation
                ${
                  let
                    skillsDir = "${omarchyPath}/default/agents/skills";
                  in
                  ''
                    for agentdir in .agents/skills .claude/skills .codex/skills .pi/agent/skills; do
                      dest="${config.home.homeDirectory}/$agentdir"
                      run mkdir -p "$dest"

                      for link in "$dest"/*; do
                        [ -L "$link" ] || continue
                        case "$(readlink "$link")" in
                          /nix/store/*/agents/skills/*) run rm -f "$link" ;;
                        esac
                      done

                      ${pkgs.findutils}/bin/find ${skillsDir} -mindepth 1 -maxdepth 1 -type d |
                        while read -r skill; do
                          run ln -sfn "$skill" "$dest/$(basename "$skill")"
                        done
                    done
                  ''
                }

                # Why: modules/AGENTS.md#declared-plugins-linked-in-by-the-id-their-manifes
                run mkdir -p "${config.xdg.configHome}/omarchy/plugins"
                ${
                  let
                    dir = "${config.xdg.configHome}/omarchy/plugins";
                    manifest = "${dir}/.nixarchy-managed";
                  in
                  ''
                    # Remove links from a previous generation before planting this
                    # one's, so a plugin dropped from the configuration goes away.
                    # Guarded on being a symlink: if you replaced one with a real
                    # checkout, that is yours and is left alone.
                    if [ -e "${manifest}" ]; then
                      while IFS= read -r stale; do
                        [ -n "$stale" ] || continue
                        if [ -L "${dir}/$stale" ]; then
                          run rm -f "${dir}/$stale"
                        fi
                      done < "${manifest}"
                    fi
                    run rm -f "${manifest}"
                    ${lib.concatMapStringsSep "
        " (drv: ''
                      id=$(cat ${drv}/id)
                      if [ -e "${dir}/$id" ] && [ ! -L "${dir}/$id" ]; then
                        echo "nixarchy: ${dir}/$id is your own directory, not replacing it"
                      else
                        run ln -sfn "$(readlink -f ${drv}/plugin)" "${dir}/$id"
                        echo "$id" >> "${manifest}"
                      fi
                    '') (lib.attrValues validatedPlugins)}
                    # Only when this module actually planted something. The file
                    # exists to remember which links to clean up next time, and
                    # creating it for a user who declares no plugins leaves an empty
                    # file sitting in their plugins directory meaning nothing --
                    # noticed on a real machine, where it was the only thing in there.
                    if [ -s "${manifest}" ]; then
                      :
                    else
                      run rm -f "${manifest}"
                    fi
                  ''
                }

                # The app selection. Seeded once and never touched again -- it holds
                # the user's picks, and clobbering it would silently undo them.
                # /etc/nixarchy/apps-template.nix always holds the current full list,
                # so a newly packaged app is discoverable with a diff against it.
                # Three files now: apps.nix, services.nix and advanced.nix.
                # Each seeded independently and only when absent, so a machine
                # that predates the split gains the two new ones and keeps the
                # apps.nix it already has.
                run mkdir -p "${config.xdg.configHome}/nixarchy"
                for part in apps services advanced; do
                  if [ ! -e "${config.xdg.configHome}/nixarchy/$part.nix" ] \
                    && [ -e "/etc/nixarchy/$part-template.nix" ]; then
                    run ${pkgs.coreutils}/bin/install -m600 \
                      "/etc/nixarchy/$part-template.nix" \
                      "${config.xdg.configHome}/nixarchy/$part.nix"
                  fi
                done

                # First-run theme. omarchy-theme-set is the only thing that may write
                # this tree; running it headless avoids poking a shell that is not up.
                if [ ! -e "${config.home.homeDirectory}/.local/state/omarchy/current/theme.name" ]; then
                  # PATH, not just the absolute path to the script: omarchy-theme-set
                  # calls its siblings by bare name -- omarchy-theme-set-templates and
                  # omarchy-theme-color among them -- and has no `set -e`. Without the
                  # package on PATH they were simply not found and it carried on and
                  # exited 0, so no template was ever rendered: the first-run theme had
                  # no btop.theme, foot.ini, alacritty.toml or gum_env.lua at all.
                  run env OMARCHY_PATH="${omarchyPath}" OMARCHY_THEME_HEADLESS=1 \
                    PATH="${cfg.package}/bin:${lib.makeBinPath cfg.package.passthru.runtimeDeps}:$PATH" \
                    ${cfg.package}/bin/omarchy-theme-set "${cfg.defaultTheme}" || true
                fi
        ${nvimActivation}
      '';
    };

    # Why: modules/AGENTS.md#the-first-run-theme-above-is-applied-headless-whic
    systemd.user.services.omarchy-theme-gnome = {
      Unit = {
        Description = "Apply the current Omarchy theme's light/dark mode to GTK";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        # omarchy-theme-set-gnome shells out to omarchy-theme-color and
        # gsettings, and a user unit does not inherit the login PATH.
        Environment = [
          "PATH=${cfg.package}/bin:${pkgs.glib}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin:%h/.nix-profile/bin"
          "OMARCHY_PATH=${omarchyPath}"
        ];
        ExecStart = [
          "${cfg.package}/bin/omarchy-theme-set-gnome"
          "${cfg.package}/bin/omarchy-cursor-set"
        ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Omarchy's own extension point -- omarchy-theme-set ends with
    # `omarchy-hook theme-set`, which runs everything in this directory. Going
    # through it rather than replacing omarchy-theme-set-gnome means the cursor
    # follows a theme change without this repo owning a fork of that script.
    xdg.configFile."omarchy/hooks/theme-set.d/cursor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${cfg.package}/bin/omarchy-cursor-set
      '';
    };

    # The default agent, recorded where omarchy-agent and the menu read it.
    #
    # ~/.config/omarchy/defaults/agent is upstream's file, written by
    # omarchy-default-agent when someone picks an agent from the menu. That
    # makes the choice imperative: it does not survive a reinstall and does not
    # travel to the next machine, which is the one thing this project exists to
    # replace.
    #
    # Written on every activation rather than seeded once, and the difference
    # matters: the option is the configuration's answer to "which agent", and a
    # menu click that outlived a rebuild would be a second answer with no
    # record. The menu still works -- it writes this file and takes effect
    # immediately -- it just does not outlive the next rebuild on a machine
    # that has declared one. programs.nixarchy.defaultAgent says so.
    #
    # Not an xdg.configFile, for the same reason the opencode provider below is
    # not: a read-only symlink here would make omarchy-default-agent fail at
    # the moment someone clicks the menu, which is worse than being overwritten
    # later.
    home.activation.nixarchyDefaultAgent = lib.mkIf (defaultAgent != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        agentfile="''${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/defaults/agent"
        run mkdir -p "$(dirname "$agentfile")"

        # Temp file and move, so an interrupted activation cannot leave the
        # menu reading half an agent name and launching nothing.
        tmp=$(${pkgs.coreutils}/bin/mktemp)
        printf '%s\n' ${lib.escapeShellArg defaultAgent} > "$tmp"
        run mv "$tmp" "$agentfile"
      ''
    );

    # Why: modules/AGENTS.md#provider-files-for-the-local-model-when-the-system
    home.activation.nixarchyOpencodeProvider =
      lib.mkIf (localAi.enable && builtins.elem "opencode" localAi.agents)
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            conf="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
            run mkdir -p "$(dirname "$conf")"
            [ -s "$conf" ] || echo '{}' > "$conf"

            # Written to a temp file and moved, so an interrupted activation
            # cannot leave the user with half a config and no working agent.
            tmp=$(${pkgs.coreutils}/bin/mktemp)
            if ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$conf" ${
              pkgs.writeText "opencode-provider.json" (
                builtins.toJSON {
                  "$schema" = "https://opencode.ai/config.json";
                  provider.ollama = {
                    npm = "@ai-sdk/openai-compatible";
                    name = "Ollama (local)";
                    options.baseURL = localAi.resolved.endpoint or "";
                    models.${localAi.model} = {
                      name = localAi.model;
                      limit = {
                        context = if localAi.contextWindow != null then localAi.contextWindow else 32768;
                        output = 8192;
                      };
                    };
                  };
                }
              )
            } > "$tmp"; then
              run mv "$tmp" "$conf"
            else
              rm -f "$tmp"
              echo "nixarchy: could not merge the local model into $conf" >&2
            fi
          ''
        );

    # Why: modules/AGENTS.md#pi-keeps-its-configuration-in-pi-agent-not-under-x
    home.activation.nixarchyPiProvider =
      lib.mkIf (localAi.enable && builtins.elem "pi" localAi.agents)
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            conf="$HOME/.pi/agent/models.json"
            run mkdir -p "$(dirname "$conf")"
            [ -s "$conf" ] || echo '{}' > "$conf"

            tmp=$(${pkgs.coreutils}/bin/mktemp)
            if ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$conf" ${
              pkgs.writeText "pi-provider.json" (
                builtins.toJSON {
                  providers.ollama = {
                    baseUrl = localAi.resolved.endpoint or "";
                    api = "openai-completions";
                    # Ignored by Ollama, but pi requires the field to be present.
                    apiKey = "ollama";
                    # pi sends system instructions in the `developer` role to
                    # reasoning-capable models. Ollama -- like vLLM and SGLang --
                    # rejects a role it does not know, and every request then fails
                    # with an error that does not name the cause.
                    compat.supportsDeveloperRole = false;
                    models = [
                      {
                        id = localAi.model;
                        contextWindow = if localAi.contextWindow != null then localAi.contextWindow else 32768;
                        maxTokens = 8192;
                      }
                    ];
                  };
                }
              )
            } > "$tmp"; then
              run mv "$tmp" "$conf"
            else
              rm -f "$tmp"
              echo "nixarchy: could not merge the local model into $conf" >&2
            fi
          ''
        );

    # settings.json is where pi reads defaultProvider/defaultModel, and it is
    # also where omarchy-theme-set-pi writes the theme -- with
    # `jq '.theme = ...'`, an in-place merge that preserves every other key.
    #
    # So it cannot be a home-manager symlink: theme-set would try to mv over a
    # read-only store path and fail on every theme change. It is seeded instead,
    # by the activation below, and only when absent -- after which it belongs to
    # the user and to theme-set, and nothing here touches it again.
    home.activation.nixarchyPiDefaultModel =
      lib.mkIf (localAi.enable && builtins.elem "pi" localAi.agents)
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            settings="$HOME/.pi/agent/settings.json"
            if [ ! -e "$settings" ]; then
              run mkdir -p "$HOME/.pi/agent"
              run install -m 0644 ${
                pkgs.writeText "pi-settings.json" (
                  builtins.toJSON {
                    defaultProvider = "ollama";
                    defaultModel = localAi.model;
                  }
                )
              } "$settings"
              echo "nixarchy: pointed pi at the local model (${localAi.model})"
            fi
          ''
        );

    # Why: modules/AGENTS.md#same-extension-point-on-the-other-hook-omarchy-alr
    xdg.configFile."omarchy/hooks/post-boot.d/config-repo" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash

        # --exec makes these clickable, which is the whole reason a notification
        # works here at all: acting on it is one click when the user is ready,
        # and ignoring it costs them nothing.
        if ${cfg.package}/bin/nixarchy-config-repo --check; then
          ${cfg.package}/bin/omarchy-notification-send \
            -u normal \
            "Back up your NixOS configuration" \
            "Everything this machine is lives in one uncommitted directory. Click to set up a backup." \
            --exec ${cfg.package}/bin/omarchy-launch-floating-terminal-with-presentation \
              ${cfg.package}/bin/nixarchy-config-repo
        elif ${cfg.package}/bin/nixarchy-config-repo --check-drift; then
          ${cfg.package}/bin/omarchy-notification-send \
            -u normal \
            "Your configuration has drifted from its backup" \
            "Changes made here have not been pushed for a while. Click to commit and push them." \
            --exec ${cfg.package}/bin/omarchy-launch-floating-terminal-with-presentation \
              ${cfg.package}/bin/nixarchy-config-repo --drift
        fi
      '';
    };

    # No systemd unit for the shell. Upstream starts it from Hyprland itself:
    #
    #   default/hypr/autostart.lua
    #   hl.on("hyprland.start", function() hl.exec_cmd("omarchy-launch-shell") end)
    #
    # A graphical-session.target unit runs before the compositor is up, and
    # omarchy-launch-shell responds to that by exiting 0 -- see its
    # compositor_alive() guard. The unit therefore "succeeded" while starting
    # nothing, and duplicated a launch Hyprland was already doing correctly.

    # The declared half of boxes (#257; the imperative half is `distrobox`
    # itself, installed by modules/services/boxes.nix). `machines` came over
    # from the NixOS side above; everything else here is what turns it into
    # containers Home Manager's own module actually writes.
    programs.distrobox = lib.mkIf boxes.enable {
      # Scalars, so mkDefault throughout -- see the header of
      # modules/services/default.nix. This is Home Manager's option, not
      # ours, but the same Mode A reasoning holds: someone who already set
      # programs.distrobox by hand in their own home-manager config keeps
      # their definition, and this yields to it. `containers` is the one
      # attrset here and stays plain assignment for the same reason -- see
      # that file's header for why mkDefault on a merging type is a bug
      # rather than a courtesy.
      enable = lib.mkDefault true;
      containers = boxes.machines;

      # Never `pkgs.distrobox` -- that would go through the overlay/plain
      # nixpkgs pkgs this file already has and add a SECOND profile entry for
      # the same package modules/services/boxes.nix already put in
      # environment.systemPackages. `null` here means Home Manager's module
      # installs nothing: one copy of distrobox, reached the way its own
      # comment requires -- by bare name, through
      # /run/current-system/sw/bin, never a store path.
      package = lib.mkDefault null;

      # Why: modules/AGENTS.md#left-at-home-managers-own-default-everywhere-else-
      enableSystemdUnit = lib.mkDefault false;
    };
  };
}
