{
  lib,
  stdenvNoCC,
  src,
  version,
  # Runtime dependencies, derived by grepping every script in upstream `bin/`
  # for the commands it shells out to. Regenerate with:
  #   nix run .#deps-report
  bash,
  coreutils,
  util-linux,
  findutils,
  gnused,
  gnugrep,
  gawk,
  jq,
  gum,
  curl,
  socat,
  systemd,
  glib,
  xdg-utils,
  libnotify,
  # Wayland / Hyprland session
  hyprland,
  hyprpicker,
  hyprsunset,
  hyprlock,
  quickshell,
  wl-clipboard,
  wtype,
  grim,
  slurp,
  # Media / capture
  imagemagick,
  ffmpeg,
  gpu-screen-recorder,
  mpv,
  yt-dlp,
  tesseract,
  zbar,
  qrencode,
  # Hardware controls
  pciutils,
  brightnessctl,
  ddcutil,
  pulseaudio,
  # provides `pactl`
  wireplumber,
  # provides `wpctl`
  playerctl,
  bluez,
  # provides `bluetoothctl`
  networkmanager,
  # provides `nmcli`
  # Shell tooling the CLI assumes is present
  fastfetch,
  btop,
  ripgrep,
  fd,
  bat,
  fzf,
  tmux,
  inotify-tools,
  python3,
  # Application tier. These are commands the bins invoke directly, not
  # libraries: omarchy-launch-terminal execs `uwsm-app -- xdg-terminal-exec`,
  # theme-set retints whichever terminals are present, and the menus launch
  # the file manager, browser and editor by name.
  xdg-terminal-exec,
  uwsm,
  foot,
  chromium,
  nautilus,
  neovim,
  mise,
  lazygit,
  lazydocker,
  eza,
  zoxide,
  starship,
  gtk3,
  udiskie,
  git,
  less,
  man-db,
  unzip,
  pamixer,
  alsa-utils,
  imv,
  evince,
  libretro-core-info,
  libretro-shaders-slang,
  retroarch-joypad-autoconfig,
  localsend,
  runCommand,
  writeText,
  fontconfig,
  tldr,
  inxi,
  ffmpegthumbnailer,
  vips,
  file,
  libxkbcommon,
  xdg-user-dirs,
  satty,
  wl-screenrec,
  # Branding: this is a NixOS port, so the menu button wears the snowflake.
  nixos-icons,
}:
let
  # Everything the 438 scripts in bin/ invoke. Kept explicit rather than
  # pulled from a generated file: a missing entry should be a readable diff,
  # not a silent PATH lookup that only fails on someone else's machine.
  runtimeDeps = [
    bash
    coreutils
    util-linux
    # omarchy-install-font asks it whether a family is installed before
    # deciding between switching to it and explaining how to add it
    fontconfig
    findutils
    gnused
    gnugrep
    gawk
    jq
    gum
    curl
    socat
    systemd
    glib
    xdg-utils
    libnotify
    hyprland
    hyprpicker
    hyprsunset
    hyprlock
    quickshell
    wl-clipboard
    wtype
    grim
    slurp
    imagemagick
    ffmpeg
    gpu-screen-recorder
    mpv
    yt-dlp
    tesseract
    zbar
    qrencode
    # `lspci`. Eight omarchy-hw-* guards ask it what hardware is present, and a
    # missing command is indistinguishable from absent hardware to every one of
    # them: on a live hybrid-GPU laptop omarchy-hw-hybrid-gpu counted zero GPUs
    # and the menu simply had no GPU row. It belongs here rather than in the
    # module's systemPackages, because it is this package's own scripts that
    # call it -- nothing a user types needs lspci on PATH.
    pciutils
    brightnessctl
    ddcutil
    pulseaudio
    wireplumber
    playerctl
    bluez
    networkmanager
    fastfetch
    btop
    ripgrep
    fd
    bat
    fzf
    tmux
    inotify-tools
    python3

    # Application tier. Omitted from the first cut of this list, which is why
    # every terminal launch failed with `Command not found: xdg-terminal-exec`
    # while the bar itself rendered fine -- the utility tier was complete and
    # the application tier was entirely absent.
    #
    # foot is the only terminal in upstream's base.packages, so it is the one
    # xdg-terminal-exec resolves to by default. alacritty, ghostty and kitty
    # are supported by upstream's theming but not installed by it; add them
    # through environment.systemPackages if you want one of those instead.
    xdg-terminal-exec
    uwsm
    foot
    chromium
    nautilus
    neovim
    mise
    lazygit
    lazydocker
    eza
    zoxide
    starship

    # Cross-checked against upstream's own install/omarchy-base.packages
    # rather than against another hand-grep of the bins. That manifest is what
    # Omarchy declares it needs; curating the list by eye is what produced one
    # missing command per boot.
    gtk3 # gtk-launch, used by every omarchy-install-* to start the app
    udiskie # autostart.lua execs this on every login
    git # theme install, update checks
    less
    man-db
    unzip
    pamixer # audio bins
    alsa-utils # amixer/alsamixer
    imv # image viewer the menus open
    evince # PDF viewer
    # See pkgs/omarchy/pacman-shim.sh: turns `pacman: command not found` into
    # a pointer at the Nix equivalent, for the ~15 upstream bins that still
    # call it. nixpkgs does carry a `pacman`, so a user who installs that one
    # gets a systemPackages collision -- which is the correct loud failure.
    (runCommand "pacman-shim" { } ''
      install -Dm755 ${./pacman-shim.sh} $out/bin/pacman
    '')

    # nixpkgs names the binary localsend_app; omarchy-menu-share and the
    # Nautilus extension both look for `localsend`. Without the alias, Share ->
    # Receive reports: Command not found: "localsend"
    (runCommand "localsend-alias" { } ''
      mkdir -p $out/bin
      ln -s ${localsend}/bin/localsend_app $out/bin/localsend
    '')
    tldr
    inxi # omarchy-debug
    ffmpegthumbnailer # nautilus thumbnails
    vips # omarchy-menu-images, the wallpaper picker, shells out to `vips`

    # Found by auditing the running VM's PATH against what the scripts call,
    # rather than by reading base.packages again.
    file # omarchy-webapp-install: "file: command not found"
    libxkbcommon # xkbcli, for the keyboard-layout widget
    xdg-user-dirs # xdg-user-dirs-update
    satty # screenshot annotation
    wl-screenrec # screen recording
  ];
  # arch-name<TAB>kind<TAB>attr<TAB>note, one per line. Apps come from
  # data/apps.nix so the two cannot drift; everything the menu does not select
  # -- fonts, the packages omarchy-install-dev-env adds behind a language --
  # comes from data/arch-extras.nix.
  archTable =
    let
      apps = import ../../data/apps.nix;
      extras = import ../../data/arch-extras.nix;
      appRows = lib.mapAttrsToList (name: app: "${app.arch}\tapp\t${name}\t") (
        lib.filterAttrs (_: a: a ? arch) apps
      );
      extraRows = lib.mapAttrsToList (arch: e: "${arch}\t${e.kind}\t${e.attr}\t${e.note or ""}") extras;
    in
    writeText "nixarchy-arch-packages.tsv" (lib.concatStringsSep "\n" (appRows ++ extraRows) + "\n");
