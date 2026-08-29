{ inputs, pkgs }:
# Adds real third-party plugins from real git repos, the way the manual says
# to: `omarchy plugin add <url> --enable`.
#
# The plugin system is the one part of Omarchy that is deliberately imperative.
# Everything else nixarchy touches is declared in a flake and built into the
# store; plugins are cloned at runtime into ~/.config/omarchy/plugins and loaded
# by the running shell. That is upstream's design, and the nixarchy-specific
# question is whether it survives contact with a system whose config directory
# is usually made of read-only store symlinks. The seed writes that tree with
# `cp -rn --no-preserve=mode`, so it is a real writable directory -- and if that
# ever changed, `plugin add` would die on its first mkdir.
#
# The repos are upstream's own, pinned by hash, and cloned over file:// because
# a NixOS test machine has no network. file:// is a real entry in
# omarchy-git-url-check's allowlist rather than a special case bolted on here,
# and every step after the clone -- validate, the id-collision check, the rescan
# IPC, enable -- is identical to what an https URL reaches. What file:// cannot
# prove is that the scheme itself is accepted, so the https URLs are checked
# against omarchy-git-url-check directly below: that is the only code in the
# whole path that reads a scheme at all.
let
  # Two plugins rather than one, because a single sample cannot tell "plugins
  # work" from "this plugin works". Both are bar-widgets, which is what third
  # parties actually publish, and they differ in the ways the registry cares
  # about: id shape (reverse-DNS against a short dotted name) and default
  # section (center against right).
  plugins = [
    {
      id = "io.github.seyhunakyurek.omteleprompt";
      name = "omteleprompt";
      url = "https://github.com/seyhunak/omteleprompt.git";
      src = pkgs.fetchgit {
        url = "https://github.com/seyhunak/omteleprompt.git";
        rev = "9a35865220a0c9d65132329e446a84c466545110";
        hash = "sha256-KJM/AC1DnPwob40lo39Rlk9qkyKTI++bss1wPIcGsTs=";
      };
    }
    {
      id = "remco.bar-toggle";
      name = "bar-toggle";
      url = "https://github.com/r3mcos3/omarchy-bar-toggle.git";
      src = pkgs.fetchgit {
        url = "https://github.com/r3mcos3/omarchy-bar-toggle.git";
        rev = "586750d0fa902b8774d1559fff954da540742a1e";
        hash = "sha256-K45Qwgdf+K943nPHxrgS0IE9slsno9uZjIkr3XnfVBM=";
      };
    }
  ];

  # fetchgit hands over a plain directory with no .git, so the history is
  # rebuilt in the VM -- each plugin's own files, unmodified, at one commit.
  makeRepos = pkgs.lib.concatMapStringsSep "\n" (p: ''
    if [ ! -d /srv/${p.name}/.git ]; then
      mkdir -p /srv/${p.name}
      cp -r --no-preserve=mode,ownership ${p.src}/. /srv/${p.name}/
      cd /srv/${p.name}
      export HOME=/root
      ${pkgs.git}/bin/git init -q -b main
      ${pkgs.git}/bin/git -c user.email=t@t -c user.name=t add -A
      ${pkgs.git}/bin/git -c user.email=t@t -c user.name=t commit -q -m ${p.name}
    fi
    chmod -R a+rX /srv/${p.name}
  '') plugins;

  pluginJSON = builtins.toJSON (map (p: { inherit (p) id name url; }) plugins);

  # The same upstream repo the imperative flow clones, handed to the module as
  # a path instead. Deliberately the *other* plugin from the one added first,
  # so the two never race for the same id.
  declarative = (builtins.elemAt plugins 1).src;
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-plugin";

  nodes.machine = {
    imports = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.nixarchy = {
      enable = true;
      flake = "/etc/nixos";
      displayManager = false;
    };

    boot.plymouth.enable = pkgs.lib.mkForce false;
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";

    services.getty.autologinUser = "omarchy";

    users.users.omarchy = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "video"
        "input"
      ];
      password = "omarchy";
    };
    security.sudo.wheelNeedsPassword = false;

    system.activationScripts.testFlakeDir = ''
      mkdir -p /etc/nixos
      chmod 0777 /etc/nixos
    '';

    system.activationScripts.pluginRepos = makeRepos;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
      users.omarchy = {
        programs.nixarchy.enable = true;
        home.stateVersion = "25.05";

        # The declarative half. Same plugin the imperative flow adds below,
        # so the two paths can be compared directly -- except this one is
        # never cloned, never touched by `plugin add`, and is a read-only
        # store symlink rather than a git checkout.
        programs.nixarchy.plugins.bar-toggle.src = declarative;
      };
    };
  };

  testScript = ''
    import json

    PLUGINS = json.loads(r"""${pluginJSON}""")

    machine.wait_for_unit("multi-user.target")
    # systemd-logind starts user@1000.service asynchronously once the session
    # opens, so there is a window where the unit is inactive with no job queued
    # yet. wait_for_unit treats exactly that as a hard failure -- it raises
    # "is inactive and there are no pending jobs" immediately rather than
    # waiting -- so on a loaded runner it fails a session that was about to come
    # up fine. Poll for "active" instead, which tolerates the window.
    machine.wait_until_succeeds("systemctl is-active user@1000.service")
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    # Bring the session up the way the greeter would, exactly as coexist does.
    session = "/run/current-system/sw/share/wayland-sessions/omarchy.desktop"
    exec = machine.succeed(f"sed -n 's/^Exec=//p' {session}").strip()
    machine.succeed(
        "systemd-run --uid=1000 --setenv=XDG_RUNTIME_DIR=/run/user/1000 "
        "--setenv=WLR_RENDERER_ALLOW_SOFTWARE=1 --setenv=XDG_SESSION_TYPE=wayland "
        "--setenv=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
        f"--unit=omarchy-session --collect {exec}")

    # Probes go through a file rather than su -c '...'. Nested single quotes
    # inside su -c have broken three separate probes in this repo already, and
    # the jq filters these commands carry are full of them.
    def user(script, timeout=120, check=True):
        machine.succeed(
            "cat > /tmp/probe.sh <<'PROBE_EOF'\n"
            + "export XDG_RUNTIME_DIR=/run/user/1000\n"
            + "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus\n"
            + "export HYPRLAND_INSTANCE_SIGNATURE="
            + "$(ls -t /run/user/1000/hypr 2>/dev/null | head -1)\n"
            # Upstream gives every IPC call 2 seconds and calls anything
            # slower "not responding". That is a guess about how fast the
            # machine is, and it was wrong on a CI runner: the second
            # `plugin add` failed there after cloning and printing "Added",
            # because enabling the first plugin had set the shell reloading
            # and it did not answer inside the budget. Raised rather than
            # retried -- the call is not failing, it is being cut off, and
            # this is the knob upstream provides for saying so.
            + "export OMARCHY_SHELL_IPC_TIMEOUT=30s\n"
            + script + "\nPROBE_EOF")
        machine.succeed("chmod 0755 /tmp/probe.sh")
        run = machine.succeed if check else machine.execute
        return run("su omarchy -c 'bash /tmp/probe.sh'", timeout=timeout)

    # Wait for the shell to answer IPC, not for a process to exist.
    #
    # `pgrep -f quickshell` was the obvious thing and is worthless here: the
    # shell running the pgrep has "quickshell" in its own command line, so it
    # matches itself and returns instantly. That is exactly what happened --
    # the wait passed at once and `plugin add` then died on "omarchy-shell is
    # not running", after cloning the plugin and printing "Added".
    #
    # `ping` is also the only probe that distinguishes a shell that is up from
    # one that is still starting: upstream's omarchy-shell turns the
    # "Not ready to accept queries yet" reply into a failure precisely because
    # a starting shell answers stdout and exits 0.
    machine.succeed(
        "cat > /tmp/ping.sh <<'EOF'\n"
        "export XDG_RUNTIME_DIR=/run/user/1000\n"
        "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus\n"
        "export OMARCHY_SHELL_IPC_TIMEOUT=30s\n"
        "omarchy-shell shell ping\n"
        "EOF")
    machine.succeed("chmod 0755 /tmp/ping.sh")
    machine.wait_until_succeeds("su omarchy -c 'bash /tmp/ping.sh'", timeout=240)
    print("the shell answers IPC; plugin commands have something to talk to")

    # ---- the scheme check, the one thing file:// cannot exercise -----------
    # omarchy-git-url-check is what every URL meets first and the only code in
    # the path that reads the scheme. Both directions, so a check that accepted
    # everything would be caught.
    for p in PLUGINS:
        user(f"omarchy-git-url-check {p['url']}")
        print(f"the https URL from the manual is accepted: {p['url']}")

    status, _ = machine.execute(
        "su omarchy -c 'omarchy-git-url-check ext::sh -c whoami'")
    assert status != 0, (
        "omarchy-git-url-check accepted an ext:: transport helper -- that URL "
        "shape runs a shell command at clone time, before anything is "
        "validated or enabled.")
    print("a transport-helper URL is still refused")

    # ---- the plugin directory has to be writable --------------------------
    # The nixarchy-specific risk in the whole flow. Home-manager's usual answer
    # for a config file is a read-only store symlink, and if ~/.config/omarchy
    # were one, `plugin add` would die on its first mkdir with no useful
    # message. The seed uses cp -rn precisely so this is a real directory.
    user("test -w ~/.config/omarchy")
    print("~/.config/omarchy is writable, so plugins can be cloned into it")

    # ---- the declarative half ---------------------------------------------
    # programs.nixarchy.plugins installs a plugin from the store with no clone
    # and no `plugin add`. What has to be true is not that a symlink exists --
    # that is trivially checkable and proves nothing -- but that the running
    # shell discovers and loads a plugin whose folder is a read-only store
    # symlink rather than a git checkout.
    #
    # Upstream's scan globs "$dir"/*/ and tests -f "$sub/manifest.json", both
    # of which follow a symlink, so this is a supported shape rather than
    # something snuck past. This asserts that, because it is the assumption the
    # whole option rests on.
    decl_id = "remco.bar-toggle"
    decl = f"/home/omarchy/.config/omarchy/plugins/{decl_id}"
    machine.succeed(f"test -L {decl}")
    machine.succeed(f"readlink {decl} | grep -q '^/nix/store/'")
    print(f"{decl_id} is a store symlink, planted with no clone")

    seen = json.loads(user("omarchy-plugin-list --json"))
    assert any(q["id"] == decl_id for q in seen), (
        f"the shell did not discover the declaratively installed {decl_id}. "
        f"It listed: {sorted(q['id'] for q in seen)}")
    print("and the shell discovered it anyway")

    # Declared but not enabled, which is the deliberate half of the design:
    # enablement lives in shell.json, and managing that from Nix would undo a
    # choice made in Setup > Plugins at the next rebuild.
    assert not [q for q in seen if q["id"] == decl_id and q["enabled"]], (
        f"{decl_id} came up enabled. The option installs a plugin; enabling "
        "it is runtime state the user owns.")
    print("installed but not enabled -- the user's choice to make")

    # Enabling it must work exactly as for any other plugin, and it is the one
    # thing that would prove the store symlink is second-class if it did not.
    user(f"omarchy plugin enable {decl_id}")
    now = json.loads(user("omarchy-plugin-list --json"))
    assert [q for q in now if q["id"] == decl_id and q["enabled"]], (
        f"{decl_id} could not be enabled")
    print("and it enables like any other plugin")

    # The two mechanisms must not double-install. `plugin add` checks the id
    # against everything already present, so the declared one is found and the
    # clone is refused -- rather than landing a second copy of the same plugin
    # under a temp directory.
    status, out = user(
        "omarchy plugin add file:///srv/bar-toggle --yes 2>&1", check=False)
    assert status != 0 and "already" in out, (
        "`omarchy plugin add` did not refuse a plugin whose id is already "
        f"installed declaratively. It said: {out!r}")
    print("`plugin add` refuses an id the configuration already provides")

    # And removing it works, through upstream's own symlink branch -- the one
    # that makes this design safe rather than a trick. It comes back at the
    # next rebuild, which is what declaring it means.
    out = user(f"omarchy plugin remove {decl_id} --yes 2>&1 || true")
    assert "Unlinked" in out, (
        f"remove did not take the symlink branch: {out!r}")
    machine.succeed(f"test ! -e {decl}")
    print("and `plugin remove` unlinks it rather than trying to delete /nix/store")

    # ---- add each plugin --------------------------------------------------
    for p in PLUGINS:
        print(f"\n--- omarchy plugin add {p['url']} --enable ---")
        print(user(
            f"omarchy plugin add file:///srv/{p['name']} --enable --yes 2>&1",
            timeout=240))

        d = f"/home/omarchy/.config/omarchy/plugins/{p['id']}"
        machine.succeed(f"test -f {d}/manifest.json")
        machine.succeed(f"test -f {d}/BarWidget.qml")
        print(f"cloned into {d}")

    # ---- what the shell itself thinks -------------------------------------
    # listPlugins is answered by the running quickshell, so this is the
    # registry having actually loaded and accepted each manifest -- the thing
    # a bare `test -f` on the clone cannot tell you.
    listed = json.loads(user("omarchy-plugin-list --json"))
    by_id = {p["id"]: p for p in listed}
    for p in PLUGINS:
        got = by_id.get(p["id"])
        assert got, (
            f"the shell does not know about {p['id']} after add --enable. "
            f"It listed: {sorted(by_id)}")
        assert got["enabled"], (
            f"--enable did not enable {p['id']}; the shell reports it "
            "discovered but off.")
        print(f"shell reports {p['id']} enabled, kinds={got['kinds']}")

    # ---- what a plugin can reach once it is loaded ------------------------
    # The generic NixOS risk, and the reason this is a check rather than a
    # note. A plugin is QML running inside the shell process, and it shells out
    # to whatever it likes: omteleprompt's voice mode runs `python3 bin/vad.py`,
    # which in turn runs `parecord` or falls back to `arecord`. On Arch all
    # three are simply present. Here only what pkgs/omarchy/default.nix declares
    # is on PATH, so a plugin that works everywhere else can be the one thing
    # that does not work on nixarchy -- silently, since the failure is inside a
    # QML Process the user never sees.
    #
    # All three are already declared. This is here so that stays true.
    for cmd in ["python3", "parecord", "arecord"]:
        status, _ = machine.execute(f"su omarchy -c 'command -v {cmd}'")
        assert status == 0, (
            f"'{cmd}' is not on a session PATH. omteleprompt's voice mode "
            "shells out to it, and a plugin cannot add its own dependencies "
            "-- it gets whatever pkgs/omarchy/default.nix declares.")
    print("the commands omteleprompt shells out to all resolve")

    # ---- the menu path ----------------------------------------------------
    # Upstream already ships the whole plugin menu -- Setup > Plugins, with
    # add, enable, disable, clone and remove -- so nothing here adds a row.
    # What is worth proving is that nixarchy does not take one away: the menu
    # the user sees is upstream's default with our extension merged over it by
    # id, and that extension rewrites every install.* and remove.* row. An
    # override that reused one of these ids, or a `when: false` landing on the
    # wrong key, would delete the plugin menu silently -- the row simply would
    # not render, with no error anywhere.
    #
    # The menu is read through $OMARCHY_PATH, not from a fixed system path --
    # that is the single indirection point the whole package is built around,
    # so the check resolves it the same way the running code does rather than
    # hardcoding a store path.
    rows = ["setup.plugin", "setup.plugin.add", "setup.plugin.enable",
            "setup.plugin.disable", "setup.plugin.clone", "setup.plugin.remove"]
    probe = (
        'menu="$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc"\n'
        'test -f "$menu" || { echo "NO-MENU $menu"; exit 1; }\n'
        'for row in ' + " ".join(rows) + '; do\n'
        '  grep -q "\\"$row\\"" "$menu" || echo "MISSING $row"\n'
        'done\n')
    missing = user(probe).strip()
    assert not missing, f"upstream's plugin menu rows are not all there: {missing}"
    print(f"upstream's menu still defines all {len(rows)} plugin rows")

    # And our extension must not shadow any of them. Checked as "no key starts
    # with setup.plugin" rather than by merging the two files, because that is
    # the property that actually has to hold: if we never name these ids, we
    # cannot break them.
    ext = machine.succeed("cat /etc/nixarchy/omarchy-menu.jsonc")
    shadowed = [r for r in rows if f'"{r}"' in ext]
    assert not shadowed, (
        f"the nixarchy menu extension overrides {shadowed}. Those rows are "
        "upstream's plugin menu, and an override merged over them by id can "
        "hide them with no error.")
    print("the nixarchy menu extension leaves them alone")

    # The commands those rows invoke, which is the other way the menu breaks:
    # a row that renders and then does nothing when chosen.
    for cmd in ["omarchy-menu-plugin", "omarchy-plugin-add",
                "omarchy-menu-select", "omarchy-notification-send",
                "omarchy-launch-floating-terminal-with-presentation"]:
        status, _ = machine.execute(f"su omarchy -c 'command -v {cmd}'")
        assert status == 0, (
            f"the Setup > Plugins menu calls '{cmd}', which is not on PATH. "
            "The row would render and do nothing.")
    print("every command the plugin rows call resolves")

    # Remove is the one row with a condition on it, and it is a bash builtin
    # -- `compgen -G`, which is not in dash or POSIX sh. With both plugins
    # installed it must say yes; the same expression is checked against an
    # empty directory after the removals below.
    user("compgen -G \"$HOME/.config/omarchy/plugins/*/manifest.json\"")
    print("the Remove Plugin row shows itself while plugins are installed")

    # ---- pictures for the README ------------------------------------------
    # Captured here rather than in docs/capture-screenshots.sh because that
    # one drives a real GL VM over ssh, and this is the only place where two
    # third-party plugins are installed and enabled at once. Frames come from
    # qemu's screendump, which needs no display backend -- the same reason
    # tests/demo.nix uses it.
    import subprocess

    def avg(path):
        out = subprocess.run(
            ["${pkgs.imagemagick}/bin/magick", path, "-resize", "1x1",
             "-format", "%[hex:u]", "info:"],
            capture_output=True, text=True, check=True)
        return tuple(int(out.stdout.strip()[i:i + 2], 16) for i in (0, 2, 4))

    def shoot(name, tries=8):
        """Screenshot, and refuse to keep a black one.

        Every assertion in this file passed once while the screen was black,
        which is how the wallpaper check in tests/session.nix came to exist.
        A screenshot for the README is worse than useless if it is a black
        rectangle, so the frame is retried until something is drawn.
        """
        for attempt in range(tries):
            machine.sleep(4)
            machine.screenshot(name)
            r, g, b = avg(os.path.join(os.environ["out"], name + ".png"))
            print(f"  {name} attempt {attempt}: #{r:02X}{g:02X}{b:02X}")
            if r + g + b > 60:
                return
        raise AssertionError(
            f"{name} came out black after {tries} tries; a screenshot of "
            "nothing is not worth shipping")

    import os

    shoot("plugins-desktop")
    print("captured the desktop with both plugins in the bar")

    # The Setup > Plugins menu itself, opened the way capture-screenshots.sh
    # opens one: the only menu IPC is toggle, so its state is observed rather
    # than assumed.
    user("omarchy-shell shell toggle omarchy.menu "
         "'{\"menu\":\"setup.plugin\"}' || true")
    shoot("plugins-menu")
    print("captured the Setup > Plugins menu")
    user("omarchy-shell shell toggle omarchy.menu "
         "'{\"menu\":\"setup.plugin\"}' || true")

    # ---- and off again ----------------------------------------------------
    # An add that cannot be undone is half a feature, and remove is what a user
    # reaches for when a plugin misbehaves -- which, for arbitrary unsandboxed
    # code running inside the shell process, is the case that matters.
    for p in PLUGINS:
        user(f"omarchy plugin disable {p['id']}")
    off = json.loads(user("omarchy-plugin-list --json"))
    still_on = [q["id"] for q in off
                if q["enabled"] and q["id"] in {p["id"] for p in PLUGINS}]
    assert not still_on, f"disable left these enabled: {still_on}"
    print("disable works for both")

    # The same frame again with both plugins off. Paired with plugins-desktop
    # above this is what actually demonstrates a plugin: the bar loses the
    # widgets. A single screenshot of a bar cannot show which icons came from
    # a plugin, and captioning one as if it could would be a guess dressed up
    # as evidence.
    shoot("plugins-desktop-off")
    print("captured the same bar with both plugins disabled")

    for p in PLUGINS:
        user(f"omarchy plugin remove {p['id']} --yes 2>&1 || true")
        machine.succeed(
            f"test ! -d /home/omarchy/.config/omarchy/plugins/{p['id']}")
    print("remove takes the directories away again")

    # and the Remove Plugin row hides itself again, which is the negative half
    # of the guard checked above. Without this the grep would pass on a `when`
    # that simply always succeeds.
    status, _ = machine.execute(
        "su omarchy -c 'compgen -G \"$HOME/.config/omarchy/plugins/*/manifest.json\"'")
    assert status != 0, (
        "the Remove Plugin row still shows itself with no plugins installed")
    print("and hides itself again once they are gone")
  '';
}
