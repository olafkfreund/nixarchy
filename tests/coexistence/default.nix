{ pkgs, reference }:
# A user's own config, beside nixarchy's: tests/coexistence/fixtures.nix
# names what a user commonly sets, and this checks nixarchy still produces a
# working machine. AGENTS.md#14 is the rule this check exists to enforce.
#
# Two failure modes, two kinds of assertion (spec: 2026-10-02-1164):
# - graphics: hardware.graphics' merged envs (nixos/modules/hardware/
#   graphics.nix) use buildEnv with no ignoreCollisions -- a clash fails the
#   BUILD, and any nixarchy assertion firing on one of these fixtures is
#   itself a failure here: these are configurations we promise work.
# - hyprland-own-package: the titlebars plugin follows programs.hyprland.package.
# - podman-own-config, nvidia-ctk-own: agent-local yields to the user's podman
#   and toolkit settings (#1577).
# - sysctl-razer, sysctl-own-mkdefault, sysctl-own-plain: the user's kernel
#   tuning evaluates and keeps its values beside nixarchy's defaults.
# - openssh: the bundled option hardens sshd, while the user's settings win (#1611).
# - systempkg-own-ffmpeg: environment.systemPackages' buildEnv sets
#   ignoreCollisions = true, so a clash resolves silently by meta.priority
#   then order. The user's own ffmpeg-full must win over nixarchy's ffmpeg.
let
  inherit (pkgs) lib;

  fixtures = import ./fixtures.nix;

  configOf = fixture: (reference.extendModules { modules = [ fixture ]; }).config;

  graphicsNames = [
    "graphics-own-mesa"
    "graphics-32bit"
    "graphics-own-package"
    "graphics-opencl"
  ];

  # "/run/opengl-driver"."L+".argument carries toString of the buildEnv
  # derivation with its store-path context intact, so interpolating it below
  # forces that exact derivation to build -- the same one systemd.tmpfiles
  # would link into place on a real machine.
  driverArgOf =
    c: path:
    let
      settings = c.systemd.tmpfiles.settings.graphics-driver;
      entry = settings.${path}."L+" or null;
    in
    if entry == null then null else entry.argument;

  checkGraphics =
    name:
    let
      c = configOf fixtures.${name};
      failing = builtins.filter (a: !a.assertion) c.assertions;
      env = driverArgOf c "/run/opengl-driver";
      env32 = if c.hardware.graphics.enable32Bit then driverArgOf c "/run/opengl-driver-32" else null;
    in
    {
      inherit name env env32;
      failingMessages = map (a: a.message) failing;
    };

  graphicsChecks = map checkGraphics graphicsNames;

  ffmpegCheck =
    let
      c = configOf fixtures.systempkg-own-ffmpeg;
      failing = builtins.filter (a: !a.assertion) c.assertions;
    in
    {
      name = "systempkg-own-ffmpeg";
      path = c.system.path;
      ffmpegFull = pkgs.ffmpeg-full;
      failingMessages = map (a: a.message) failing;
    };

  # The plugin must be built against the user's Hyprland. Compared by drvPath
  # with the context discarded: this check must not build either Hyprland.
  hyprlandCheck =
    let
      c = configOf fixtures.hyprland-own-package;
      plugin = lib.findFirst (
        p: (p.pname or "") == "omarchy-hyprland-titlebars"
      ) null c.environment.systemPackages;
      theirs = builtins.unsafeDiscardStringContext c.programs.hyprland.package.drvPath;
    in
    plugin != null
    && lib.any (p: builtins.unsafeDiscardStringContext (p.drvPath or "") == theirs) plugin.buildInputs;

  nmConnectivity =
    (configOf fixtures.nm-connectivity-own).networking.networkmanager.settings.connectivity;

  keyboardOwnXkb = configOf fixtures.keyboard-own-xkb;
  keyboardOwnOptions = configOf fixtures.keyboard-own-options;
  keyboardOwnVconsole = configOf fixtures.keyboard-own-vconsole;
  keyboardXkbConsole = configOf fixtures.keyboard-xkb-console;
  keyboardImperative = configOf fixtures.keyboard-imperative;
  keyboardKwinGreeter = configOf fixtures.keyboard-kwin-greeter;

  vconsoleOf = c: c.environment.etc."vconsole.conf".source;
  westonIniOf =
    c:
    let
      cmd = c.services.displayManager.sddm.wayland.compositorCommand;
      path = builtins.head (builtins.match ".* -c (/nix/store/[^ ]+-weston.ini)" cmd);
    in
    # Keep only the ini derivation, not weston's closure from the command.
    builtins.appendContext path (
      lib.filterAttrs (k: _: lib.hasSuffix "weston.ini.drv" k) (builtins.getContext cmd)
    );
  keyboardCheck = name: condition: ''
    if ${condition}
    then
      echo "${name}: ok"
    else
      echo "${name}: FAIL keyboard setting did not stand" >&2
      fail=1
    fi
  '';
  keyboardScripts = [
    (keyboardCheck "keyboard-own-xkb" ''
      grep -Fxq 'XKBLAYOUT=fr' ${shQuote (vconsoleOf keyboardOwnXkb)} &&
      grep -Fxq 'keymap_layout=fr' ${shQuote (westonIniOf keyboardOwnXkb)}
    '')
    (keyboardCheck "keyboard-own-options" ''
      grep -Fxq 'keymap_options=grp:caps_toggle' ${shQuote (westonIniOf keyboardOwnOptions)}
    '')
    (keyboardCheck "keyboard-own-vconsole" ''
      grep -Fxq 'KEYMAP=own' ${shQuote (vconsoleOf keyboardOwnVconsole)}
    '')
    (keyboardCheck "keyboard-xkb-console" ''
      grep -Eq '^KEYMAP=.*xkb-console-keymap' ${shQuote (vconsoleOf keyboardXkbConsole)} &&
      grep -Fxq 'XKBLAYOUT=de' ${shQuote (vconsoleOf keyboardXkbConsole)}
    '')
    (keyboardCheck "keyboard-imperative" (
      if keyboardImperative.environment.etc ? "vconsole.conf" then "false" else "true"
    ))
    (keyboardCheck "keyboard-kwin-greeter" (
      (
        if
          lib.hasInfix "kwin" (
            builtins.unsafeDiscardStringContext keyboardKwinGreeter.services.displayManager.sddm.wayland.compositorCommand
          )
        then
          "true"
        else
          "false"
      )
      + "&& grep -Fxq 'XKBLAYOUT=de' ${shQuote (vconsoleOf keyboardKwinGreeter)}"
    ))
  ];

  chromiumEtc = (configOf fixtures.chromium-own-policy).environment.etc;
  chromiumScript =
    if
      chromiumEtc ? "chromium/policies/managed/extra.json"
      && chromiumEtc ? "chromium/policies/managed/omarchy.json"
    then
      ''
        echo "chromium-own-policy: ok"
      ''
    else
      ''
        echo "chromium-own-policy: FAIL extra.json and omarchy.json are not both in etc" >&2
        fail=1
      '';

  # agent-local (#1577): their podman and their toolkit choice stand, and no
  # nixarchy assertion fires on either machine.
  agentLocalCheck =
    name: holds:
    let
      c = configOf fixtures.${name};
      failing = builtins.filter (a: !a.assertion) c.assertions;
    in
    if failing != [ ] then
      ''
        echo ${shQuote "${name}: FAIL nixarchy assertion fired: ${lib.concatStringsSep "; " (map (a: a.message) failing)}"} >&2
        fail=1
      ''
    else if holds c then
      ''
        echo ${shQuote "${name}: ok"}
      ''
    else
      ''
        echo ${shQuote "${name}: FAIL the user's own setting did not stand"} >&2
        fail=1
      '';
  inputAddonPnames = [
    "fcitx5-mozc"
    "fcitx5-hangul"
    "fcitx5-chewing"
    "fcitx5-table-extra"
    "fcitx5-chinese-addons"
  ];

  ibusHolds =
    c:
    c.i18n.inputMethod.fcitx5.addons == [ ]
    && lib.hasPrefix "ibus" (lib.getName c.i18n.inputMethod.package)
    && !(c.systemd.user.services ? omarchy-fcitx5);

  agentLocalScripts = [
    (agentLocalCheck "podman-own-config" (
      c: c.virtualisation.podman.enable && c.virtualisation.podman.dockerCompat
    ))
    (agentLocalCheck "nvidia-ctk-own" (c: !c.hardware.nvidia-container-toolkit.enable))
    (agentLocalCheck "input-own-ibus" ibusHolds)
    (agentLocalCheck "input-default-ibus" ibusHolds)
    (agentLocalCheck "input-disabled" (
      c: c.i18n.inputMethod.fcitx5.addons == [ ] && !(c.systemd.user.services ? omarchy-fcitx5)
    ))
    (agentLocalCheck "input-own-addon" (
      c:
      let
        pnames = map (p: p.pname or "") c.i18n.inputMethod.fcitx5.addons;
      in
      lib.all (n: builtins.elem n pnames) ([ "fcitx5-rime" ] ++ inputAddonPnames)
    ))
    (agentLocalCheck "input-no-addons" (c: c.i18n.inputMethod.fcitx5.addons == [ ]))
    (agentLocalCheck "input-own-profile" (
      c: !(c.systemd.user.services.omarchy-fcitx5.serviceConfig ? ExecStartPre)
    ))
    (agentLocalCheck "preinstalls-exclude-retired" (_: true))
    (agentLocalCheck "xdg-mime-own-pdf" (
      c: c.xdg.mime.defaultApplications."application/pdf" == "own.desktop"
    ))
  ];
  opensshScripts = [
    (agentLocalCheck "openssh-on-reference" (
      c:
      !c.services.openssh.settings.PasswordAuthentication
      && !c.services.openssh.settings.KbdInteractiveAuthentication
      && !c.security.pam.services.sshd.unixAuth
    ))
    (agentLocalCheck "openssh-own-passwords" (
      c:
      c.services.openssh.settings.PasswordAuthentication
      && !c.services.openssh.settings.KbdInteractiveAuthentication
    ))
    (agentLocalCheck "openssh-own-null" (c: c.services.openssh.settings.PasswordAuthentication == null))
    (agentLocalCheck "openssh-plain-line" (
      c:
      c.services.openssh.settings.PasswordAuthentication
      && c.services.openssh.settings.KbdInteractiveAuthentication
    ))
  ];

  opensshMkDefault =
    let
      r = builtins.tryEval (configOf fixtures.openssh-own-mkdefault)
        .services.openssh.settings.PasswordAuthentication;
    in
    if r.success then
      ''
        echo "openssh-own-mkdefault: FAIL expected the mkDefault conflict: the module's priority changed" >&2
        fail=1
      ''
    else
      ''
        echo "openssh-own-mkdefault: ok, a loud evaluation error"
      '';

  # boot.kernel.sysctl merges through mergeOneOption, so a tie is a throw. Forced
  # to a bool inside tryEval, so it names the fixture and doesn't abort the check.
  sysctlCheck =
    name: want:
    let
      sysctl = (configOf fixtures.${name}).boot.kernel.sysctl;
      got = builtins.tryEval (lib.all (k: sysctl.${k} == want.${k}) (builtins.attrNames want));
    in
    if !got.success then
      ''
        echo ${shQuote "${name}: FAIL did not evaluate: two definitions tie at one priority"} >&2
        fail=1
      ''
    else if got.value then
      ''
        echo ${shQuote "${name}: ok"}
      ''
    else
      ''
        echo ${shQuote "${name}: FAIL the user's own value did not stand"} >&2
        fail=1
      '';
  sysctlScripts = [
    (sysctlCheck "sysctl-razer" {
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_notsent_lowat" = 16384;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_fastopen" = 3;
    })
    (sysctlCheck "sysctl-own-mkdefault" {
      "net.core.default_qdisc" = "fq_codel";
      "net.ipv4.tcp_congestion_control" = "cubic";
      "vm.swappiness" = 10;
    })
    (sysctlCheck "sysctl-own-plain" {
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "cubic";
    })
  ];

  shQuote = lib.escapeShellArg;

  hyprlandScript =
    if hyprlandCheck then
      ''
        echo "hyprland-own-package: ok"
      ''
    else
      ''
        echo "hyprland-own-package: FAIL omarchy-hyprland-titlebars is not built against the user's programs.hyprland.package" >&2
        fail=1
      '';

  graphicsScriptOf =
    gc:
    let
      failBody =
        if gc.failingMessages != [ ] then
          ''
            echo ${shQuote "${gc.name}: FAIL nixarchy assertion fired: ${lib.concatStringsSep "; " gc.failingMessages}"} >&2
            fail=1
          ''
        else
          ''
            ok=1
            for env in ${shQuote gc.env} ${if gc.env32 == null then "" else shQuote gc.env32}; do
              if [ -n "$env" ]; then
                if ! ls "$env"/share/glvnd/egl_vendor.d/*mesa*.json >/dev/null 2>&1; then
                  echo ${shQuote "${gc.name}: FAIL no mesa egl_vendor.d json under $env"} >&2
                  ok=0
                fi
              fi
            done
            if [ "$ok" = 1 ]; then
              echo ${shQuote "${gc.name}: ok"}
            else
              fail=1
            fi
          '';
    in
    failBody;

  ffmpegScript =
    if ffmpegCheck.failingMessages != [ ] then
      ''
        echo ${shQuote "systempkg-own-ffmpeg: FAIL nixarchy assertion fired: ${lib.concatStringsSep "; " ffmpegCheck.failingMessages}"} >&2
        fail=1
      ''
    else
      ''
        target=$(readlink -f "${ffmpegCheck.path}/bin/ffmpeg")
        case "$target" in
          ${ffmpegCheck.ffmpegFull}/*|${ffmpegCheck.ffmpegFull})
            echo "systempkg-own-ffmpeg: ok"
            ;;
          *)
            echo "systempkg-own-ffmpeg: FAIL bin/ffmpeg resolved to $target, not the user's ffmpeg-full" >&2
            fail=1
            ;;
        esac
      '';

  ownHypeScript =
    let
      c = configOf fixtures.systempkg-own-hype;
      failing = builtins.filter (a: !a.assertion) c.assertions;
    in
    if failing != [ ] then
      ''
        echo ${shQuote "systempkg-own-hype: FAIL nixarchy assertion fired: ${lib.concatStringsSep "; " (map (a: a.message) failing)}"} >&2
        fail=1
      ''
    else
      ''
        if grep -q own-hype-marker "${c.system.path}/bin/hype"; then
          echo "systempkg-own-hype: ok"
        else
          echo "systempkg-own-hype: FAIL user's hype binary did not win" >&2
          fail=1
        fi
      '';

  nmScript =
    if nmConnectivity.uri == "http://example.invalid/check" && nmConnectivity.enabled == false then
      ''
        echo "nm-connectivity-own: ok"
      ''
    else
      ''
        echo ${shQuote "nm-connectivity-own: FAIL the user's connectivity setting lost: ${builtins.toJSON nmConnectivity}"} >&2
        fail=1
      '';
in
pkgs.runCommand "nixarchy-coexistence"
  {
    # Named so the drivers env derivations and system.path are build inputs,
    # not just strings -- see driverArgOf's comment.
    passthru.fixtures = fixtures;
  }
  ''
    fail=0
    ${lib.concatMapStringsSep "\n" graphicsScriptOf graphicsChecks}
    ${ffmpegScript}
    ${ownHypeScript}
    ${nmScript}
    ${hyprlandScript}
    ${chromiumScript}
    ${lib.concatStrings agentLocalScripts}
    ${lib.concatStrings sysctlScripts}
    ${lib.concatStrings opensshScripts}
    ${opensshMkDefault}
    ${lib.concatStrings keyboardScripts}
    if [ "$fail" = 1 ]; then
      exit 1
    fi
    touch $out
  ''
