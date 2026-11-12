# Why each visible menu row that reaches a hazard is acceptable or pending (#1304).
# Read by checks.menu-actions (tests/menu-actions.nix); the walk is described in
# .github/scripts/check-menu-actions.py. A `hidden:` row must have when = false;
# any other reason must still reach a hazard, or the entry is stale. `pending`
# is temporary: Part 4 of the series forbids it.
{
  "agent.make.app" = {
    reason = "unreached: omarchy-agent-make starts the default agent through omarchy-agent, which calls omarchy-agent-local only for status and overlay, never share (the branch that sets up sshd); the OpenClaw user unit starts only when OpenClaw is the default agent, as for the agent.harness rows";
    edge = "only";
  };
  "agent.make.plugin" = {
    reason = "unreached: omarchy-agent-make starts the default agent through omarchy-agent, which calls omarchy-agent-local only for status and overlay, never share (the branch that sets up sshd); the OpenClaw user unit starts only when OpenClaw is the default agent, as for the agent.harness rows";
    edge = "only";
  };
  "agent.make.theme" = {
    reason = "unreached: omarchy-agent-make starts the default agent through omarchy-agent, which calls omarchy-agent-local only for status and overlay, never share (the branch that sets up sshd); the OpenClaw user unit starts only when OpenClaw is the default agent, as for the agent.harness rows";
    edge = "only";
  };
  "install.browser.chromium" = {
    reason = "unreached: the row is disabled while omarchy-pkg-present chromium holds, and Chromium is a runtime dependency of the package (chromium-flags in pkgs/omarchy/default.nix), so the pacman path in omarchy-install-browser never runs";
    edge = "only";
  };
  "agent.harness.agy" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.amp" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.claude" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.codex" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.commandcode" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.copilot" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.crush" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.cursor-agent" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.devin" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.dsh" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.freebuff" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.grok" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.hermes" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.kilo" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.kimi" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.kiro-cli" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.mcode" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.muse" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.omp" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.openclaw" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.opencode" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.ori" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.pi" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "agent.harness.qwen" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it The agents panel's tailnet sharing (omarchy-agent-local share) sets up sshd; omarchy-agent calls omarchy-agent-local only for status and overlay, so this row never takes that branch.";
    edge = "only";
  };
  "install.ai.herdr" = {
    reason = "unreached: its theme refresh reaches theme-set-hermes, which runs omarchy-install-hermes-cli --check only; its user-unit stop is the --now branch";
    edge = "only";
  };
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
  "remove.security.fido2" = "guidance: exits 1 before its writers (decision 7, checks.menu-guidance)";
  "remove.security.sudoless-docker" =
    "guidance: exits 1 before its writers (decision 6, checks.menu-guidance)";
  "remove.service.ssh-agent" =
    "session: disables the user's gcr-ssh-agent socket and removes its own environment.d file";
  "setup.config.git" =
    "session: restarts the user's XCompose unit after writing the git identity into ~/.XCompose";
  "setup.config.xcompose" = "session: restarts the user's XCompose unit";
  "setup.default.agent.agy" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.amp" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.claude" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.codex" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.commandcode" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.copilot" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.crush" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.cursor-agent" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.devin" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.dsh" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.freebuff" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.grok" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.hermes" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.kilo" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.kimi" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.kiro-cli" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.mcode" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.muse" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.omp" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.openclaw" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.opencode" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.ori" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.pi" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
  "setup.default.agent.qwen" = {
    reason = "session: the OpenClaw branch starts a user unit; other agents never take it";
    edge = "absent";
  };
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
  "setup.default.editor.plain" = {
    reason = "owned: its one rm clears its own pending-default-editor marker after setting the default (#1623, checks.menu-conditions)";
    edge = "only";
  };
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
