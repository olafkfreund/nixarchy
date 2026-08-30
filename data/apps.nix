# Every app Omarchy's Install menu offers, mapped to how NixOS installs it.
#
# The ids and labels come from upstream's own
# default/omarchy/omarchy-menu.jsonc; the right-hand side is the curated part
# and is the only place in this repo that needs a human when upstream adds an
# app. build.yml and omarchy.yml both compare this file against that menu and
# fail on anything unmapped, so the list cannot rot silently.
#
# Per-app fields:
#   label      Shown in the generated template and the menu.
#   category   Groups rows in the template; matches the menu's own grouping.
#   attr       nixpkgs attribute, for apps that are only a package.
#   option     NixOS option path for apps that are a module rather than a
#              package. `settings` is merged HERE, which is what makes
#              `apps.tailscale.settings.useRoutingFeatures` land in the right
#              place. An app with an `option` must NOT also set `attr`: the
#              module owns installing its own package.
#   unfree     Marks a package nixpkgs licenses as unfree. nixarchy defaults
#              allowUnfree on, so this is a note in the template rather than a
#              build failure nobody can read -- it still matters to anyone who
#              turns the default back off.
#   note       Anything a reader would otherwise have to discover the hard way.
#   arch       Upstream's Arch package name. Kept solely so the CI cross-check
#              can match rows; nothing at runtime reads it.
{
  # ── Browsers ────────────────────────────────────────────────────────────
  brave = {
    menuId = "install.browser.brave";
    label = "Brave";
    category = "Browser";
    attr = "brave";
    arch = "brave-bin";
  };
  chrome = {
    menuId = "install.browser.chrome";
    label = "Chrome";
    category = "Browser";
    attr = "google-chrome";
    unfree = true;
    arch = "google-chrome";
  };
  edge = {
    menuId = "install.browser.edge";
    label = "Edge";
    category = "Browser";
    attr = "microsoft-edge";
    unfree = true;
    arch = "microsoft-edge-stable-bin";
  };
  firefox = {
    menuId = "install.browser.firefox";
    label = "Firefox";
    category = "Browser";
    option = [
      "programs"
      "firefox"
    ];
    arch = "firefox";
    note = "A NixOS module, so policies and extensions are declarative too.";
  };

  # ── Editors ─────────────────────────────────────────────────────────────
  vscode = {
    menuId = "install.editor.vscode";
    label = "VSCode";
    category = "Editor";
    attr = "vscode";
    unfree = true;
    arch = "visual-studio-code-bin";
  };
  cursor = {
    menuId = "install.editor.cursor";
    label = "Cursor";
    category = "Editor";
    attr = "code-cursor";
    unfree = true;
    arch = "cursor-bin";
  };
  zed = {
    menuId = "install.editor.zed";
    label = "Zed";
    category = "Editor";
    attr = "zed-editor";
    arch = "zed";
  };
  helix = {
    menuId = "install.editor.helix";
    label = "Helix";
    category = "Editor";
    attr = "helix";
    arch = "helix";
  };
  emacs = {
    menuId = "install.editor.emacs";
    label = "Emacs";
    category = "Editor";
    attr = "emacs";
    arch = "omarchy-emacs";
  };
  vim = {
    menuId = "install.editor.vim";
    label = "Vim";
    category = "Editor";
    attr = "vim";
    arch = "vim";
  };
  sublime = {
    menuId = "install.editor.sublime";
    label = "Sublime Text";
    category = "Editor";
    # nixpkgs marks sublimetext4 broken -- "Packages, including core ones, do
    # not run without plug-in host depending on insecure OpenSSL" -- and
    # enabling it aborts the whole rebuild rather than failing on its own.
    unavailable = "nixpkgs marks sublimetext4 broken over an insecure OpenSSL dependency; enabling it fails the rebuild.";
    arch = "sublime-text-4";
  };

  # ── Terminals ───────────────────────────────────────────────────────────
  # foot already ships in the base session, but its Install row still exists
  # upstream and has to be mapped or it stays wired to pacman. Enabling it is
  # harmless: systemPackages is a set.
  foot = {
    menuId = "install.terminal.foot";
    label = "Foot";
    category = "Terminal";
    attr = "foot";
    arch = "foot";
  };
  alacritty = {
    menuId = "install.terminal.alacritty";
    label = "Alacritty";
    category = "Terminal";
    attr = "alacritty";
    arch = "alacritty";
  };
  ghostty = {
    menuId = "install.terminal.ghostty";
    label = "Ghostty";
    category = "Terminal";
    attr = "ghostty";
    arch = "ghostty";
  };
  kitty = {
    menuId = "install.terminal.kitty";
    label = "Kitty";
    category = "Terminal";
    attr = "kitty";
    arch = "kitty";
  };

  # ── Services ────────────────────────────────────────────────────────────
  tailscale = {
    menuId = "install.service.tailscale";
    label = "Tailscale";
    category = "Service";
    option = [
      "services"
      "tailscale"
    ];
    arch = "tailscale";
    note = "A daemon. `settings.useRoutingFeatures = \"client\"` for exit nodes.";
  };
  _1password = {
    menuId = "install.service.1password";
    label = "1Password";
    category = "Service";
    option = [
      "programs"
      "_1password-gui"
    ];
    arch = "1password";
    unfree = true;
    note = ''
      Needs the module, not the package: unlocking requires a setuid helper
      that only programs._1password-gui installs. Set
      `settings.polkitPolicyOwners = [ "yourname" ]`.
    '';
  };
  dropbox = {
    menuId = "install.service.dropbox";
    label = "Dropbox";
    category = "Service";
    # A package, not a module: nixpkgs has no services.dropbox option, despite
    # dropbox being a daemon on other distros.
    attr = "dropbox";
    unfree = true;
    arch = "dropbox";
  };
  signal = {
    menuId = "install.service.signal";
    label = "Signal";
    category = "Service";
    attr = "signal-desktop";
    arch = "signal-desktop";
  };
  spotify = {
    menuId = "install.service.spotify";
    label = "Spotify";
    category = "Service";
    attr = "spotify";
    unfree = true;
    arch = "spotify";
  };
  bitwarden = {
    menuId = "install.service.bitwarden";
    label = "Bitwarden";
    category = "Service";
    attr = "bitwarden-desktop";
    arch = "bitwarden";
  };
  nordvpn = {
    menuId = "install.service.nordvpn";
    label = "NordVPN";
    category = "Service";
    attr = "nordvpn";
    unfree = true;
    arch = "nordvpn-bin";
  };

  # ── Gaming ──────────────────────────────────────────────────────────────
  steam = {
    menuId = "install.gaming.steam";
    label = "Steam";
    category = "Gaming";
    option = [
      "programs"
      "steam"
    ];
    unfree = true;
    arch = "steam";
    note = "A module, not a package: Steam needs an FHS wrapper to run at all.";
  };
  lutris = {
    menuId = "install.gaming.lutris";
    label = "Lutris";
    category = "Gaming";
    attr = "lutris";
    arch = "lutris";
  };
  heroic = {
    menuId = "install.gaming.heroic";
    label = "Heroic (Epic Games)";
    category = "Gaming";
    attr = "heroic";
    arch = "heroic-games-launcher-bin";
  };
  retroarch = {
    menuId = "install.gaming.retroarch";
    label = "RetroArch";
    category = "Gaming";
    # Not plain `pkgs.retroarch`: that is `retroarch-with-cores` built with no
    # cores at all, so it installs cleanly and then emulates nothing.
    attr = "retroarch";
    ours = true;
    arch = "retroarch";
    note = ''
      Ships 13 free cores. For more -- including snes9x, genesis-plus-gx, mame
      and dolphin, which nixpkgs marks unfree -- set allowUnfree and override
      the package:
        apps.retroarch.package =
          pkgs.retroarch.withCores (c: [ c.snes9x c.mame c.dolphin ]);
    '';
  };
  xbox-controllers = {
    menuId = "install.gaming.xbox-controllers";
    label = "Xbox Controllers";
    category = "Gaming";
    option = [
      "hardware"
      "xpadneo"
    ];
    arch = "xpadneo-dkms";
    note = "A kernel driver, so it is a hardware option rather than a package.";
  };

  # ── AI ──────────────────────────────────────────────────────────────────
  lm-studio = {
    menuId = "install.ai.lm-studio";
    label = "LM Studio";
    category = "AI";
    attr = "lmstudio";
    unfree = true;
    arch = "lmstudio-bin";
  };

  # ── Development ─────────────────────────────────────────────────────────
  php = {
    menuId = "install.development.php.php";
    label = "PHP";
    category = "Development";
    attr = "php";
    arch = "php";
  };
  symfony = {
    menuId = "install.development.php.symfony";
    label = "Symfony";
    category = "Development";
    attr = "symfony-cli";
    unfree = true;
    arch = "symfony-cli";
  };

  # ── No nixpkgs equivalent ───────────────────────────────────────────────
  # Listed so the CI cross-check stays honest and so the menu can say WHY a
  # row is gone rather than silently dropping it. `unavailable` entries
  # generate no option and no template row.
  minecraft = {
    menuId = "install.gaming.minecraft";
    label = "Minecraft";
    category = "Gaming";
    # nixpkgs removed `minecraft` as broken and its own error message says
    # to use prismlauncher, so this is nixpkgs' recommendation rather than a
    # substitution invented here.
    attr = "prismlauncher";
    arch = "minecraft-launcher";
  };
  zen = {
    menuId = "install.browser.zen";
    label = "Zen";
    category = "Browser";
    # Upstream's own flake, not a derivation here: it tracks Zen's releases
    # far more closely than we could.
    attr = "zen-browser";
    ours = true;
    arch = "zen-browser-bin";
  };
  brave-origin = {
    menuId = "install.browser.brave-origin";
    label = "Brave Origin";
    category = "Browser";
    unavailable = "Brave's managed build is AUR-only with no published source; enable apps.brave and put policies in /etc/brave/policies/managed, which stock Brave honours identically.";
    arch = "brave-origin-bin";
  };
  chatgpt = {
    menuId = "install.ai.chatgpt";
    label = "ChatGPT Desktop";
    category = "AI";
    attr = "chatgpt";
    unfree = true;
    arch = "openai-codex-desktop";
  };
  dictation = {
    menuId = "install.ai.dictation";
    label = "Dictation";
    category = "AI";
    attr = "voxtype";
    arch = "voxtype-bin";
  };
  grok-bot = {
    menuId = "install.ai.grok-bot";
    label = "Grok Bot";
    category = "AI";
    attr = "grok-bot";
    ours = true;
    unfree = true;
    arch = "grok-bot";
  };
  t3-code = {
    # No menuId: Omarchy v4.0.1 has no install.ai.t3-code row -- it was added
    # upstream after the tag this flake pins. The package is still available
    # as programs.nixarchy.apps.t3-code; the menu row returns when the omarchy
    # input is bumped. The generator fails on a menuId upstream does not
    # ship, which is how this was caught.
    label = "T3 Code";
    category = "AI";
    attr = "t3code";
    arch = "t3code-bin";
  };
  omawrite = {
    # No menuId: Omarchy has no install row for its own applications -- upstream
    # installs omawrite, omacalc, omacut and aether as preinstalls instead. Here
    # they cannot be preinstalls, because nixpkgs carries none of them, so this
    # is the opt-in form: programs.nixarchy.apps.omawrite.
    label = "Omawrite";
    category = "Utility";
    attr = "omawrite";
    ours = true;
  };
  omacalc = {
    # As omawrite. Ships no .desktop of its own, so the package writes one --
    # see pkgs/apps/omacalc.nix.
    label = "Omacalc";
    category = "Utility";
    attr = "omacalc";
    ours = true;
  };
  omacut = {
    # As omawrite and omacalc. Needs ffmpeg at runtime, which the package wraps
    # in rather than adding to systemPackages -- see pkgs/apps/omacut.nix.
    label = "Omacut";
    category = "Utility";
    attr = "omacut";
    ours = true;
  };
  hey-cli = {
    # No menuId: Omarchy v4.0.1 ships no HEY row at all -- hey.com/agents asks
    # for "Omarchy 4.1 or later", which is unreleased, and v4.0.1's AI group is
    # chatgpt/dictation/grok-bot/lm-studio/ollama. The package is available now
    # as programs.nixarchy.apps.hey-cli; the menu row arrives with the omarchy
    # bump. The generator fails on a menuId upstream does not ship, which is
    # what keeps this honest.
    #
    # `hey-cli` rather than `hey`, because nixpkgs already has a `hey` and it is
    # an unrelated HTTP load generator. The binary still installs as `hey`; see
    # meta.mainProgram in pkgs/apps/hey-cli.nix, which is what the Install menu
    # and nixarchy-doctor use to notice you already have it.
    label = "HEY CLI";
    category = "AI";
    attr = "hey-cli";
    ours = true;
  };
  once = {
    menuId = "install.service.once";
    label = "ONCE";
    category = "Service";
    attr = "once";
    ours = true;
    arch = "once-bin";
  };

  # ── Preinstalls ─────────────────────────────────────────────────────────
  # Upstream ships these installed and offers Remove > Preinstalls to take
  # them away; programs.nixarchy.preinstalls is the declarative form of that
  # and covers the rest of the group. Obsidian cannot travel with it: an
  # unfree package in the always-on set aborts the entire rebuild rather than
  # failing on its own, so it is opt-in here instead.
  # No menuId: upstream has no per-app Install row for a preinstall either,
  # and inventing one would put a row in the menu that Omarchy does not have.
  # It reaches users through the app-selection template instead.
  obsidian = {
    label = "Obsidian";
    category = "Preinstalls";
    attr = "obsidian";
    unfree = true;
    arch = "obsidian";
    note = ''
      Preinstalled upstream, opt-in here because it is unfree. Theme syncing
      needs the Omarchy theme selected under Appearance > Themes in the app;
      omarchy-theme-set-obsidian writes it on every theme change.
    '';
  };

  # ── Development environments ────────────────────────────────────────────
  #
  # Upstream installs these with `mise use --global <lang>@latest`, which
  # fetches a prebuilt toolchain into ~/.local/share/mise. That is a poor fit
  # twice over: nothing about it survives into the configuration, and mise's
  # binaries are dynamically linked against paths NixOS does not have, so
  # several of them will not execute at all.
  #
  # As selection entries they go through the same Install / Remove / Apply
  # loop as every other app, and the compiler comes from the same nixpkgs the
  # rest of the system does. mise is still installed and still works for
  # anything not listed here.
  go = {
    menuId = "install.development.go";
    label = "Go";
    category = "Development";
    attr = "go";
    arch = "go";
    note = "mise use --global go@latest downloads a toolchain outside Nix. This is nixpkgs' go, rebuilt with the system.";
  };
  rust = {
    menuId = "install.development.rust";
    label = "Rust";
    category = "Development";
    attr = "rustup";
    arch = "rustup";
    note = "rustup manages its own toolchains under ~/.rustup, the same as upstream. Use pkgs.cargo and pkgs.rustc instead if you would rather Nix pinned the compiler.";
  };
  nodejs = {
    menuId = "install.development.javascript.node";
    label = "Node.js";
    category = "Development";
    attr = "nodejs";
    arch = "nodejs";
    note = "mise' prebuilt Node is dynamically linked against paths NixOS does not have, so it often will not execute at all. This one does.";
  };
  bun = {
    menuId = "install.development.javascript.bun";
    label = "Bun";
    category = "Development";
    attr = "bun";
    arch = "bun";
  };
  deno = {
    menuId = "install.development.javascript.deno";
    label = "Deno";
    category = "Development";
    attr = "deno";
    arch = "deno";
  };
  java = {
    menuId = "install.development.java";
    label = "Java";
    category = "Development";
    attr = "jdk";
    arch = "jdk-openjdk";
  };
  elixir = {
    menuId = "install.development.elixir.elixir";
    label = "Elixir";
    category = "Development";
    attr = "elixir";
    arch = "elixir";
  };
  zig = {
    menuId = "install.development.zig";
    label = "Zig";
    category = "Development";
    attr = "zig";
    arch = "zig";
  };
  clojure = {
    menuId = "install.development.clojure";
    label = "Clojure";
    category = "Development";
    attr = "clojure";
    arch = "clojure";
  };
  scala = {
    menuId = "install.development.scala";
    label = "Scala";
    category = "Development";
    attr = "scala";
    arch = "scala";
  };
  dotnet = {
    menuId = "install.development.dotnet";
    label = ".NET";
    category = "Development";
    attr = "dotnet-sdk";
    arch = "dotnet-sdk";
  };
  python = {
    menuId = "install.development.python";
    label = "Python";
    category = "Development";
    attr = "python3";
    arch = "python";
    note = ''
      Already on the system as a runtime dependency of Omarchy's own scripts,
      so this row shows dim on a stock install. Select it to say so in your
      configuration rather than relying on that.
    '';
  };
  ocaml = {
    menuId = "install.development.ocaml";
    label = "OCaml";
    category = "Development";
    attr = "ocaml";
    arch = "ocaml";
  };
}
