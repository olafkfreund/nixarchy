# Every command this port does not ship exactly as Omarchy wrote it.
#
# nixarchy vendors upstream's whole `bin/` tree -- 431 commands at v4.0.2 --
# and ships 440. Until this file existed, nothing said which of them the port
# has its hands on: an Omarchy release could add, rename or absorb a command
# and the only thing that noticed was a human reading a diff.
#
# THE RULE THAT MAKES THIS FILE HONEST: a vendored command does NOT get a row.
# 384 of the 431 are byte-identical to upstream below the shebang -- patchShebangs
# rewrites line 1 of every script and nothing else differs -- and writing rows
# for those would restate what `cmp` already proves. That is the failure
# .github/scripts/omarchy-patched-files.sh names out loud: a hand list that
# agrees with itself proves nothing.
#
# So .github/scripts/check-bin-ledger.py DERIVES the class by comparing the
# built package against the upstream source, and fails in both directions:
# a command that diverges without a row, and a row for a command that does not.
# What it cannot derive is the REASON, which is the whole point of a row.
#
# class, derived and then checked against what is written here:
#
#   patch    substituteInPlace or sed in pkgs/omarchy/default.nix
#   replace  a whole file from pkgs/omarchy/nix-bin/
#   new      a command upstream does not have, marked `# nixarchy:new`
#   vendor   identical to upstream -- legal ONLY with a `pacman` field, below
#
# fields:
#
#   reason   required, one line, why this port diverges. "FIXME" is refused.
#   pacman   why an Arch-only package path is carried and unreachable here.
#            This subsumes the allowlist that used to live in build.yml: every
#            shipped bin is scanned, and the check fails BOTH ways -- a bin that
#            calls pacman with no field, and a field whose bin went clean.
#   stub     the command refuses on NixOS rather than doing its job. Verified
#            for nix-bin files, which carry a `# nixarchy:stub` marker; on patch
#            rows it is annotation, and the check says so rather than pretending.
#   standIn  what to run instead, when there is one.
#
# Adding a row is a deliberate act with a diff and a reviewer. That is the
# difference from a list that can only fail to grow.

