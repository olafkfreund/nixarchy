# Why each visible menu row that reaches a hazard is acceptable or pending (#1304).
# Read by checks.menu-actions (tests/menu-actions.nix); the walk is described in
# .github/scripts/check-menu-actions.py. A `hidden:` row must have when = false;
# any other reason must still reach a hazard, or the entry is stale. `pending`
# is temporary: Part 4 of the series forbids it.
{
  "install.ai.hermes" = "pending #1304 class 4: decision 12";
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
  "install.windows" = "pending #1304 class 4: decision 12";
  "remove.ai.hermes" = "pending #1304 class 4: decision 12";
  "remove.ai.perplexity" = "pending #1304 class 4: decision 12";
  "remove.browser.brave-origin" = "pending #1304 class 4: decision 12";
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
  "remove.security.fido2" = "pending #1304 class 2: decision 7";
  "remove.security.fingerprint" = "pending #1304 class 2: decision 7";
  "remove.security.sshd" = "pending #1304 class 2: decision 5";
  "remove.security.sudoless-docker" = "pending #1304 class 2: decision 6";
  "remove.windows" = "pending #1304 class 4: decision 12";
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
  "setup.network.dns.cloudflare" = "pending #1304 class 2: decision 4";
  "setup.network.dns.custom" = "pending #1304 class 2: decision 4";
  "setup.network.dns.dhcp" = "pending #1304 class 2: decision 4";
  "setup.network.dns.google" = "pending #1304 class 2: decision 4";
  "setup.security.fido2" =
    "unreached: names omarchy-remove-security-fido2 in its guidance text and never runs it";
  "setup.security.fingerprint" = "pending #1304 class 2: decision 8";
  "setup.security.sshd" = "pending #1304 class 2: decision 5";
  "setup.security.sudoless-docker" = "pending #1304 class 2: decision 6";
  "style.theme" = "owned: omarchy-install-hermes-cli removes only the wrapper it wrote (--owns)";
  "trigger.hardware.hybrid-gpu" = "pending #1304 class 4: decision 12";
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
  "update.timezone" = "pending #1304 class 2: decision 9";
}
