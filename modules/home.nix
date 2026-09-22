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

  # #623 and #630, read across from the NixOS side for the same reason
  # `localAi` above is: these are machine decisions -- a package installed, a
  # language server on PATH -- whose effect is a file in somebody's home. A
  # second option here would be a second answer to the same question.
  #
  # `or` defaults throughout, because a standalone home-manager user has no
  # NixOS module to have set any of them and every block below must then be
  # inert.
  mcpEnabled = osConfig.programs.nixarchy.mcp or false;
  languageServer = osConfig.programs.nixarchy.languageServer or false;
  nixdSettings = osConfig.programs.nixarchy.nixdSettings or { };

  # The Nix IDE extension's half of the same settings, shared by VSCode and
  # Cursor because they are the same editor with two config directories.
  vscodeNixdSettings = pkgs.writeText "nixarchy-vscode-nixd.json" (
    builtins.toJSON {
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = lib.getExe pkgs.nixd;
      "nix.serverSettings".nixd = nixdSettings;
      "nix.formatterPath" = lib.getExe pkgs.nixfmt;
    }
  );

  # Whether an app from the Install menu is actually selected. The editor
  # blocks below are gated on it so that nothing writes a configuration file
  # for an editor this machine does not have -- an orphan settings.json in
  # ~/.config/Cursor is indistinguishable, to the person who finds it, from
  # one they made themselves.
  appEnabled = name: osConfig.programs.nixarchy.apps.${name}.enable or false;

  # Whether this machine declares a secret -- the predicate sops-nix itself
  # gates on, so the editor plugin below (#658) appears exactly when the
  # mechanism it drives is live and never on a machine that has none.
  secretsInUse = (osConfig.sops.secrets or { }) != { } || (osConfig.sops.templates or { }) != { };

  # The formatter the editor runs by name, read off the same nixd settings
  # the LSP formats with rather than spelled a second time: one answer to
  # "which formatter", and tests/options.nix runs it against the flake's own
  # `nix fmt` to prove they agree (#657).
  nixFormatter = baseNameOf (lib.head (nixdSettings.formatting.command or [ "nixfmt" ]));

  # The Install-menu agents LazyVim's sidekick extra can drive, each with the
  # <leader>a key it gets. Cloud, large, costs money -- <leader>o is the
  # local model, below.
  aiTools = {
    claude-code = {
      tool = "claude";
      key = "c";
      label = "Claude Code";
    };
    codex = {
      tool = "codex";
      key = "x";
      label = "Codex";
    };
    gemini-cli = {
      tool = "gemini";
      key = "g";
      label = "Gemini CLI";
    };
    opencode = {
      tool = "opencode";
      key = "o";
      label = "OpenCode";
    };
  };

  # Why: modules/AGENTS.md#neovim-specs-written-once-and-gated-on-what-was-se
  nvimSpecScript =
    {
      file,
      because,
      said,
      text,
    }:
    ''
      spec="${config.xdg.configHome}/nvim/lua/plugins/${file}"
      if [ -d "${config.xdg.configHome}/nvim/lua/plugins" ] && [ ! -e "$spec" ]; then
        run install -m 0644 ${pkgs.writeText "nixarchy-nvim-${file}" ''
          -- Written by nixarchy (${because}).
          -- Delete this file to be rid of it; nothing here rewrites it.
          ${text}''} "$spec"
        echo "nixarchy: ${said}"
      fi
    '';
  nvimSpec = args: lib.hm.dag.entryAfter [ "writeBoundary" ] (nvimSpecScript args);

  # LazyVim's own sidekick extra, imported from inside a spec file. Every AI
  # spec below imports it; lazy.nvim keeps one copy (Spec:import dedups by
  # module name). NES is off because it needs the Copilot language server,
  # which this machine does not have -- left on, every buffer reports it.
  sidekickSpec = ''
    { import = "lazyvim.plugins.extras.ai.sidekick" },
    {
      "folke/sidekick.nvim",
      opts = { nes = { enabled = false } },
  '';

  # One agent's spec: the extra, plus one <leader>a key for that tool.
  aiSpec =
    app:
    let
      t = aiTools.${app};
    in
    lib.mkIf (appEnabled app && cfg.neovim != "off") (nvimSpec {
      file = "nixarchy-ai-${app}.lua";
      because = "${t.label} is selected in the Install menu";
      said = "gave Neovim <leader>a${t.key} for ${t.label}";
      text = ''
        return {
          ${sidekickSpec}
            keys = {
              {
                "<leader>a${t.key}",
                function() require("sidekick.cli").toggle({ name = "${t.tool}", focus = true }) end,
                desc = "${t.label}",
              },
            },
          },
        }
      '';
    });

  # The MCP server declaration, in whichever shape the agent being written to
  # reads. mcp-servers-nix owns the shapes: `mcpServers` in JSON for Claude
  # Code, `mcp_servers` in TOML for Codex, `mcp` with the command as an array
  # and a `type` of "local" for opencode. Three files, one declaration, and no
  # chance of a key that one agent reads and the other two ignore.
  mcpConfig =
    args:
    inputs.mcp-servers-nix.lib.mkConfig pkgs (
      {
        programs.nixos.enable = true;
      }
      // args
    );

  # Merge a generated JSON fragment into a config file the user also owns.
  #
  # The same shape as nixarchyOpencodeProvider below it, and for the same
  # reasons: never a home-manager symlink, because these are files the agent
  # and the editor both write to at runtime and a read-only store path makes
  # them fail at the moment somebody clicks something; written to a temp file
  # and moved, so an interrupted activation cannot leave half a config.
  #
  # `.[0] * .[1]` -- jq's `*` is a RECURSIVE object merge, so every key the
  # file already had survives and only the ones named here are replaced. That
  # is the difference between adding a server and replacing somebody's agent
  # configuration.
  mergeJson =
    {
      what,
      file,
      json,
    }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      conf="${file}"
      run mkdir -p "$(dirname "$conf")"
      [ -s "$conf" ] || echo '{}' > "$conf"

      tmp=$(${pkgs.coreutils}/bin/mktemp)
      if ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$conf" ${json} > "$tmp"; then
        run mv "$tmp" "$conf"
      else
        rm -f "$tmp"
        echo "nixarchy: could not merge ${what} into $conf" >&2
      fi
    '';

  # The same job for the two TOML files, where there is no jq.
  #
  # Appending a table rather than merging one, which is safe TOML precisely
  # once: a second `[mcp_servers.nixos]` in the same file is a duplicate-key
  # error, so the guard is the point and not a nicety. Guarded on the table
  # header rather than on a marker comment of ours, because the thing that
  # must not be written twice is the table -- including when the user wrote
  # the first one themselves, in which case theirs is kept and nothing here
  # touches it.
  appendToml =
    {
      what,
      file,
      table,
      toml,
    }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      conf="${file}"
      run mkdir -p "$(dirname "$conf")"
      [ -e "$conf" ] || : > "$conf"

      if ${pkgs.gnugrep}/bin/grep -qF '[${table}]' "$conf"; then
        echo "nixarchy: $conf already declares [${table}]; leaving it alone"
      else
        {
          echo ""
          echo "# ${what} -- added by nixarchy. Delete this block to be rid of it;"
          echo "# programs.nixarchy in your configuration decides whether it comes back."
          ${pkgs.coreutils}/bin/cat ${toml}
        } >> "$conf"
      fi
    '';

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

  # The GitLab pipelines panel as nixarchy installs it (#770): upstream's copy
  # plus `menu.managed`, which tells its menu.py that nixarchy owns the rows,
  # and the MIT notice from the source tree when upstream's package omits it.
  gitlabPipelines = pkgs.runCommand "nixarchy-gltui" { } ''
    cp -r ${inputs.nixarchy-gltui.packages.${pkgs.stdenv.hostPlatform.system}.default} $out
    chmod -R u+w $out
    touch $out/menu.managed
    [ -f $out/LICENSE ] || cp ${inputs.nixarchy-gltui}/LICENSE $out/LICENSE
  '';

  # The GitHub Actions panel, the same way (#772): gltui is its fork.
  githubActions = pkgs.runCommand "nixarchy-ghtui" { } ''
    cp -r ${inputs.nixarchy-ghtui.packages.${pkgs.stdenv.hostPlatform.system}.default} $out
    chmod -R u+w $out
    touch $out/menu.managed
    [ -f $out/LICENSE ] || cp ${inputs.nixarchy-ghtui}/LICENSE $out/LICENSE
  '';

  # The Distrobox panel as nixarchy installs it (#766 PR D): upstream's copy with
  # its manifest's default templatesFile pointed at the file boxes.nix writes
  # from data/box-templates.nix. A default, not a setting: a path the user sets
  # in Setup > Plugins still wins, and nothing here writes shell.json.
  distroboxPanel = pkgs.runCommand "nixarchy-distrobox" { nativeBuildInputs = [ pkgs.jq ]; } ''
    cp -r ${inputs.nixarchy-distrobox.packages.${pkgs.stdenv.hostPlatform.system}.default} $out
    chmod -R u+w $out
    jq '.barWidget.defaults.templatesFile = "/etc/nixarchy/box-templates.ini"' \
      $out/manifest.json > manifest.json
    mv manifest.json $out/manifest.json
  '';

  # The herdr sessions widget as nixarchy installs it (#771). Upstream has no
  # flake, so this is the package: the plugin without its design documents, and
  # its scripts' `#!/bin/bash` pointed into the store -- they run by path, and
  # today that only works through envfs.
  herdrSessions = pkgs.runCommand "nixarchy-herdr" { } ''
    cp -r ${inputs.nixarchy-herdr} $out
    chmod -R u+w $out
    rm -rf $out/intent $out/spec $out/plan $out/tests $out/preview.png
    chmod +x $out/bin/*
    patchShebangs $out/bin
    grep -q "Jankees van Woezik" $out/LICENSE && grep -q olafkfreund $out/LICENSE || {
      echo "nixarchy-herdr: LICENSE must keep both copyright holders" >&2
      exit 1
    }
  '';

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

  # Why: modules/AGENTS.md#the-default-plugins-are-on-from-the-first-login
  # Standalone Home Manager has no osConfig, so it resolves nothing (Mode A).
  resolvedDefaults = lib.filterAttrs (
    name: p:
    (osConfig.programs.nixarchy.enable or false) && p.gate && (cfg.defaultPlugins.${name} or true)
  ) cfg.defaultPluginSet;
  defaultIds = lib.mapAttrsToList (_: p: p.id) resolvedDefaults;

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
        ${lib.optionalString (builtins.elem name defaultIds) ''
          # A default is named by id in menu rows and binds, so a pin that
          # renames it must fail here, not leave those rows opening nothing.
          if [ "$id" != ${lib.escapeShellArg name} ]; then
            echo "default plugin ${name}: its manifest.json now says id '$id'." >&2
            echo "Menu rows and key binds name it '${name}'; update them with the pin." >&2
            exit 1
          fi
        ''}
        mkdir -p $out
        echo -n "$id" > $out/id
        ln -s "$src" $out/plugin
      ''
  ) cfg.plugins;
in
{
  # Nixi: the guide that should come with nixarchy -- since 0.10 (#709) an
  # Omarchy overlay card with a hands-on tour, a manual search grounded in this
  # machine, and an AI tutor (Claude Code by default). No server, no port.
  #
  # Imported unconditionally, and TURNED ON for every nixarchy desktop below.
  # Upstream's whole config is `lib.mkIf cfg.enable`, so `false` really does
  # leave nothing behind -- no timer, no plugin, no activation step, no
  # package. That is the half tests/options.nix
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
  imports = [
    inputs.nixi.homeModules.default
    # Voice (#774). Imported on every machine, enabled on none: its options
    # default off upstream, so this costs an evaluation and nothing else until
    # somebody picks Voice out of Install > Search and their own flake sets
    # programs.omarchy-voice.enable. It is deliberately NOT in
    # defaultPluginSet -- about a gigabyte with whisper and the Piper models,
    # which are in the package, so an off switch would not shrink anything.
    inputs.nixarchy-voice.homeModules.default
  ];

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

    neovimSpecs = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      example = lib.literalExpression ''
        {
          codecompanion = '''
            return {
              {
                "olimorris/codecompanion.nvim",
                opts = { adapters = { http = { ollama = { url = vim.env.OLLAMA_ENDPOINT } } } },
              },
            }
          ''';
        }
      '';
      description = ''
        LazyVim plugin specs of your own, one file each under
        `~/.config/nvim/lua/plugins/<name>.lua`.

        For a plugin nixarchy does not ship -- a different AI plugin, a
        language extra -- declared in your configuration rather than dropped
        into the tree by hand. Each is written the way every generated spec
        here is: once, only when the file does not exist, and never over a
        file you wrote. Delete the file and it is gone until you change the
        text here; nothing rewrites it behind you.

        `OLLAMA_ENDPOINT` is in the session environment when
        `programs.nixarchy.localAi` is on, so a plugin that reads it follows
        the local model to wherever it actually listens.
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

        The exception is nixarchy's own default plugins
        (`programs.nixarchy.defaultPlugins`), which are also turned on, once.
      '';
    };

    defaultPlugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = {
        pkg = true;
        gitlab = true;
        github = true;
        herdr = true;
        podman = true;
        distrobox = true;
        microvm = true;
        devenv = true;
      };
      example = lib.literalExpression "{ podman = false; }";
      description = ''
        nixarchy's own shell plugins, installed and turned on for you: the
        package manager, GitLab pipelines, GitHub Actions and herdr panels
        always, podman when podman is on, distrobox when Boxes is on,
        microvms always, dev environments when the devenv service is on. A
        name left out counts as on.

        Each is turned on once, at the first login that has it, and a marker
        in ~/.local/state/nixarchy/enabled-once records that. Turn one off in
        Setup > Plugins and it stays off. Setting a name to `false` here stops
        nixarchy installing and enabling it; it never edits your shell.json,
        so a plugin you already have on stays on until you turn it off there.
      '';
    };

    # The defaults' sources, by the name `defaultPlugins` uses. Filled in by
    # the PRs that add each plugin's input; tests put a fixture here.
    defaultPluginSet = lib.mkOption {
      internal = true;
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.str; };
            src = lib.mkOption { type = lib.types.path; };
            gate = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            # Runtime tools the plugin shells out to (glab, gh, ...), on the
            # session PATH wherever the plugin itself is installed (#770).
            packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
          };
        }
      );
      default = { };
    };

    # The build-time validation of each declared plugin, exposed so
    # tests/options.nix can assert that a bad one fails to build.
    pluginChecks = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.attrsOf lib.types.package;
      default = validatedPlugins;
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

    # The one nixi default nixarchy DOES change, and the only one it needs to.
    #
    # Upstream's default is `lib.optional (pkgs.config.allowUnfree or false)
    # "claude" ++ [ "codex" ]` -- conditional on a flag modules/nixos.nix sets,
    # so the agent set moved with allowUnfree and nobody ever chose it. That is
    # how claude-agent-acp, and the unfree claude-code under it, arrived in
    # every system closure: 650 MiB nobody asked for, in every installed
    # machine and in a public cache (#725).
    #
    # Named rather than inherited, so the set is a property of nixarchy instead
    # of a side effect. opencode is added because it speaks ACP itself and pins
    # no adapter at all; codex is Apache-2.0 (data/apps.nix); claude stays by
    # decision, its 650 MiB and its licence consequence accepted in #725's spec.
    #
    # Plain assignment, not mkDefault: a list is a merging type, and mkDefault
    # on one is dropped whole the moment a user adds an element (AGENTS.md 7).
    # A user naming their own agents concatenates with these, which is right --
    # their machine, their adapters.
    #
    # claude keeps upstream's allowUnfree guard, and it is a guard rather than a
    # defaulting trick: nixi forces pkgs.claude-agent-acp whenever "claude" is
    # in this list, and BOTH that adapter and claude-code throw under
    # allowUnfree = false. An unconditional list is an evaluation failure on
    # every machine that sets programs.nixarchy.allowUnfree = false -- measured,
    # not guessed. nixarchy allows unfree by default, so the default machine
    # gets all three.
    # claude is pinned where this machine actually USES claude, not wherever
    # unfree happens to be allowed.
    #
    # The person this condition exists for is the menu-chooser. Picking Claude
    # from Install runs omarchy-default-agent, which writes `claude` into
    # ~/.config/omarchy/defaults/agent AND adds claude-code to
    # ~/.config/nixarchy/apps.nix through nixarchy-pkg-add. nixi reads that
    # defaults file and treats the name as an EXPLICIT choice -- its fallback
    # (nixi-nixarchy#13) deliberately does not override one -- so a machine
    # whose user chose Claude and no longer has claude-agent-acp gets an error
    # at SUPER+H, not a different agent. Keying on the apps entry keeps them
    # working with no action from them at all (#731).
    #
    # Keying on allowUnfree instead, as this did, put claude-agent-acp and the
    # unfree claude-code -- 651 MiB, 42% of a public 5 GB cache, for two
    # packages that are FETCHED rather than built -- into every closure CI
    # pushes, including two that never wanted them.
    #
    # Both halves are needed: appEnabled catches the menu, defaultAgent catches
    # the declarative user, whose modules/apps.nix mapping installs claude-code
    # without going through the apps catalogue at all.
    #
    # It cannot pin an adapter on a machine that refuses unfree: claude-code is
    # `unfree = true` in data/apps.nix, so it cannot be enabled there, and
    # defaultAgent = "claude" already fails to evaluate with nixpkgs' own
    # message naming the package (modules/apps.nix).
    services.nixi.agents = [
      "opencode"
      "codex"
    ]
    ++ lib.optional (appEnabled "claude-code" || defaultAgent == "claude") "claude";

    # And the three defaults nixarchy deliberately does NOT change.
    #
    # `autoEnable` is true upstream and stays true here, and it is the one
    # exception to the rule programs.nixarchy.plugins above keeps (and
    # tests/plugin.nix asserts): an installed plugin is not an enabled one.
    # Nixi's card is turned on for you, ONCE, on the first activation -- nixi
    # adds it to shell.json and leaves a marker, so turning it off in Setup >
    # Plugins sticks. Decided for #709, for a measured reason: the shell
    # accepts a toggle for a plugin that is not enabled and does nothing, with
    # exit status 0, so an installed-but-off card meant the snowflake and
    # `nixi` silently did nothing. nixi writes that file, never nixarchy,
    # and tests/options.nix fails (nixiEnablesCard) if a bump drops it.
    #
    # `barWidget.enable` is true upstream, and stays true here: the snowflake
    # is a second small plugin beside the card (Omarchy gives a third-party
    # plugin a bar widget or an overlay, never both), turned on with it.
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
    # silence. Nixi does not need the row either way -- the bar button and
    # `nixi` are its front doors.
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
      ++ lib.optionals (!(osConfig.programs.nixarchy.enable or false)) cfg.package.passthru.runtimeDeps
      # lowPrio, because these arrive without being asked for: the default
      # plugins are on from the first login, and their runtime tools are
      # ordinary things a user may already keep -- gh, glab, jq, python3. A
      # user's own `python3.withPackages` beside a panel's bare python3 is two
      # interpreters in one profile, which buildEnv refuses over bin/idle3;
      # home-manager-path fails and the whole closure with it, naming idle3 and
      # nothing of ours (#809). Whatever the user installed themselves wins.
      ++ map lib.lowPrio (lib.concatMap (p: p.packages) (lib.attrValues resolvedDefaults))
      # ai-mirror on every nixarchy machine, whether or not its widget is on
      # (#773): the seeded kill switch runs it. lowPrio for #809's reason -- a
      # user who installs it through its own module keeps theirs.
      ++ lib.optional (osConfig.programs.nixarchy.enable or false) (
        lib.lowPrio inputs.ai-mirror.packages.${pkgs.stdenv.hostPlatform.system}.ai-mirror
      );

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
                  # --update=none: a file the user has edited is theirs, not ours.
                  # A real failure (a full disk, a directory they cannot write)
                  # is reported, not swallowed -- and does not stop the others.
                  run ${pkgs.coreutils}/bin/cp -r --update=none --no-preserve=mode,ownership \
                    "$src"/. "$dest"/ ||
                    echo "nixarchy: could not seed $dest from $src; see the error above" >&2
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
                    # Built OUTSIDE the watched directory: the shell reloads every
                    # plugin on any event in `dir`, and a temp file there is an event
                    # even though its name is hidden (#710).
                    staging = "${config.xdg.configHome}/omarchy/.nixarchy-managed.new";
                  in
                  ''
                    # Reconcile, never relink: the shell reloads every plugin on any
                    # change in this directory, so a link whose target is already right
                    # is left alone (#710). Only a missing or changed link is written.
                    run rm -f "${staging}"
                    : > "${staging}"
                    ${lib.concatMapStringsSep "
        " (drv: ''
                      id=$(cat ${drv}/id)
                      target=$(readlink -f ${drv}/plugin)
                      if [ -e "${dir}/$id" ] && [ ! -L "${dir}/$id" ]; then
                        echo "nixarchy: ${dir}/$id is your own directory, not replacing it"
                      else
                        if [ "$(readlink "${dir}/$id")" != "$target" ]; then
                          run ln -sfn "$target" "${dir}/$id"
                        fi
                        echo "$id" >> "${staging}"
                      fi
                    '') (lib.attrValues validatedPlugins)}
                    # A plugin dropped from the configuration goes away. Guarded on
                    # being a symlink: if you replaced one with a real checkout, that
                    # is yours and is left alone.
                    if [ -e "${manifest}" ]; then
                      while IFS= read -r stale; do
                        [ -n "$stale" ] || continue
                        if ! grep -qxF "$stale" "${staging}" && [ -L "${dir}/$stale" ]; then
                          run rm -f "${dir}/$stale"
                        fi
                      done < "${manifest}"
                    fi
                    # The manifest exists only while this module planted something: an
                    # empty file in a user's plugins directory means nothing to them.
                    # Hidden names are ignored by the shell's watcher.
                    if [ ! -s "${staging}" ]; then
                      run rm -f "${manifest}" "${staging}"
                    elif cmp -s "${staging}" "${manifest}"; then
                      rm -f "${staging}"
                    else
                      run mv "${staging}" "${manifest}"
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

    # #707: first login's mise launchers in ~/.local/bin shadow the Nix package
    # of the same name. New ones are no longer written for a Nix command; this
    # removes the ones already there, and any a later Install-menu pick shadows.
    home.activation.nixarchyMiseUnshadow = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${omarchyPath}/bin/omarchy-mise-unshadow \
        /etc/profiles/per-user/${config.home.username}/bin /run/current-system/sw/bin
    '';

    # ---- #623: the NixOS MCP server, in the agents that have one --------
    #
    # Three agents, not the four this module seeds skills into. `~/.agents`
    # and `~/.pi/agent` have no documented MCP configuration file, and a path
    # invented for them would be a feature that writes a file nothing reads --
    # the shape §2 of AGENTS.md is about. Named here so the gap is a decision
    # rather than an oversight; close it the day either tool documents one.
    home.activation.nixarchyMcpClaude = lib.mkIf mcpEnabled (mergeJson {
      what = "the NixOS MCP server";
      # Claude Code's user scope is ~/.claude.json, not a file under
      # ~/.claude/ -- the directory beside it is where the skills go. It is a
      # large stateful file the tool rewrites constantly, which is exactly why
      # this merges into it rather than generating it.
      file = "${config.home.homeDirectory}/.claude.json";
      json = mcpConfig {
        flavor = "claude-code";
        fileName = "nixarchy-mcp-claude.json";
      };
    });

    home.activation.nixarchyMcpOpencode = lib.mkIf mcpEnabled (mergeJson {
      what = "the NixOS MCP server";
      # The same file nixarchyOpencodeProvider below writes the local model
      # into, and merged the same way, so the two cannot undo each other.
      file = "${config.xdg.configHome}/opencode/opencode.json";
      json = mcpConfig {
        flavor = "opencode";
        fileName = "nixarchy-mcp-opencode.json";
      };
    });

    home.activation.nixarchyMcpCodex = lib.mkIf mcpEnabled (appendToml {
      what = "The NixOS MCP server";
      file = "${config.home.homeDirectory}/.codex/config.toml";
      table = "mcp_servers.nixos";
      toml = mcpConfig {
        flavor = "codex";
        format = "toml";
        fileName = "nixarchy-mcp-codex.toml";
      };
    });

    # ---- #630: nixd, in the editors the Install menu offers --------------
    #
    # Every block is gated on the editor actually being selected. nixd itself
    # is on PATH from modules/nixos.nix; what these do is the half a user
    # cannot be expected to write, which is telling it which flake and which
    # attribute -- see programs.nixarchy.nixdSettings.
    home.activation.nixarchyNixdZed = lib.mkIf (languageServer && appEnabled "zed") (mergeJson {
      what = "nixd";
      file = "${config.xdg.configHome}/zed/settings.json";
      json = pkgs.writeText "nixarchy-zed-nixd.json" (
        builtins.toJSON {
          lsp.nixd.initialization_options = nixdSettings;
          # Zed ships nil as its Nix default, and a language_servers list
          # naming only nixd would still leave nil running -- the `!` prefix
          # is Zed's own way of removing a default, and without it two servers
          # answer every completion request.
          languages.Nix.language_servers = [
            "nixd"
            "!nil"
          ];
        }
      );
    });

    # VSCode and Cursor read the same settings file under different product
    # directories, and both go through the Nix IDE extension -- `nix.*` are
    # its settings, not the editor's. `nix.serverPath` is an absolute store
    # path on purpose: the extension spawns the server itself, and it does not
    # inherit the login shell's PATH when the editor was launched from a
    # desktop file.
    home.activation.nixarchyNixdVscode = lib.mkIf (languageServer && appEnabled "vscode") (mergeJson {
      what = "nixd";
      file = "${config.xdg.configHome}/Code/User/settings.json";
      json = vscodeNixdSettings;
    });

    home.activation.nixarchyNixdCursor = lib.mkIf (languageServer && appEnabled "cursor") (mergeJson {
      what = "nixd";
      file = "${config.xdg.configHome}/Cursor/User/settings.json";
      json = vscodeNixdSettings;
    });

    # Helix takes its language server configuration as TOML, and what it puts
    # under `[language-server.nixd.config]` is what it sends as the LSP
    # initializationOptions -- the same attrset the other three editors get,
    # spelled in Helix's file.
    home.activation.nixarchyNixdHelix = lib.mkIf (languageServer && appEnabled "helix") (appendToml {
      what = "nixd, the Nix language server";
      file = "${config.xdg.configHome}/helix/languages.toml";
      table = "language-server.nixd";
      toml = (pkgs.formats.toml { }).generate "nixarchy-helix-nixd.toml" {
        language-server.nixd = {
          command = "nixd";
          config = nixdSettings;
        };
        # A [[language]] entry rather than a table: this is how Helix takes a
        # per-language override, and without it the `nixd` server defined
        # above is configured and never used.
        language = [
          {
            name = "nix";
            language-servers = [ "nixd" ];
          }
        ];
      };
    });

    # Neovim, through the LazyVim tree this module already seeds. A file of
    # its own under lua/plugins rather than an edit to one of Omarchy's, so a
    # user who wants it gone deletes one file -- and written only when it is
    # absent, for the reason the seed above states: every .lua under
    # lua/plugins is read as a plugin spec, and clobbering one somebody wrote
    # is not this module's to do. Every spec below is the same shape, through
    # nvimSpec; each is its own file so a machine that already has nixd.lua
    # from #630 still gains the ones added since.
    home.activation.nixarchyNixdNeovim = lib.mkIf (languageServer && cfg.neovim != "off") (nvimSpec {
      file = "nixd.lua";
      because = "programs.nixarchy.languageServer";
      said = "pointed Neovim at nixd, which knows this machine's flake";
      text = ''
        return {
          {
            "neovim/nvim-lspconfig",
            opts = {
              servers = {
                nixd = {
                  cmd = { "nixd" },
                  settings = { nixd = vim.json.decode([==[${builtins.toJSON nixdSettings}]==]) },
                },
              },
            },
          },
        }
      '';
    });

    # ---- #656, #657: the grammar, and format on save with what CI runs ----
    #
    # The nixd settings the issue asked for beyond these -- diagnostics
    # exclusions, failure handling, eval workers -- are not nixd settings:
    # nixd 2.x reads `nixpkgs`, `formatting`, `options` and
    # `diagnostic.suppress` and nothing else (nixd/lib/Controller/
    # Configuration.cpp). Formatting through the LSP is already in
    # nixdSettings. What was genuinely missing is here.
    home.activation.nixarchyNeovimNix = lib.mkIf (languageServer && cfg.neovim != "off") (nvimSpec {
      file = "nixarchy-nix.lua";
      because = "programs.nixarchy.languageServer";
      said = "gave Neovim the nix grammar and format-on-save with ${nixFormatter}";
      text = ''
        return {
          -- The grammar. nvim-treesitter compiles it with the tree-sitter CLI
          -- and the C compiler programs.nixarchy.languageServer puts on PATH.
          { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "nix" } } },
          -- Format on save with the tool `nix fmt` runs, so the editor and CI
          -- agree by construction. `optional`: extends conform if LazyVim
          -- loaded it, and does nothing if you removed it.
          {
            "stevearc/conform.nvim",
            optional = true,
            opts = { formatters_by_ft = { nix = { "${nixFormatter}" } } },
          },
        }
      '';
    });

    # ---- #660: the project environment, from inside the editor -------------
    #
    # devenv activates on `cd`, through a SHELL hook -- `devenv hook bash|zsh|
    # fish` in interactiveShellInit, not direnv (the manual is explicit that
    # running both would have each try to own the environment). So Neovim
    # started from a terminal already inside the project inherits it, and
    # Neovim started from the app launcher, or told to `:cd` into a project it
    # was not launched from, does not: the LSP and the formatter then see the
    # machine's toolchain rather than the project's, quietly and with no error.
    #
    # `:DevenvShell` is the half the shell hook cannot reach. Gated on the
    # devenv service rather than on the editor, because a machine that never
    # turned devenv on has no project environment for this to enter.
    home.activation.nixarchyNeovimDevenv =
      lib.mkIf (osConfig.programs.nixarchy.services.devenv.enable or false && cfg.neovim != "off")
        (nvimSpec {
          file = "nixarchy-devenv.lua";
          because = "programs.nixarchy.services.devenv";
          said = "gave Neovim :DevenvShell for this project's environment";
          text = ''
            return {
              -- :DevenvShell enters this project's devenv in the running
              -- instance, so the LSP and the formatter see the project's
              -- toolchain. :NixDevelop and :NixShell come with it for flakes
              -- that are not devenv projects.
              { "figsoda/nix-develop.nvim", event = "VeryLazy" },
            }
          '';
        });

    # ---- #658: sops files, from the editor ---------------------------------
    #
    # Gated on a secret being declared, not on the editor: the machine that
    # declares none must gain nothing, which is the inertness tests/options.nix
    # asserts for sops-nix itself. <leader>k rather than the <leader>e/<leader>d
    # pair the source config used, because <leader>e is neo-tree in the config
    # this module seeds and <leader>d is LazyVim's debug group.
    home.activation.nixarchyNeovimSops = lib.mkIf (secretsInUse && cfg.neovim != "off") (nvimSpec {
      file = "nixarchy-sops.lua";
      because = "a secret is declared under sops.secrets";
      said = "gave Neovim :SopsDecrypt and :SopsEncrypt; docs/manual/secrets.md says where the plaintext goes";
      text = ''
        return {
          {
            "prismatic-koi/nvim-sops",
            event = { "BufReadPre" },
            keys = {
              { "<leader>k", "", desc = "+secrets (sops)" },
              { "<leader>kd", vim.cmd.SopsDecrypt, desc = "Decrypt this file in place" },
              { "<leader>ke", vim.cmd.SopsEncrypt, desc = "Encrypt this file in place" },
            },
            opts = function()
              -- The identity `nixarchy secret new --user` made, when there is
              -- one. A system secret is encrypted to the host's SSH key, which
              -- only root can read: add your own age key as a recipient in
              -- .sops.yaml to edit those from here.
              local id = vim.fn.expand("~/.local/share/nixarchy/secrets/identity.txt")
              return { defaults = { ageKeyFile = vim.fn.filereadable(id) == 1 and id or nil } }
            end,
          },
        }
      '';
    });

    # ---- #659: the AI plugins follow the AI tools you chose -----------------
    #
    # One file per selected agent, each importing LazyVim's sidekick extra
    # (lazy.nvim loads it once) and adding one <leader>a key for its own tool.
    # Per tool rather than one file listing all of them, because a file is
    # written once: an agent selected later still gets its spec, and the one
    # failure that matters -- a spec for an agent the user never installed --
    # cannot happen, because nothing writes one.
    home.activation."nixarchyNeovimAi-claude-code" = aiSpec "claude-code";
    home.activation."nixarchyNeovimAi-codex" = aiSpec "codex";
    home.activation."nixarchyNeovimAi-gemini-cli" = aiSpec "gemini-cli";
    home.activation."nixarchyNeovimAi-opencode" = aiSpec "opencode";

    # <leader>o: the local model. pi is the agent modules/local-ai.nix already
    # points at Ollama by default (nixarchyPiDefaultModel), so the offline path
    # is the same extra with a different tool -- small, private, free, and
    # reachable by muscle memory when the network is not. No third-party
    # plugin, and therefore nothing to pin at every bump; a plugin that talks
    # to Ollama directly goes in programs.nixarchy.neovimSpecs and reads
    # OLLAMA_ENDPOINT.
    home.activation.nixarchyNeovimAiLocal =
      lib.mkIf (localAi.enable && builtins.elem "pi" localAi.agents && cfg.neovim != "off")
        (nvimSpec {
          file = "nixarchy-ai-local.lua";
          because = "programs.nixarchy.localAi points pi at the local model";
          said = "gave Neovim <leader>o for the local model, through pi";
          text = ''
            return {
              ${sidekickSpec}
                keys = {
                  { "<leader>o", "", desc = "+local ai (pi, offline)", mode = { "n", "v" } },
                  { "<leader>oo", function() require("sidekick.cli").toggle({ name = "pi", focus = true }) end, desc = "Toggle pi" },
                  { "<leader>ot", function() require("sidekick.cli").send({ name = "pi", msg = "{this}" }) end, mode = { "n", "x" }, desc = "Send this to pi" },
                  { "<leader>ov", function() require("sidekick.cli").send({ name = "pi", msg = "{selection}" }) end, mode = { "x" }, desc = "Send selection to pi" },
                  { "<leader>op", function() require("sidekick.cli").prompt({ name = "pi" }) end, mode = { "n", "x" }, desc = "Prompt pi" },
                },
              },
            }
          '';
        });

    # The user's own specs, through the same helper and under the same rules.
    home.activation.nixarchyNeovimSpecs = lib.mkIf (cfg.neovimSpecs != { } && cfg.neovim != "off") (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatStrings (
          lib.mapAttrsToList (
            name: text:
            nvimSpecScript {
              file = "${name}.lua";
              because = "programs.nixarchy.neovimSpecs.${name}";
              said = "wrote your ${name} spec for Neovim";
              inherit text;
            }
          ) cfg.neovimSpecs
        )
      )
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

    programs.nixarchy = {
      defaultPluginSet = {
        # The package manager panel, on wherever nixarchy is (#766).
        pkg = {
          id = "nixarchy.pkg";
          src = inputs.nixarchy-pkg.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
        # Wherever podman is on -- the Services row or Boxes -- and nowhere
        # else: a podman panel with no podman behind it is a broken panel.
        # `or false` also covers standalone Home Manager, whose osConfig is null.
        podman = {
          id = "nixarchy.podman";
          src = inputs.nixarchy-podman.packages.${pkgs.stdenv.hostPlatform.system}.default;
          gate = osConfig.virtualisation.podman.enable or false;
        };
        # The GitLab pipelines panel, on wherever nixarchy is, with the CLI it
        # drives and the python its actions.py runs on (#770).
        gitlab = {
          id = "olafkfreund.gitlab-pipelines";
          src = gitlabPipelines;
          packages = [
            pkgs.glab
            pkgs.python3
            pkgs.xdg-utils
          ];
        };
        # The GitHub Actions panel, the same way, with gh (#772).
        github = {
          id = "olafkfreund.github-actions";
          src = githubActions;
          packages = [
            pkgs.gh
            pkgs.python3
            pkgs.xdg-utils
          ];
        };
        # The herdr sessions widget, with herdr itself and the tools its
        # herdr-sessions script calls (#771).
        herdr = {
          id = "nixarchy.herdr";
          src = herdrSessions;
          packages = [
            # Stable lacks herdr. Prefer the consumer's CLI when it exists;
            # only the missing standalone tool comes from our pinned nixpkgs.
            (pkgs.herdr or inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr)
            pkgs.jq
            pkgs.iproute2
          ];
        };
        # The Distrobox panel wherever Boxes are on, which is also where
        # distrobox itself and the templates file are (#766 PR D).
        distrobox = {
          id = "nixarchy.distrobox";
          src = distroboxPanel;
          gate = osConfig.programs.nixarchy.services.boxes.enable or false;
        };
        # The MicroVMs panel, on wherever nixarchy is: gated like the Sandbox
        # rows it replaces, whose `nixarchy-vm --check` always succeeds (#766).
        microvm = {
          id = "nixarchy.microvm";
          src = inputs.nixarchy-microvm.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
        # The Dev environments panel wherever devenv is, the way Podman
        # follows podman (#802): the panel lists, creates and enters devenv
        # projects, and with no devenv behind it there is nothing to list and
        # nothing it could create. `packages` carries the CLI it drives --
        # `nixarchy-devenv`, which is also what `nixarchy dev` dispatches to.
        devenv = {
          id = "nixarchy.devenv";
          src = inputs.nixarchy-devenv.packages.${pkgs.stdenv.hostPlatform.system}.plugin;
          gate = osConfig.programs.nixarchy.services.devenv.enable or false;
          packages = [ inputs.nixarchy-devenv.packages.${pkgs.stdenv.hostPlatform.system}.cli ];
        };
        # The ai-mirror widget, on every machine (#773): it shows when an agent
        # is watching or driving, draws the confirm dialog, and a click stops a
        # live grant. No agent is connected to ai-mirror by this; see
        # programs.nixarchy.aiMirror.mcp. Why: spec/2026-09-22-773-ai-mirror-default.md
        ai-mirror = {
          id = "olafkfreund.ai-mirror";
          src = inputs.ai-mirror.packages.${pkgs.stdenv.hostPlatform.system}.plugin;
        };
      };

      # Why: modules/AGENTS.md#the-default-plugins-are-on-from-the-first-login
      plugins = lib.mapAttrs' (
        _: p: lib.nameValuePair p.id { src = lib.mkDefault p.src; }
      ) resolvedDefaults;
    };

    # Turned on through the running shell's own writer, never by editing
    # shell.json: the shell rewrites that whole file from memory, so a second
    # writer loses updates. The marker is written only once the enable worked.
    xdg.configFile = {
      "omarchy/hooks/post-boot.d/default-plugins" = lib.mkIf (resolvedDefaults != { }) {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          export PATH=${
            lib.makeBinPath [
              cfg.package
              pkgs.jq
              pkgs.coreutils
              pkgs.systemd
            ]
          }:$PATH
          state="''${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/enabled-once"
          # Enabling makes the shell reload its plugins, which can outlast
          # upstream's 2 s IPC budget; this runs in the background, so wait.
          export OMARCHY_SHELL_IPC_TIMEOUT=''${OMARCHY_SHELL_IPC_TIMEOUT:-30s}

          todo=()
          for id in ${lib.escapeShellArgs defaultIds}; do
            [ -e "$state/$id" ] || todo+=("$id")
          done
          [ ''${#todo[@]} -gt 0 ] || exit 0

          # The shell may still be starting. No answer means next login.
          for _ in $(seq 120); do
            omarchy-shell shell ping >/dev/null 2>&1 && break
            sleep 1
          done
          omarchy-shell shell ping >/dev/null 2>&1 || exit 0
          omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

          mkdir -p "$state"
          list=$(omarchy-plugin-list --json 2>/dev/null) || list='[]'
          for id in "''${todo[@]}"; do
            if jq -e --arg id "$id" 'any(.[]; .id == $id and .enabled)' <<<"$list" >/dev/null; then
              : >"$state/$id"
            elif out=$(omarchy-plugin-enable "$id" right 2>&1); then
              : >"$state/$id"
            else
              printf '%s: %s\n' "$id" "$out" | systemd-cat -t nixarchy-default-plugins
            fi
          done
        '';
      };

      # Why: modules/AGENTS.md#same-extension-point-on-the-other-hook-omarchy-alr
      "omarchy/hooks/post-boot.d/config-repo" = {
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
    # One `programs` block, not three keys. statix refuses a third top-level
    # programs.* assignment as a repeated key -- main has two and is clean --
    # so voice's switch nests here beside distrobox's.
    #
    # The bridge itself (#774): the machine's switch, read the way every gated
    # default reads one. Voice's own settings are left alone; desktop control,
    # the wake word and the notification log all start off upstream, and
    # restating them would be a second place to change.
    programs = {
      omarchy-voice.enable = lib.mkDefault (osConfig.programs.nixarchy.voice.enable or false);

      distrobox = lib.mkIf boxes.enable {
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
  };
}
