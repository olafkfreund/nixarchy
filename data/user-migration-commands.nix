# Every omarchy-* command named by an Omarchy migration that is not already a direct
# user-file hit has a row here; `checks.user-migrations-ledger` (tests/user-migrations-ledger.nix)
# follows one level of calls when `follow = true`, and `edge` ("only" | "absent") says when a row
# is needed on one pin only. See pkgs/AGENTS.md#user-file-migrations-1610.
{
  "omarchy-audio-tuning" = {
    follow = true;
    reason = "writes ~/.config/pipewire/omarchy-speaker-tuning.conf and ~/.config/systemd/user/omarchy-speaker-tuning.service";
  };
  "omarchy-bar" = {
    follow = true;
    reason = "updates bar layout and widget settings in ~/.config/omarchy/shell.json via omarchy-shell-config and omarchy-shell IPC";
  };
  "omarchy-cmd-editor-mimetypes" = {
    edge = "only";
    follow = true;
    reason = "rewrites ~/.config/mimeapps.list and copies omarchy-launch-editor.desktop into ~/.local/share/applications";
  };
  "omarchy-hook-install" = {
    follow = true;
    reason = "copies a hook script into ~/.config/omarchy/hooks/<type>.d/";
  };
  "omarchy-hyprland-monitor-config-upgrade" = {
    edge = "only";
    follow = true;
    reason = "rewrites ~/.config/hypr/monitors.lua to the new template and saves a .bak.<time> backup";
  };
  "omarchy-install-chromium-copy-url" = {
    follow = true;
    reason = "writes NativeMessagingHosts/org.omarchy.copy_url.json into browser dirs under ~/.config";
  };
  "omarchy-install-chromium-ytdlp" = {
    follow = true;
    reason = "writes NativeMessagingHosts/org.omarchy.ytdlp.json into browser dirs under ~/.config";
  };
  "omarchy-install-video-decode" = {
    follow = true;
    reason = "writes ~/.config/mpv/mpv.conf and ~/.config/chromium-flags.conf (plus ~/.config/chrome-flags.conf on edge)";
  };
  "omarchy-migrate" = {
    follow = false;
    reason = "records markers in ~/.local/state/omarchy/migrations and runs migrations, which are triaged themselves";
  };
  "omarchy-mise-default-tools" = {
    follow = true;
    reason = "writes or removes ~/.config/mise/miserc.toml on disable/enable";
  };
  "omarchy-powerprofiles-set" = {
    follow = false;
    reason = "writes only Omarchy's own state under ~/.local/state/omarchy/powerprofiles";
  };
  "omarchy-refresh-applications" = {
    follow = true;
    reason = "copies .desktop launchers into ~/.local/share/applications/";
  };
  "omarchy-state" = {
    follow = false;
    reason = "writes and removes only state markers in ~/.local/state/omarchy";
  };
  "omarchy-theme-refresh" = {
    follow = true;
    reason = "runs omarchy-theme-set for the active theme, which rewrites themed user configs in ~/.config and ~/.local/share";
  };
  "omarchy-theme-set-browser" = {
    follow = false;
    reason = "reads ~/.local/state/omarchy/current/theme and writes only system policy files under /etc via omarchy-theme-set-browser-policy";
  };
  "omarchy-theme-set-fcitx5" = {
    follow = true;
    reason = "writes ~/.local/share/fcitx5/themes/omarchy/theme.conf and edits ~/.config/fcitx5/conf/classicui.conf on --activate";
  };
  "omarchy-theme-set-hermes" = {
    follow = true;
    reason = "writes ~/.hermes/skins/omarchy.yaml and updates ~/.hermes/config.yaml via hermes config set";
  };
  "omarchy-update-keyring" = {
    edge = "only";
    follow = false;
    reason = "GNUPGHOME is a temporary mktemp directory used to refresh /etc/pacman.d/gnupg";
  };
}
