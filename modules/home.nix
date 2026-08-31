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
  omarchyPath = "${cfg.package}/share/omarchy";

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

  # Each declared plugin, checked at build time against the schema the shell
  # enforces, and carrying the id its own manifest claims.
  #
  # Validated with upstream's own omarchy-plugin-validate rather than a
  # reimplementation of it here: that script exists precisely to refuse what
  # the running shell would silently reject, and a second copy of those rules
  # in Nix would drift from it at the first upstream bump. A plugin that would
  # not load now fails the rebuild, with the reason, instead of being installed
  # and doing nothing.
  #
  # The id comes out of manifest.json rather than the attribute name. It is
  # what the shell, the menu and every omarchy-plugin-* command key on, and a
  # directory named anything else would be a plugin the user cannot enable,
  # disable or remove by the name they see on screen.
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

        id=$(jq -r '.id' "$src/manifest.json")
        mkdir -p $out
        echo -n "$id" > $out/id
        ln -s "$src" $out/plugin
      ''
  ) cfg.plugins;
in
{
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

    # Declares which plugins are *present*, and deliberately not which are on.
    #
    # Upstream already splits the two: a plugin's code lives in
    # ~/.config/omarchy/plugins/<id>/, while whether it is enabled, and where
    # it sits in the bar, is recorded separately in ~/.config/omarchy/shell.json
    # by the running shell. Content and state are already different files, so
    # the content can come from the store without freezing the state.
    #
    # Enablement is therefore left alone on purpose. Managing shell.json here
    # would mean a plugin you turned off in Setup > Plugins came back at the
    # next rebuild, which is the sort of thing that makes people stop using the
    # menu. Declare the plugin, enable it once, and your choice persists.
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
    # Omarchy's desktop is its Hyprland config: hyprland.lua requires
    # autostart.lua, which is what starts the bar, and bindings.lua, which is
    # every keybinding the manual documents. The seed below is --no-clobber, so
    # a hyprland.lua that Home Manager already owns is kept and the other seven
    # files land beside it, loaded by nothing.
    #
    # That failure is silent and total: every Omarchy binary, menu and theme
    # installs, `nixarchy` looks like it worked, and the session that comes up
    # is the user's own with no bar and none of the keybindings. Worth a
    # warning rather than leaving someone to work it out from an empty bar.
    warnings =
      let
        ownsHyprConfig =
          (config.wayland.windowManager.hyprland.enable or false)
          || lib.any (n: lib.hasPrefix "hypr/" n) (lib.attrNames config.xdg.configFile);

        # Whether there is an Omarchy session entry to log into.
        #
        # When there is, a home-manager-owned ~/.config/hypr is not a problem:
        # it is the arrangement this module is built for, and the session runs
        # Omarchy's config with --config regardless. Warning anyway meant every
        # rebuild on a machine already doing the right thing printed twelve
        # lines telling it to do the right thing.
        #
        # Only the case that actually loses the desktop is worth a warning: no
        # session entry, and a hypr directory that will never load Omarchy. The
        # informational half is one line from the seed instead, and the doctor
        # says it before anyone installs at all.
        #
        # `or true` is the option's default; `or false` on enable because a
        # standalone home-manager install has no NixOS module registering
        # sessions at all.
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

                # The Hyprland toggles tree, and deliberately only flags.lua out of it.
                #
                # These flags are state, not config: a flag is *on* because its file is
                # there, so copying all of default/hypr/toggles would bring the session
                # up with no window gaps and every single window forced square.
                # omarchy-hyprland-toggle copies the other two out of $OMARCHY_PATH the
                # moment you ask for one, so nothing is lost by leaving them there --
                # upstream's own omarchy-refresh-hyprland seeds exactly this one file.
                #
                # flags.lua is what makes the directory exist, and it has to exist
                # before the shell starts rather than before the first toggle: the bar
                # watches ~/.local/state/omarchy/toggles with a FileView to notice
                # bar-off appearing, and a watch on a directory that is not there never
                # fires. Hiding the bar wrote the flag and changed nothing on screen
                # until the shell was restarted.
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

                # And the two files that belong in it, which upstream seeds from
                # /etc/skel. Without them the About window opens with an empty logo
                # column -- fastfetch's config sources about.txt as its logo -- and the
                # screensaver dies on the spot, because omarchy-screensaver hands
                # screensaver.txt to ttfx as the art to animate.
                #
                # The same two sources `omarchy branding <about|screensaver> reset`
                # copies back, so a reset returns to exactly what was seeded. logo.txt
                # is this repo's NIXARCHY banner rather than upstream's, by the same
                # reasoning as the menu's snowflake.
                seed_file "${omarchyPath}/icon.txt" \
                  "${config.xdg.configHome}/omarchy/branding/about.txt"
                seed_file "${omarchyPath}/logo.txt" \
                  "${config.xdg.configHome}/omarchy/branding/screensaver.txt"

                # The menu extension is generated, not seeded: it carries the
                # install-row rewrites, so it has to keep tracking the package. Add
                # your own rows with programs.nixarchy.menu.extraEntries.
                run mkdir -p "${config.xdg.configHome}/omarchy/extensions"
                if [ -e /etc/nixarchy/omarchy-menu.jsonc ]; then
                  run ln -sfn /etc/nixarchy/omarchy-menu.jsonc \
                    "${config.xdg.configHome}/omarchy/extensions/omarchy-menu.jsonc"
                fi

                # Agent skills, relinked on every activation.
                #
                # Upstream does this in omarchy-provision-user, which is guarded by a
                # `finalize-user` marker and therefore runs exactly once, ever. That is
                # fine on Arch, where the skill directory is a fixed path that gets
                # overwritten in place. Here every bump moves the package to a new store
                # path, so a once-only link points at the previous one -- still resolving
                # until it is garbage-collected, then dangling. Renaming the `omarchy`
                # skill to `nixarchy` made it worse than stale: the machine kept serving
                # the old Arch skill from a path nothing would update again.
                #
                # provision-user's own --force would fix the links and also replay
                # /etc/skel over $HOME, which is not a thing to do for four symlinks.
                # So: the same loop, declaratively, on every rebuild.
                #
                # Only symlinks whose target is itself a skills directory in the store
                # are removed. That is what distinguishes a link this module or
                # provision-user planted from a skill the user wrote by hand, which is a
                # real directory and is never touched.
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

                # Declared plugins, linked in by the id their manifest claims.
                #
                # A symlink rather than a copy, and that is a supported shape rather
                # than a trick: upstream's scan globs "$dir"/*/ , which matches a
                # symlink to a directory, and omarchy-plugin-remove has an explicit
                # branch for one -- it offers to "Unlink" and prints where it pointed.
                # Its picker globs -type d -o -type l for the same reason.
                #
                # Only links this module planted are cleaned up, tracked in a
                # .nixarchy-managed file beside them. A plugin you added yourself with
                # `omarchy plugin add` is a real directory that this never touches, so
                # the two ways of installing one live side by side.
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
                run mkdir -p "${config.xdg.configHome}/nixarchy"
                if [ ! -e "${config.xdg.configHome}/nixarchy/apps.nix" ] \
                  && [ -e /etc/nixarchy/apps-template.nix ]; then
                  run ${pkgs.coreutils}/bin/install -m600 /etc/nixarchy/apps-template.nix \
                    "${config.xdg.configHome}/nixarchy/apps.nix"
                fi

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

    # The first-run theme above is applied headless, which by design skips every
    # post-theme command -- including omarchy-theme-set-gnome, the one that
    # tells GTK and the settings portal whether this theme is light or dark.
    # Upstream never notices: on Arch that command runs during install with a
    # live session, and dconf keeps the answer forever after. Here the first
    # session would come up dark-themed with light GTK apps until the user
    # switched themes by hand.
    #
    # Unlike the shell below, this needs only the session bus, not a running
    # compositor, so a graphical-session unit is the right shape for it. It is
    # a no-op on every later login, because it writes what dconf already holds.
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

    # Provider files for the local model, when the system module turned it on.
    #
    # Written here rather than in modules/local-ai.nix because only the home
    # module knows where a user's home is, and read back out of osConfig so the
    # address the server binds and the address the agents dial cannot drift.
    # Guarded by `or null` throughout: home.nix is usable on its own, without
    # the NixOS module, and then there is no osConfig to read.
    #
    # Both agents get a file whether or not either is the current default. They
    # are a few hundred bytes, and the alternative is that switching agent in
    # the menu silently produces one that cannot reach the model.
    # opencode's provider, merged into the file rather than owning it.
    #
    # ~/.config/opencode/opencode.json already exists on every Omarchy machine
    # -- it is seeded with the theme and an autoupdate setting -- so declaring
    # it as an xdg.configFile fails activation outright:
    #
    #   Existing file '~/.config/opencode/opencode.json' would be clobbered
    #
    # and takes the whole home-manager generation down with it, not just this
    # file. `force = true` is worse: it would throw away the user's own opencode
    # settings and Omarchy's theme wiring to install a provider block.
    #
    # So the provider is merged in with jq, on every activation, leaving every
    # other key alone. Same reasoning as the pi settings below, arrived at the
    # same way: both files already have an owner.
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

    # pi keeps its configuration in ~/.pi/agent, not under XDG.
    #
    # supportsDeveloperRole is the field that has to be right. pi sends system
    # instructions in the `developer` role to reasoning-capable models, and
    # Ollama -- like vLLM and SGLang -- rejects a role it does not know. Every
    # request then fails with an error that does not name the cause.
    # pi's provider. Merged for the same reason, though less urgently: nothing
    # in Omarchy writes models.json today. Doing it the same way means a future
    # version that does cannot break activation, and means a user's own extra
    # providers survive.
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

    # Same extension point, on the other hook Omarchy already runs:
    # default/hypr/autostart.lua ends its startup with `omarchy-hook post-boot`.
    #
    # A notification rather than a window. The installer leaves /etc/nixos as a
    # repository with one staged, never-committed tree -- so there is something
    # real to say -- but a terminal that seizes the screen on a first-ever boot
    # arrives before the user has signed in to anything, which makes the one
    # answer they can give "dismiss". The nudge is a notification they can act
    # on when they are ready, and the script's own --check decides whether
    # there is any point showing it: already committed and pushed, no agent
    # chosen yet, or already answered once, and it stays quiet.
    xdg.configFile."omarchy/hooks/post-boot.d/config-repo" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        ${cfg.package}/bin/nixarchy-config-repo --check || exit 0

        # --exec makes it clickable, which is the whole reason a notification
        # works here at all: acting on it is one click when the user is ready,
        # and ignoring it costs them nothing.
        ${cfg.package}/bin/omarchy-notification-send \
          -u normal \
          "Back up your NixOS configuration" \
          "Everything this machine is lives in one uncommitted directory. Click to set up a backup." \
          --exec ${cfg.package}/bin/omarchy-launch-floating-terminal-with-presentation \
            ${cfg.package}/bin/nixarchy-config-repo
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
  };
}