in
stdenvNoCC.mkDerivation {
  pname = "omarchy";
  inherit version src;

  strictDeps = true;

  # Not for linking -- this is what patchShebangs resolves against. With
  # strictDeps set it looks interpreters up in $HOST_PATH, which contains only
  # buildInputs; without bash here it finds nothing to rewrite `#!/bin/bash`
  # to and silently leaves all 425 scripts pointing at a path that does not
  # exist on NixOS. The build still succeeds, which is why CI asserts on it.
  buildInputs = [
    bash
    python3
  ];

  # Build-time only, and separate from buildInputs above: strictDeps keeps the
  # two apart, and these are for generating the greeter wordmark, not for
  # patchShebangs to resolve against.
  nativeBuildInputs = [
    python3
    imagemagick
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
                runHook preInstall

                # Upstream resolves everything through $OMARCHY_PATH, so the tree is kept
                # intact under share/ rather than being split across the FHS-ish outputs.
                # See default/hypr/bootstrap.lua, which builds its Lua package.path from it.
                #
                # Copied wholesale minus dev-only directories, rather than as an allowlist
                # of the directories that look important. An allowlist silently drops what
                # upstream adds next -- and already did: the root icon.png/logo.txt that
                # omarchy-show-logo, omarchy-branding-about and omarchy-plymouth-set read,
                # one of which default/chromium/extensions/copy-url symlinks to.
                mkdir -p $out/share/omarchy
                cp -r . $out/share/omarchy/
                rm -rf $out/share/omarchy/{.git,.github,docs,manual,test,plans,agents}

                # bin/ is a symlink farm, NOT wrapProgram'd. `bin/omarchy` discovers its
                # subcommands by grepping the first 80 lines of each sibling for
                # `# omarchy:summary=` metadata; a generated wrapper script has no such
                # comment, so wrapping every bin makes the CLI report zero commands.
                # Runtime deps reach the scripts through the NixOS module's systemPackages
                # instead -- see passthru.runtimeDeps.
                mkdir -p $out/bin
                for script in $out/share/omarchy/bin/*; do
                  ln -s "$script" "$out/bin/$(basename "$script")"
                done

                # Upstream installs its bundled icon font to /usr/share/fonts/omarchy.
                # Nothing on NixOS scans $OMARCHY_PATH for fonts, so without this the
                # menu button renders U+E900 as tofu -- a literal empty box in the bar.
                # See default/fonts/omarchy/README.md for the private-use glyph map.
                install -Dm644 default/fonts/omarchy/omarchy.ttf \
                  $out/share/fonts/truetype/omarchy.ttf

                # $OMARCHY_THEMES_PATH is a store path, and `cp -r` preserves its modes --
                # including r-xr-xr-x on directories. Upstream copies the chosen theme
                # into ~/.local/state/omarchy/current/theme, so on NixOS that staging
                # directory lands read-only and the NEXT theme switch cannot clean it up:
                #
                #   rm: cannot remove '.../current/theme/backgrounds/0-winding-road.jpg':
                #   Permission denied
                #
                # On Arch the source lives in /usr/share with writable modes, so upstream
                # never has to think about it.
                substituteInPlace $out/share/omarchy/bin/omarchy-theme-set \
                  --replace-fail \
                    'cp -r "$OMARCHY_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/"' \
                    'cp -r --no-preserve=mode "$OMARCHY_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/"'

                # The banner every omarchy-launch-floating-terminal-with-presentation
                # prints. It says NIXARCHY so it is obvious which of the two is running --
                # the letters ARCHY are sliced from upstream's own logo.txt rather than
                # redrawn, so only NIX is new.
                install -Dm444 ${./branding/logo.txt} $out/share/omarchy/logo.txt

                # Omarchy ships wallpapers up to 7680px wide. Anything wider than
                # GL_MAX_TEXTURE_SIZE cannot become a texture, and the background renders
                # black with no error anywhere -- Qt reports the image Ready, the layer
                # surface exists at full size, and nothing is drawn. 4096 is the limit on
                # llvmpipe and on plenty of integrated GPUs, and 5 of the 8 backgrounds in
                # the default theme are over it.
                #
                # sourceSize caps what Qt decodes to. Setting only the width keeps the
                # aspect ratio, and 4096 is wider than any display this would be shown on,
                # so there is no visible loss -- and every machine decodes less. A plain
                # constant rather than anything derived from Screen: Screen is an attached
                # property that does not resolve inside an Image, and a QML error here
                # would take out the whole background rather than just the size hint.
                for prop in displayedBackground oldBackground incomingBackground; do
                  substituteInPlace $out/share/omarchy/shell/plugins/background/Background.qml \
                    --replace-fail \
                      "source: root.imageUrl(root.$prop)" \
                      "source: root.imageUrl(root.$prop)
                    sourceSize.width: 4096"
                done

                # Same store-mode problem as omarchy-theme-set, in a different script.
                # omarchy-plugin-clone copies a first-party plugin out of $OMARCHY_PATH
                # with `cp -aL`, and -a preserves mode -- so its staging directory lands
                # read-only and it cannot clean up after itself:
                #
                #   rm: cannot remove '.../plugins/.clone.XXXXXX/manifest.json':
                #   Permission denied
                #
                # The clone never completes and nothing appears in the plugin list.
                sed -i 's/cp -aL /cp -aL --no-preserve=mode /g' \
                  $out/share/omarchy/bin/omarchy-plugin-clone

                # The third site of the same store-mode problem, and the expensive one.
                #
                # These two copies land 17 desktop files in ~/.local/share/applications
                # at the store's 444, so the NEXT run cannot rewrite its own output:
                #
                #   cp: cannot create regular file '.../Basecamp.desktop': Permission denied
                #
                # omarchy-provision-user runs under `set -euo pipefail` and calls this
                # eleven lines before `omarchy-done mark finalize-user`, so it aborted
                # here, the marker was never written, and provisioning re-ran and
                # re-failed on every login -- with nothing after the call ever running
                # once. ~/.local/state/omarchy/done did not exist on a machine that had
                # been in daily use for months.
                #
                # -f as well as --no-preserve=mode: the mode flag only stops NEW copies
                # from landing read-only, and every machine installed before this
                # already has 444 files that cp cannot open for writing even as their
                # owner. -f unlinks and retries, which repairs those in place.
                substituteInPlace $out/share/omarchy/bin/omarchy-refresh-applications \
                  --replace-fail \
                    'cp "$OMARCHY_PATH"/applications/*.desktop' \
                    'cp -f --no-preserve=mode "$OMARCHY_PATH"/applications/*.desktop' \
                  --replace-fail \
                    'cp "$OMARCHY_PATH/default/alacritty/Alacritty.desktop"' \
                    'cp -f --no-preserve=mode "$OMARCHY_PATH/default/alacritty/Alacritty.desktop"'

                # Both launchers accept a handful of browser desktop-file names and fall
                # back to "chromium.desktop" for anything else. nixpkgs ships chromium's
                # entry as chromium-browser.desktop, so xdg-settings returns a name that
                # matches nothing, gets replaced by one that does not exist, and every web
                # app fails with
                #
                #   Error: Path "--app=https://..." does not exist!
                # Only launch-webapp has this list; launch-browser uses whatever
                # xdg-settings returns and needed nothing beyond the path fix below.
                substituteInPlace $out/share/omarchy/bin/omarchy-launch-webapp \
                  --replace-fail \
                    'google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium*) ;;' \
                    'google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium* | chromium*) ;;'

                # omarchy-launch-webapp and omarchy-launch-browser find the browser by
                # reading its .desktop out of {~/.local,~/.nix-profile,/usr}/share/
                # applications. On NixOS a system package's desktop file is under
                # /run/current-system/sw and a per-user one under /etc/profiles/per-user,
                # so that search finds nothing, the command substitution collapses to
                # empty, and the launcher runs `uwsm-app -- --app=<url>`:
                #
                #   Error: Path "--app=https://search.nixos.org/options" does not exist!
                for f in omarchy-launch-webapp omarchy-launch-browser; do
                  substituteInPlace $out/share/omarchy/bin/$f \
                    --replace-fail \
                      '{~/.local,~/.nix-profile,/usr}/share/applications' \
                      '{~/.local,~/.nix-profile,/etc/profiles/per-user/$USER,/run/current-system/sw,/usr}/share/applications'
                done

                # RetroArch loads its cores from /usr/lib/libretro upstream. nixpkgs puts
                # them inside the wrapper's own store path -- and which cores exist depends
                # on how the package was built -- so the directory has to be resolved at
                # runtime. Without this, RetroArch installs and then reports
                #
                #   No RetroArch cores found   /usr/lib/libretro
                for f in omarchy-games-retro-install omarchy-install-gaming-retroarch; do
                  substituteInPlace $out/share/omarchy/bin/$f \
                    --replace-quiet '/usr/lib/libretro' '$(omarchy-retroarch-cores)'
                done

                # `omarchy version` said "dev".
                #
                # Upstream reads the version from `pacman -Q omarchy`, and treats an
                # OMARCHY_PATH that is not /usr/share/omarchy as a developer running from a
                # git checkout -- printing "dev", or "dev (abc1234)" when it can read a
                # commit. On nixarchy the path is always a store path and there is never a
                # .git, so it took the developer branch every time and printed a bare
                # "dev".
                #
                # That is not just cosmetic: etc/fastfetch/config.jsonc calls this, so the
                # splash Omarchy prints in every new terminal reported the desktop as an
                # unversioned dev checkout. omarchy-snapshot and omarchy-channel-current
                # read it too.
                substituteInPlace $out/share/omarchy/bin/omarchy-version \
                  --replace-fail 'hash=$(git -C "$omarchy_path" rev-parse --short HEAD 2>/dev/null || true)' \
                  'echo "${version}"; exit 0'

                # Vulkan was never detected.
                #
                # Upstream looks in /usr/share/vulkan/icd.d, which does not exist on NixOS:
                # the ICD manifests live under /run/opengl-driver, put there by
                # hardware.graphics. So this answered "no Vulkan" on a machine with a dozen
                # of them, and omarchy-voxtype-install -- the only caller -- took its
                # no-Vulkan path on every machine.
                substituteInPlace $out/share/omarchy/bin/omarchy-hw-vulkan \
                  --replace-fail '/usr/share/vulkan/icd.d' '/run/opengl-driver/share/vulkan/icd.d'

                # RetroArch was configured to look in /usr/share/libretro for everything
            # except its cores.
            #
            # The cores path was fixed long ago; the other eight settings this script
            # writes into retroarch.cfg were not, so a RetroArch installed through the
            # selection came up with no core descriptions, no shaders and no controller
            # profiles -- each one a silent absence rather than an error.
            #
            # Three have real packages in nixpkgs and now point at them. The rest --
            # overlays, the on-screen-keyboard overlays, and the three databases --
            # have none, so they point into the user's own data directory instead of a
            # directory that cannot exist. That is where RetroArch's own online updater
            # downloads them to, which turns "permanently empty" into "empty until you
            # fetch them".
            substituteInPlace $out/share/omarchy/bin/omarchy-install-gaming-retroarch \
              --replace-fail '"/usr/share/libretro/info"' \
              '"${libretro-core-info}/share/retroarch/cores"' \
              --replace-fail '"/usr/share/libretro/shaders/shaders_slang"' \
              '"${libretro-shaders-slang}/share/libretro/shaders/shaders_slang"' \
              --replace-fail '"/usr/share/libretro/autoconfig"' \
              '"${retroarch-joypad-autoconfig}/share/libretro/autoconfig"' \
              --replace-fail '"/usr/share/libretro/overlays/keyboards"' \
              '"$HOME/.local/share/retroarch/overlays/keyboards"' \
              --replace-fail '"/usr/share/libretro/overlays"' \
              '"$HOME/.local/share/retroarch/overlays"' \
              --replace-fail '"/usr/share/libretro/database/rdb"' \
              '"$HOME/.local/share/retroarch/database/rdb"' \
              --replace-fail '"/usr/share/libretro/database/cht"' \
              '"$HOME/.local/share/retroarch/database/cht"' \
              --replace-fail '"/usr/share/libretro/database/cursors"' \
              '"$HOME/.local/share/retroarch/database/cursors"'

            # One shader preset the loop above missed, named in full rather than under
            # the directory it lives in.
            substituteInPlace $out/share/omarchy/bin/omarchy-install-gaming-retroarch \
              --replace-fail '/usr/share/libretro/shaders/shaders_slang/crt/crt-royale.slangp' \
              '${libretro-shaders-slang}/share/libretro/shaders/shaders_slang/crt/crt-royale.slangp'

            # "Restart to finish the update" was going to be the answer every time.
            #
            # Upstream decides whether the kernel changed by walking
            # /usr/lib/modules/*/vmlinuz and asking pacman who owns each one. Here the
            # glob matches nothing, so the loop never runs and kernel_updated keeps the
            # `true` it was initialised with -- a reboot prompt after every update,
            # whether or not anything needing one changed.
            #
            # NixOS answers this exactly rather than by inference: /run/booted-system
            # is what is running and /run/current-system is what is activated, so the
            # kernels differing is precisely "you are not running what you installed".
            substituteInPlace $out/share/omarchy/bin/omarchy-update-restart \
              --replace-fail 'for kernel in /usr/lib/modules/*/vmlinuz; do' \
              'for kernel in /run/current-system/kernel; do' \
              --replace-fail 'if [[ -f $kernel ]] && pacman -Qo "$kernel" &>/dev/null; then' \
              'if [[ -e $kernel ]]; then
              if [[ "$(readlink -f /run/booted-system/kernel)" == "$(readlink -f "$kernel")" ]]; then
                kernel_updated=false
              fi
              continue
            fi
            if false; then'

            # The speaker-tuning limiter was never found.
            #
            # omarchy-audio-tuning tests for the LSP limiter at a fixed path under
            # /usr/lib/lv2. NixOS keeps LV2 plugins in the store and points hosts at
            # them with LV2_PATH, so that test failed on every machine -- including
            # ones with the plugin installed -- and the tuning that protects laptop
            # speakers silently never applied.
            #
            # Searched rather than pinned, and lsp-plugins is deliberately NOT added as
            # a runtime dependency: its closure is over 500MB, which is a great deal to
            # put on every install for a feature that matters on some laptops. Anyone
            # who wants it installs it, and this then finds it.
            substituteInPlace $out/share/omarchy/bin/omarchy-audio-tuning \
              --replace-fail 'ls /usr/lib/lv2/lsp-plugins.lv2/limiter_stereo.ttl >/dev/null 2>&1 || {' \
              'lv2_found=""
            for lv2_dir in $(printf "%s" "$LV2_PATH" | tr ":" " ") \
              /run/current-system/sw/lib/lv2 "$HOME/.nix-profile/lib/lv2"; do
              if [ -e "$lv2_dir/lsp-plugins.lv2/limiter_stereo.ttl" ]; then
                lv2_found=1
                break
              fi
            done
            [ -n "$lv2_found" ] || {' \
              --replace-fail 'echo "lsp-plugins-lv2 is required for the tuning limiter." >&2' \
              'echo "The tuning limiter needs the LSP LV2 plugins, which are not installed." >&2
              echo "Add pkgs.lsp-plugins to environment.systemPackages and rebuild." >&2'

            # Every unit in default/systemd/user has ExecStart=/usr/bin/..., and one
            # of them is not a dead file: the script above installs
            # omarchy-speaker-tuning.service from there into ~/.config/systemd/user
            # every time the tuning is switched on, so that /usr path travels out of
            # the store and into a real unit. systemd requires an absolute ExecStart,
            # so there is nothing to fall back to on PATH -- the service would fail to
            # start with status=203/EXEC and the tuning would never appear.
            #
            # /run/current-system/sw rather than pipewire's store path, for the same
            # reason install/user/xcompose.sh points at /etc: what this writes into
            # $HOME outlives the generation that wrote it, and a store path would go
            # stale the first time that generation was collected, taking the
            # already-installed tuning down with it. pipewire is deliberately not a
            # dependency of this package either -- it is the audio daemon the running
            # system provides, and services.pipewire.enable is what puts it there.
            substituteInPlace $out/share/omarchy/default/systemd/user/omarchy-speaker-tuning.service \
              --replace-fail 'ExecStart=/usr/bin/pipewire' \
              'ExecStart=/run/current-system/sw/bin/pipewire'

            # 1Password'"'"'s Chromium extension, installed the way NixOS installs one.
            #
            # Upstream drops a JSON stub into /usr/share/chromium/extensions with sudo,
            # which Chromium reads on startup. That directory is in the store here and
            # the write simply fails. NixOS has the same feature as an option, so the
            # answer is to name it rather than to find somewhere writable to imitate it.
            #
            # echo lines rather than the heredoc this was first written as. A heredoc
            # terminator has to sit at column 0 of the generated script, and this text
            # is indented twice over -- once as an indented Nix string and once as the
            # body of a shell function -- so bash never found EXTMSG and the whole
            # script stopped parsing:
            #
            #   syntax error: unexpected end of file
            #
            # substituteInPlace cannot see that and neither can the build: the
            # installer was a syntax error for as long as this patch existed. `bash -n`
            # over the patched bins is what catches this class, and nothing else does.
            substituteInPlace $out/share/omarchy/bin/omarchy-install-service-1password \
              --replace-fail 'sudo mkdir -p "$EXTENSION_DIR"' \
              'echo "Chromium extensions are declared on NixOS, not dropped into a directory." >&2
              echo "" >&2
              echo "  Add the extension to your configuration:" >&2
              echo "" >&2
              echo "    programs.chromium.enable = true;" >&2
              echo "    programs.chromium.extensions = [ \"$EXTENSION_ID\" ];" >&2
              echo "" >&2
              echo "  then rebuild. 1Password itself is handled above." >&2
              return' \
              --replace-fail 'printf '"'"'{ "external_update_url": "%s" }\n'"'"' "$WEBSTORE_UPDATE_URL" | sudo tee "$EXTENSION_FILE" >/dev/null' \
              ':' \
              --replace-fail 'sudo chmod 644 "$EXTENSION_FILE"' ':' \
          --replace-fail 'EXTENSION_DIR="/usr/share/chromium/extensions"' \
          'EXTENSION_DIR=""  # declared, not written -- see the message below'

            # Every web app failed with
        #
        #   Error: Path "--app=https://messages.google.com/..." does not exist!
        #
        # omarchy-launch-webapp resolves the browser by reading Exec= out of a
        # .desktop file and passing the binary to uwsm-app. When that lookup finds
        # nothing the substitution is empty, so `--app=<url>` lands where the
        # program should be and uwsm-app reports it as a missing path.
        #
        # It found nothing because the fallback names chromium.desktop, which is
        # what Arch installs. NixOS calls it chromium-browser.desktop. The default
        # browser here was a Chrome web-app profile entry -- chrome-<id>-Default
        # -- which matches none of the patterns upstream lists, so every launch
        # took the fallback and every web app was broken: all nine that call this
        # directly, plus HEY and Zoom through their handlers.
        #
        # Both names are tried rather than one swapped for the other, because
        # someone may have a chromium.desktop of their own and upstream's name
        # should keep working.
        substituteInPlace $out/share/omarchy/bin/omarchy-launch-webapp \
          --replace-fail '*) browser="chromium.desktop" ;;' \
          '*) browser="chromium-browser.desktop" ;;'

        # And say so when the browser cannot be resolved at all, rather than
        # handing uwsm-app an --app= flag to run as a program. The message it
        # produced named the URL, which reads like the URL is at fault.
        substituteInPlace $out/share/omarchy/bin/omarchy-launch-webapp \
          --replace-fail 'exec setsid uwsm-app -- $(sed -n' \
          'browser_bin=$(sed -n' \
          --replace-fail "| head -1) --app=\"\$1\" \"\''${@:2}\"" \
          '| head -1)

    if [ -z "$browser_bin" ]; then
      echo "omarchy-launch-webapp: no browser found for $browser." >&2
      echo "Set one with: xdg-settings set default-web-browser <name>.desktop" >&2
      echo "Installed browsers:" >&2
      find {~/.local,~/.nix-profile,/etc/profiles/per-user/$USER,/run/current-system/sw}/share/applications \
        -maxdepth 1 -name "*.desktop" 2>/dev/null |
        xargs -r grep -l "^Categories=.*WebBrowser" 2>/dev/null |
        xargs -r -n1 basename | sed "s/^/  /" >&2
      exit 1
    fi

    exec setsid uwsm-app -- "$browser_bin" --app="$1" "''${@:2}"'
        # Clicking Spotify offered to install Spotify.
            #
            # Both launchers focus an existing window if there is one, and otherwise
            # decide whether the app is installed by testing `-x /usr/bin/<app>`. That
            # is never true here -- nixpkgs puts them on PATH from the store -- so a
            # user with programs.nixarchy.apps.spotify enabled clicked Spotify in the
            # menu and got a terminal offering to install it, with the real Spotify one
            # command away on their PATH the whole time.
            #
            # `command -v` rather than a store path, because the app comes from the
            # user's own configuration and may be overridden, in a profile, or absent
            # -- and absent is a case these scripts already handle correctly.
            for app in spotify signal; do
              case $app in
                signal) binary=signal-desktop ;;
                *) binary=$app ;;
              esac
              substituteInPlace $out/share/omarchy/bin/omarchy-launch-$app \
                --replace-fail "[[ -x /usr/bin/$binary ]]" \
                "command -v $binary >/dev/null 2>&1" \
                --replace-fail "uwsm-app -- /usr/bin/$binary" \
                "uwsm-app -- $binary"
            done

            # The App Library's Remove, for an app that came from the store.
                #
                # omarchy-remove-launcher-entry handles four cases that all work here --
                # web apps, TUI entries, a user's own .desktop, and flatpaks -- and a fifth
                # that cannot: an entry owned by a system package, which it removes by
                # asking `pacman -Qqo` who owns the file and running `pacman -Rns`. The
                # shim makes that query fail cleanly, so the branch is skipped and the user
                # got "Don't know how to uninstall firefox.desktop" from the App Library.
                #
                # Only the dead end is replaced. Every branch above it is left exactly as
                # upstream wrote it, because every one of them already does the right thing.
                substituteInPlace $out/share/omarchy/bin/omarchy-remove-launcher-entry \
                  --replace-fail 'echo "Don'"'"'t know how to uninstall $desktop_file_name" >&2' \
                  'echo "$desktop_file_name comes from a package, not from your home directory." >&2
            echo "" >&2
            echo "Remove it the way it was installed:" >&2
            echo "  omarchy remove            the Remove menu, which edits your app selection" >&2
            echo "  \$EDITOR ~/.config/nixarchy/apps.nix    then: nixarchy-apply" >&2'

                # Replace the bins that drive pacman. These are not reachable through the
                # menu extension: the shell's bar widget and its "Update System"
                # notification call omarchy-update directly from QML, so overriding a menu
                # row would fix one of three entry points.
                #
                # Each replacement keeps its `# omarchy:summary=` line, because bin/omarchy
                # discovers subcommands by grepping siblings for exactly that.
                for replacement in ${./nix-bin}/*; do
                  name=$(basename "$replacement")
                  target=$out/share/omarchy/bin/$name
                  if [ ! -e "$target" ] && ! grep -q '^# nixarchy:new' "$replacement"; then
                    echo "nix-bin/$name replaces nothing in this Omarchy version" >&2
                    exit 1
                  fi
                  install -Dm755 "$replacement" "$target"

                  # The symlink farm above was built from the files upstream shipped, and
                  # it runs before this loop. A replacement already has its link; a
                  # `# nixarchy:new` bin has none, and without one it is not on PATH --
                  # which is exactly how omarchy-retroarch-cores came to be installed and
                  # yet unreachable to the scripts that call it.
                  [ -e "$out/bin/$name" ] || ln -s "$target" "$out/bin/$name"
                done

                # Agent skills. omarchy-provision-user symlinks every directory under
                # default/agents/skills/ into ~/.claude/skills, ~/.agents/skills,
                # ~/.codex/skills and ~/.pi/agent/skills, so whatever is here is what an
                # AI agent on this machine is told to do. Upstream's are written for
                # Arch: they point at /usr/share/omarchy, and their decision framework
                # answers "install a package" with `omarchy pkg add`, which is a script
                # this repo replaced with one that deliberately refuses. Shipping them
                # unchanged means an agent confidently doing imperative things a rebuild
                # then wipes -- the one failure mode that looks like success.
                #
                # The `omarchy` skill is renamed to `nixarchy`, so the skill an agent
                # loads is named for the system it is actually on, and a new `nixos`
                # skill owns packages and system changes. `diagnose-crash` keeps its
                # name: bin/omarchy-agent-crash reads that path literally.
                #
                # SKILL.md and contributing.md are replaced outright -- their guidance
                # is wrong here, not merely misspelt -- while the rest are patched, so
                # an upstream edit to a line we depend on fails the build instead of
                # quietly shipping Arch instructions again.
                #
                # Every --replace-fail pattern AND replacement below is a single line
                # on purpose. `nix fmt` re-indents multi-line strings inside this
                # expression, which silently breaks a literal match against file
                # content that was never indented.
                mv $out/share/omarchy/default/agents/skills/omarchy \
                   $out/share/omarchy/default/agents/skills/nixarchy
                cp -r --no-preserve=mode ${./skills}/. \
                   $out/share/omarchy/default/agents/skills/

                skills=$out/share/omarchy/default/agents/skills

                # Paths. $OMARCHY_PATH is exported for every one of these readers, and
                # hardcoding a store hash into documentation would be wrong at the next
                # bump anyway.
                substituteInPlace $skills/nixarchy/theming.md \
                  --replace-fail '2. See how an existing theme is done via `/usr/share/omarchy/themes/catppuccin`.' '2. See how an existing theme is done via `$OMARCHY_PATH/themes/catppuccin`.' \
                  --replace-fail 'Never edit stock themes under `/usr/share/omarchy/themes/` — changes are lost' 'Stock themes live under `$OMARCHY_PATH/themes/` — a read-only store path, so' \
                  --replace-fail 'on update. Two safe options:' 'editing one is not possible. Two safe options:' \
                  --replace-fail 'cp /usr/share/omarchy/themes/catppuccin/colors.toml ~/.config/omarchy/themes/catppuccin/' 'cp --no-preserve=mode "$OMARCHY_PATH"/themes/catppuccin/colors.toml ~/.config/omarchy/themes/catppuccin/' \
                  --replace-fail 'cp -r /usr/share/omarchy/themes/catppuccin ~/.config/omarchy/themes/catppuccin-custom' 'cp -r --no-preserve=mode "$OMARCHY_PATH"/themes/catppuccin ~/.config/omarchy/themes/catppuccin-custom'

                # `omarchy refresh pacman` does not exist here, so neither does the hook
                # that runs before it. Marked inert rather than deleted: an agent that
                # sees the name mentioned upstream should find out here that it is dead.
                substituteInPlace $skills/nixarchy/hooks.md \
                  --replace-fail '├── pre-refresh-pacman.d/   # Before `omarchy refresh pacman` re-syncs packages' '├── pre-refresh-pacman.d/   # Arch only — never runs on NixOS' \
                  --replace-fail '├── post-update.d/          # During `omarchy update`, after system packages and migrations' '├── post-update.d/          # During `omarchy update`, i.e. after nixos-rebuild switch'

                # The crash skill is upstream's and mostly distro-neutral; three claims
                # are not. Arch'"'"'s debuginfod does not serve nixpkgs builds, "recent
                # package updates" has a far better answer here than mtimes, and a bug
                # report has two possible destinations rather than one.
                substituteInPlace $skills/diagnose-crash/SKILL.md \
                  --replace-fail 'This is Arch, which runs a public debuginfod server:' 'No public debuginfod serves nixpkgs builds. Symbols resolve only if this machine runs `nixseparatedebuginfod` (which serves the whole store on 127.0.0.1:1949 and exports `DEBUGINFOD_URLS` itself) or the package was built with `separateDebugInfo`. Run it anyway — gdb degrades to an unsymbolized stack rather than failing:' \
                  --replace-fail 'DEBUGINFOD_URLS="https://debuginfod.archlinux.org" \' 'DEBUGINFOD_URLS="''${DEBUGINFOD_URLS:-}" \' \
                  --replace-fail '- **Recent package updates.** A crash that starts right after an update points at' '- **Recent system generations.** A crash that starts right after a rebuild points at' \
                  --replace-fail '  the update.' '  the rebuild. `nix profile diff-closures --profile /nix/var/nix/profiles/system` names exactly what changed between generations — stronger evidence than any package log — and `sudo nixos-rebuild --rollback switch` tests the theory in one command.' \
                  --replace-fail '## If it is an Omarchy bug' '## If it is a Nixarchy or Omarchy bug' \
                  --replace-fail 'Most application crashes are upstream bugs in those applications, not Omarchy'"'"'s' 'Most application crashes are upstream bugs in those applications, not the distribution'"'"'s' \
                  --replace-fail 'doing. In the minority of cases where the cause really does sit within Omarchy'"'"'s' 'doing. In the minority of cases where the cause really does sit within Nixarchy'"'"'s or Omarchy'"'"'s'

                substituteInPlace $skills/diagnose-crash/reporting.md \
                  --replace-fail '# Reporting a Crash Upstream to Omarchy' '# Reporting a Crash to Nixarchy or Omarchy' \
                  --replace-fail 'Read this only after concluding that a crash is genuinely Omarchy'"'"'s to fix.' 'Read this only after concluding that a crash is genuinely the distribution'"'"'s to fix. Two projects can own it: Nixarchy (<https://github.com/olafkfreund/nixarchy>) for anything specific to NixOS — the store, a rebuild, `nixarchy-apply`, a hardcoded `/usr` path, a replaced `omarchy-*` command — and Omarchy (<https://github.com/basecamp/omarchy>) for anything that would happen identically on Arch. When unsure, file against Nixarchy; the `nixarchy` skill'"'"'s `contributing.md` has the full rule.' \
                  --replace-fail 'Omarchy is a configuration layer over Arch Linux, so a crash' 'Omarchy is a configuration layer and Nixarchy packages it for NixOS, so a crash' \
                  --replace-fail 'Include what happened, what was expected, steps to reproduce, system details from' 'Include what happened, what was expected, steps to reproduce, `nixos-version` and the locked inputs from `nix flake metadata`, system details from'

                # The Arch-name lookup omarchy-pkg-add answers with. Generated rather than
                # hand-written into the script: data/apps.nix already maps every Install
                # row that names a package and CI holds it to that, so deriving from it
                # means a newly mapped app is answered without touching this script.
                install -Dm644 ${archTable} $out/share/omarchy/nixarchy-arch-packages.tsv
                substituteInPlace $out/share/omarchy/bin/omarchy-pkg-add \
                  --replace-fail '@table@' \
                    "$out/share/omarchy/nixarchy-arch-packages.tsv"

                substituteInPlace $out/share/omarchy/bin/omarchy-games-retro-cores \
                  --replace-fail '@info@' '${libretro-core-info}/share/retroarch/cores'

                # The desktop entries, which were not installed at all: without them the
                # shipped web apps -- HEY, Basecamp, WhatsApp, X, YouTube, Zoom, Discord,
                # the Google ones -- and the Docker and Disk Usage launchers are simply
                # absent from the launcher, and `omarchy webapp` can only add new ones.
                install -d $out/share/applications $out/share/icons/hicolor/256x256/apps
                for desktop in ${src}/applications/*.desktop; do
                  base=$(basename "$desktop")

                  # foot, imv and mpv already ship these, and two identical relative paths
                  # make buildEnv refuse to construct the profile at all. Upstream carries
                  # them because on Arch it owns /usr/share/applications outright.
                  case "$base" in
                    foot.desktop | imv.desktop | mpv.desktop) continue ;;
                  esac

                  # Everything else is prefixed. These are Omarchy's web apps, and their
                  # names are the names of real programs: a machine with the zoom package
                  # installed has its own share/applications/Zoom.desktop, and buildEnv
                  # refuses to build a profile containing both -- which is a rebuild that
                  # fails for having installed a desktop, with no way to tell why from the
                  # message. Prefixing makes a collision impossible with any package,
                  # including ones that do not exist yet.
                  #
                  # Only the filename changes; Name= still reads "Zoom", so the launcher
                  # shows what upstream shows.
                  install -m644 "$desktop" "$out/share/applications/omarchy-$base"
                done

                # The one place a shipped entry is named rather than merely launched.
                substituteInPlace $out/share/omarchy/bin/omarchy-provision-user \
                  --replace-fail 'xdg-mime default HEY.desktop' \
                    'xdg-mime default omarchy-HEY.desktop'

                # The same chromium-browser.desktop rename as omarchy-launch-webapp, on
                # the three other paths that name the file rather than launch it.
                #
                # provision-user is the one that mattered. `xdg-settings set
                # default-web-browser chromium.desktop` exits 2 -- "one of the files
                # does not exist" -- under `set -euo pipefail`, so it aborted on the
                # line BEFORE the xdg-mime patch above, which is why that patch had
                # never once run on any machine. In a clean $HOME, against nixpkgs' own
                # entry:
                #
                #   chromium.desktop          exit 2
                #   chromium-browser.desktop  exit 0
                #
                # omarchy-default-browser names it twice and both halves were broken by
                # it: `omarchy default browser chromium` exited 1 having set nothing,
                # and the no-argument read fell through to printing the raw desktop id
                # instead of "chromium" -- which is the string the menu shows as the
                # current browser. omarchy-remove-browser only writes the fallback, and
                # its `|| true` swallowed the failure, so removing Chrome quietly left
                # the machine with a default browser that resolves to nothing.
                for f in omarchy-provision-user omarchy-default-browser omarchy-remove-browser; do
                  substituteInPlace $out/share/omarchy/bin/$f \
                    --replace-fail 'chromium.desktop' 'chromium-browser.desktop'
                done

                # Nothing may sed /etc/pam.d.
                #
                # /etc/pam.d/sudo and /etc/pam.d/polkit-1 are symlinks into
                # /etc/static/pam.d, and GNU `sed -i` does not follow a symlink: it
                # writes a temporary file and renames it over the link, so the entry
                # stops being NixOS-managed and becomes a stale regular file holding a
                # copy of the stack. Two of the four scripts here do that on the way in
                # and two on the way out, and the way out is the one that fires unasked:
                # its guard is `grep -q pam_u2f.so /etc/pam.d/sudo`, which is TRUE on a
                # machine that enabled u2fAuth the NixOS way -- so Remove FIDO2 detached
                # the stack of a user who never ran Setup at all.
                #
                # The edit was inert either way. It inserts a bare `pam_u2f.so`, and
                # every module NixOS names in these stacks is an absolute store path;
                # the detached file is then silently restored by the next rebuild. So it
                # read as a no-op that quietly broke /etc in between.
                #
                # The functions go rather than being emptied, and their call sites are
                # replaced separately: `setup_pam_config` is then a single occurrence in
                # each file, so what is left is a one-line anchor that cannot be broken
                # by how this Nix string happens to be indented.
                sed -i \
                  -e '/^setup_pam_config() {$/,/^}$/d' \
                  -e '/^setup_lock_fingerprint_pam() {$/,/^}$/d' \
                  $out/share/omarchy/bin/omarchy-setup-security-fido2 \
                  $out/share/omarchy/bin/omarchy-setup-security-fingerprint
                sed -i '/^remove_pam_config() {$/,/^}$/d' \
                  $out/share/omarchy/bin/omarchy-remove-security-fido2 \
                  $out/share/omarchy/bin/omarchy-remove-security-fingerprint

                # Only the PAM step goes. Everything before it works and is worth
                # keeping: pamu2fcfg really does register a key into /etc/fido2/fido2,
                # and fprintd-enroll really does enroll a print. What cannot be done
                # from inside a running system is the last step, so that is the step
                # that says so -- and exits non-zero, because at that point the feature
                # is registered but not yet usable.
                substituteInPlace $out/share/omarchy/bin/omarchy-setup-security-fido2 \
                  --replace-fail 'setup_pam_config' \
                    'echo "" >&2
                    echo "PAM is configured by your NixOS build, not by editing /etc/pam.d." >&2
                    echo "" >&2
                    echo "  Your key is registered -- /etc/fido2/fido2 holds the credential." >&2
                    echo "  What is left is telling PAM to accept it:" >&2
                    echo "" >&2
                    echo "    security.pam.u2f.enable = true;" >&2
                    echo "    security.pam.u2f.settings.authfile = \"/etc/fido2/fido2\";" >&2
                    echo "    security.pam.u2f.settings.cue = true;" >&2
                    echo "    security.pam.services.sudo.u2fAuth = true;" >&2
                    echo "    security.pam.services.polkit-1.u2fAuth = true;" >&2
                    echo "" >&2
                    echo "  then: sudo nixos-rebuild switch --flake <your-flake>" >&2
                    exit 1'

                substituteInPlace $out/share/omarchy/bin/omarchy-setup-security-fingerprint \
                  --replace-fail 'setup_pam_config' \
                    'echo "" >&2
                    echo "PAM is configured by your NixOS build, not by editing /etc/pam.d." >&2
                    echo "" >&2
                    echo "  Your fingerprint is enrolled and verified. What is left is" >&2
                    echo "  telling PAM to accept it:" >&2
                    echo "" >&2
                    echo "    services.fprintd.enable = true;" >&2
                    echo "    security.pam.services.sudo.fprintAuth = true;" >&2
                    echo "    security.pam.services.polkit-1.fprintAuth = true;" >&2
                    echo "    security.pam.services.hyprlock.fprintAuth = true;" >&2
                    echo "" >&2
                    echo "  then: sudo nixos-rebuild switch --flake <your-flake>" >&2
                    exit 1' \
                  --replace-fail 'setup_lock_fingerprint_pam' ':'

                # The removal side says the same thing in one breath. Both keep
                # everything else they do -- dropping the packages, and in the
                # fingerprint case removing /etc/pam.d/omarchy-lock-fingerprint, which
                # is a plain file the lock screen writes rather than a link into the
                # store, so removing it is right.
                substituteInPlace $out/share/omarchy/bin/omarchy-remove-security-fido2 \
                  --replace-fail 'remove_pam_config' \
                    'echo "PAM is configured by your NixOS build, so there is nothing to unpick" >&2
                    echo "in /etc/pam.d. Drop security.pam.u2f and the u2fAuth lines from your" >&2
                    echo "configuration and rebuild. The registration itself is removed below." >&2
                    echo "" >&2'

                substituteInPlace $out/share/omarchy/bin/omarchy-remove-security-fingerprint \
                  --replace-fail 'remove_pam_config' \
                    'echo "PAM is configured by your NixOS build, so there is nothing to unpick" >&2
                    echo "in /etc/pam.d. Drop the fprintAuth lines and services.fprintd from" >&2
                    echo "your configuration and rebuild." >&2
                    echo "" >&2'

                # The drift guard for all four: if an upstream release moves these edits
                # into a script this does not name, the build stops here rather than
                # shipping something that detaches a PAM stack.
                if grep -rln '/etc/pam.d/sudo\|/etc/pam.d/polkit-1' $out/share/omarchy/bin/; then
                  echo "the scripts above still edit a NixOS-managed PAM stack" >&2
                  exit 1
                fi

                # Each Icon= key is the file's basename lowercased with runs of non
                # alphanumerics collapsed to a dash -- safe_icon_name() in
                # omarchy-webapp-install, which is what names icons for web apps the user
                # adds later. Same rule here so both kinds resolve the same way.
                for icon in ${src}/applications/icons/*.png; do
                  base=$(basename "$icon" .png)
                  name=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
                    | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')
                  install -m644 "$icon" \
                    "$out/share/icons/hicolor/256x256/apps/$name.png"
                done

                # Nothing may ship an unprefixed desktop file. Upstream's names are the
                # names of real programs -- Zoom, Discord, Docker -- and a user who has any
                # of those packages gets a profile buildEnv refuses to construct, with a
                # message that never mentions nixarchy. The prefix is what makes that
                # impossible, so it is checked rather than assumed.
                for desktop in $out/share/applications/*.desktop; do
                  case "$(basename "$desktop")" in
                    omarchy-*) ;;
                    *)
                      echo "$(basename "$desktop") is not prefixed; it can collide with a" >&2
                      echo "package of the same name in a user's profile." >&2
                      exit 1
                      ;;
                  esac
                done

                # Every Icon= must resolve, or the entry shows up in the launcher as a
                # blank tile. This is the drift guard: an upstream release that adds a
                # desktop file, or renames an icon, fails here rather than shipping.
                for desktop in $out/share/applications/*.desktop; do
                  icon=$(sed -n 's/^Icon=//p' "$desktop")
                  [ -n "$icon" ] || continue
                  if [ ! -e "$out/share/icons/hicolor/256x256/apps/$icon.png" ]; then
                    echo "$(basename "$desktop") wants icon '$icon', which is not installed" >&2
                    exit 1
                  fi
                done

                # install/user/xcompose.sh writes ~/.XCompose at first login with a
                # hardcoded include of /usr/share/omarchy/default/xcompose, which does not
                # exist here -- so xkbcommon failed to parse the file and every compose
                # sequence the manual documents (CapsLock m s for an emoji) was silently
                # dead:
                #
                #   .XCompose:4:9: failed to open included Compose file
                #   warn: failed to instantiate compose table; dead keys will not work
                #
                # Pointed at /etc rather than at this store path: ~/.XCompose is written
                # once and never rewritten, so a store path would go stale the first time
                # the old generation is collected. /etc/omarchy is rebuilt with the system
                # and always names the current package -- see modules/nixos.nix.
                substituteInPlace $out/share/omarchy/install/user/xcompose.sh       --replace-fail '/usr/share/omarchy/default/xcompose'         '/etc/omarchy/xcompose'

                # The SDDM greeter theme. Upstream installs this with omarchy-refresh-sddm,
                # which copies default/sddm/omarchy into /usr/share/sddm/themes -- a path
                # NixOS has no writable version of. Putting it in the package instead means
                # the greeter travels with the Omarchy release it came from, and
                # services.displayManager.sddm.theme = "omarchy" is all the module needs.
                #
                # Without it SDDM falls back to its stock theme and the login screen is a
                # blue gradient with a placeholder avatar, which is the first thing anyone
                # sees of the system.
                # The boot splash. Upstream ships a complete Plymouth theme -- the script,
                # the logo and the progress assets -- and installs it with
                # `sudo cp -r ... /usr/share/plymouth/themes/omarchy` from
                # omarchy-refresh-plymouth. Nothing did that here, so boot.plymouth.enable
                # came up with NixOS' default theme and the one place a user cannot miss
                # was the one place that was not branded.
                #
                # NixOS collects themes from boot.plymouth.themePackages by looking in
                # share/plymouth/themes, so putting it there is the whole of it.
                install -d $out/share/plymouth/themes
                cp -r ${src}/default/plymouth $out/share/plymouth/themes/omarchy
                chmod -R u+w $out/share/plymouth/themes/omarchy

                # The theme names its own directory twice, absolutely, and Plymouth reads
                # those literally -- left alone it would look for the script under
                # /usr/share and render nothing. NixOS copies themes into the initrd at a
                # path of its own, so the reference has to be relative to wherever it lands
                # rather than to the store.
                substituteInPlace $out/share/plymouth/themes/omarchy/omarchy.plymouth \
                  --replace-fail 'ImageDir=/usr/share/plymouth/themes/omarchy' \
                  'ImageDir=/etc/plymouth/themes/omarchy' \
                  --replace-fail 'ScriptFile=/usr/share/plymouth/themes/omarchy/omarchy.script' \
                  'ScriptFile=/etc/plymouth/themes/omarchy/omarchy.script'

                install -d $out/share/sddm/themes
                cp -r ${src}/default/sddm/omarchy $out/share/sddm/themes/omarchy
                # cp from the store carries the store's read-only bits across, and the
                # wordmark below is written over one of these files.
                chmod -R u+w $out/share/sddm/themes/omarchy

                # Omarchy's greeter is password-only: it shows no user list and logs in
                # whoever userModel.lastUser says, which upstream's installer seeds into
                # /var/lib/sddm/state.conf. Nothing seeds that here, so on a fresh machine
                # lastUser is "" and SDDM answers every password with
                #
                #   pam_unix(sddm:auth): check pass; user unknown
                #   Authentication for user  ""  failed
                #
                # with no user list to pick from -- an install that cannot be logged into.
                # SDDM writes state.conf itself after the first successful login, so this
                # only has to cover the case where it does not exist yet.
                #
                # NameRole is Qt::UserRole + 1 in SDDM's UserModel. --replace-fail so that
                # an upstream rewrite of this line fails the build rather than silently
                # restoring the lockout.
                substituteInPlace $out/share/sddm/themes/omarchy/Main.qml       --replace-fail         'property string currentUser: userModel.lastUser'         'property string currentUser: userModel.lastUser || userModel.data(userModel.index(0, 0), Qt.UserRole + 1) || ""'

                # Omarchy's shell for zsh. Upstream has a bash rc chain and nothing else,
                # so a zsh user got none of the aliases or functions the manual documents.
                # See the file for what is sourced as-is and what had to be rewritten.
                install -Dm644 ${./zsh-rc} $out/share/omarchy/default/zsh/rc

                # And fish, which cannot source any of it -- see the file for why nothing
                # is translated and everything is derived from the same bash instead.
                install -Dm644 ${./fish-rc} $out/share/omarchy/default/fish/rc

                # Make the shell rc files say where they actually are.
                #
                # All three open with a fallback to /usr/share/omarchy for when
                # OMARCHY_PATH is unset. On NixOS that path can never exist, so any
                # context that sources one of these without the variable already
                # set -- a systemd unit, a container, ssh with a restricted
                # environment -- gets
                #
                #   no such file or directory: /usr/share/omarchy/default/bash/envs
                #
                # and none of the aliases or functions. It works today only because
                # environment.sessionVariables puts OMARCHY_PATH in
                # /etc/set-environment and the login path reads that first, which
                # is a lot of machinery for a file that already knows where it
                # lives: it is installed here, at a path this build knows.
                #
                # So the fallback becomes that path. Nothing else changes -- an
                # OMARCHY_PATH that is already set still wins, which is what makes
                # `omarchy dev link` work.
                for rc in bash zsh fish; do
                  substituteInPlace $out/share/omarchy/default/$rc/rc \
                    --replace-fail /usr/share/omarchy $out/share/omarchy
                done

                # Wear the name. Omarchy's logo is a pixel font on a 15-unit grid and
                # logo.png is logo.svg rendered 800px wide and tinted, so "NIXARCHY" can be
                # built from the same source: ARCHY is upstream's own five glyphs moved
                # right, and only N, I and X are drawn -- on the same grid, with the same
                # one-cell beveled corners. Deriving it means the wordmark still matches
                # after an Omarchy bump instead of drifting into a lookalike.
                python3 ${./nixarchy-logo.py} ${src}/logo.svg nixarchy-logo.svg
                magick -background none nixarchy-logo.svg -resize 800x       -fill '#a8cd76' -colorize 100       $out/share/sddm/themes/omarchy/logo.png

                # The greeter's own compositor config, referenced by upstream's
                # 10-wayland.conf. Nothing in the theme reaches outside its directory, so
                # this is the only companion file it needs.
                install -Dm644 ${src}/default/sddm/hyprland.lua $out/share/sddm/hyprland.lua

                # Wear the snowflake.
                substitute ${./menu-bar-widget.qml} \
                  $out/share/omarchy/shell/plugins/menu/BarWidget.qml \
                  --subst-var-by snowflake \
                  "${nixos-icons}/share/icons/hicolor/256x256/apps/nix-snowflake.png"

                runHook postInstall
  '';

  # Upstream ships `#!/bin/bash`, which does not exist on NixOS.
  postFixup = ''
    patchShebangs $out/share/omarchy/bin
  '';

  passthru = {
    inherit runtimeDeps;
  };

  meta = {
    description = "Omarchy desktop environment, vendored for NixOS";
    longDescription = ''
      The upstream basecamp/omarchy tree packaged as-is: 438 shell commands,
      a QuickShell desktop shell, 22 themes, and the Hyprland Lua defaults.
      Vendored rather than reimplemented so that tracking an upstream release
      is a source bump instead of a re-port.
    '';
    homepage = "https://omarchy.org";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omarchy";
  };
}
