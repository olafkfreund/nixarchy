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
  "install.package" = "installs an arbitrary named package; the row IS the mechanism.";
  "install.preinstalls" =
    "re-runs Omarchy's own preinstall set, which this port expresses as modules.";
  "install.style.background" = "sets a wallpaper. Not a package.";
  "install.style.theme" = "installs a theme. Handled by programs.nixarchy.theme.";
  "install.tui" = "installs a TUI app by name, like install.package.";
  "install.webapp" = "installs a web app as a chromium PWA. Nothing to package.";
  "install.windows" = "a Windows VM helper, out of scope for this port.";
  "install.service.chromium-account" = "adds a browser profile. Not a package.";

  # Fonts go through omarchy-install-font and the Arch-name map.
  "install.style.font.bitstream" = "font, installed by omarchy-install-font.";
  "install.style.font.cascadia" = "font, installed by omarchy-install-font.";
  "install.style.font.fira" = "font, installed by omarchy-install-font.";
  "install.style.font.iosevka" = "font, installed by omarchy-install-font.";
  "install.style.font.meslo" = "font, installed by omarchy-install-font.";
  "install.style.font.victor" = "font, installed by omarchy-install-font.";

  # Documented gaps -- the README names these as needing a hand.
  "install.ai.ollama" = "a service, not an app: programs.nixarchy.services.local-ai.";
  "install.gaming.battlenet" = "needs a hand; documented in the README.";
  "install.gaming.geforce-now" = "needs a hand; documented in the README.";
  "install.gaming.retro-launcher" = "needs a hand; documented in the README.";
  "install.gaming.xbox-cloud" = "needs a hand; documented in the README.";
  "install.development.docker-dbs" = "a compose stack, not a package.";
  "install.development.elixir.phoenix" = "a framework scaffold, not a package.";
  "install.development.php.laravel" = "a framework scaffold, not a package.";
  "install.development.rails" = "a framework scaffold, not a package.";

  # New in Omarchy 4.0.3.
  "install.ai.hermes" =
    "nixpkgs has no `hermes` and no `hermes-cli`; upstream fetches a binary "
    + "with its own installer. Left unmapped rather than pointed at some other "
    + "`hermes` -- see the openclaw note in data/apps.nix for why that matters.";
  "install.ai.perplexity" =
    "a web app, not a package: its action is `omarchy-install-and-launch "
    + "Perplexity perplexity perplexity`, the same shape as install.webapp.";
}
