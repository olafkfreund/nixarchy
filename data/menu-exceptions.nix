# Install rows that are deliberately NOT applications in this port.
#
# One file, read by both gates that ask the question -- .github/scripts/
# check-menu-mapping.py and tests/options.nix. Before this existed the answer
# lived only in tests/options.nix, so recording a decision satisfied one gate
# and left the other red on the same row. A bump then looked like two
# problems and was one.
#
# ## What belongs here
#
# A row whose action installs something this port cannot or should not offer
# as `programs.nixarchy.apps.<name>`:
#
#   - an ACTION rather than an application (install.webapp, install.aur)
#   - a package nixpkgs does not carry, where wrapping it would mean packaging
#     it first
#   - a row upstream documents as needing a hand
#
# A row does NOT belong here just because mapping it is work. The reason is
# read by a human at review time and by whoever bumps Omarchy next; "not done
# yet" is a TODO, not an exception.
#
# ## What the reason is for
#
# Both gates require it to be non-empty. It is the difference between "we
# decided" and "nobody looked", and on a bump those are the only two states
# that matter -- see docs/internals/omarchy-bumps.md.
{
  # Actions, not applications.
  "install.aur" = "an Arch package manager. There is no NixOS equivalent to map.";
  # quattro's Install > Service > Microsoft (#1278): Outlook, Word, Excel,
  # PowerPoint, Teams and OneDrive as web apps, through omarchy-webapp-install,
  # which works here unchanged. An action, not a package.
  "install.service.microsoft" =
    "Microsoft 365 as web apps: omarchy-webapp-install creates them, the same as on Arch; nothing to map.";
  # quattro's Install > AI > Claude Desktop (#1278).
  "install.ai.claude" =
    "Claude Desktop: nixpkgs has no claude-desktop package (checked 2026-10-15). The Claude Code agent is in the Default Agent menu.";
  "install.ai.desktop.claude" = {
    edge = "only";
    reason = "Claude Desktop has no mapped Linux package; Claude Code CLI is a separate app selection.";
  };
  "install.package" = "installs an arbitrary named package; the row IS the mechanism.";
  "install.preinstalls" =
    "re-runs Omarchy's own preinstall set, which this port expresses as modules.";
  "install.style.background" = "sets a wallpaper. Not a package.";
  "install.style.theme" = "installs a theme. Handled by programs.nixarchy.theme.";
  "install.tui" = "installs a TUI app by name, like install.package.";
  "install.webapp" = "installs a web app as a chromium PWA. Nothing to package.";
  "install.windows" = "a Windows VM helper needing rooted Docker; dimmed with a reason (#1320).";
  # quattro 36b70f1 removed the row (#1760).
  "install.service.chromium-account" = {
    reason = "adds a browser profile. Not a package.";
    edge = "absent";
  };

  # Fonts go through omarchy-install-font and the Arch-name map.
  "install.style.font.bitstream" = "font, installed by omarchy-install-font.";
  "install.style.font.cascadia" = "font, installed by omarchy-install-font.";
  "install.style.font.fira" = "font, installed by omarchy-install-font.";
  "install.style.font.iosevka" = "font, installed by omarchy-install-font.";
  "install.style.font.meslo" = "font, installed by omarchy-install-font.";
  "install.style.font.victor" = "font, installed by omarchy-install-font.";

  # Documented gaps -- the README names these as needing a hand.
  "install.ai.ollama" =
    "rewired (#1304) to setup.local-ai's action: Ollama is programs.nixarchy.localAi, a service rather than an app.";
  "install.gaming.battlenet" =
    "a Windows launcher under umu-launcher; the row ends at omarchy-pkg-add's declarative umu-launcher line.";
  "install.gaming.geforce-now" =
    "rewired (#1304) to nixarchy-service-enable geforce-now, the Flatpak in data/flatpaks.nix.";
  "install.gaming.retro-launcher" = "needs a hand; documented in the README.";
  "install.gaming.xbox-cloud" = "a web app: omarchy-webapp-install, nothing to package.";
  "install.development.docker-dbs" = "a compose stack, not a package.";
  "install.development.elixir.phoenix" =
    "a framework scaffold with no package; dimmed and pointing at devenv's languages.* (#1625).";
  "install.development.php.laravel" =
    "a framework scaffold with no package; dimmed and pointing at devenv's languages.* (#1625).";
  "install.development.rails" =
    "a framework scaffold with no package; dimmed and pointing at devenv's languages.* (#1625).";

  # New in Omarchy 4.0.3.
  "install.ai.hermes" =
    "dimmed with a reason (#1320): upstream installs a binary with its own installer under "
    + "/usr/share/hermes-desktop; nixpkgs has no hermes";
  "install.ai.desktop.hermes" = {
    edge = "only";
    reason = "Hermes Desktop uses an upstream binary installer, not a Nixarchy app selection.";
  };
  # New in quattro ae64a4b.
  "install.ai.desktop.herdr" = {
    reason =
      "Herdr's desktop app, which Herdr's own installer puts in ~/.local/share/herdr-app and updates itself; "
      + "nixpkgs has no herdr-app (its herdr is the terminal multiplexer, carried as nixarchy's herdr plugin). "
      + "The row runs upstream's installer unchanged, and the app runs through nix-ld (untested).";
    edge = "only";
  };
  "install.ai.desktop.opencode" = {
    edge = "only";
    reason = "OpenCode Desktop is a separate Electron app from the mapped opencode CLI; no desktop package is selected by programs.nixarchy.apps.opencode.";
  };
  "install.ai.desktop.perplexity" = {
    edge = "only";
    reason = "Perplexity Desktop has no mapped package in this catalogue; its upstream action uses the Arch package.";
  };
  # Quattro's new agent CLIs are Arch curated packages. The four available
  # catalogue apps (Amp, Claude Code, Codex and OpenCode) are mapped above.
  "install.ai.cli.antigravity" = {
    edge = "only";
    reason = "Antigravity CLI is separate from the mapped Antigravity desktop app; no CLI app is offered by this catalogue.";
  };
  "install.ai.cli.copilot" = {
    edge = "only";
    reason = "GitHub Copilot CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.crush" = {
    edge = "only";
    reason = "Crush CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.cursor" = {
    edge = "only";
    reason = "Cursor Agent is separate from the mapped Cursor desktop app; no CLI app is offered by this catalogue.";
  };
  "install.ai.cli.deepseek" = {
    edge = "only";
    reason = "DeepSeek dsh is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.devin" = {
    edge = "only";
    reason = "Devin CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.freebuff" = {
    edge = "only";
    reason = "Freebuff CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.grok" = {
    edge = "only";
    reason = "Grok CLI is separate from the mapped Grok Bot desktop app; no CLI app is offered by this catalogue.";
  };
  "install.ai.cli.kilo" = {
    edge = "only";
    reason = "Kilo CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.kimi" = {
    edge = "only";
    reason = "Kimi CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.minimax" = {
    edge = "only";
    reason = "MiniMax CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.muse" = {
    edge = "only";
    reason = "Muse CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.oh-my-pi" = {
    edge = "only";
    reason = "Oh My Pi is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.ori" = {
    edge = "only";
    reason = "Ori CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.ai.cli.qwen" = {
    edge = "only";
    reason = "Qwen CLI is an Arch curated package, not a Nixarchy app selection.";
  };
  "install.cli.basecamp" = {
    edge = "only";
    reason = "Basecamp CLI uses upstream's installer, not an app package selected by this catalogue.";
  };
  "install.cli.cloudflare" = {
    edge = "only";
    reason = "Cloudflare CLI is requested through Omarchy's curated package action, not this app catalogue.";
  };
  "install.cli.github" = {
    edge = "only";
    reason = "GitHub CLI is requested through Omarchy's curated package action, not this app catalogue.";
  };
  "install.cli.hey" = {
    edge = "only";
    reason = "Hey CLI uses upstream's installer, not an app package selected by this catalogue.";
  };
  "install.cli.hunk" = {
    edge = "only";
    reason = "Hunk CLI is requested through Omarchy's curated package action, not this app catalogue.";
  };
  # New in quattro efcf615 (#1896), with regions.
  "install.service.dingtalk" = {
    reason =
      "DingTalk, offered only on a machine installed for mainland China (omarchy-region-cn), which nixarchy never is; "
      + "nixpkgs has no dingtalk, so the row would end at omarchy-pkg-add's refusal naming the search.";
    edge = "only";
  };
  "install.service.wechat" = {
    reason =
      "WeChat (x86_64): upstream installs the AUR wechat-bin. nixpkgs' wechat is unfree and not mapped here yet, "
      + "so the row ends at omarchy-pkg-add's refusal naming the search; mapping it is a data/apps.nix row.";
    edge = "only";
  };
  # New in quattro 36b70f1 (#1760), once Chrome became upstream's default.
  "install.browser.chromium" = {
    reason =
      "Chromium is nixarchy's default browser and ships inside the omarchy package (its chromium-flags wrapper), "
      + "so every machine already has it; there is nothing to install or map.";
    edge = "only";
  };
  # New in quattro 9f68da8 (#1793), with icon sets.
  "install.style.icons" = {
    reason = "an action, not a package: omarchy-icons-install clones an icon set's git repository into ~/.config/omarchy/icons.";
    edge = "only";
  };
  # New in quattro 2eb7eb3 (#1847), with Game Vibes.
  "install.gaming.vibes" = {
    reason = "an action, not a package: omarchy-games-vibes-install clones a web game's git repository into ~/Games/vibes.";
    edge = "only";
  };
  "install.ai.perplexity" =
    "dimmed with a reason (#1320): a pacman package nixpkgs does not carry, not a web app";
}
