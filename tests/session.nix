{
  inputs,
  pkgs,
  # The doctor is a package, not part of the module, so the test has to be
  # handed it rather than finding it in the system profile.
  doctor,
}:
let
  # A real published Omarchy theme, pinned. `omarchy theme install` is the
  # sibling of `omarchy plugin add`: it clones a git URL at runtime, past the
  # same omarchy-git-url-check, into ~/.config/omarchy -- so it depends on the
  # same thing being writable, and nothing covered it.
  lumonTheme = pkgs.fetchgit {
    url = "https://github.com/OldJobobo/omarchy-lumon-theme.git";
    rev = "553638f04efc12f4439debd413eaf3ac838a1f9a";
    hash = "sha256-DkuuYlxYYh4hZrL+2dUVnrlxfP3uXsbuIJWRVaZcmGk=";
  };
in
# Drives a real Omarchy session and reports what it logged.
#
# This exists because the failure that matters -- "the panel shows for a few
# seconds then dies" -- leaves its reason in a *user* journal that nobody can
# reach without logging in, and the session that would let you log in is the
# broken thing. Reading it over a serial console does not work either: once a
# GPU device is present the kernel moves its console to tty0 and the serial
# log ends at the login prompt.
#
# No GPU is needed. Hyprland always registers the headless aquamarine backend
# as MANDATORY and only adds DRM if available (src/Compositor.cpp), so the
# compositor comes up on a machine with no display hardware whatsoever.
pkgs.testers.runNixOSTest {
  name = "nixarchy-session";

  nodes.machine = {
    imports = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
    ];

    programs = {
      # zsh and fish alongside bash. Upstream ships a bash rc chain only, so
      # without these two the other halves are untested by construction -- and
      # they are the shells people who already have a NixOS config tend to be
      # running.
      zsh.enable = true;
      fish.enable = true;

      nixarchy = {
        enable = true;
        # Off by default; on here so the accent path is actually exercised.
        # Without it omarchy-theme-set-browser skips every policy directory
        # and the accent silently never applies -- which is what shipped.
        browserThemeUser = "omarchy";
        # Somewhere real for nixarchy-apply to copy the selection into. The VM
        # in vm/configuration.nix builds a full flake there; this test only
        # needs the copy to have a destination.
        flake = "/etc/nixos";
      };
    };

    # Log in the way a user actually does: through SDDM's greeter. An earlier
    # version autologged in on tty1 and launched Hyprland from the login
    # shell, which exercised the compositor but skipped the greeter entirely
    # -- so SDDM being enabled by this module was never tested at all, and
    # neither was the session file it launches.
    #
    # (Running Hyprland under `su` was tried before that and is worse: no
    # logind session means no seat, and aquamarine dies with
    # `CBackend::create() failed!`. SDDM gives a genuine seat.)

    # plymouth-quit-wait never finishes without a display and blocks the boot.
    boot.plymouth.enable = pkgs.lib.mkForce false;

    # No GPU in the VM, and Hyprland refuses a software renderer unless told.
    # This has to be system-wide now: SDDM starts the session, not a login
    # shell this test controls.
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";

    # No extra GPU device. qemu-vm already gives the machine a display, and
    # machine.screenshot() dumps *that* one -- adding a second sent Hyprland
    # to the new device while the screenshot kept reading the original, which
    # came back pure black and made the wallpaper check fail on a machine
    # whose desktop was fine.

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
      users.omarchy = {
        programs.nixarchy.enable = true;
        home.stateVersion = "25.05";
      };
    };

    users.users.omarchy = {
      isNormalUser = true;
      uid = 1000;
      password = "omarchy";
      extraGroups = [
        "wheel"
        "video"
        "input"
      ];
    };

    virtualisation = {
      memorySize = 6144;
      cores = 4;
    };

    # An app the user already has, installed the way a user would -- their own
    # systemPackages, nothing to do with the app selection. This is the exact
    # case the Install menu could not see: vim is in data/apps.nix, is not
    # selected here, and is on PATH. Its row must draw dim rather than offering
    # to install what is already there.
    environment.systemPackages = [ pkgs.vim ];

    system.activationScripts.testFlakeDir = ''
      mkdir -p /etc/nixos
      chmod 0777 /etc/nixos
    '';

    # The theme's own files turned back into a repository to clone from, the
    # same way tests/plugin.nix serves its plugins: fetchgit hands over a plain
    # directory with no .git, and a test machine has no network.
    system.activationScripts.themeRepo = ''
      if [ ! -d /srv/lumon/.git ]; then
        mkdir -p /srv/lumon
        cp -r --no-preserve=mode,ownership ${lumonTheme}/. /srv/lumon/
        cd /srv/lumon
        export HOME=/root
        ${pkgs.git}/bin/git init -q -b main
        ${pkgs.git}/bin/git -c user.email=t@t -c user.name=t add -A
        ${pkgs.git}/bin/git -c user.email=t@t -c user.name=t commit -q -m lumon
      fi
      chmod -R a+rX /srv/lumon
    '';
  };

  # Reading the greeter means reading pixels: SDDM's Qt greeter puts nothing
  # on a console or in a file that says it is ready for a password.
  enableOCR = true;

  testScript = ''
    import os
    machine.wait_for_unit("multi-user.target")

    # ---- app selection -------------------------------------------------
    # Deliberately before anything graphical: Home Manager seeds apps.nix at
    # system activation, so none of this needs a session, and a slow login
    # must not be able to mask a broken selection loop.
    machine.wait_for_file("/home/omarchy/.config/nixarchy/apps.nix")
    machine.succeed("su omarchy -c 'nixarchy-app-enable brave'")
    machine.succeed("su omarchy -c 'nixarchy-app-enable helix'")
    enabled = machine.succeed(
        "grep -E '^[[:space:]]*[a-z0-9_-]+\\.enable' /home/omarchy/.config/nixarchy/apps.nix"
    )
    print(enabled)
    assert "brave.enable" in enabled, "brave was not enabled"
    assert "helix.enable" in enabled, "helix was not enabled"
    # A pick that leaves the file unparseable would break the next rebuild.
    machine.succeed("nix-instantiate --parse /home/omarchy/.config/nixarchy/apps.nix >/dev/null")

    # Picking the same app twice must be a no-op, not a second uncomment.
    machine.succeed("su omarchy -c 'nixarchy-app-enable brave'")
    machine.succeed("nix-instantiate --parse /home/omarchy/.config/nixarchy/apps.nix >/dev/null")

    # Answering "no" to the prompt asserts the copy, not a full rebuild.
    print(machine.succeed("su omarchy -c 'echo n | nixarchy-apply' 2>&1"))
    # Both halves of the layout, because either alone would pass while the
    # machine was broken: the selection has to arrive in nixarchy/apps.nix,
    # AND nixarchy-apps.nix has to import it. A copy nothing imports is the
    # exact failure the warning in nixarchy-apply exists for -- apps marked
    # enabled, a rebuild running to completion, and nothing installed.
    machine.succeed("grep -q 'brave.enable' /etc/nixos/nixarchy/apps.nix")
    machine.succeed("grep -q './nixarchy/apps.nix' /etc/nixos/nixarchy-apps.nix")
    print("selection reached /etc/nixos/nixarchy/apps.nix, and the stub imports it")

    # That the user's own configuration still imports nixarchy-apps.nix is
    # asserted in tests/install.nix, on an installed machine that has a
    # configuration.nix. This VM does not; its module comes from the flake.

    # ---- the greeter ---------------------------------------------------
    machine.wait_for_unit("display-manager.service")

    # OCR rather than a unit or a file: what is being asserted is that a human
    # is actually being offered a login, which only the pixels can say.
    # logind knows when the greeter has a seat; OCR does not, and matching on
    # greeter text raced -- wait_for_text returned on a frame the greeter was
    # still painting, the keystrokes went nowhere, and the login never
    # happened.
    machine.wait_until_succeeds("loginctl list-sessions | grep -q greeter")

    # A blank greeter would still accept the password and log in, so assert
    # something was actually drawn. This theme OCRs badly -- a few characters
    # is all that comes back -- so the check is "not blank", not the wording.
    #
    # Retried rather than slept at. Eight seconds was enough here and not on a
    # CI runner, where this failed with "the greeter drew nothing" on a greeter
    # that was merely slower to paint. A fixed wait is a guess about how fast
    # the machine is; the same guess was wrong in tests/coexist.nix for the
    # same reason. Retrying still fails if it never draws.
    drawn = ""
    for attempt in range(10):
        machine.sleep(4)
        machine.screenshot("greeter")
        drawn = machine.get_screen_text().strip()
        print(f"attempt {attempt}: greeter OCR {drawn!r}")
        if drawn:
            break

    assert drawn, (
        "the greeter never drew anything in 40s; a user would see a blank "
        "screen")

    # The only user is preselected and the password field has focus.
    machine.send_chars("omarchy\n")

    # The dialog accepting the password is the thing under test; the session
    # starting is the consequence.
    machine.wait_until_succeeds(
        "journalctl -b -u display-manager --no-pager"
        " | grep -q 'Authentication for user .*omarchy.* successful'")

    # ---- session -------------------------------------------------------
    # systemd-logind starts user@1000.service asynchronously once the session
    # opens, so there is a window where the unit is inactive with no job queued
    # yet. wait_for_unit treats exactly that as a hard failure -- it raises
    # "is inactive and there are no pending jobs" immediately rather than
    # waiting -- so on a loaded runner it fails a session that was about to come
    # up fine. Poll for "active" instead, which tolerates the window.
    machine.wait_until_succeeds("systemctl is-active user@1000.service")

    # Long enough for omarchy-launch-shell to exhaust its supervision budget:
    # it gives up after 5 relaunches inside one minute.
    machine.sleep(75)

    print("=========== hyprland ===========")
    print(machine.succeed("journalctl -b _UID=1000 -t Hyprland --no-pager || true"))

    print("=========== omarchy-shell ===========")
    print(machine.succeed("journalctl -b -t omarchy-shell --no-pager || true"))

    print("=========== user journal ===========")
    print(machine.succeed("journalctl -b _UID=1000 --no-pager | tail -100 || true"))

    print("=========== is the shell alive? ===========")
    print(machine.succeed("pgrep -a quickshell || echo 'NO QUICKSHELL PROCESS'"))

    # ---- power ----------------------------------------------------------
    # omarchy-powerprofiles-set autodetect reads this exact property, and it
    # reads it as `2>/dev/null` with a fallback: with no UPower the call fails
    # silently and every machine looks like it is on AC forever. So assert the
    # call succeeds, not that a unit is running -- UPower is DBus-activated,
    # so an activatable name is the whole contract.
    onbattery = machine.succeed(
        "busctl get-property org.freedesktop.UPower /org/freedesktop/UPower "
        "org.freedesktop.UPower OnBattery").strip()
    print(f"UPower OnBattery -> {onbattery}")
    assert onbattery.startswith("b "), (
        f"UPower did not answer on DBus (got {onbattery!r}); "
        "omarchy-powerprofiles-set autodetect would silently assume AC.")

    # The VM has no battery, so `false` is the correct answer here. This
    # asserts the channel works, not the value -- a real charge state can only
    # be checked on hardware.
    machine.succeed("powerprofilesctl get")

    # ---- theme reaches GTK ----------------------------------------------
    # The default theme is dark. Everything below is what carries that fact out
    # of Omarchy's own state and into apps it does not own, and every step of it
    # was silently broken: the schemas gsettings writes are installed but were
    # not on XDG_DATA_DIRS, so `gsettings set` was a no-op and a dark desktop
    # came up with light GTK apps and a light Chromium.
    #
    # Nothing is run by hand here on purpose -- login alone must be enough.
    user = ("su omarchy -c 'export XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; %s'")

    mode = machine.succeed(
        user % "omarchy-theme-color --file "
               "$HOME/.local/state/omarchy/current/theme/colors.toml mode").strip()
    assert mode == "dark", f"the default theme is not dark any more (got {mode!r})"

    machine.wait_until_succeeds(
        user % "gsettings get org.gnome.desktop.interface color-scheme"
               " | grep -q prefer-dark")

    scheme = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface color-scheme").strip()
    gtk = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface gtk-theme").strip()
    icons = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface icon-theme").strip()
    print(f"color-scheme {scheme} / gtk-theme {gtk} / icon-theme {icons}")

    # "No schemas installed" is what this returned before gsettings-desktop-schemas
    # was reachable, and gsettings exits 0 while saying it.
    assert "prefer-dark" in scheme, f"GTK was not told the theme is dark: {scheme}"

    # Adwaita-dark is not built into GTK 3; it comes from gnome-themes-extra.
    assert "Adwaita-dark" in gtk, f"gtk-theme is {gtk}"
    machine.succeed("test -d /run/current-system/sw/share/themes/Adwaita-dark")

    # Every theme names a Yaru variant, so the name must resolve to a real dir.
    theme_name = icons.strip("'")
    machine.succeed(f"test -d /run/current-system/sw/share/icons/{theme_name}")

    # What Chromium actually reads for BrowserColorScheme "device": 1 is
    # prefer-dark, and 0 -- "no preference" -- is what it read before, which
    # Chromium renders as light.
    portal = machine.succeed(
        user % ("busctl --user call org.freedesktop.portal.Desktop "
                "/org/freedesktop/portal/desktop org.freedesktop.portal.Settings "
                "ReadOne ss org.freedesktop.appearance color-scheme")).strip()
    print(f"portal color-scheme -> {portal}")
    assert portal == "v u 1", (
        f"the settings portal reports {portal!r}, not dark; Chromium and every "
        "other portal-reading app will come up light.")

    # ---- cursor and seeded configs --------------------------------------
    # Omarchy sets a cursor size but no cursor theme, so Hyprland fell back to
    # its own pointer and never followed a theme.
    cursor = machine.succeed(
        user % "gsettings get org.gnome.desktop.interface cursor-theme").strip()
    print(f"cursor-theme {cursor}")
    assert "Bibata" in cursor, f"cursor theme is {cursor}, not Bibata"
    # The dark default theme must get the white half of the pair.
    assert "Ice" in cursor, f"a dark theme should use Bibata-Modern-Ice, got {cursor}"
    machine.succeed(f"test -d /run/current-system/sw/share/icons/{cursor.strip(chr(39))}/cursors")

    # config/ was seeded in full, not just hypr and omarchy. These are the
    # three the manual points users at, and each was missing.
    machine.succeed("test -s /home/omarchy/.config/starship.toml")
    machine.succeed("test -s /home/omarchy/.config/tmux/tmux.conf")
    machine.succeed("test -s /home/omarchy/.config/foot/foot.ini")

    # Agent skills, linked into all four agent homes by the activation script
    # in modules/home.nix rather than by omarchy-provision-user.
    #
    # provision-user does this too, and is guarded by a finalize-user marker, so
    # it runs once in a machine's life. That is fine on Arch, where the skill
    # directory is a fixed path overwritten in place, and wrong here: every bump
    # moves the package to a new store path, so a once-only link keeps pointing
    # at the previous one. A machine that took the omarchy -> nixarchy rename
    # went on serving the old Arch skill from a path nothing would update again,
    # which is what this asserts against.
    #
    # The names matter as much as the links: an agent keys on the directory
    # name, so `omarchy` still being here would mean the rename never reached
    # the only place it is read.
    for home in [".agents/skills", ".claude/skills", ".codex/skills",
                 ".pi/agent/skills"]:
        for skill in ["nixarchy", "nixos", "nixos-gpu", "nixos-ai",
                      "nixos-services", "nixos-secrets", "nixos-performance",
                      "nixos-security", "nixos-doctor", "nixos-config-repo",
                      "diagnose-crash"]:
            machine.succeed(f"test -L /home/omarchy/{home}/{skill}")
            # -e follows the link: a link into a store path that is not in this
            # closure would pass -L and fail here, which is the stale case.
            machine.succeed(f"test -e /home/omarchy/{home}/{skill}/SKILL.md")
        machine.fail(f"test -e /home/omarchy/{home}/omarchy")
    print("agent skills linked into all four agent homes, under the new names")

    # The config-repo nudge, and the two ways it is supposed to stay silent.
    #
    # The hook is the whole delivery mechanism: default/hypr/autostart.lua ends
    # startup with `omarchy-hook post-boot`, which runs everything in this
    # directory. Without the file there is no nudge at all, and nothing else in
    # this test would notice.
    machine.succeed(
        "test -x /home/omarchy/.config/omarchy/hooks/post-boot.d/config-repo")

    # It must call --check first and bail on a non-zero exit. A hook that
    # notifies unconditionally is the failure mode this whole design exists to
    # avoid, and it looks identical to a working one until it annoys someone.
    machine.succeed(
        "grep -q 'nixarchy-config-repo --check || exit 0' "
        "/home/omarchy/.config/omarchy/hooks/post-boot.d/config-repo")

    # Silence, gate one: no default agent. Omarchy deliberately ships without
    # one, so this is the state of every machine whose owner has not finished
    # setting up -- exactly who must not be interrupted. /etc/nixos here is a
    # bare directory (activationScripts.testFlakeDir), so there is genuinely
    # something to nudge about; the agent gate is the only reason it is quiet,
    # which is what makes this an honest test of that gate.
    machine.succeed("su - omarchy -c 'test -z \"$(omarchy-default-agent)\"'")
    machine.fail("su - omarchy -c 'nixarchy-config-repo --check'")
    print("config-repo nudge stays silent until an agent is set up")

    # Silence, gate two: a configuration already in git with a remote. Nothing
    # here is left for the nudge to offer, and asking anyway is how a user
    # learns to dismiss Nixarchy's notifications without reading them.
    #
    # Checked against a repo of its own rather than /etc/nixos, so the assertion
    # is about the detection and not about what the installer happens to leave
    # behind. The done marker is removed first: --check short-circuits on it,
    # which would let this pass without testing anything.
    machine.succeed("su - omarchy -c 'rm -f ~/.local/state/omarchy/done/config-repo'")
    machine.succeed(
        "su - omarchy -c '"
        "mkdir -p ~/donerepo && cd ~/donerepo && "
        "git init -q && git config user.email t@example.com && "
        "git config user.name Test && "
        "echo \"{ }\" > flake.nix && git add -A && git commit -qm init && "
        "git remote add origin https://example.com/x.git'")
    machine.fail(
        "su - omarchy -c 'NIXARCHY_FLAKE=$HOME/donerepo nixarchy-config-repo --check'")

    # And having decided that, it says so permanently: a machine that arrived
    # already in git costs its owner zero notifications, on this boot and every
    # one after it.
    machine.succeed(
        "su - omarchy -c 'test -f ~/.local/state/omarchy/done/config-repo'")
    print("config-repo nudge marks itself done on an already-published config")

    # bin/omarchy-agent-crash reads this path literally, so the rename must
    # never reach it.
    machine.succeed(
        "grep -q 'agents/skills/diagnose-crash/SKILL.md' "
        "$(readlink -f /run/current-system/sw/bin/omarchy-agent-crash)")

    # btop.conf asks for a theme literally named "current"; without the link
    # btop starts with no theme at all.
    machine.succeed("test -L /home/omarchy/.config/btop/themes/current.theme")
    machine.succeed("test -s /home/omarchy/.config/btop/themes/current.theme")

    # btop.theme is rendered from default/themed/*.tpl, and nothing was: the
    # first-run theme-set ran without the package on PATH, so every sibling it
    # calls by bare name was silently not found. foot.ini and gum_env.lua come
    # from the same pass, so they stand in for the rest of it.
    for generated in ["btop.theme", "foot.ini", "gum_env.lua"]:
        machine.succeed(
            f"test -s /home/omarchy/.local/state/omarchy/current/theme/{generated}")


    # ---- the shell chain, in zsh -----------------------------------------
    # Omarchy's aliases and functions are a bash rc chain upstream; a zsh user
    # got none of them. Asserted by running zsh the way a login shell would,
    # rather than by checking a file exists somewhere.
    # Double quotes inside: the `user` template wraps its argument in su -c
    # '...', so a single quote here closes it early and su runs something
    # else entirely.
    zsh_probe = (
        'zsh -ic "type tdl >/dev/null 2>&1 && echo HAVE_TDL; '
        'type compress >/dev/null 2>&1 && echo HAVE_COMPRESS; '
        'alias ls >/dev/null 2>&1 && echo HAVE_LS_ALIAS" 2>&1')
    shell_out = machine.succeed(user % zsh_probe)
    print(f"zsh: {shell_out.split()}")
    assert "HAVE_TDL" in shell_out, (
        f"the tmux layout functions did not reach zsh: {shell_out}")
    assert "HAVE_COMPRESS" in shell_out, (
        f"Omarchy's functions did not reach zsh: {shell_out}")
    assert "HAVE_LS_ALIAS" in shell_out, (
        f"Omarchy's aliases did not reach zsh: {shell_out}")

    # fish gets the same names, by a different route: it cannot source any of
    # upstream's files, so its rc derives them from the same bash instead --
    # the functions stay bash implementations behind a fish wrapper.
    # Written to a file rather than passed inline. Three of these probes have
    # now been broken by the same thing: the `user` template wraps its
    # argument in su -c '...', and any single quote in a fish or zsh one-liner
    # closes it early and runs something else entirely.
    machine.succeed(
        "cat > /tmp/fish-probe.fish <<'PROBE'\n"
        "functions -q compress; and echo HAVE_COMPRESS\n"
        "functions -q tdl; and echo HAVE_TDL\n"
        "alias | string match -q '*cd ..*'; and echo HAVE_ALIASES\n"
        "test -n \"$BAT_THEME\"; and echo HAVE_ENV\n"
        "PROBE\n")
    fish_out = machine.succeed(
        user % "fish -i -c \"source /tmp/fish-probe.fish\" 2>&1")
    print(f"fish: {fish_out.split()}")
    for marker in ["HAVE_COMPRESS", "HAVE_TDL", "HAVE_ALIASES", "HAVE_ENV"]:
        assert marker in fish_out, f"{marker} missing from fish: {fish_out}"

    # A wrapper that only defines the name is worthless -- run one and check
    # it reaches upstream's bash implementation.
    ran = machine.succeed(
        user % 'fish -i -c "compress" 2>&1 || true')
    assert "tar" in ran, (
        f"the fish wrapper did not reach the bash implementation: {ran}")

    # And the same in bash, which must not have regressed.
    bash_out = machine.succeed(
        user % 'bash -ic "type tdl >/dev/null 2>&1 && echo HAVE_TDL" 2>&1')
    assert "HAVE_TDL" in bash_out, f"bash regressed: {bash_out}"

    # ---- Arch package names get nixpkgs answers --------------------------
    # Every omarchy-install-* script routes through omarchy-pkg-add, so this is
    # the one place that decides whether an Install row is useful or a dead
    # end. Asserted in a real session rather than by running the binary on a
    # workstation: what matters is that the table and fontconfig are reachable
    # from where the menu actually calls it.
    advice = machine.succeed(user % "omarchy-pkg-add ttf-firacode-nerd 2>&1 || true")
    print(advice)
    assert "nerd-fonts.fira-code" in advice, "font not mapped to nixpkgs"
    assert "fonts.packages" in advice, (
        "a font in environment.systemPackages installs and is still not found "
        "by fontconfig, so the advice has to name the right option")

    # The app half of the table is generated from data/apps.nix.
    advice = machine.succeed(user % "omarchy-pkg-add php 2>&1 || true")
    assert "nixarchy-app-enable php" in advice, f"php not answered as an app: {advice}"

    # PHP extensions are not packages to add beside PHP.
    advice = machine.succeed(user % "omarchy-pkg-add xdebug 2>&1 || true")
    assert "withExtensions" in advice, f"xdebug not answered as an extension: {advice}"

    # And a name nothing maps still gets the generic answer rather than a
    # traceback.
    advice = machine.succeed(
        user % "omarchy-pkg-add some-unmapped-thing 2>&1 || true")
    assert "search.nixos.org" in advice, advice

    # ---- bluetooth --------------------------------------------------------
    # The bar's Bluetooth widget and both omarchy-bluetooth-* commands talk to
    # org.bluez, and nothing here was enabling the service -- the same shape as
    # UPower: tools installed, daemon not.
    #
    # What is asserted is the configuration, not a running daemon. This VM has
    # no radio, so bluetooth.service skips itself on
    # ConditionPathIsDirectory=/sys/class/bluetooth and org.bluez can never
    # appear. Waiting for the bus here would be waiting for hardware, and
    # dropping the check to make it pass would leave the actual bug -- the
    # service never being enabled -- untested again.
    machine.succeed("systemctl is-enabled bluetooth.service")

    # And why it is not running: no radio. Checked as the absence of the
    # directory the unit conditions on, not by looking for the "skipped"
    # message -- systemd logs that only when something tries to start the
    # unit, so on a run where nothing does, grepping for it finds nothing and
    # proves nothing.
    #
    # If this ever fails, the VM has grown Bluetooth and the assertion above
    # should become the stronger one: that org.bluez answers.
    machine.succeed("test ! -d /sys/class/bluetooth")
    print("bluetooth.service enabled; inert here only for having no radio")

    # ---- the browser accent -----------------------------------------------
    # Chromium reads policy only from /etc/<browser>/policies/managed, so
    # upstream's script skipped it on NixOS and the accent never applied.
    # Asserted on the file it writes, not on the directory existing.
    machine.succeed("test -d /etc/chromium/policies/managed")
    user_theme = machine.succeed(user % "omarchy-theme-set-browser 2>&1 || true")
    machine.wait_until_succeeds("test -s /etc/chromium/policies/managed/color.json")
    policy = machine.succeed("cat /etc/chromium/policies/managed/color.json")
    print(f"chromium policy: {policy.strip()}")
    assert "BrowserThemeColor" in policy, policy

    # The colour has to be the current theme's, not the script's fallback
    # grey -- writing #1c2027 for every theme would satisfy a weaker check.
    expected = machine.succeed(
        "cat /home/omarchy/.local/state/omarchy/current/theme/chromium.theme"
        " 2>/dev/null || true").strip()
    if expected:
        r, g, b = (int(x) for x in expected.split(","))
        assert f"#{r:02x}{g:02x}{b:02x}" in policy.lower(), (
            f"policy has the fallback colour, not the theme's: {policy}")
        print(f"accent matches the theme: {expected}")

    # ---- the gaming rows --------------------------------------------------
    # Three rows, three different shapes. Battle.net and GeForce NOW route
    # through omarchy-pkg-add and are answered from the table; Xbox Cloud is a
    # web app and touches no package manager at all.
    advice = machine.succeed(
        user % "omarchy-pkg-add umu-launcher lib32-nvidia-utils 2>&1 || true")
    assert "pkgs.umu-launcher" in advice, advice
    assert "hardware.graphics.enable32Bit" in advice, (
        "the 32-bit driver halves are a system option on NixOS, not packages, "
        f"and saying systemPackages would send someone nowhere: {advice}")

    advice = machine.succeed(user % "omarchy-pkg-add flatpak 2>&1 || true")
    assert "services.flatpak.enable" in advice, advice

    # Xbox Cloud only fails here for want of a network -- the icon download is
    # under `set -e`. What matters is that it gets that far: no pacman, no
    # shim, nothing NixOS-specific in its way. Asserted as "the failure is the
    # icon fetch", because "it failed" alone would also be true if it were
    # dying on a package manager.
    out = machine.succeed(
        user % ('omarchy-webapp-install "Test App" "https://example.invalid" '
                '"https://example.invalid/icon.png" 2>&1 || true'))
    print(f"webapp-install offline: {out.strip()[:120]}")
    assert "pacman" not in out and "omarchy-pkg-add" not in out, (
        f"the web app path reached a package manager: {out}")

    # ---- switching to a font that is already installed --------------------
    # Upstream's row is `omarchy-pkg-add <pkg> && omarchy-font-set '<family>'`,
    # so the switch never ran here even when the font was present. This module
    # installs JetBrainsMono Nerd Font, so the positive branch is real.
    out = machine.succeed(
        user % ("omarchy-install-font \"JetBrains Mono\" ttf-jetbrains-mono-nerd "
                "\"JetBrainsMono Nerd Font\" 2>&1 || true"))
    print(out)
    assert "already installed" in out, (
        "a font this system ships was reported missing -- fc-list is either "
        "not on PATH or the check is losing to SIGPIPE under pipefail")

    # ---- the menu knows what is already installed -------------------------
    # An Install row used to offer an app the machine already had. The row's
    # `disabled` is a shell command the menu runs, so the invariant is
    # checkable directly: for every app whose command is on PATH, that command
    # must succeed -- meaning the row draws dim rather than offering to install
    # what is already there.
    #
    # Driven off the generated menu rather than a list written here, so an app
    # added to data/apps.nix is covered without touching this check.
    # Written as an explicit list of unindented lines. A triple-quoted block
    # with a hand-rolled dedent turned `print` into `t(` -- the lines did not
    # all carry the same indent, so slicing a fixed number of characters off
    # each one cut into the code.
    probe = "\n".join([
        "import json, re, shutil, subprocess",
        "raw = open('/etc/nixarchy/omarchy-menu.jsonc').read()",
        # str() rather than an empty-string literal: this whole probe lives
        # inside a Nix indented string, which two apostrophes terminate --
        # including two inside a comment, as this comment first proved.
        "raw = re.sub(r'^\\s*//[^\\n]*(\\n|$)', str(), raw, flags=re.M)",
        "raw = re.sub(r',(\\s*[}\\]])', r'\\1', raw)",
        "rows = json.loads(raw)",
        "bad = []",
        "checked = 0",
        "for key, row in rows.items():",
        "    if not key.startswith('install.') or 'disabled' not in row:",
        "        continue",
        "    m = re.search(r'command -v (\\S+)', row['disabled'])",
        "    if not m or shutil.which(m.group(1)) is None:",
        "        continue",
        "    checked += 1",
        "    if subprocess.run(['bash', '-c', row['disabled']]).returncode != 0:",
        "        bad.append(key)",
        "print('CHECKED', checked)",
        "print('BAD', ' '.join(bad))",
    ])
    machine.succeed(
        "cat > /tmp/menuprobe.py <<'PYEOF'\n" + probe + "\nPYEOF")
    out = machine.succeed(user % "python3 /tmp/menuprobe.py")
    print(out.strip())
    bad = [w for w in out.split("BAD", 1)[1].split()] if "BAD" in out else []
    assert not bad, (
        f"these Install rows offer an app that is already on PATH: {bad}")

    # The count matters as much as the verdict. With nothing installed outside
    # the selection this loop checks almost nothing and passes for that reason
    # -- it read CHECKED 1 before the machine was given a vim of its own.
    assert int(out.split("CHECKED", 1)[1].split()[0]) >= 2, (
        "the menu probe found almost nothing on PATH to check, so its verdict "
        "means almost nothing")

    # And vim specifically, since it is the one this machine installs the way a
    # user would -- through systemPackages, with the selection none the wiser.
    machine.succeed(
        user % "grep -q vim $HOME/.config/nixarchy/apps.nix && ! grep -qE "
               "'^[[:space:]]*vim\\.enable[[:space:]]*=[[:space:]]*true' "
               "$HOME/.config/nixarchy/apps.nix")
    print("vim is offered by the selection, not selected, and already on PATH")

    # ---- what the seed puts in a new user's home --------------------------
    # Each of these was absent on a real machine, and each broke something
    # quietly.
    root = ("$(dirname $(dirname $(readlink -f "
            "/run/current-system/sw/bin/omarchy)))")

    # flags.lua, and *only* flags.lua. For these toggles presence is
    # enablement -- seeding the directory wholesale brings the desktop up with
    # no window gaps and every window forced square, which is the obvious
    # wrong fix. The directory itself is what the bar's FileView watches, and
    # a watch on a directory that does not exist never fires: omarchy-toggle-bar
    # wrote bar-off and the bar stayed on screen until the shell restarted.
    machine.succeed(
        "test -f /home/omarchy/.local/state/omarchy/toggles/hypr/flags.lua")
    for absent in ["window-no-gaps", "single-window-aspect-ratio"]:
        machine.succeed(
            f"test ! -e /home/omarchy/.local/state/omarchy/toggles/hypr/{absent}.lua")
    print("the toggle state directory is seeded, with only flags.lua in it")

    # Branding. Without about.txt the About window opens with a blank logo
    # column; without screensaver.txt the screensaver has no art. Both must be
    # writable -- a store file copied verbatim lands read-only, and these exist
    # to be edited.
    for f in ["about.txt", "screensaver.txt"]:
        machine.succeed(f"test -s /home/omarchy/.config/omarchy/branding/{f}")
        machine.succeed(f"test -w /home/omarchy/.config/omarchy/branding/{f}")
    # Compared byte-for-byte against the package's own logo.txt rather than
    # grepped for "NIXARCHY": the banner is block-character art, so the word
    # never appears as text. This pins that the branded banner this repo
    # builds is what gets seeded, not upstream's.
    machine.succeed(
        f"cmp -s {root}/logo.txt "
        "/home/omarchy/.config/omarchy/branding/screensaver.txt")
    machine.succeed(
        f"cmp -s {root}/icon.txt "
        "/home/omarchy/.config/omarchy/branding/about.txt")
    print("branding files are seeded, writable, and ours")

    # ---- the scripts that write into a home directory ---------------------
    # omarchy-refresh-applications copied store files with a plain cp, so they
    # landed 444 and the *next* run could not overwrite them. That aborted
    # omarchy-provision-user under pipefail before it marked finalize-user, so
    # the whole first-run sequence re-ran and re-failed on every login.
    refresh = machine.succeed(
        f"cat {root}/bin/omarchy-refresh-applications")
    assert "--no-preserve=mode" in refresh, (
        "omarchy-refresh-applications still copies store files with their mode")
    assert "cp -f" in refresh, (
        "without -f it cannot overwrite the 444 files already on disk")
    print("refresh-applications copies without the store's read-only mode")

    # Every shipped bash script parses. This is the check that would have
    # caught omarchy-install-service-1password, whose heredoc terminator landed
    # indented by a patch in this repo -- a hard syntax error that shipped
    # because nobody ever ran bash -n over the result.
    machine.succeed(
        "cat > /tmp/parseprobe.sh <<'PPEOF'\n"
        "root=$(dirname $(dirname $(readlink -f /run/current-system/sw/bin/omarchy)))\n"
        "for f in \"$root/bin\"/*; do\n"
        "  head -1 \"$f\" 2>/dev/null | grep -q bash || continue\n"
        "  bash -n \"$f\" 2>/dev/null || basename \"$f\"\n"
        "done\n"
        "PPEOF")
    unparseable = machine.succeed("bash /tmp/parseprobe.sh").split()
    assert not unparseable, (
        f"these shipped scripts are not valid bash: {unparseable}")
    print("every shipped bash script parses")

    # ---- every keybinding launches something that exists ------------------
    # A key bound to a missing program fails only when somebody presses it,
    # with a notification naming the program and nothing else. SUPER + SHIFT +
    # ALT + M did that for cliamp, which had been in nixpkgs for a while by
    # then, and SUPER + SHIFT + W still does for omawrite, which is not.
    #
    # Checked in the VM rather than at build time on purpose: the answer is
    # what is on the session PATH, and a build sandbox cannot see the system
    # profile. Tried there first and it reported btop, cliamp and obsidian
    # missing on a machine that has all three.
    #
    # Two forms: `omarchy = "x"` runs omarchy-launch-x, `launch`/`tui` run x
    # directly. Only the first word is a program; the rest are flags.
    machine.succeed(
        "cat > /tmp/bindprobe.sh <<'BPEOF'\n"
        "root=$(dirname $(dirname $(readlink -f /run/current-system/sw/bin/omarchy)))\n"
        "for f in \"$root/default/hypr/bindings\"/*.lua; do\n"
        "  grep -oE '(omarchy|launch|tui) *= *\"[^\"]+\"' \"$f\" 2>/dev/null |\n"
        "    sed -E 's/ *= *\"/ /; s/\"$//' | while read -r kind target; do\n"
        # awk, not a parameter expansion: this file is a Nix indented string
        # and a dollar-brace is interpolated even inside a quoted fragment.
        "      cmd=$(echo \"$target\" | awk '{print $1}')\n"
        "      [ \"$kind\" = omarchy ] && cmd=\"omarchy-launch-$cmd\"\n"
        "      command -v \"$cmd\" >/dev/null 2>&1 || echo \"$cmd\"\n"
        "    done\n"
        "done | sort -u\n"
        "BPEOF")
    machine.succeed("chmod 0755 /tmp/bindprobe.sh")
    dead = machine.succeed(user % "bash /tmp/bindprobe.sh").split()

    # Two are absent on purpose, and named rather than tolerated so either
    # surfaces the day it stops being true.
    #
    # omawrite is Omarchy's own writing application and is not in nixpkgs, so
    # SUPER + SHIFT + W has nothing to launch on any machine.
    #
    # obsidian is unfree, so it is opt-in through apps.obsidian rather than
    # preinstalled -- an unfree package in the always-on set aborts the whole
    # rebuild rather than failing on its own. Its key works on a machine that
    # enables it; this one does not.
    expected_absent = {"omawrite", "obsidian"}
    dead = [d for d in dead if d not in expected_absent]
    assert not dead, (
        f"these keybindings launch something that does not exist: {dead}. "
        "Install it, or name it here with the reason.")
    print("every keybinding launches something that exists (bar omawrite)")

    # ---- the shell rc files know where they live --------------------------
    # All three opened with a fallback to /usr/share/omarchy for when
    # OMARCHY_PATH is unset, which on NixOS can never exist. Anything sourcing
    # one without the variable already set -- a systemd unit, a container, ssh
    # with a restricted environment -- got
    #
    #   no such file or directory: /usr/share/omarchy/default/bash/envs
    #
    # and none of the aliases or functions. It worked from a login only because
    # environment.sessionVariables puts OMARCHY_PATH in /etc/set-environment
    # and the login path reads that first.
    #
    # Tested with the variable explicitly unset, because that is the case that
    # was broken; sourcing it from a normal login proves nothing here.
    # Written to a file rather than quoted inline: this needs a shell command
    # inside a Python string inside a Nix indented string, and hand-quoting
    # that produced an empty result the first time -- which the check then
    # reported as the fallback being wrong.
    machine.succeed(
        "cat > /tmp/rcprobe.sh <<'RCEOF'\n"
        # dirname twice, not a parameter expansion: this file is a Nix
        # indented string and a dollar-brace is interpolated even inside a
        # quoted shell fragment.
        "root=$(dirname $(dirname $(readlink -f /run/current-system/sw/bin/omarchy)))\n"
        "unset OMARCHY_PATH\n"
        ". \"$root/default/$1/rc\" >/dev/null 2>&1\n"
        "echo \"$OMARCHY_PATH\"\n"
        "RCEOF")
    for shell in ["bash", "zsh"]:
        out = machine.succeed(
            f"env -i PATH=/run/current-system/sw/bin {shell} /tmp/rcprobe.sh {shell}"
        ).strip()
        assert out.startswith("/nix/store/"), (
            f"the {shell} rc fell back to a path that cannot exist here: {out!r}")
    print("the bash and zsh rc files locate themselves with no environment")

    # ---- no shipped command still reaches into /usr -----------------------
    # The sweep that found the version string, Vulkan detection, both app
    # launchers and RetroArch's asset paths, kept as a check so the next one
    # cannot creep back in unnoticed.
    #
    # Comment lines are stripped first. Several of these scripts explain in
    # prose what upstream does with /usr, and matching those was what first
    # made this scan accuse a file we had already rewritten.
    #
    # The exceptions are named rather than the check weakened: each is a
    # command that only means anything on Arch, and each already refuses or
    # explains itself when run here.
    allowed = ["omarchy-upgrade-to-quattro", "omarchy-system-factory-reset",
               "omarchy-migrate", "omarchy-plymouth-set",
               "omarchy-refresh-plymouth", "omarchy-refresh-sddm",
               "omarchy-provision-owner", "omarchy-provision-user",
               "omarchy-apply-hardware", "omarchy-apply-system",
               "omarchy-channel-set", "omarchy-channel-current",
               "omarchy-dns", "omarchy-hibernation-setup",
               "omarchy-toggle-hybrid-gpu",
               # Tries /usr/bin/omarchy-windows-vm as the first candidate for a
               # trustworthy path to re-exec itself as root, then falls back to
               # a PATH lookup. The first simply does not exist here and the
               # loop moves on; the store path it finds instead is root-owned
               # and mode 555, which is exactly what its own check demands.
               "omarchy-windows-vm",
               "omarchy-remove-service-1password",
               "omarchy-remove-launcher-entry", "omarchy-remove-dev-env",
               "omarchy-chromium-copy-url-host", "omarchy-chromium-ytdlp-host",
               "omarchy-launch-docker-tui", "omarchy-hyprland-reload-guard",
               "omarchy-setup-security-fingerprint", "omarchy-theme-set-vscode",
               "omarchy-install-browser", "omarchy-install-ai-chatgpt",
               "omarchy-install-gaming-lutris", "omarchy-install-service-signal",
               "omarchy-install-service-spotify",
               "omarchy-install-service-sunshine", "omarchy-plymouth-current",
               "omarchy-dev-link", "omarchy-dev-pkg-test", "omarchy-dev-status",
               "omarchy-dev-unlink",
               # These four spell /usr/share/omarchy only as the default in
               # a shell parameter expansion on OMARCHY_PATH, or compare against
               # tell a packaged install from a checkout. OMARCHY_PATH is always
               # set here, so the fallback is unreachable and the comparison
               # always takes the branch it should.
               "omarchy-version", "omarchy-version-branch",
               "omarchy-update-dev", "omarchy-update-system-pkgs",
               # fwupd's EFI capsule lives wherever the fwupd package puts it;
               # on NixOS that is services.fwupd's business, not a path this
               # repo should pin.
               "omarchy-update-firmware"]
    # The offender list comes back from one plain shell command and the
    # filtering happens here. A first version did the allowlisting in shell
    # too, with a grep -v -x -F against a generated list, and it matched
    # nothing at all -- removing an entry from `allowed` did not fail the
    # check, which is how a check that inspects nothing looks from outside.
    offenders = machine.succeed(
        # readlink -f already lands inside share/omarchy/bin, because bin/omarchy
        # is a symlink to it. Appending ../share/omarchy/bin to that pointed at
        # nothing, the cd failed, and the trailing `true` turned an empty
        # result into a pass -- the check inspected zero files and said so to
        # nobody.
        "cd $(dirname $(readlink -f /run/current-system/sw/bin/omarchy)) && "
        "for f in *; do "
        "  grep -v '^[[:space:]]*#' \"$f\" 2>/dev/null "
        "    | grep -q '/usr/' && basename \"$f\"; "
        "done; true").split()
    assert len(offenders) > 5, (
        f"the /usr scan inspected almost nothing ({offenders}); it is looking "
        "in the wrong directory again")
    found = sorted(set(offenders) - set(allowed))
    assert not found, (
        "these shipped commands still reach into /usr in code: "
        + " ".join(found)
        + ". Either point them at what NixOS actually uses, or add them to the "
        "named exceptions with a command that explains itself.")
    print("no unexpected command reaches into /usr")

    # ---- launchers must look on PATH, not in /usr/bin ---------------------
    # Clicking Spotify offered to install Spotify. Both launchers decide
    # whether the app is present by testing `-x /usr/bin/<app>`, which is never
    # true on NixOS -- so someone with apps.spotify enabled got the install
    # flow, with the real binary on their PATH the whole time.
    #
    # Asserted on the shipped script rather than by launching: the VM has the
    # launchers but not the apps, and a `-x /usr/bin` test is wrong here
    # whether or not anything is installed. A grep is the honest shape of the
    # claim -- the bug was a hardcoded path, so the check is that the path is
    # gone.
    for launcher in ["spotify", "signal"]:
        script = machine.succeed(
            f"cat $(readlink -f /run/current-system/sw/bin/omarchy-launch-{launcher})")
        assert "/usr/bin/" not in script, (
            f"omarchy-launch-{launcher} still tests a /usr/bin path; on NixOS "
            "that is never true and the menu offers to install an app the user "
            "already has.")
        assert "command -v" in script, (
            f"omarchy-launch-{launcher} no longer looks the app up on PATH")
    print("the Spotify and Signal launchers look on PATH")

    # ---- migrations refuse to run -----------------------------------------
    # The one finding in this sweep that could have done damage. Omarchy ships
    # 86 migration scripts that bring an older Arch install forward -- 29 use
    # sudo, 12 write under /usr, 8 call pacman -- and with no state directory
    # every one of them counts as pending. `omarchy migrate` on a machine
    # installed today would have run all 86 as root.
    #
    # Asserted on the command refusing, not on a pending count: the count is
    # answered by the same replacement being tested, so it would agree with
    # itself no matter what. What has to hold is that a person running this
    # gets an explanation and a non-zero exit.
    status, out = machine.execute(user % "omarchy migrate 2>&1")
    assert status != 0, "omarchy migrate did not refuse to run"
    assert "not how a NixOS install moves forward" in out, (
        f"omarchy migrate ran or said something unexpected: {out!r}")
    print("omarchy migrate refuses and says why")

    # --pending still answers the way the bar asks, because nothing is pending
    # -- a refusal where a caller expects a list would be a worse answer than
    # the true one.
    assert not machine.succeed(
        user % "omarchy migrate --pending").strip(), (
        "omarchy migrate --pending should be silent")
    print("and --pending answers the bar honestly")

    # ---- installing a theme from a git URL --------------------------------
    # The sibling of `omarchy plugin add`, and it was the larger untested
    # surface: it clones a real repository into ~/.config/omarchy/themes at
    # runtime and then applies it. Everything the plugin flow needs, this needs
    # too -- a writable config directory, git on PATH, the URL gate -- plus one
    # thing plugins never touch: the theme has to actually be *applied*, which
    # runs the whole template chain across foot, btop, gtk, chromium and the
    # wallpaper.
    #
    # file:// for the clone, as in tests/plugin.nix: a real transport in
    # omarchy-git-url-check's allowlist, with the scheme itself checked
    # separately below since that is the only part file:// cannot exercise.
    machine.succeed(user % "omarchy-git-url-check "
                    "https://github.com/OldJobobo/omarchy-lumon-theme.git")
    print("the https theme URL from omarchy.org/themes is accepted")

    # The current theme is named in current/theme.name, which is what
    # `omarchy theme current` reads. Not the current/theme path: that is a
    # staging directory theme-set *populates* with the files a theme is allowed
    # to contribute, so it never moves and reads as success no matter what
    # happened.
    before = machine.succeed(user % "omarchy theme current").strip()

    print(machine.succeed(
        user % "omarchy theme install file:///srv/lumon 2>&1", timeout=300))

    # Cloned where the CLI and the menu both look for user themes.
    machine.succeed("test -f /home/omarchy/.config/omarchy/themes/lumon/colors.toml")

    # And actually applied. `omarchy theme install` ends by calling
    # omarchy-theme-set, so a clone that installed without applying would leave
    # the desktop on tokyo-night and still look like success.
    after = machine.succeed(user % "omarchy theme current").strip()
    assert after != before, (
        f"installing a theme did not change the current theme (still {after!r})")
    assert "lumon" in after.lower(), (
        f"the current theme is {after!r}, not the one just installed")
    print(f"current theme moved from {before!r} to {after!r}")

    # The wallpaper is the visible half, and the one that would break quietly:
    # a theme's backgrounds live in the clone, not in the store, so this is the
    # first thing in the whole session reading an image from outside /nix/store.
    # Matched by filename against the clone's own backgrounds directory, not by
    # looking for the theme's name in the path: the background resolves through
    # current/theme/backgrounds, the staging directory, so the theme name never
    # appears in it however well the install went.
    paper = machine.succeed(
        user % "readlink -f $HOME/.local/state/omarchy/current/background").strip()
    machine.succeed(f"test -s {paper}")
    machine.succeed(
        "test -f /home/omarchy/.config/omarchy/themes/lumon/backgrounds/"
        + paper.split("/")[-1])
    print(f"wallpaper came from the cloned theme: {paper.split('/')[-1]}")

    # ---- what `omarchy version` reports -----------------------------------
    # It said "dev". Upstream reads the version from `pacman -Q omarchy` and
    # treats any OMARCHY_PATH that is not /usr/share/omarchy as a developer
    # running from a git checkout -- which, on a store path with no .git, is
    # every nixarchy machine.
    #
    # Checked here rather than trusted to the build patch because the value is
    # user-visible: etc/fastfetch/config.jsonc calls this, so it is printed in
    # every new terminal, and omarchy-snapshot and omarchy-channel-current read
    # it too.
    reported = machine.succeed(user % "omarchy version").strip()
    assert reported == "${(pkgs.extend inputs.self.overlays.default).omarchy.version}", (
        f"omarchy version reports {reported!r}, not the packaged version. "
        "'dev' means it took upstream's git-checkout branch again.")
    print(f"omarchy version reports {reported}")

    # ---- the doctor ------------------------------------------------------
    # `nix run .#doctor` is the first thing the README tells anyone to run, so
    # it is worth more than having been run once by hand on a workstation. This
    # VM is a known machine -- SDDM greeting, Hyprland configured, Omarchy's own
    # config seeded -- so its answers are checkable.
    # As the user, not root: it reads $HOME, and run as root it reported "No
    # Hyprland config" on a machine whose config was sitting in /home/omarchy.
    report = machine.succeed(
        user % "${doctor}/bin/nixarchy-doctor 2>&1 || true")
    print(report)

    # It must never write anything: it runs on a machine that has not decided
    # to adopt nixarchy yet.
    assert "SDDM is greeting" in report, report
    assert "Hyprland already configured" in report, report

    # And it has to end with something to paste, not just a diagnosis.
    assert "programs.nixarchy.enable = true;" in report, report

    # A machine already greeting with SDDM does not need displayManager=false;
    # advising it would be wrong.
    assert "displayManager = false" not in report, (
        "the doctor told an SDDM machine to turn SDDM off")

    # ---- the Omarchy session entry ---------------------------------------
    # What lets nixarchy sit beside an existing Hyprland: a session of its own
    # that names Omarchy's hyprland.lua with --config, rather than needing to
    # own ~/.config/hypr/hyprland.lua.
    #
    # Asserted in the system profile, not just in sessionPackages: greetd
    # greeters read /run/current-system/sw/share/wayland-sessions and
    # sessionPackages alone does not populate it.
    session_file = "/run/current-system/sw/share/wayland-sessions/omarchy.desktop"
    machine.succeed(f"test -s {session_file}")

    # DesktopNames must stay Hyprland: xdg-desktop-portal-hyprland declares
    # UseIn=wlroots;Hyprland;... and binds for nothing else, so any other name
    # silently breaks ScreenCast and Screenshot inside the session.
    machine.succeed(f"grep -q '^DesktopNames=Hyprland$' {session_file}")

    # And the config it points at has to exist, or the session dies on launch
    # with a message nobody sees.
    launcher = machine.succeed(
        f"sed -n 's/^Exec=//p' {session_file}").strip().split()[0]
    cfg = machine.succeed(
        f"grep -oE '[^ ]+/config/hypr/hyprland.lua' {launcher} | head -1").strip()
    machine.succeed(f"test -f {cfg}")
    print(f"omarchy session -> {cfg}")

    # ---- compose sequences ----------------------------------------------
    # install/user/xcompose.sh writes ~/.XCompose at first login including a
    # path that upstream owns as /usr/share/omarchy. Getting that wrong is
    # silent: xkbcommon logs a parse failure into the client's stderr and
    # every CapsLock compose sequence in the manual stops working, with
    # nothing on screen to say so.
    machine.succeed("test -s /etc/omarchy/xcompose")
    machine.succeed("grep -q 'Multi_key' /etc/omarchy/xcompose")

    # The include has to resolve from the file the session will actually read.
    included = machine.succeed(
        "sed -n 's/^include \"\\(.*\\)\"$/\\1/p' /home/omarchy/.XCompose"
        " | grep -v '%L' || true").strip()
    print(f"~/.XCompose includes: {included!r}")
    if included:
        machine.succeed(f"test -e {included}")

    # ---- does the wallpaper actually render? ----------------------------
    # Everything else here proves the tree assembles. This proves the desktop
    # is not black -- which every other check passed while it was.
    #
    # machine.screenshot() goes through qemu's own screendump rather than a
    # compositor screencopy, so it works with no display backend; `grim`
    # blocks forever in that situation because nothing consumes the frames.
    import subprocess

    def avg(path):
        out = subprocess.run(
            ["${pkgs.imagemagick}/bin/magick", path, "-resize", "1x1", "-format", "%[hex:u]", "info:"],
            capture_output=True, text=True, check=True)
        return tuple(int(out.stdout.strip()[i:i + 2], 16) for i in (0, 2, 4))

    machine.wait_until_succeeds("test -s $(readlink -f /home/omarchy/.local/state/omarchy/current/background)")
    paper = machine.succeed(
        "readlink -f /home/omarchy/.local/state/omarchy/current/background").strip()
    machine.copy_from_machine(paper, "")
    local_paper = os.path.join(os.environ["out"], os.path.basename(paper))
    w_r, w_g, w_b = avg(local_paper)

    # Retried, not slept at. This one has been passing on a five second wait
    # only because a great deal of test runs between login and here; the same
    # guess was wrong for the greeter above and wrong again in
    # tests/coexist.nix, where the desktop needed twenty seconds more than it
    # was given.
    #
    # A wallpaper that never became a texture leaves the theme background --
    # near-black, and nothing like the image. Tolerance is wide on purpose:
    # the bar and any toast tint the average, and the point is to catch black,
    # not to grade colour accuracy.
    delta = None
    for attempt in range(12):
        machine.sleep(5)
        machine.screenshot("desktop")
        shot = os.path.join(os.environ["out"], "desktop.png")
        s_r, s_g, s_b = avg(shot)
        delta = abs(s_r - w_r) + abs(s_g - w_g) + abs(s_b - w_b)
        print(f"attempt {attempt}: screen #{s_r:02X}{s_g:02X}{s_b:02X} "
              f"wallpaper #{w_r:02X}{w_g:02X}{w_b:02X} delta {delta}")
        if delta < 120:
            break

    assert delta is not None and delta < 120, (
        f"the desktop never looked like its wallpaper (delta {delta} after "
        "60s). A wallpaper wider than GL_MAX_TEXTURE_SIZE renders as nothing "
        "at all, with Qt still reporting the image Ready -- see the "
        "sourceSize cap in pkgs/omarchy/default.nix.")
    print(f"wallpaper renders (delta {delta})")

  '';
}
