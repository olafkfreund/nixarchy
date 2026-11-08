# Every Omarchy migration that touches a user's files (`grep -lE 'HOME|XDG_CONFIG|\.config|shell\.json' migrations/*.sh`)
# has a row here or is in `predates`; `checks.user-migrations-ledger` (tests/user-migrations-ledger.nix)
# compares this file with the pinned source, and a bump adds a row for each new hit it names.
# See pkgs/AGENTS.md#user-file-migrations-1610.
{
  "1786719479" = {
    decision = "declined";
    reason = "real user-file edit that may apply; needs its own fixture first (#1610 follow-up)";
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
    decision = "declined";
    reason = "real user-file edit that may apply; needs its own fixture first (#1610 follow-up)";
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
  "1790863209" = {
    decision = "not-needed";
    reason = "no mise here; omarchy-mise-install refuses (#1625)";
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
    decision = "declined";
    reason = "real user-file edit that may apply; needs its own fixture first (#1610 follow-up)";
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
  "1792259038" = {
    decision = "ported";
    run = "upstream";
    reason = "repair saved selections of renumbered bundled backgrounds (#1674)";
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
  "1792648436" = {
    decision = "declined";
    reason = "real user-file edit that may apply; needs its own fixture first (#1610 follow-up)";
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
  "1793565796" = {
    decision = "declined";
    reason = "real user-file edit that may apply; needs its own fixture first (#1610 follow-up)";
  };
  "1793667581" = {
    decision = "not-needed";
    reason = "gated on omarchy-pkg-*, pacman or /var/lib; apps and system state come from the flake";
  };

  # In v4.0.6 already; every nixarchy seed carries its effect.
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
    "1784767406"
    "1784909971"
    "1784989000"
    "1785002349"
    "1785095882"
    "1785167800"
    "1785189600"
    "1785344985"
    "1785543725"
    "1785591762"
    "1785608166"
    "1785617047"
    "1785633225"
    "1785846769"
    "1786099804"
    "1786181929"
    "1786273938"
    "1786451567"
    "1786517850"
    "1786539345"
    "1786643346"
    "1786782461"
    "1787481315"
    "1787580187"
    "1787618700"
    "1787843905"
    "1788102906"
    "1788124236"
    "1788577553"
    "1788724825"
    "1788745941"
    "1788848726"
    "1788996284"
    "1789095456"
    "1789130779"
    "1790114905"
    "1791934674"
    "1791935188"
  ];
}
