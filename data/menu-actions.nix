# Why each visible menu row that reaches a hazard is acceptable or pending (#1304).
# Read by checks.menu-actions (tests/menu-actions.nix); the walk is described in
# .github/scripts/check-menu-actions.py. A `hidden:` row must have when = false;
# any other reason must still reach a hazard, or the entry is stale. `pending`
# is temporary: Part 4 of the series forbids it.
{
  "install.ai.herdr" =
    "unreached: its theme refresh reaches theme-set-hermes, which runs omarchy-install-hermes-cli --check only; its user-unit stop is the --now branch";
  "install.preinstalls" =
    "owned: adds missing launchers only, never overwrites; its one rm is its own marker (decision 2, checks.remove-preinstalls)";
  "install.style.font.bitstream" = "session: restarts the user's shell unit";
  "install.style.font.cascadia" = "session: restarts the user's shell unit";
  "install.style.font.fira" = "session: restarts the user's shell unit";
  "install.style.font.iosevka" = "session: restarts the user's shell unit";
  "install.style.font.meslo" = "session: restarts the user's shell unit";
  "install.style.font.victor" = "session: restarts the user's shell unit";
  "install.style.theme" =
    "unreached: theme-set-hermes runs omarchy-install-hermes-cli --check only; its user-unit stop is the --now branch";
  "learn.keybindings" =
    "unreached: omarchy-menu-keybindings runs omarchy-language with no argument, which only prints the language; its shell restart is the set branch";
  "remove.development.elixir.phoenix" = "hidden: there is nothing to remove (#1625)";
  "remove.gaming.battlenet" =
    "owned: deletes its own prefix; GE-Proton and umu only after a confirm; pkg-drop is inert here (decision 10)";
  "remove.gaming.moonlight" = "owned: pkg-drop is inert here (decision 10)";
  "remove.security.fido2" = "guidance: exits 1 before its writers (decision 7, checks.menu-guidance)";
  "remove.security.sudoless-docker" =
    "guidance: exits 1 before its writers (decision 6, checks.menu-guidance)";
  "remove.service.ssh-agent" =
    "session: disables the user's gcr-ssh-agent socket and removes its own environment.d file";
  "setup.config.git" =
    "session: restarts the user's XCompose unit after writing the git identity into ~/.XCompose";
  "setup.config.xcompose" = "session: restarts the user's XCompose unit";
  "setup.default.agent.agy" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.amp" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.claude" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.codex" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.commandcode" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.copilot" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.crush" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.cursor-agent" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.devin" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.dsh" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.freebuff" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.grok" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.hermes" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.kilo" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.kimi" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.kiro-cli" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.mcode" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.muse" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.omp" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.openclaw" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.opencode" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.ori" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.pi" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.agent.qwen" =
    "session: the OpenClaw branch starts a user unit; other agents never take it";
  "setup.default.browser.brave" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.browser.brave-origin" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.browser.chrome" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.browser.chromium" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.browser.edge" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.browser.firefox" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.browser.zen" =
    "owned: its one rm clears its own pending-default-browser marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.cursor" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.emacs" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.helix" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.neovim" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.plain" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.sublime" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.vim" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.vscode" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
  "setup.default.editor.zed" =
    "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
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
  "setup.security.fingerprint" = "guidance: exits 1 before omarchy-apply-lock";
  "setup.security.ssh-agent" = "session: enables the user's gcr-ssh-agent socket";
  "setup.security.sudoless-docker" =
    "guidance: exits 1 before its writers (decision 6, checks.menu-guidance)";
  "trigger.reminder.clear" = "session: creates, shows or clears the user's reminder timer unit";
  "trigger.reminder.set" = "session: creates, shows or clears the user's reminder timer unit";
  "trigger.reminder.show" = "session: creates, shows or clears the user's reminder timer unit";
  "trigger.toggle.crash-capture-on" = "session: toggles the user's crash-capture unit";
  "trigger.toggle.crash-capture-off" = "session: toggles the user's crash-capture unit";
  "update.config.shell" = "session: restarts the user's shell unit";
  "update.firmware" =
    "unreached: the /boot install runs only if /usr/lib/fwupd/efi/fwupdx64.efi exists, which it never does here (decision 11)";
  "update.hardware.audio" = "session: restarts the user's audio units";
  "update.hardware.bluetooth" = "runtime: resets bluetooth for this boot; nothing a rebuild owns";
  "update.hardware.trackpad" =
    "runtime: reloads the trackpad driver for this boot; nothing a rebuild owns";
  "update.hardware.wifi" = "runtime: resets wifi for this boot; nothing a rebuild owns";
  "update.password.drive" =
    "unreached: pacman is omarchy-lifecycle-dispatch reading /var/lib/pacman/local, which x86_64 never reaches (exit 0 first)";
  "update.process.shell" = "session: restarts the user's shell unit";
}
