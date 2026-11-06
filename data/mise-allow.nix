# Every remaining reference to mise or MISE_ in the shipped tree, the shell
# rcs and modules/, and why it is inert (#1625).
#
# Read by checks.mise-free (tests/mise-free.nix, .github/scripts/check-mise-free.py).
# Matched per stripped, comment-removed line in both directions: an unrecorded
# match fails, and a recorded line that no longer matches is stale.
{
  "modules/home.nix" = {
    reason = "data the removal needs, or the refusal naming it";
    lines = [
      "}:$PATH \${omarchyPath}/bin/omarchy-mise-unshadow ||"
      "echo \"nixarchy: omarchy-mise-unshadow failed; mise launchers not checked\" >&2"
      "\"omarchy/hooks/post-boot.d/mise-notice\" = {"
      "exec \${cfg.package}/bin/omarchy-mise-unshadow --notify"
    ];
  };
  "tree/bin/omarchy" = {
    reason = "a path or name lookup that runs nothing";
    lines = [
      "GROUP_DESCRIPTIONS[mise]=\"Mise tool wrappers\""
    ];
  };
  "tree/bin/omarchy-agent" = {
    reason = "reads a generated launcher without running it";
    lines = [
      "[[ ! -L $1 ]] && head -c 4096 \"$1\" | grep -qaE 'mise (use|x) '"
    ];
  };
  "tree/bin/omarchy-agent-usage-codex" = {
    reason = "rejects generated launchers and mise shims without running them";
    lines = [
      "data_home = ENV.get(\"MISE_DATA_DIR\") or os.path.join("
      "ENV.get(\"XDG_DATA_HOME\") or os.path.join(str(Path.home()), \".local\", \"share\"), \"mise\")"
      "mise = find_command(\"mise\")"
      "return bool(mise) and os.path.realpath(path) == os.path.realpath(mise)"
      "return b\"mise use\" in head or b\"mise x \" in head"
    ];
  };
  "tree/bin/omarchy-agent-integrate-herdr" = {
    reason = "reads an environment variable mise would set; empty here, and it runs nothing";
    lines = [
      "done < <(jq -r '.[].name' <<<\"\${MISE_INSTALLED_TOOLS:-[]}\" 2>/dev/null)"
    ];
  };
  "tree/bin/omarchy-default-agent" = {
    reason = "#1622's stale-PATH step: looks for mise, runs none";
    lines = [
      "*/mise/shims | */mise/installs/* | */mise/command-wrappers/*) stale=true ;;"
      "if [[ $stale == true ]] && ! PATH=$live_path command -v mise &>/dev/null; then"
    ];
  };
  "tree/bin/omarchy-install-hermes-cli" = {
    reason = "this task's refusals";
    lines = [
      "echo \"The Hermes that mise built stays in ~/.local/share/mise.\" >&2"
      "--retire-mise)"
      "echo \"Usage: omarchy-install-hermes-cli <--check|--now|--retire-mise>\" >&2"
    ];
  };
  "tree/bin/omarchy-install-openclaw-cli" = {
    reason = "a path or name lookup that runs nothing";
    lines = [
      "local shims=\${MISE_SHIMS_DIR:-\${MISE_DATA_DIR:-\${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims}"
      "PATH=\"$shims:$HOME/.local/share/mise/shims:/usr/local/bin:$PATH:$HOME/.local/bin\" type -aP openclaw"
    ];
  };
  "tree/bin/omarchy-mise-default-tools" = {
    reason = "this task's refusals";
    lines = [
      "echo \"nixarchy does not ship mise.\" >&2"
    ];
  };
  "tree/bin/omarchy-mise-install" = {
    reason = "this task's refusals";
    lines = [
      "echo \"nixarchy does not ship mise.\" >&2"
    ];
  };
  "tree/bin/omarchy-mise-unshadow" = {
    reason = "data the removal needs, or the refusal naming it";
    lines = [
      "notice=\"$state/mise-notice\""
      "if omarchy-notification-send -u normal \"mise is no longer part of nixarchy\" \"$(<\"$notice\")\"; then"
      "quiet) printf '#!/bin/bash\\nexport MISE_MINIMUM_RELEASE_AGE=0\\nmise use -g --quiet \"%s\" || exit 1\\nexec mise x \"%s\" -- \"%s\" \"$@\"\\n' \"$2\" \"$2\" \"$3\" ;;"
      "cooldown-export) printf '#!/bin/bash\\nexport MISE_MINIMUM_RELEASE_AGE=0\\nmise use -g \"%s\" || exit 1\\nexec mise x \"%s\" -- \"%s\" \"$@\"\\n' \"$2\" \"$2\" \"$3\" ;;"
      "bail-on-failure) printf '#!/bin/bash\\nmise use -g \"%s\" || exit 1\\nexec mise x \"%s\" -- \"%s\" \"$@\"\\n' \"$2\" \"$2\" \"$3\" ;;"
      "mise-exec) printf '#!/bin/bash\\nmise use -g \"%s\"\\nexec mise exec \"%s\" -- \"%s\" \"$@\"\\n' \"$2\" \"$2\" \"$3\" ;;"
      "if [[ $line =~ ^mise\\ use\\ -g(\\ --quiet)?\\ \\\"([^\\\"]+)\\\" ]]; then"
      "for form in quiet cooldown-export bail-on-failure mise-exec bare-exec; do"
      "echo \"omarchy-mise-unshadow: removed $f\""
      "elif grep -qaE '(^|[^[:alnum:]_-])mise([[:space:]]|$)' -- \"$f\"; then"
      "for d in \"$HOME/.local/share/mise/installs\"/*; do"
      "echo \"mise is no longer part of nixarchy. Nothing you own was deleted except any launchers listed here.\""
      "echo \"Off your PATH now, in ~/.local/share/mise/installs: \${tools[*]}\""
      "echo \"To clean up, if you want to: rm -rf ~/.local/share/mise ~/.config/mise\""
      "echo \"nixarchy: mise is no longer part of nixarchy; see $notice\""
      "echo \"nixarchy: removed mise launchers; see $notice\""
    ];
  };
  "tree/bin/omarchy-remove-dev-env" = {
    reason = "this task's refusals";
    lines = [
      "echo \"Remove languages in Remove > Development. For something your own mise installed, use your own mise rm.\" >&2"
    ];
  };
  "tree/bin/omarchy-update-mise" = {
    reason = "this task's refusals";
    lines = [
      "echo \"nixarchy does not ship mise. If you installed it yourself: mise up.\" >&2"
    ];
  };
  "tree/bin/omarchy-upgrade-to-quattro" = {
    reason = "unreachable (data/bin-ledger.nix:704)";
    lines = [
      "if PATH=\"$package_path\" command -v omarchy-update-mise >/dev/null 2>&1; then"
      "if ! run_as_user_omarchy omarchy-update-mise; then"
      "warn \"Could not update mise tools; running omarchy-update after reboot may still update mise-managed tools.\""
      "/^[[:space:]]*omarchy-cmd-present[[:space:]]+mise && eval \"\\$\\(mise activate bash --shims\\)\"[[:space:]]*$/ { omitted(\"mise activation\") }"
    ];
  };
  "tree/default/agents/skills/devenv/SKILL.md" = {
    reason = "documentation telling agents mise is not the answer here; runs nothing";
    lines = [
      "per-project, project environment, direnv, mise, \"for this project\", \"pin the"
      "| `mise use --global <lang>@latest` | Not on this machine. See below |"
      "Upstream Omarchy's Install menu sets languages up with `mise use --global`,"
      "which fetches a prebuilt toolchain into `~/.local/share/mise`. `data/apps.nix`"
      "survives into the configuration, and mise's prebuilt binaries are dynamically"
      "all. nixarchy does not ship or activate mise (#1625), and it is never the answer"
      "- \"Use mise to install Python 3.12\" → not on this machine; `nixarchy dev init python`, then `languages.python.version`"
    ];
  };
  "tree/default/bash/env-bootstrap" = {
    reason = "behind a [ -r /usr/share/... ] guard that is false on NixOS";
    lines = [
      "omarchy_wrapper_dir=\"\${MISE_DATA_DIR:-\${XDG_DATA_HOME:-$HOME/.local/share}/mise}/command-wrappers/bin\""
      "*\":$HOME/.local/share/mise/shims:\"*) ;;"
      "*) PATH=\"\${PATH:+$PATH:}$HOME/.local/share/mise/shims\" ;;"
    ];
  };
  "tree/default/uwsm/env.d/10-omarchy" = {
    reason = "nothing here reads it";
    lines = [
      "omarchy-cmd-present mise && eval \"$(mise activate bash --shims)\""
    ];
  };
  "tree/install/config/ssh-command-path.sh" = {
    reason = "nothing here reads it";
    lines = [
      "PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin"
    ];
  };
  "tree/install/omarchy-base.packages" = {
    reason = "a package name in a list nothing installs";
    lines = [
      "mise-bin"
    ];
  };
  "tree/install/user/all.sh" = {
    reason = "a directory name; the script only runs mkdir";
    lines = [
      "run_logged \"$OMARCHY_INSTALL/user/mise-work.sh\""
    ];
  };
  "tree/shell/plugins/agents/collectors.py" = {
    reason = "a path or name lookup that runs nothing";
    lines = [
      "f\"{home}/.local/share/mise/shims\","
    ];
  };
  "tree/shell/services/AppLibrary.qml" = {
    reason = "a path or name lookup that runs nothing";
    lines = [
      "// profile, and tools like mise touch ~/.local/share on activation — a"
    ];
  };
}
