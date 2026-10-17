# Why each visible menu row that reaches a hazard is acceptable or pending (#1304).
# Read by checks.menu-actions (tests/menu-actions.nix); the walk is described in
# .github/scripts/check-menu-actions.py. A `hidden:` row must have when = false;
# any other reason must still reach a hazard, or the entry is stale. `pending`
# is temporary: Part 4 of the series forbids it.
{
  "install.ai.hermes" = "hidden: needs /usr/share/hermes-desktop (decision 12)";
  "install.preinstalls" =
    "owned: adds missing launchers only, never overwrites; its one rm is its own marker (decision 2, checks.remove-preinstalls)";
  "install.style.font.bitstream" = "session: restarts the user's shell unit";
  "install.style.font.cascadia" = "session: restarts the user's shell unit";
  "install.style.font.fira" = "session: restarts the user's shell unit";
  "install.style.font.iosevka" = "session: restarts the user's shell unit";
  "install.style.font.meslo" = "session: restarts the user's shell unit";
  "install.style.font.victor" = "session: restarts the user's shell unit";
  "install.style.theme" =
    "owned: omarchy-install-hermes-cli removes only the wrapper it wrote (--owns)";
  "install.windows" = "hidden: needs rooted Docker and an FHS PATH (decision 12)";
  "remove.ai.hermes" = "hidden: needs /usr/share/hermes-desktop (decision 12)";
  "remove.ai.perplexity" = "hidden: a pacman package nixpkgs lacks (decision 12)";
  "remove.browser.brave-origin" = "hidden: AUR-only (decision 12)";
  "remove.development.elixir.phoenix" =
    "hidden: its elixir|phoenix arm removes Elixir and Erlang (decision 3)";
  "remove.development.php.laravel" =
    "unreached: the pacman lines are the php and symfony arms, which the generator overrides; rails removes its own mise Ruby and ~/.gemrc, laravel its composer package (decision 3)";
  "remove.development.rails" =
    "unreached: the pacman lines are the php and symfony arms, which the generator overrides; rails removes its own mise Ruby and ~/.gemrc, laravel its composer package (decision 3)";
  "remove.gaming.battlenet" =
    "owned: deletes its own prefix; GE-Proton and umu only after a confirm; pkg-drop is inert here (decision 10)";
  "remove.preinstalls" =
    "owned: deletes only unmodified seeds and exact mise stubs; omarchy-install-hermes-cli removes only the wrapper it wrote (--owns) (decision 2, checks.remove-preinstalls)";
  "remove.security.fido2" = "guidance: exits 1 before its writers (decision 7, checks.menu-guidance)";
  "remove.security.fingerprint" =
    "guidance: exits 1 before its writers (decision 7, checks.menu-guidance)";
  "remove.security.sudoless-docker" =
    "guidance: exits 1 before its writers (decision 6, checks.menu-guidance)";
  "remove.windows" = "hidden: needs rooted Docker and an FHS PATH (decision 12)";
  "setup.config.xcompose" = "session: restarts the user's XCompose unit";
  "setup.default.agent.antigravity" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.claude" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.codex" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.copilot" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.crush" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.cursor-agent" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.gemini" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.grok" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.hermes" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.muse" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.omp" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.openclaw" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.opencode" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.pi" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.network.dns.cloudflare" =
    "guidance: exits 1 before its writers (decision 4, checks.menu-guidance)";
  "setup.network.dns.custom" =
    "guidance: exits 1 before its writers (decision 4, checks.menu-guidance)";
  "setup.network.dns.dhcp" =
    "guidance: exits 1 before its writers (decision 4, checks.menu-guidance)";
  "setup.network.dns.google" =
    "guidance: exits 1 before its writers (decision 4, checks.menu-guidance)";
  "setup.security.fido2" =
    "unreached: names omarchy-remove-security-fido2 in its guidance text and never runs it";
  "setup.security.sudoless-docker" =
    "guidance: exits 1 before its writers (decision 6, checks.menu-guidance)";
  "style.theme" = "owned: omarchy-install-hermes-cli removes only the wrapper it wrote (--owns)";
  "trigger.hardware.hybrid-gpu" =
    "hidden: needs supergfxd and /usr/lib/systemd/system-sleep (decision 12)";
  "trigger.reminder.clear" = "session: creates, shows or clears the user's reminder timer unit";
  "trigger.reminder.set" = "session: creates, shows or clears the user's reminder timer unit";
  "trigger.reminder.show" = "session: creates, shows or clears the user's reminder timer unit";
  "trigger.toggle.crash-capture" = "session: toggles the user's crash-capture unit";
  "update.config.shell" = "session: restarts the user's shell unit";
  "update.firmware" =
    "unreached: the /boot install runs only if /usr/lib/fwupd/efi/fwupdx64.efi exists, which it never does here (decision 11)";
  "update.hardware.audio" = "session: restarts the user's audio units";
  "update.hardware.bluetooth" = "runtime: resets bluetooth for this boot; nothing a rebuild owns";
  "update.hardware.trackpad" =
    "runtime: reloads the trackpad driver for this boot; nothing a rebuild owns";
  "update.hardware.wifi" = "runtime: resets wifi for this boot; nothing a rebuild owns";
  "update.process.shell" = "session: restarts the user's shell unit";
  "setup.direct-boot" = "hidden: needs efibootmgr and an Omarchy UKI (decision 12)";
  "install.ai.perplexity" = "hidden: a pacman package nixpkgs lacks (decision 12)";
}
