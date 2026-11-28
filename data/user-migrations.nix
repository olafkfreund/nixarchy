# Every Omarchy migration that touches a user's files (`grep -lE 'HOME|XDG_CONFIG|\.config|shell\.json|~/' migrations/*.sh`,
# or through a `follow = true` command in `data/user-migration-commands.nix`)
# has a row here or is in `predates`; `checks.user-migrations-ledger` (tests/user-migrations-ledger.nix)
# compares this file with the pinned source, and a bump adds a row for each new hit it names.
# See pkgs/AGENTS.md#user-file-migrations-1610.
{
  "1786719479" = {
    decision = "ported";
    run = "edited";
    reason = "replace the Gemini default, remove its old wrapper, and link agent skills (#1681)";
  };
  "1786967403" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1787215824" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1787342993" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1787481315" = {
    decision = "ported";
    run = "port";
    reason = "re-stage a repository-installed theme once, so staged code from an older install is dropped (#1705)";
  };
  "1787573629" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1787679775" = {
    decision = "ported";
    run = "upstream";
    reason = "remove saved layouts for named workspaces and reload Hyprland (#1673)";
  };
  "1788129995" = {
    decision = "ported";
    run = "edited";
    reason = "replace old Satty and Tensaku imv bindings with Omasnap and remove its stale launcher (#1671)";
  };
  "1788261467" = {
    decision = "not-needed";
    reason = "portal set by modules/nixos.nix, and config/ is seeded on activation by modules/home.nix";
  };
  "1788281348" = {
    decision = "ported";
    run = "upstream";
    reason = "refresh active themes with packaged intro videos (#1674)";
  };
  "1788595060" = {
    decision = "not-needed";
    reason = "modules/home.nix (nixarchyChromiumHosts) runs omarchy-install-chromium-copy-url and omarchy-install-chromium-ytdlp on every activation (#1491), and Brave Origin is unavailable here (data/apps.nix, #1676)";
  };
  "1788941927" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1789310715" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1789764927" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };
  "1790042972" = {
    decision = "ported";
    run = "bar";
    reason = "ported in omarchy-migrate-user (#1610)";
  };
  "1790457067" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1790528634" = {
    decision = "not-needed";
    reason = "no seed ever had omacom.elsewhen";
  };
  "1790539857" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };
  "1790542069" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };
  "1790702606" = {
    decision = "not-needed";
    reason = "modules/home.nix runs nixarchy-skills-relink (pkgs/skills-relink.nix) on every activation (#888), and 1786719479 already links agent skills (#1681)";
  };
  "1790863209" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1790973240" = {
    decision = "not-needed";
    reason = "gated on ASUS ProArt P14 NVIDIA N1x ARM hardware and omarchy-pkg-add; this port targets x86_64-linux and speaker tuning is patched in pkgs/omarchy/default.nix";
  };
  "1791123731" = {
    decision = "declined";
    reason = "a commented example in looknfeel.lua; no visible break (#1674)";
  };
  "1791345484" = {
    decision = "not-needed";
    reason = "handled in the package and runtimeDeps; see pkgs/AGENTS.md (Disktree)";
  };
  "1791376887" = {
    decision = "ported";
    run = "upstream";
    reason = "enable overlay scrollbars in existing Chromium-family flags files (#1676)";
  };
  "1791382872" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1791470456" = {
    decision = "ported";
    run = "upstream";
    reason = "repair saved JPG backgrounds after bundled images moved to WebP (#1674)";
  };
  "1791479273" = {
    decision = "ported";
    run = "port";
    reason = "switch an unused Superwhisper default to installed Voxtype (#1677)";
  };
  "1791640449" = {
    decision = "declined";
    reason = "a v4.0.x seed keeps the keyboard-layout widget in the centre, where it still works; newer seeds already put it on the right, and omarchy-migrate-user ports only the three bar moves #1610 names (#1763)";
  };
  "1791676907" = {
    decision = "ported";
    run = "upstream";
    reason = "restore Shift for an empty Fcitx alternate trigger list (#1677)";
  };
  "1791696584" = {
    decision = "ported";
    run = "upstream";
    reason = "add window classes to standard web app launchers (#1675)";
  };
  "1791698594" = {
    decision = "ported";
    run = "upstream";
    reason = "convert saved workspace layout rules to modes (#1673)";
  };
  "1791705142" = {
    decision = "ported";
    run = "upstream";
    reason = "move the saved animation opacity rule to the opaque toggle (#1674)";
  };
  "1791708587" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };
  "1791722809" = {
    decision = "ported";
    run = "upstream";
    reason = "make the old black Herdr tab bar transparent while retaining a black dim surface (#1678)";
  };
  "1791723398" = {
    decision = "ported";
    run = "edited";
    reason = "add Omarchy 4.5 transparency files only to configs with an unmodified Omarchy transparency file, unless Neovim is off (#1672)";
  };
  "1791769486" = {
    decision = "not-needed";
    reason = "no nixarchy release shipped the USB approval units";
  };
  "1791875754" = {
    decision = "ported";
    run = "upstream";
    reason = "add window classes to custom command web app launchers (#1675)";
  };
  "1791968925" = {
    decision = "partial";
    run = "bar";
    reason = "order ported in omarchy-migrate-user; duplicate trays kept (no IPC delete; no seed had two)";
  };
  "1791969355" = {
    decision = "ported";
    run = "bar";
    reason = "ported in omarchy-migrate-user (#1610)";
  };
  "1792020559" = {
    decision = "not-needed";
    reason = "omarchy-theme-set runs omarchy-theme-set-fcitx5 on theme switches, and modules/home.nix repairs existing fcitx5 themes via post-boot.d/fcitx5-glyphs (#1624, #1688)";
  };
  "1792202836" = {
    decision = "not-needed";
    reason = "omarchy-install-video-decode is gated on omarchy-hw-aarch64-qualcomm (Snapdragon aarch64), which this port does not target";
  };
  "1792259038" = {
    decision = "ported";
    run = "upstream";
    reason = "repair saved selections of renumbered bundled backgrounds (#1674)";
  };
  "1792343099" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-default-tools refuses (#1625)";
  };
  "1792343225" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
  };
  "1792345511" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };
  "1792474908" = {
    decision = "declined";
    reason = "Brave Origin is unavailable on nixarchy (data/apps.nix) (#1676)";
  };
  "1792504295" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-default-tools refuses (#1625)";
  };
  "1792648436" = {
    decision = "ported";
    run = "upstream";
    reason = "removes 4.0 notification files and carries Do Not Disturb into quiet state (#1680)";
  };
  "1792902457" = {
    edge = "only";
    decision = "ported";
    run = "edited";
    reason = "points Qt at qtengine; nixpkgs provides the qtengine package (#1736)";
  };
  "1793179949" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "keeps a user's own touchpad gestures by turning Omarchy's new defaults off in hyprland.lua; grep and sed only, runs as shipped (quattro, #1696)";
  };
  "1793301931" = {
    edge = "only";
    decision = "not-needed";
    reason = "gated on omarchy-hw-aarch64-qualcomm (Snapdragon aarch64) and omarchy-pkg-add, which this port does not target";
  };
  "1793315076" = {
    decision = "not-needed";
    reason = "Apple Silicon ~/.bashrc; bash setup comes from /etc/bashrc (modules/nixos.nix)";
  };
  "1793477875" = {
    decision = "ported";
    run = "upstream";
    reason = "retain existing dictation keys and move Superwhisper off Alt+Space (#1677)";
  };
  "1793461630" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "moves the monitor workspace blocks and scaling log under ~/.local/state/omarchy/monitors; mv and cat only, runs as shipped (quattro, #1696)";
  };
  "1793467369" = {
    edge = "only";
    decision = "declined";
    reason = "default/hypr/monitors.lua and default/hypr/toggles.lua already apply the monitor defaults and panel settings, while omarchy-hyprland-monitor-config-upgrade writes through readlink -f and leaves a .bak file beside monitors.lua (#1304)";
  };
  "1793565796" = {
    decision = "ported";
    run = "upstream";
    reason = "set OpenCode 2 system theme without replacing a chosen theme (#1679)";
  };
  "1793667581" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };

  # In v4.0.6 already; every nixarchy seed carries its effect.
  "1787481314" = {
    edge = "only";
    decision = "not-needed";
    reason = "the package bundles Osaka Jade, so $OMARCHY_PATH/themes/osaka-jade/colors.toml exists and the migration exits 0 before it clones or switches (#1698)";
  };
  "1793650506" = {
    edge = "only";
    decision = "not-needed";
    reason = "Snapdragon OEM firmware through pacman, sudo and mkinitcpio; aarch64 Qualcomm only, which this port does not target";
  };
  "1794068501" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "reseeds the Herdr desktop app's keybindings through omarchy-refresh-herdr-app, only when ~/.config/herdr-app exists (quattro, #1696)";
  };
  "1794165002" = {
    edge = "only";
    decision = "ported";
    run = "edited";
    reason = "switches the PDF default from Evince to Papers; nixpkgs provides papers, and the rewrite leaves a symlinked mimeapps.list alone (#1736)";
  };
  "1794210626" = {
    edge = "only";
    decision = "not-needed";
    reason = "modules/home.nix (nixarchyChromiumHosts) runs omarchy-install-chromium-copy-url and omarchy-install-chromium-ytdlp on every activation (#1491), and Chrome policy is managed in modules/nixos.nix";
  };
  "1794330979" = {
    edge = "only";
    decision = "partial";
    run = "edited";
    reason = "points a Nautilus handler at Files and leaves a symlinked mimeapps.list alone; the dock pin is not moved, because shell.json is written only through the shell (#847, #1750)";
  };
  "1794341736" = {
    edge = "only";
    decision = "ported";
    run = "edited";
    reason = "keeps Neovim for an existing home without a saved editor; a symlinked mimeapps.list is left alone (#1750)";
  };
  "1794344676" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "links the shared AGENTS.md into added Grok accounts; omarchy-agent-account-state link creates a link only where nothing exists (#1760)";
  };
  "1794387387" = {
    decision = "ported";
    run = "edited";
    edge = "only";
    reason = "rebinds the exact legacy Super + Ctrl + X dictation line 1793477875 wrote so the agents panel keeps the key; a store-owned bindings.lua is left alone (#1760)";
  };
  "1794390043" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "points text types at the editor handler unless the user chose an app; a Home Manager mimeapps.list is left alone, and NixOS's /etc/xdg list counts as a choice (#1760)";
  };
  "1794397144" = {
    decision = "partial";
    run = "port";
    edge = "only";
    reason = "the GTK and Qt settings that named Yaru move to Adwaita; there is no pacman and the store is read-only, so the package removal and the /usr/share/icons/Yaru cleanup do not apply (#1760)";
  };
  "1794484010" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "redraws Omarchy's app icons in the current theme through omarchy-theme-refresh; activation themes only a first run, so an existing home would wait for its next theme switch (#1776)";
  };
  "1794495065" = {
    edge = "only";
    decision = "not-needed";
    reason = "the package installs omarchy-terminal.desktop and omarchy-browser.desktop into share/applications (pkgs/omarchy/default.nix), and a copy in ~/.local/share/applications would shadow every later package version (#1776)";
  };
  "1794642577" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "edge shipped Slack theme sync, whose slack.desktop override in ~/.local/share/applications runs omarchy-launch-slack, which quattro 74de104 removes; this puts Slack's own launcher back (#1782)";
  };
  "1794644424" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "moves the user's themed/icons/*.svg.tpl to icons/papercraft/ with mv -n and redraws; reads the read-only tree only (#1793)";
  };
  "1794741886" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "runs omarchy-install-browser-extensions chrome; the policy itself is environment.etc's and already names the new ids, so here it refreshes the native-messaging hosts under ~/.config (#1793)";
  };
  "1794763180" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "installs omarchy-agent-<provider>.desktop from $OMARCHY_PATH/default/applications for signed-in agents (#1793)";
  };
  "1794774234" = {
    decision = "partial";
    run = "edited";
    edge = "only";
    reason = "deletes stock imv/mpv launchers by checksum as upstream does; omarchy-pkg-add omaview and omarchy-pkg-drop imv mpv-mpris are the runtime list's job (#1793)";
  };
  "1794775358" = {
    decision = "ported";
    run = "upstream";
    edge = "only";
    reason = "adds FileChooser=folio;gtk to the user's hyprland-portals.conf only where no chooser is chosen (#1793)";
  };
  "1794839007" = {
    edge = "only";
    decision = "ported";
    run = "edited";
    reason = "runs omarchy-agent-local-launchers once, so local models set up before launchers existed get theirs in ~/.local/share/applications; edited to skip a machine without omarchy-local-ai, which is opt-in here (services.agent-local) where Arch ships it everywhere: the launchers script exits 1 without it, and a failed migration stops every later one (#1847)";
  };
  "1794931275" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "gives each agent harness already installed its own launcher in ~/.local/share/applications through omarchy-agent-launcher, then redraws the icon set; it asks omarchy-default-agent --installed, which nixarchy's replacement answers by its exit status as upstream's does (#1847)";
  };
  "1794938310" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "appends `[update] version_check = false` to ~/.config/herdr/config.toml when the file exists, is not a symlink at any level and has no [update] table. It holds here: nixpkgs' herdr 0.9.5 leaves the check on, recognises a /nix/store binary and tells the user to \"update through Nix\", a notice they cannot act on outside a rebuild. Its python3 (tomllib) is in Omarchy's runtimeDeps, on the session PATH the migration hook keeps";
  };
  predates = [
    "1780057136"
    "1780294774"
    "1780517689"
    "1780739888"
    "1781043107"
    "1781063758"
    "1781158082"
    "1781485962"
    "1781587663"
    "1782049344"
    "1784401744"
    "1784479832"
    "1784508556"
    "1784510887"
    "1784763917"
    "1784767406"
    "1784909971"
    "1784960000"
    "1784989000"
    "1785002349"
    "1785095882"
    "1785101000"
    "1785166747"
    "1785167800"
    "1785189600"
    "1785344985"
    "1785543725"
    "1785591762"
    "1785608166"
    "1785617047"
    "1785633225"
    "1785846769"
    "1786098807"
    "1786099804"
    "1786181929"
    "1786183928"
    "1786273938"
    "1786278735"
    "1786279107"
    "1786451567"
    "1786517850"
    "1786539345"
    "1786549201"
    "1786643346"
    "1786782461"
    "1787580187"
    "1787618700"
    "1787843905"
    "1788025225"
    "1788102906"
    "1788124236"
    "1788577553"
    "1788619462"
    "1788724825"
    "1788745941"
    "1788848726"
    "1788996284"
    "1789095456"
    "1789130779"
    "1790017600"
    "1790114905"
    "1790397381"
    "1791934674"
    "1791935188"
    "1792334754"
  ];
  "1794988405" = {
    edge = "only";
    decision = "not-needed";
    reason = "runs omarchy-agent-skills-link once; modules/home.nix runs nixarchy-skills-relink (pkgs/skills-relink.nix) on every activation (#888), which links every shipped skill into .agents, .claude, .pi and, where they exist, Gemini and Hermes (#1847)";
  };
  "1795023056" = {
    edge = "only";
    decision = "not-needed";
    reason = "installs Fantasi with omarchy-pkg-add, which is the package list's job here, and Fantasi is not packaged (#1847)";
  };
  "1795080474" = {
    edge = "only";
    decision = "not-needed";
    reason = "copies Game Vibes.desktop into ~/.local/share/applications for existing installs; this port installs it system-wide as omarchy-Game Vibes.desktop, so a copy would list Game Vibes twice (#1847)";
  };
  "1795093910" = {
    edge = "only";
    decision = "not-needed";
    reason = "runs omarchy-agent-skills-link for the renamed omarchy-make-* skills; nixarchy-skills-relink on every activation links the new names and removes links into a store skills tree that is gone (#888, #1847)";
  };
  "1795099916" = {
    edge = "only";
    decision = "not-needed";
    reason = "gated on omarchy-hw-aarch64-qualcomm (Snapdragon aarch64), which this port does not target";
  };
  "1795113315" = {
    edge = "only";
    decision = "not-needed";
    reason = "restages the current theme when its packaged background loops exist; omarchy-themes-loops is not packaged here (data/omarchy-packages.nix), so the loops directory it tests for never exists (#1896)";
  };
  "1795181196" = {
    edge = "only";
    decision = "not-needed";
    reason = "runs omarchy-agent-skills-link for the omarchy-diagnose-crash rename; nixarchy-skills-relink on every activation links the new name and removes links into a store skills tree that is gone (#888, #1896)";
  };
  "1795191169" = {
    edge = "only";
    decision = "not-needed";
    reason = "installs Flowtunes with omarchy-pkg-add, which is the package list's job here, and Flowtunes is not packaged (#1896)";
  };
  "1795200237" = {
    edge = "only";
    decision = "ported";
    run = "bar";
    reason = "inserts omarchy.local-models before each omarchy.agents entry through shell IPC, only when agents are present and local models are absent (#1975)";
  };
  "1795263097" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "marks the first-update setup task done under ~/.local/state/omarchy/done/, so the bar's update icon watches Omarchy only; a marker is harmless on a machine whose updates are rebuilds (#1896)";
  };
  "1795277141" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "runs omarchy-models-launchers to take away the launchers of image, video and music models, which Fantasi now lists itself, leaving the coding models' alone. Upstream already skips a machine without omarchy-local-ai, which is opt-in here (services.agent-local), so it holds unedited (#1896)";
  };
  "1795318856" = {
    edge = "only";
    decision = "not-needed";
    reason = "moves Pi from a mise tool to the pi-coding-agent package; there is no mise here, and Pi comes from nixpkgs through omarchy-default-agent or services.agent-local (#1896)";
  };
  "1795372675" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "reruns omarchy-agent-pi-defaults, as 1795294173 does, to leave the loaded-resource listing out of Pi's startup; it does nothing until the user installs Pi (#1896)";
  };
  "1795380483" = {
    edge = "only";
    decision = "ported";
    run = "bar";
    reason = "removes every omarchy.local-models bar entry through shell IPC after local models moved into the agents panel, leaving the local models service enabled (#1975)";
  };
  "1795376239" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "turns Pi's quietStartup \"header\" into true with jq, only when the earlier Pi migration set it; a value the user chose stays, and with no Pi settings file it does nothing (#1896)";
  };
  "1795294173" = {
    edge = "only";
    decision = "ported";
    run = "upstream";
    reason = "runs omarchy-agent-pi-defaults to link Omarchy's Pi extensions and condense Pi's changelog. It holds unedited: the link points into the Omarchy tree and is moved to the current one at the next run, and it does nothing until the user installs Pi (#1896)";
  };
  "1795441383" = {
    edge = "only";
    decision = "not-needed";
    reason = "moves Arch's bundled mise tools to packages and removes retired agent defaults and launchers; Nixarchy has its own package and agent routes, so existing user selections stay";
  };
  "1795613633" = {
    edge = "only";
    decision = "declined";
    reason = "auto-enables Dell XPS 16 speaker tuning after an Arch package install; Nixarchy supports user-installed LSP limiter tuning and keeps activation opt-in";
  };
  "1795692660" = {
    edge = "only";
    decision = "declined";
    reason = "clock catch-up expects /usr/lib/systemd/user units and may link them into user config; Nixarchy would need declarative user units";
  };
  "1795697268" = {
    edge = "only";
    decision = "declined";
    reason = "auto-enables Flower Sakura speaker tuning after an Arch package install; Nixarchy supports user-installed LSP limiter tuning and keeps activation opt-in";
  };
  "1795704234" = {
    edge = "only";
    decision = "not-needed";
    reason = "ASUS speaker tuning refresh targets Qualcomm ARM hardware, while this port targets x86_64-linux";
  };
  "1795705800" = {
    edge = "only";
    decision = "not-needed";
    reason = "Anduril camera migration depends on the Arch anduril-bluechip-support package and its legacy units";
  };
  "1795709363" = {
    edge = "only";
    decision = "declined";
    reason = "installs Shure's hidraw udev rule with sudo into /etc/udev/rules.d, which NixOS generates, then puts omarchy.mv7plus on the bar. Nixarchy ships no such rule, so an existing bar is left as it is; an owner of the mic adds default/udev/shure-mv7plus.rules through services.udev.packages (before 73-seat-late) and runs `omarchy bar put omarchy.mv7plus`";
  };
  "1795743653" = {
    edge = "only";
    decision = "not-needed";
    reason = "repairs Git credential helpers after Omarchy retired its mise-provided gh. Nixarchy never provided that shim; it leaves any user-managed Git credential configuration alone (#1985)";
  };
  "1795777042" = {
    edge = "only";
    decision = "declined";
    reason = "unconditionally removes imv.desktop, including a customized file or a Home Manager link. The checksum-based 1794774234 already removes stock copies while preserving user-owned launchers (#1985)";
  };
  "1795778751" = {
    edge = "only";
    decision = "declined";
    reason = "rewrites Chromium-family flags files through symlinks and overrides browser settings the user may manage declaratively (#1985)";
  };
  "1795791370" = {
    edge = "only";
    decision = "not-needed";
    reason = "reorders Arch's mise shims by editing its PAM environment file. Nixarchy has no managed mise shims, and NixOS owns the SSH PAM configuration (#1985)";
  };
  "1795799308" = {
    edge = "only";
    decision = "declined";
    reason = "translates udiskie keyfile rules into persistent automatic-unlock links. It assumes Arch's /usr/bin/python3 and package installation, and the new automounter cannot preserve all udiskie device rules. Leave existing configuration and keyfiles in place (#1985)";
  };
}