{

  # ── Patched in place -- substituteInPlace or sed in pkgs/omarchy/default.nix ──

  "omarchy-agent" = {
    class = "patch";
    reason = ''
      patched twice: mise activates from the shell rc, and the menu
      launches an agent through `bash -c` in a floating terminal that
      sources none -- so an agent mise had installed perfectly was
      reported as not installed
    '';
  };
  "omarchy-agent-crash" = {
    class = "patch";
    reason = "The prompt sets the destination before the skill is read";
  };
  "omarchy-audio-tuning" = {
    class = "patch";
    reason = ''
      the speaker-tuning limiter was never found: it tests for the LSP
      plugin at a fixed path under /usr/lib/lv2, and NixOS keeps LV2
      plugins in the store
    '';
  };
  "omarchy-clipboard-open" = {
    class = "patch";
    reason = ''
      The two image-editor call sites that hardcode tensaku-edit, which is
      not packaged anywhere here -- see the satty-edit wrapper in the
      runtime dependencies above for why a wrapper and not satty itself
    '';
  };
  "omarchy-default-browser" = {
    class = "patch";
    reason = ''
      The same chromium-browser.desktop rename as omarchy-launch-webapp,
      on the three other paths that name the file rather than launch it
    '';
  };
  "omarchy-games-retro-install" = {
    class = "patch";
    reason = "RetroArch loads its cores from /usr/lib/libretro upstream";
  };
  "omarchy-hw-vulkan" = {
    class = "patch";
    reason = ''
      Vulkan was never detected -- the probe looks for an ICD at an Arch
      path
    '';
  };
  "omarchy-install-gaming-retroarch" = {
    class = "patch";
    reason = "RetroArch loads its cores from /usr/lib/libretro upstream";
  };
  "omarchy-install-service-1password" = {
    class = "patch";
    reason = ''
      1Password'"'"'s Chromium extension, installed the way NixOS installs
      one
    '';
  };
  "omarchy-launch-browser" = {
    class = "patch";
    reason = ''
      omarchy-launch-webapp and omarchy-launch-browser find the browser by
      reading its .desktop out of {~/.local,~/.nix-profile,/usr}/share/
      applications
    '';
  };
  "omarchy-launch-signal" = {
    class = "patch";
    reason = ''
      tested for /usr/bin/signal-desktop, so a user with the app enabled
      clicked Signal and was offered a terminal to install it -- `command
      -v` instead, because the app comes from their own configuration
    '';
  };
  "omarchy-launch-spotify" = {
    class = "patch";
    reason = ''
      tested for /usr/bin/spotify, so a user with the app enabled clicked
      Spotify and was offered a terminal to install it -- `command -v`
      instead, because the app comes from their own configuration
    '';
  };
  "omarchy-launch-webapp" = {
    class = "patch";
    reason = ''
      Both launchers accept a handful of browser desktop-file names and
      fall back to "chromium.desktop" for anything else
    '';
  };
  "omarchy-plugin-clone" = {
    class = "patch";
    reason = ''
      `cp -aL` preserves mode, so the staging directory landed read-only
      in the store and the clone could not remove its own temp files; the
      plugin never appeared in the list
    '';
  };
  "omarchy-provision-user" = {
    class = "patch";
    reason = ''
      The one place a shipped entry is named rather than merely launched
    '';
  };
  "omarchy-refresh-applications" = {
    class = "patch";
    reason = ''
      The third site of the same store-mode problem, and the expensive one
    '';
  };
  "omarchy-remove-browser" = {
    class = "patch";
    reason = ''
      The same chromium-browser.desktop rename as omarchy-launch-webapp,
      on the three other paths that name the file rather than launch it
    '';
  };
  "omarchy-remove-launcher-entry" = {
    class = "patch";
    reason = "The App Library's Remove, for an app that came from the store";
    pacman = "the menu row modules/apps.nix overrides away";
  };
  "omarchy-remove-security-fido2" = {
    class = "patch";
    reason = ''
      the dangerous half: its guard `grep -q pam_u2f.so /etc/pam.d/sudo`
      is TRUE on a machine that enabled u2fAuth the NixOS way, so Remove
      FIDO2 detached the PAM stack of a user who never ran Setup
    '';
  };
  "omarchy-remove-security-fingerprint" = {
    class = "patch";
    reason = "same guard, same unasked detach of a NixOS-managed PAM stack";
  };
  "omarchy-setup-security-fido2" = {
    class = "patch";
    reason = ''
      its PAM function is deleted and the call site says so: nothing may
      sed /etc/pam.d on NixOS, where those files are symlinks into the
      store
    '';
  };
  "omarchy-setup-security-fingerprint" = {
    class = "patch";
    reason = ''
      same as setup-security-fido2 -- registration works, and the last
      step, editing the PAM stack, is the one that cannot be done from a
      running system
    '';
    pacman = "the menu row modules/apps.nix overrides away";
  };
  "omarchy-theme-set" = {
    class = "patch";
    reason = ''
      $OMARCHY_THEMES_PATH is a store path, and `cp -r` preserves its
      modes -- including r-xr-xr-x on directories
    '';
  };
  "omarchy-theme-set-browser-policy" = {
    class = "patch";
    reason = ''
      the theme accent stopped reaching the browser in 4.0.2, and the
      sudo/pkexec escalation it used to write the policy has nowhere to
      write on NixOS
    '';
  };
  "omarchy-update-restart" = {
    class = "patch";
    reason = ''
      "Restart to finish the update" was going to be the answer every time
    '';
  };
  "omarchy-version" = {
    class = "patch";
    reason = ''
      `omarchy version` said "dev": it reads a version file the Arch
      package installs and this port does not
    '';
    pacman = ''
      our own nix-bin file; the pacman lines are heredoc prose or dead
      upstream code after an early exit, which comment-stripping cannot
      see
    '';
  };
  "omarchy-version-channel" = {
    class = "patch";
    reason = ''
      the channel line under the version said "unknown", read from the
      same Arch-only file
    '';
    pacman = ''
      our own nix-bin file; the pacman lines are heredoc prose or dead
      upstream code after an early exit, which comment-stripping cannot
      see
    '';
  };

  # ── Replaced wholesale by a file in pkgs/omarchy/nix-bin/ ─────────────────────

  "omarchy-default-agent" = {
    class = "replace";
    reason = ''
      replaced wholesale: set and launch the default coding agent
      (declaratively, on nixos)
    '';
  };
  "omarchy-games-retro-cores" = {
    class = "replace";
    reason = "replaced wholesale: list installed retroarch core names";
  };
  "omarchy-install-font" = {
    class = "replace";
    reason = ''
      replaced wholesale: switch to a nerd font, installing it
      declaratively if needed
    '';
  };
  "omarchy-migrate" = {
    class = "replace";
    reason = "replaced wholesale: run pending omarchy migrations";
    pacman = ''
      our own nix-bin file; the pacman lines are heredoc prose or dead
      upstream code after an early exit, which comment-stripping cannot
      see
    '';
  };
  "omarchy-pkg-add" = {
    class = "replace";
    reason = ''
      replaced wholesale: install the named packages (declaratively, on
      nixos)
    '';
  };
  "omarchy-pkg-aur-add" = {
    class = "replace";
    reason = "replaced wholesale: the aur has no equivalent here";
  };
  "omarchy-pkg-aur-install" = {
    class = "replace";
    reason = "replaced wholesale: the aur has no equivalent here";
  };
  "omarchy-pkg-install" = {
    class = "replace";
    reason = ''
      replaced wholesale: show the declarative app list instead of a
      package picker
    '';
  };
  "omarchy-pkg-missing" = {
    class = "replace";
    reason = ''
      replaced wholesale: returns true if any of the named packages are
      missing from the system (or false if they're all there)
    '';
  };
  "omarchy-pkg-present" = {
    class = "replace";
    reason = ''
      replaced wholesale: returns true if all of the named packages are
      installed on the system (or false if any of them are missing)
    '';
  };
  "omarchy-plymouth-current" = {
    class = "replace";
    reason = "replaced wholesale: show the current plymouth theme";
  };
  "omarchy-plymouth-set" = {
    class = "replace";
    reason = "replaced wholesale: set the plymouth boot splash colours and logo";
  };
  "omarchy-refresh-plymouth" = {
    class = "replace";
    reason = "replaced wholesale: refresh the plymouth boot splash";
  };
  "omarchy-refresh-sddm" = {
    class = "replace";
    reason = "replaced wholesale: refresh the sddm login theme";
  };
  "omarchy-snapshot" = {
    class = "replace";
    reason = ''
      replaced wholesale: snapshot your home directory, or go back to one
    '';
  };
  "omarchy-sudo-passwordless" = {
    class = "replace";
    reason = ''
      replaced wholesale: passwordless sudo, which is a nixos option
      rather than a toggle
    '';
  };
  "omarchy-system-factory-reset" = {
    class = "replace";
    reason = ''
      replaced wholesale: factory-reset this machine back to its freshly-
      installed state
    '';
  };
  "omarchy-update" = {
    class = "replace";
    reason = "replaced wholesale: update omarchy and system packages";
  };
  "omarchy-update-available" = {
    class = "replace";
    reason = "replaced wholesale: check whether omarchy updates are available";
  };
  "omarchy-voxtype-config" = {
    class = "replace";
    reason = "replaced wholesale: configure dictation";
  };

  # ── This port's own commands, which upstream does not have ────────────────────

  "nixarchy-ask" = {
    class = "new";
    reason = ''
      Ask the default agent to do something about this machine, with the
      right skill already chosen
    '';
  };
  "nixarchy-config-repo" = {
    class = "new";
    reason = ''
      Put this machine's NixOS configuration in a git repository, with a
      remote and CI
    '';
  };
  "nixarchy-home-backup" = {
    class = "new";
    reason = ''
      Back up the desktop configuration in your home directory to a git
      repository, and restore it
    '';
  };
  "nixarchy-local-ai" = {
    class = "new";
    reason = "Set up the local language model, and check it is actually working";
  };
  "nixarchy-rollback" = {
    class = "new";
    reason = "Go back to an earlier system generation";
  };
  "nixarchy-unfreeze" = {
    class = "new";
    reason = "Let this machine receive updates again";
  };
  "nixarchy-version" = {
    class = "new";
    reason = ''
      Print the Omarchy version and the nixarchy revision this machine was
      built from
    '';
  };
  "omarchy-cursor-set" = {
    class = "new";
    reason = ''
      Point the cursor theme at the light or dark half of the current
      Omarchy theme
    '';
  };
  "omarchy-retroarch-cores" = {
    class = "new";
    reason = "Print the directory RetroArch loads libretro cores from";
  };

  # ── Carried exactly as upstream wrote them, and unreachable here ──────────────

  "omarchy-channel-current" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-channel-set" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-debug" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "reads pacman state for display only";
  };
  "omarchy-dev-pkg-test" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "dev tooling; reads pacman state for display only";
  };
  "omarchy-pkg-drop" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "the menu row modules/apps.nix overrides away";
  };
  "omarchy-pkg-remove" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "the menu row modules/apps.nix overrides away";
  };
  "omarchy-provision-owner" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "reads pacman state for display only";
  };
  "omarchy-refresh-pacman" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-reinstall-pkgs" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-remove-dev-env" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "the menu row modules/apps.nix overrides away";
  };
  "omarchy-update-aur-pkgs" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-update-keyring" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-update-orphan-pkgs" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-update-pacman-guard" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "its whole job is PRINTING advice about pacman";
  };
  "omarchy-update-system-pkgs" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-update-system-pkgs-when-conflicted" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-upgrade-to-quattro" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = ''
      update plumbing the UI never reaches: nix-bin replaces the entry
      points (omarchy-update, omarchy-update-available)
    '';
  };
  "omarchy-upload-log" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "reads pacman state for display only";
  };
  "omarchy-version-pkgs" = {
    class = "vendor";
    reason = "carried untouched; unreachable here";
    pacman = "reads pacman state for display only";
  };
}
