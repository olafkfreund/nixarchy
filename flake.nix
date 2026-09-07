{
  description = "Nixarchy - Omarchy, vendored for NixOS";

  # Why: docs/internals/flake.md#for-the-person-who-has-never-seen-this-repository-
  nixConfig = {
    extra-substituters = [
      "https://nixarchy.cachix.org"
      "https://hyprland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default-linux";

    # Why: docs/internals/flake.md#deliberately-unpinned-unlike-hyprland-sops-nix-and
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#hyprland-from-hyprwm-tracking-their-branch-not-a
    hyprland.url = "github:hyprwm/Hyprland";

    omarchy = {
      url = "github:basecamp/omarchy/v4.0.2";
      flake = false;
    };

    # Why: docs/internals/flake.md#declarative-flatpaks-for-the-software-nixpkgs-genu
    nix-flatpak.url = "github:gmodena/nix-flatpak/v0.7.0";

    # The installer's one disk layout is a disko expression, and the installed
    # machine imports the same file -- that is what keeps `fileSystems`
    # declarative instead of frozen into a hardware-configuration.nix nobody
    # re-derives. See installer/disk-config.nix and issue #7.
    #
    # `follows` is right here and wrong for hyprland above: disko needs little
    # more than lib, and there is no binary cache to forfeit by overriding it.
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 439 per-machine modules, and the reason nixarchy does not need its own
    # install/hardware/ directory.
    #
    # Omarchy's hardware reputation is ~35 scripts under install/hardware/,
    # gated at runtime on DMI strings, PCI ids, /proc/cpuinfo model numbers,
    # ACPI HIDs -- omarchy-hw-dell-xps-oled parses EDID bytes. Every family
    # they hand-quirk (framework, surface, asus-rog, dell-xps, apple-t2,
    # thinkpad) is already in here, along with 400 more machines, maintained
    # by people who own them.
    #
    # It carries a nixpkgs of its own for its tests. Without the follows the
    # lock grows a SECOND nixpkgs node -- measured: adding this input pulled
    # in nixos-26.05pre924538 alongside ours -- and every one of those is a
    # tarball the offline image copies into inputSources for nothing.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#zen-is-not-in-nixpkgs-and-upstream-maintains-its-o
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake/ec2c94c95846";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-rdp-server-behind-the-remote-desktop-feature-1
    hypr-rdp = {
      url = "github:MuNeNiCK/hypr-rdp/v0.1.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#declarative-secrets-adopted-for-one-concrete-reaso
    sops-nix = {
      url = "github:Mic92/sops-nix/a8627b21b9107c5711c96b84f32a9a4b3d45295f";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#221-222
    microvm = {
      url = "github:microvm-nix/microvm.nix/fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      home-manager,
      hyprland,
      omarchy,
      zen-browser,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs (import systems);
      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          localSystem = system;
          overlays = [ self.overlays.default ];
        }
      );

      omarchyVersion = "4.0.2";

      # Why: docs/internals/flake.md#which-nixarchy-built-this-machine-208-for-nixarchy
      nixarchyRev = self.shortRev or self.dirtyShortRev or "unknown";
      #
      # `lastModifiedDate` is absent, not empty, when a lock node has no
      # `lastModified` -- which is what installer/mkFlake.nix used to write,
      # and is why the offline install broke the first time this landed: the
      # generated flake evaluated a DIFFERENT omarchy than the installer had
      # seeded, for want of one field. mkFlake now writes it. The fallback
      # stays for the machines whose flake.lock was generated before it did:
      # they get "unknown" and a rebuild that has a network, rather than an
      # evaluation error on a system they cannot rebuild to fix.
      nixarchyDate =
        let
          d = self.lastModifiedDate or "";
        in
        if d == "" then
          "unknown"
        else
          "${lib.substring 0 4 d}-${lib.substring 4 2 d}-${lib.substring 6 2 d}";
    in
    {
      overlays.default = final: _prev: {

        # nixarchy-doctor and nixarchy-verify live here rather than only under
        # `packages` so the module can install them. A module cannot take them
        # from inputs.self.packages -- see the note on programs.nixarchy.package
        # in modules/nixos.nix: those are built from NIXARCHY's nixpkgs, and
        # mixing instances makes buildEnv refuse the profile with two builds of
        # the same version. The overlay is how this repo hands a package to a
        # configuration, and `packages.doctor` now just names the overlay's.
        nixarchy-doctor = final.writeShellApplication {
          name = "nixarchy-doctor";
          runtimeInputs = with final; [
            systemd
            gnused
            gnugrep
            gawk
            coreutils
            # Why: docs/internals/flake.md#vainfo-for-the-graphics-section
            libva-utils
            # For reading the machine's flake.lock, which is JSON. Reaching for
            # sed on JSON is how a check starts reporting confidently wrong
            # things the first time nix reformats a lock.
            jq
          ];
          # @apps@ is the app-to-command table, generated here for the same
          # reason the menu's is: the doctor has to answer "which of these do
          # you already have" on a machine that has never had nixarchy, so it
          # cannot ask the running system and cannot be handed a list by it.
          #
          # meta.mainProgram where nixpkgs states one -- it is right where the
          # attribute name is wrong, and vscode putting `code` on PATH is not a
          # guess anyone would make. tryEval because unfree packages throw at
          # evaluation when allowUnfree is off.
          text =
            builtins.replaceStrings
              [ "@apps@" "@nixpkgstested@" "@hardwaremodules@" ]
              [
                (
                  let
                    pkgs = final;
                    apps = import ./data/apps.nix;
                    usable = final.lib.filterAttrs (_: a: !(a ? unavailable)) apps;
                    binaryOf =
                      name: app:
                      let
                        probe = builtins.tryEval (
                          let
                            # Why: docs/internals/flake.md#nixarchy-apps-first-then-the-top-level
                            path = final.lib.splitString "." (app.attr or name);
                            p = final.lib.attrByPath path (final.lib.attrByPath path null pkgs) pkgs.nixarchy-apps;
                          in
                          if p == null then null else (p.meta.mainProgram or null)
                        );
                      in
                      if probe.success && probe.value != null then probe.value else name;
                  in
                  final.lib.concatStringsSep "\n" (
                    final.lib.mapAttrsToList (n: a: "${binaryOf n a}\t${a.label or n}") usable
                  )
                )
                # The nixpkgs THIS build was tested against, so a machine can
                # say how far its own has drifted from it.
                #
                # Read from the lock at build time because it is knowable then
                # and unknowable later: nixarchy follows the machine's nixpkgs,
                # so on the installed system both names resolve to the same
                # node and the question cannot be asked at runtime at all.
                (
                  let
                    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
                    node = lock.nodes.${lock.nodes.root.inputs.nixpkgs};
                  in
                  toString node.locked.lastModified
                )

                # The same detector the installer runs, so the doctor's
                # suggestion and the file the installer writes cannot disagree.
                # A second copy of these rules would be a second copy that
                # drifts, and the drift would show up as the doctor telling a
                # user to add a module they already have.
                "${./installer/hardware-modules.sh}"
              ]
              (builtins.readFile ./pkgs/doctor.sh);
        };

        nixarchy-verify = final.writeShellApplication {
          name = "nixarchy-verify";
          runtimeInputs = with final; [
            systemd
            gnugrep
            gnused
            coreutils
            findutils
            glib
            bluez
            # pgrep and ps. The Session and Screen sharing probes both look for
            # a running process by name, and writeShellApplication's PATH does
            # not carry the caller's -- an undeclared pgrep here is a probe that
            # reports "not running" for everything.
            procps
            # awk, in the Session section's quickshell match. Undeclared until
            # the Fails-in-silence probes went in and the list was read again.
            gawk
            # wpctl. "pipewire is running" and "there is a sink" are different
            # questions and only wireplumber answers the second.
            wireplumber
            # The menu-row probe. The menu is JSONC -- comments and trailing
            # commas -- and the shell's own parser is three lines of Python
            # that build.yml and both VM tests already share. A fourth
            # spelling of it in sed would be a parser that disagrees with the
            # shell, reporting on a menu nobody has.
            python3
            # rfkill, and flock for the MicroVM guests section below (#229):
            # the same running/stopped test `nixarchy-vm list` uses on
            # $dir/.lock. An undeclared rfkill reads as "no radios on this
            # machine" rather than "rfkill is missing" -- the same trap the
            # doctor's vainfo hit.
            util-linux
            # Why: docs/internals/flake.md#podman-info-podman-inspect-for-the-boxes-section
            podman
            # nix-store, for the MicroVM guests section's GC-root check
            # (#229): `--print-roots` reads the store, never `--gc`. Pinning
            # a second nix here is fine in a way it is not in pkgs/microvm.nix
            # -- that one execs `nix build` against live system state and a
            # version drift there is a real hazard; this only lists roots.
            nix
            # ssh, for the same section's clocksource read over a forwarded
            # port on a declarative machine. Undeclared here reads as "could
            # not read clocksource" for a reason that has nothing to do with
            # whether the guest has a key configured.
            openssh
          ];
          text = builtins.readFile ./pkgs/verify.sh;
        };

        # Apps Omarchy offers that nixpkgs does not carry. Packaged here so a
        # NixOS user gets the same menu Arch users do, rather than a menu with
        # holes in it.
        nixarchy-apps = {
          once = final.callPackage ./pkgs/apps/once.nix { };
          grok-bot = final.callPackage ./pkgs/apps/grok-bot.nix { };

          # nixpkgs' `hey` is an unrelated HTTP load generator, so this cannot
          # simply follow nixpkgs the way most apps here do.
          hey-cli = final.callPackage ./pkgs/apps/hey-cli.nix { };

          # Why: docs/internals/flake.md#not-built-here-upstreams-own-flake-re-exported-int
          zen-browser = zen-browser.packages.${final.stdenv.hostPlatform.system}.default;

          # Two of the four applications Omarchy writes itself. nixpkgs has
          # none of them, which is why modules/nixos.nix cannot reproduce
          # upstream's preinstall set; these two close half that gap.
          omawrite = final.callPackage ./pkgs/apps/omawrite.nix { };
          omacalc = final.callPackage ./pkgs/apps/omacalc.nix { };
          omacut = final.callPackage ./pkgs/apps/omacut.nix { };

          # Not one of Omarchy's preinstalls -- a terminal-effects toy from the
          # same authors, packaged because it was asked for.
          ttfx = final.callPackage ./pkgs/apps/ttfx.nix { };

          # Why: docs/internals/flake.md#nixpkgs-retroarch-is-retroarch-with-cores-built-wi
          retroarch = final.retroarch.withCores (
            cores:
            map (n: cores.${n}) [
              "bsnes" # SNES
              "mesen" # NES
              "gambatte" # Game Boy / Color
              "mgba" # Game Boy Advance
              "blastem" # Mega Drive / Genesis
              "beetle-pce-fast" # PC Engine
              "beetle-psx-hw" # PlayStation
              "parallel-n64" # Nintendo 64
              "desmume" # Nintendo DS
              "flycast" # Dreamcast
              "ppsspp" # PSP
              "puae" # Amiga
              "vice-x64" # Commodore 64
            ]
          );
        };

        # Omarchy's Neovim configuration. A separate derivation rather than
        # part of the omarchy package: it is seeded into a directory the user
        # owns and may already have filled, so whether it is installed at all
        # is a decision, and a decision needs something to point at.
        omarchy-nvim-config = final.callPackage ./pkgs/omarchy-nvim {
          inherit omarchyVersion;
        };

        # Why: docs/internals/flake.md#the-rdp-daemon-re-exported-from-its-own-flake-so-t
        hypr-rdp = inputs.hypr-rdp.packages.${final.stdenv.hostPlatform.system}.hypr-rdp;

        omarchy = final.callPackage ./pkgs/omarchy {
          src = omarchy;
          version = omarchyVersion;
          inherit nixarchyRev nixarchyDate;
          # The compositor the Lua config is written against, not nixpkgs'.
          inherit (hyprland.packages.${final.stdenv.hostPlatform.system}) hyprland;

          # The desktop shell. nixpkgs' own, since #35: it was overridden to
          # 0.3.1 while nixpkgs sat on 0.3.0, whose session lock reaches
          # qFatal when screens sleep and wake while locked -- and the
          # Wayland protocol keeps the compositor locked when its lock client
          # dies, so the machine is left blank with nowhere to type a
          # password. nixpkgs now ships 0.3.1 from the same tag and the same
          # URL the override fetched, so the override had become a no-op.
          inherit (final) quickshell;
          # The screensaver's text-effects engine, packaged in this repo rather
          # than nixpkgs. Passed explicitly for the same reason hyprland is: it
          # lives under nixarchy-apps, which callPackage does not search.
          inherit (final.nixarchy-apps) ttfx;
        };

        # Why: docs/internals/flake.md#the-boot-splash-and-nothing-else-on-the-disk-with-
        nixarchy-plymouth = final.runCommand "nixarchy-plymouth-theme" { } ''
          install -d $out/share/plymouth/themes
          cp -r ${final.omarchy}/share/plymouth/themes/omarchy \
            $out/share/plymouth/themes/omarchy
        '';
      };

      packages = eachSystem (
        system:
        {
          default = self.packages.${system}.omarchy;
          inherit (pkgsFor.${system}) omarchy nixarchy-plymouth;

          # `nix run github:olafkfreund/nixarchy#agent-bus-mcp` -- the bus MCP
          # server as a flake output (#268), so an outside agent's mcp.json can
          # name a store path instead of `uv run --with mcp --with httpx` on a
          # copy of the script. The script itself stays the single source in
          # share/agent-bus/; this wraps it with its two dependencies from the
          # locked nixpkgs. bus-peek.sh's AGENT_BUS_CMD accepts this binary
          # verbatim.
          agent-bus-mcp = pkgsFor.${system}.writeShellApplication {
            name = "agent-bus-mcp";
            runtimeInputs = [
              (pkgsFor.${system}.python3.withPackages (p: [
                p.mcp
                p.httpx
              ]))
            ];
            text = ''
              exec python3 ${./share/agent-bus/agent_bus_mcp.py} "$@"
            '';
          };

          # Why: docs/internals/flake.md#nix-run-github-olafkfreund-nixarchy-verify-from-in
          install = pkgsFor.${system}.writeShellApplication {
            name = "nixarchy-install";
            runtimeInputs = with pkgsFor.${system}; [
              gum
              coreutils
              gnused
              gnugrep
              gawk
              findutils
              util-linux # lsblk, findmnt, blkid, blockdev, partx, wipefs
              # `btrfs subvolume snapshot -r`, for the @factory baseline taken
              # at the end of the install. writeShellApplication builds a strict
              # PATH from this list, so a command that is not named here is a
              # runtime failure no build catches -- and this one would fail on
              # the last step of a completed install, which is the worst place
              # to discover it.
              btrfs-progs
              # sgdisk, and only sgdisk: the free-space mode's whole safety
              # argument rests on `--new=0:` picking the next free partition
              # number, which is gptfdisk's behaviour and nothing else's.
              gptfdisk
              git
              mkpasswd
              nixos-install-tools # nixos-install, nixos-generate-config
              nix
              ncurses # clear and tput, which the screens are drawn with
              kbd # loadkeys, and the keymap list
              tzdata # the timezone list
              # Both only used by ask_network, which the offline image returns
              # from before it reaches either. Carried anyway rather than
              # conditionally: this is one script, `nix run .#install` on a stock
              # ISO needs them, and a runtime input that is missing on one image
              # is a class of bug that only shows up on that image.
              curl # the connectivity test -- can we reach the binary cache
              networkmanager # nmcli, for joining a wireless network
              # The failure and finish screens offer a way out of both. Present
              # on the live medium anyway; named here so `nix run .#install` on
              # some other host does not discover them missing at the one moment
              # a person needs them.
              systemd # systemctl reboot / poweroff
              bashInteractive # the shell the failure screen drops into
            ];
            # Spliced at build time the way doctor splices @apps@, so the script
            # never has to find these itself and `nix run` works from anywhere.
            text =
              builtins.replaceStrings
                [
                  "@template@"
                  "@gumenv@"
                  "@ui@"
                  "@logo@"
                  "@logocompact@"
                  "@tips@"
                  "@keymaps@"
                  "@dashboard@"
                  "@tzdata@"
                  "@kbd@"
                  "@initrdmodules@"
                  "@initrdforced@"
                  "@initrdmodulesplain@"
                  "@initrdforcedplain@"
                  "@initrdkernel@"
                  "@hardwaremodules@"
                ]
                [
                  "${self.packages.${system}.flake-template}"
                  "${./installer/gum-env.sh}"
                  "${./installer/lib/ui.sh}"
                  "${./installer/brand/logo.txt}"
                  "${./installer/brand/logo-compact.txt}"
                  "${./installer/brand/tips.txt}"
                  "${./installer/brand/keymaps.txt}"
                  "${./installer/lib/dashboard.sh}"
                  "${pkgsFor.${system}.tzdata}"
                  "${pkgsFor.${system}.kbd}"
                  # The initrd modules the reference host carries, and therefore
                  # the ones already baked into any image built from this commit.
                  # install.sh compares what it detected against this list to
                  # decide whether the installed machine can reuse that initrd.
                  (nixpkgs.lib.concatStringsSep " " self.nixosConfigurations.reference.config.boot.initrd.availableKernelModules)
                  # And the ones it loads unconditionally, which the same pin has
                  # to cover: an imported profile sets this list too.
                  (nixpkgs.lib.concatStringsSep " " self.nixosConfigurations.reference.config.boot.initrd.kernelModules)
                  # And the same two for an unencrypted install. They are not the
                  # same lists: LUKS adds a dozen crypto modules to the initrd, so
                  # a machine installed without encryption that pinned the
                  # encrypted set would match neither baked initrd and build a
                  # third.
                  (nixpkgs.lib.concatStringsSep " " self.nixosConfigurations.reference-unencrypted.config.boot.initrd.availableKernelModules)
                  (nixpkgs.lib.concatStringsSep " " self.nixosConfigurations.reference-unencrypted.config.boot.initrd.kernelModules)
                  # The kernel those four lists were captured from.
                  #
                  # The pin install.sh writes is only VALID for this kernel.
                  # nixpkgs gates entries in the default initrd module set on
                  # the kernel version -- xhci_pci_prom21 appears only at 7.2
                  # and later -- so a list captured here and forced onto a
                  # machine running a different kernel asks modprobe for a
                  # module that does not exist, and the initrd cannot build.
                  #
                  # That is not hypothetical: it is what `omarchy update`
                  # produced on a machine installed from a 7.2 image whose
                  # flake still resolved nixarchy to a revision with no kernel
                  # policy, and the machine dropped back to 6.18.
                  #
                  # So the pin is conditional on this exact version. When the
                  # kernel moves the pin evaporates, nixpkgs computes the list
                  # its own kernel warrants, and the machine builds a new
                  # initrd -- which it had to do anyway, because a different
                  # kernel is a different initrd.
                  self.nixosConfigurations.reference-unencrypted.config.boot.kernelPackages.kernel.version

                  # Which nixos-hardware modules this machine wants. A separate
                  # script rather than a function in install.sh because it takes
                  # its whole world from four environment variables and can
                  # therefore be driven against fixture machines --
                  # checks.hardware-modules does, and the install VM is one
                  # machine where these rules are about being on many.
                  "${./installer/hardware-modules.sh}"
                ]
                (builtins.readFile ./installer/install.sh);
          };

          # The flake the installer writes to /etc/nixos: the template files with
          # their @tokens@ still in place, plus a lock derived from this repo's
          # own so the installed machine resolves to exactly what was built.
          # Requires a committed tree -- it pins nixarchy by commit.
          flake-template = pkgsFor.${system}.callPackage ./installer/mkFlake.nix { inherit self; };

          # Exposed at top level, rather than only reachable through
          # modules/apps.nix's callPackage, so checks.microvm-template can
          # build and read the exact command `nixarchy vm` execs -- same
          # reasoning as `verify` and `doctor` just below.
          nixarchy-vm = pkgsFor.${system}.callPackage ./pkgs/microvm.nix { inherit self; };

          # Exposed at top level for the same reason as nixarchy-vm just
          # above: checks.box-template builds and reads the exact command
          # `nixarchy box` execs.
          nixarchy-box = pkgsFor.${system}.callPackage ./pkgs/box.nix { };

          verify = pkgsFor.${system}.nixarchy-verify;

          # `nix run .#review` -- what needs updating, and what is quietly
          # broken. An app rather than a check because it asks GitHub what
          # upstream ships and what CI did last night, and a check has no
          # network. The half that needs neither is checks.review-pins.
          review = pkgsFor.${system}.writeShellApplication {
            name = "nixarchy-review";
            runtimeInputs = with pkgsFor.${system}; [
              gh
              curl
              git
              gnugrep
              gnused
              coreutils
              python3
              nix
            ];
            text = builtins.readFile ./pkgs/review.sh;
          };

          # Why: docs/internals/flake.md#nix-run-release-notes-from-tag-to-ref-what-changed
          release-notes = pkgsFor.${system}.writeShellApplication {
            name = "nixarchy-release-notes";
            runtimeInputs = with pkgsFor.${system}; [
              git
              curl
              jq
              nix
              gawk
              gnugrep
              gnused
              coreutils
            ];
            text = builtins.replaceStrings [ "@delta@" ] [ "${./.github/scripts/omarchy-package-delta.sh}" ] (
              builtins.readFile ./.github/scripts/release-notes.sh
            );
          };

          # `nix run github:olafkfreund/nixarchy#doctor` -- reads the running
          # system and prints the configuration it would need. Runnable before
          # nixarchy is an input anywhere, which is the only entry point someone
          # deciding whether to adopt it actually has.
          doctor = pkgsFor.${system}.nixarchy-doctor;

          # Why: docs/internals/flake.md#nix-run-devenv-presets-scaffolds-every-preset-in
          devenv-presets =
            let
              pkgs = pkgsFor.${system};
            in
            pkgs.writeShellApplication {
              name = "nixarchy-devenv-presets";
              runtimeInputs = [
                pkgs.coreutils
                # The same devenv the catalogue entry installs: pkgs.devenv is
                # what modules/services/devenv.nix defaults its `package` to, so
                # what evaluates here is what a user's machine would run.
                pkgs.devenv
                pkgs.gnused
                (pkgs.callPackage ./pkgs/dev-init.nix { })
              ];
              text = ''
                presets=( ${nixpkgs.lib.concatStringsSep " " (builtins.attrNames (import ./data/devenv-presets.nix))} )

                # Everything under one temp root, HOME included: `devenv allow`
                # writes a trust database into XDG state, and a check has no
                # business touching the trust decisions of whoever ran it.
                root=$(mktemp -d)
                trap 'rm -rf "$root"' EXIT
                HOME="$root/home"
                export HOME
                mkdir -p "$HOME"

                fail=0
                for preset in "''${presets[@]}"; do
                  echo "== $preset"
                  dir="$root/$preset"
                  mkdir -p "$dir"
                  cd "$dir"

                  if ! nixarchy-dev-init "$preset" > init.log 2>&1; then
                    echo "   scaffolding failed:"
                    sed 's/^/   /' init.log
                    fail=1
                    continue
                  fi

                  # `devenv info` is the cheapest command that evaluates the whole
                  # module set -- it prints the packages the environment would
                  # have, which it cannot know without resolving every option the
                  # preset set. A renamed option dies here.
                  if devenv info > eval.log 2>&1; then
                    echo "   ok"
                  else
                    echo "   does not evaluate:"
                    sed 's/^/   /' eval.log
                    echo "   the devenv.nix it wrote:"
                    sed 's/^/   /' devenv.nix
                    fail=1
                  fi
                done

                if [ "$fail" -ne 0 ]; then
                  echo
                  echo "A preset in data/devenv-presets.nix no longer evaluates against"
                  echo "devenv. Either an option was renamed upstream -- fix the preset,"
                  echo "the new name is in devenv's src/modules -- or the scaffold this"
                  echo "edits changed shape and pkgs/dev-init.nix has to follow."
                  exit 1
                fi
                echo
                echo "all ''${#presets[@]} presets evaluate"
              '';
            };

          # Why: docs/internals/flake.md#screencasts-of-a-real-session-scene-by-scene-see
          inherit
            (import ./tests/demo {
              inherit inputs;
              pkgs = pkgsFor.${system};
              microvmRunner = self.packages.${system}."microvm-shell-tcg";
            })
            demo
            demo-record
            demo-verify
            demo-scene-menus
            demo-scene-themes
            demo-scene-install
            demo-scene-devenv
            demo-scene-plugin
            demo-scene-microvm
            # Not a GIF but the scene's test DRIVER: boxes needs the real
            # network in the VM (podman pulls the image, and the first
            # `distrobox enter` provisions online), which no sandboxed build
            # has. demo-record runs it outside the sandbox and applies the
            # same encode and the same verify gate to the frames.
            demo-scene-boxes
            ;

          inherit (pkgsFor.${system}.nixarchy-apps)
            once
            grok-bot
            retroarch
            hey-cli
            omawrite
            omacalc
            omacut
            ttfx
            ;

          # Re-exported so programs.nixarchy.apps.zen resolves like any other
          # `ours` app, without every consumer needing the extra flake input.
          zen-browser = zen-browser.packages.${system}.default;

          # Why: docs/internals/flake.md#nix-run-update-rewrites-the-pinned-versions-and-ha
          update =
            let
              pinned = lib.filterAttrs (_: p: p ? updateScript) pkgsFor.${system}.nixarchy-apps;
            in
            pkgsFor.${system}.writeShellApplication {
              name = "nixarchy-update";
              text = ''
                rc=0
                ${lib.concatMapStrings (p: ''
                  ${lib.getExe p.updateScript} || rc=1
                '') (lib.attrValues pinned)}
                exit "$rc"
              '';
              # `|| rc=1` rather than fail-fast: one upstream breaking its
              # release layout (hey-cli's 1.4.1 SBOMs did exactly that) must
              # not block every other package's bump for the night.
              derivationArgs.passthru.pinned = lib.attrNames pinned;
            };

          # Boot the smoke test: `nix run .#vm`
          vm = self.nixosConfigurations.vm.config.system.build.vm;

          # The same machine with room for a model: `nix run .#vm-big`.
          # 32GB, 8 cores, and a real disk rather than a tmpfs root.
          vm-big = self.nixosConfigurations.vm-big.config.system.build.vm;

          # The bootable image: boot it and answer the questions. Still online
          # at this stage -- #15 bakes the closure onto it, #16 takes the
          # network away.
          iso = self.nixosConfigurations.iso.config.system.build.isoImage;

          # The same installer, without the desktop on it. Small enough to
          # download over a hotel connection, and it fetches the closure from
          # the binary caches instead of carrying it. Needs a working network
          # before it can do anything, which is what the wizard's first screen
          # is for.
          iso-net = self.nixosConfigurations.iso-net.config.system.build.isoImage;

          # Why: docs/internals/flake.md#a-vm-that-installs-onto-a-blank-disk-with-a-networ
          installer-vm =
            let
              cfg = self.nixosConfigurations.installer-vm.config;
              vm = cfg.system.build.vm;
            in
            pkgsFor.${system}.writeShellApplication {
              name = "run-installer-vm";
              runtimeInputs = with pkgsFor.${system}; [ coreutils ]; # df, tail
              text =
                builtins.replaceStrings
                  [
                    "@tmpneed@"
                    "@pwdneed@"
                    "@vmscript@"
                  ]
                  [
                    (toString (builtins.head cfg.virtualisation.emptyDiskImages).size)
                    (toString cfg.virtualisation.diskSize)
                    "${vm}/bin/${vm.meta.mainProgram}"
                  ]
                  (builtins.readFile ./installer/vm-preflight.sh);
            };

          # Why: docs/internals/flake.md#the-front-door
          try =
            let
              pkgs = pkgsFor.${system};
            in
            pkgs.writeShellApplication {
              name = "nixarchy-try";
              runtimeInputs = with pkgs; [
                coreutils # df, install, mktemp, nproc, sha256sum
                curl # the release-image fallback
                gnugrep
                gnused
                gawk
              ];
              text =
                builtins.replaceStrings
                  [
                    "@rev@"
                    "@qemu@"
                    "@qemu_img@"
                    "@ovmf_code@"
                    "@ovmf_vars@"
                  ]
                  [
                    (self.rev or "")
                    "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
                    "${pkgs.qemu_kvm}/bin/qemu-img"
                    "${pkgs.OVMF.firmware}"
                    "${pkgs.OVMF.variables}"
                  ]
                  (builtins.readFile ./installer/try.sh);
            };

          # Every command the vendored scripts exec by name, in one prefix.
          # The bins are unwrapped on purpose, so an incomplete runtimeDeps list
          # produces a package that builds cleanly and then fails at the click
          # -- which is how `Command not found: xdg-terminal-exec` shipped.
          # CI builds this and asserts the binaries are actually in it.
          omarchy-runtime = pkgsFor.${system}.buildEnv {
            name = "omarchy-runtime";
            paths = pkgsFor.${system}.omarchy.passthru.runtimeDeps;
            ignoreCollisions = true;
          };
        }
        # Why: docs/internals/flake.md#two-runners-per-data-microvm-templates-nix-entry-b
        // lib.concatMapAttrs (
          name: template:
          let
            mkMicrovm =
              modules:
              self.lib.mkMicrovm {
                inherit system modules;
                template = template.module;
              };
          in
          {
            "microvm-${name}" = mkMicrovm [ ];
            "microvm-${name}-tcg" = mkMicrovm [
              {
                microvm.cpu = "max";
                microvm.qemu.machineOpts = {
                  accel = "tcg";
                  acpi = "on";
                  "mem-merge" = "on";
                  pcie = "on";
                  pit = "on";
                  pic = "on";
                  rtc = "on";
                  usb = "off";
                };
              }
            ];
          }
        ) (import ./data/microvm-templates.nix)
      );

      nixosModules = {
        default = self.nixosModules.nixarchy;
        nixarchy = import ./modules/nixos.nix inputs;
      };

      homeManagerModules = {
        default = self.homeManagerModules.nixarchy;
        nixarchy = import ./modules/home.nix inputs;
      };

      # Smoke-test VM. Not a daily driver -- it exists to prove the QuickShell
      # bar comes up against Hyprland's Lua config before any packaging effort
      # is spent on the long tail.
      nixosConfigurations = {
        # The live image. See installer/cd.nix.
        iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            offline = true;
          };
          modules = [ ./installer/cd.nix ];
        };

        # Same module, one argument different. See the `offline` parameter in
        # installer/cd.nix for what it turns off.
        iso-net = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            offline = false;
          };
          modules = [ ./installer/cd.nix ];
        };

        installer-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./installer/vm.nix ];
        };

        vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.nixarchy
            home-manager.nixosModules.home-manager
            ./vm/configuration.nix
          ];
        };

        # Why: docs/internals/flake.md#the-same-vm-with-room-to-run-a-model
        vm-big = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.nixarchy
            home-manager.nixosModules.home-manager
            ./vm/configuration.nix
            (
              { lib, ... }:
              {
                virtualisation = {
                  memorySize = lib.mkForce 32768;
                  cores = lib.mkForce 8;
                  diskSize = lib.mkForce 131072; # 128GB: several models, comfortably
                  diskImage = lib.mkForce "./nixarchy-vm-big.qcow2";
                  # A different port, so this and .#vm can run side by side.
                  forwardPorts = lib.mkForce [
                    {
                      from = "host";
                      host.port = 2224;
                      guest.port = 22;
                    }
                  ];
                };

                # Sized for the machine rather than inherited from the smoke
                # test: with 32GB the 8b tier is comfortable, and 8b is the
                # smallest size shown to follow the skills rather than answer
                # from memory while claiming to have read them.
                programs.nixarchy.localAi = {
                  enable = lib.mkDefault true;
                  model = lib.mkDefault "qwen3:8b";
                  # A VM has no GPU, and localAi refuses to build without one
                  # unless told. This is the case the option exists for: a rig
                  # for exercising the wiring, where a slow answer is still an
                  # answer and nobody is trying to work.
                  allowCpu = lib.mkDefault true;
                };
              }
            )
          ];
        };

        # The machine the installer produces, with the installer's own defaults.
        # Built in CI so the install path cannot rot between releases, and baked
        # into the ISO's store later so that installing copies rather than
        # downloads -- which only works if this closure is a closure of something
        # a real install actually produces.
        #
        # `device` is a placeholder: nothing here formats a disk. What matters is
        # that the expensive derivations in this toplevel are the same ones a real
        # install needs, and the device string is not one of them.
        reference = self.lib.mkReference { encrypt = true; };

        # The same machine on an unencrypted disk.
        #
        # Not a variant anybody installs -- it exists so the ISO can carry
        # both. The installer offers encryption on or off, and the two produce
        # different systems: 51 derivations differ, all of them unit files and
        # etc fragments, 180 MiB of content. Small, but not present is not
        # present, and on an image with no network the difference between
        # having them and not is a source bootstrap.
        reference-unencrypted = self.lib.mkReference { encrypt = false; };

        # The same machine again, with every hardware attribute
        # nixos-generate-config can emit that ADDS A PACKAGE turned on. It is
        # not a machine anyone installs; it exists so installer/cd.nix can put
        # those packages on the image.
        #
        # #382: an Intel NPU made the tool write hardware.cpu.intel.npu.enable
        # into hardware-configuration.nix, which put intel-npu-driver into
        # environment.systemPackages, which no baked closure carried, so the
        # target had to BUILD it -- and building a cmake package with no
        # compiler on the image is the stdenv source bootstrap, which is where
        # two users' installs died, after the disk was partitioned.
        #
        # boot.swraid.enable is the one that matters most and was found by
        # tests/generate-config-surface.nix rather than by a user: a machine
        # whose root is on mdraid gets it written, and it pulls mdadm. That
        # one cannot be worked around by commenting it out either -- without
        # it the installed machine does not boot at all.
        reference-hardware = self.lib.mkReference {
          encrypt = false;
          hardware = true;
        };
      };

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./shell.nix { };
      });

      # The installed machine, as the installer would produce it. Both disk
      # modes come from here so they cannot drift apart, and so installer/cd.nix
      # can bake each one onto the image without restating the host.
      lib.mkReference =
        {
          encrypt,
          hardware ? false,
        }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.nixarchy
            home-manager.nixosModules.home-manager
            inputs.disko.nixosModules.disko

            # Why: docs/internals/flake.md#one-module-that-imports-the-machines-own-two-rathe
            {
              imports = [
                (import ./installer/host.nix {
                  hostname = "nixarchy";
                  username = "omarchy";
                })
                (import ./installer/disk-config.nix {
                  device = "/dev/vda";
                  inherit encrypt;
                })
              ];
            }
          ]
          ++ nixpkgs.lib.optional hardware {
            # Kept in step with tests/generate-config-surface.nix, which fails
            # if this list stops covering what nixos-generate-config emits.
            # Two of the tool's package-adding attributes are deliberately NOT
            # here, and the check states why: hardware.parallels.enable pulls
            # a proprietary Parallels disk image that cannot be redistributed
            # on an ISO, and boot.isNspawnContainer is emitted only when the
            # tool runs INSIDE an nspawn container, which an installer that
            # partitions a physical disk never is.
            hardware.cpu.intel.npu.enable = true;
            boot.swraid.enable = true;
            virtualisation.hypervGuest.enable = true;
            virtualisation.virtualbox.guest.enable = true;

            # Every nixos-hardware module installer/hardware-modules.sh can
            # select, so the packages behind them are on the offline image.
            #
            # This is the same argument as the attributes above, and the same
            # one #382 made the hard way: a real machine's generated config is
            # not the reference's, and where the difference is a PACKAGE, an
            # offline install has to build it from parts with no compiler.
            # common-gpu-intel alone pulls intel-media-driver, the compute
            # runtime and vpl-gpu-rt.
            #
            # The UNION, not a machine: no real machine has an Intel and an
            # AMD GPU and both microcode sets. Every entry is mkDefault config
            # and this host is never installed -- it exists so the medium
            # carries the parts, which is exactly what the header above says.
            #
            # checks.hardware-modules asserts these names exist; the ISO budget
            # check is what says whether they FIT.
            imports = with inputs.nixos-hardware.nixosModules; [
              common-cpu-intel-cpu-only
              common-cpu-amd
              common-gpu-intel
              common-gpu-amd
              # Imports common-pc and common-pc-laptop too, so it covers all
              # four of the chassis/disk outcomes.
              common-pc-laptop-ssd
            ];
          };
        };

      # Why: docs/internals/flake.md#one-closure-per-template-shared-by-every-vm-a-user
      lib.mkMicrovm =
        {
          template,
          system,
          modules ? [ ],
        }:
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            inputs.microvm.nixosModules.microvm
            ./modules/microvm/guest.nix
            template
          ]
          ++ modules;
        }).config.microvm.declaredRunner;

      formatter = eachSystem (system: pkgsFor.${system}.nixfmt-tree);

      checks = eachSystem (
        system:
        let
          # `imagePins` for the box checks, taken by hand against
          # registry-1.docker.io, once per template, the same way a `fetchurl`
          # sha256 is -- a new template (data/box-templates.nix) adds an entry
          # here too, or checks.box-template fails loudly with "no imagePins
          # entry for". One table, shared: checks.box-template reads every
          # entry structurally, checks.box-boot creates a real container from
          # the default template's -- two checks disagreeing about which image
          # is pinned would be the #288/#289 failure shape again.
          boxImagePins = {
            archlinux = {
              imageName = "archlinux";
              imageDigest = "sha256:818793c894d94534c22f2149154a39ebaee57e4e67321023b0866a1d5722036c";
              tag = "latest";
              sha256 = "sha256-XqDfBl6Ehkzgw/3LPVd+nrQnV3CxDCqyynqBOfTFZDs=";
            };
            debian = {
              imageName = "debian";
              imageDigest = "sha256:f324c7ff54321e8d9c588493a20244965938ce0aa50bbd1022d38010e9ffc4b1";
              tag = "trixie";
              sha256 = "sha256-iL1J4Iro9wW+yL7dHgGlaMpoTxCU5XzuEgKkWAar4yA=";
            };
          };
        in
        {
          omarchy = self.packages.${system}.omarchy;
          inherit (self.packages.${system}) omarchy-runtime;

          # Drives a real session and reports what it logged. See tests/session.nix
          # for why neither a serial console nor the smoke-test VM can do this.
          session = import ./tests/session.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) doctor;
          };
          # Boots the Omarchy session on a machine whose hyprland.lua belongs to
          # somebody else -- the case the session entry exists for.
          coexist = import ./tests/coexist.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The installer's interactive screens, at every width worth caring
          # about. Nothing else draws them: every other harness passes
          # --answers, which is exactly how #133 shipped.
          installer-store-space = import ./tests/installer-store-space.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
            dashboardScript = ./installer/lib/dashboard.sh;
          };

          # The doctor's GPU rules, against fixture machines. checks.install's
          # VM runs llvmpipe and has no PCI display controller, so this is the
          # only place these branches are ever exercised -- and one of them was
          # unreachable until the fixtures grew a vainfo that behaves like the
          # real one.
          doctor-graphics = import ./tests/doctor-graphics.nix {
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) doctor;
          };

          # The same argument for the Wireless section, and a sharper one: the
          # install VM has a virtio NIC and no radio, so none of the three
          # no-wlan0 cases can occur there at all. Two users hit them in one
          # week and neither could tell which they had.
          doctor-wireless = import ./tests/doctor-wireless.nix {
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) doctor;
          };

          # The `try` front door's refusals, each driven with a stubbed
          # environment that lies about KVM, RAM, disk and the build plan.
          # Building tryApp is itself half the assertion: the app evaluates
          # and its script passes shellcheck, by writeShellApplication's own
          # checkPhase. See tests/try-preflight.nix.
          try-preflight = import ./tests/try-preflight.nix {
            pkgs = pkgsFor.${system};
            tryScript = ./installer/try.sh;
            tryApp = self.packages.${system}.try;
          };

          # --from-repo's two branches -- host already in the repository, host
          # added to it -- against git repositories built in the check. The
          # mode touches a user's config repository and had never executed
          # under any test.
          installer-from-repo = import ./tests/installer-from-repo.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          # The bus redaction hook blocks what a pattern can decide, and only
          # that (#272). A security hook that passes everything looks
          # identical to a working one, which is why this exists.
          # The vendored MCP server is a copy of a file CI cannot see, so this
          # holds it to the contract its own SKILL.md documents instead of
          # diffing against an upstream that is not there (#268). See
          # tests/bus-mcp.nix for why a checksum was rejected.
          bus-mcp = import ./tests/bus-mcp.nix {
            pkgs = pkgsFor.${system};
            server = ./share/agent-bus/agent_bus_mcp.py;
            skill = ./share/agent-bus/SKILL.md;
          };

          bus-redact = import ./tests/bus-redact.nix {
            pkgs = pkgsFor.${system};
            hook = ./share/agent-bus/hooks/bus-redact.sh;
            peekHook = ./share/agent-bus/hooks/bus-peek.sh;
            registerScript = ./share/agent-bus/register.sh;
          };

          installer-lock = import ./tests/installer-lock.nix {
            pkgs = pkgsFor.${system};
            flakeTemplate = self.packages.${system}.flake-template;
          };

          # Where a crash report goes. The prose said Nixarchy and every gh
          # command said Basecamp; this greps the built tree so the two cannot
          # disagree again.
          crash-report-repo = import ./tests/crash-report-repo.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          installer-ui = import ./tests/installer-ui.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: installer/AGENTS.md#generate-config-surface
          generate-config-surface = import ./tests/generate-config-surface.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: tests/initrd-pin-guard.nix
          initrd-pin-guard = import ./tests/initrd-pin-guard.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: tests/firmware-guard.nix
          firmware-guard = import ./tests/firmware-guard.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: tests/hardware-modules.nix
          hardware-modules = import ./tests/hardware-modules.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: tests/offline-hardware-packages.nix
          offline-hardware-packages = import ./tests/offline-hardware-packages.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: installer/AGENTS.md#try-nixarchy-sh
          try-nixarchy = import ./tests/try-nixarchy.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The dashboard the installer draws while it works, against a clock
          # that goes backwards -- which is what NTP does to a machine whose
          # RTC was wrong, mid-install. Not covered by the VM checks: their
          # clocks are stable, so every duration there is positive.
          dashboard-clock = import ./tests/dashboard-clock.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The other half of the installer: the questions themselves, answered
          # over a serial line. checks.installer-ui proves a widget can be drawn;
          # this proves the wizard can be answered, which no harness passing
          # --answers has ever done. See tests/installer-wizard.nix.
          installer-wizard = import ./tests/installer-wizard.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The package delta that goes in every Omarchy bump PR. Its dangerous
          # failure is silence, so this feeds it a known answer. See
          # tests/package-delta.nix.
          package-delta = import ./tests/package-delta.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The other two halves of that PR body. Same shape, same reason: both
          # report on a release by grepping upstream's file layout, and a grep
          # that has stopped matching prints what a quiet release prints. See
          # tests/config-delta.nix and tests/patched-files.nix.
          config-delta = import ./tests/config-delta.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };
          patched-files = import ./tests/patched-files.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The release notes, against a fixture repository whose diff is known.
          # Same dangerous failure as the delta above, over more scans: a release
          # note that reads calm because a grep stopped matching. See
          # tests/release-notes.nix.
          release-notes = import ./tests/release-notes.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # `nix run .#review` watches the pinned packages; this watches that
          # it can still see them. See tests/review-pins.nix.
          review-pins = import ./tests/review-pins.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Every option that adds something, checked with it turned off too --
          # see tests/options.nix for why that half is the one at risk.
          options = import ./tests/options.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The other half of that: every option path the README and the manual
          # quote, checked against the option set they claim to describe. See
          # tests/doc-options.nix and #214.
          doc-options = import ./tests/doc-options.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Built, not evaluated, and onto a config that already exists. See
          # tests/integration.nix for the three bugs that shipped because every
          # other check here starts from a clean machine.
          integration = import ./tests/integration.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Adds a real third-party plugin from a real repo. The plugin system
          # is the one deliberately imperative corner of Omarchy, and the part
          # of it that could break here is the writable ~/.config/omarchy the
          # seed creates.
          plugin = import ./tests/plugin.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Installs onto a blank disk, reboots into the result on the
          # bootloader the installer wrote, and asserts a rebuild builds
          # nothing. See tests/install.nix for why the second machine is not a
          # normal test node.
          install = import ./tests/install.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The same question with encrypt=yes -- the DEFAULT interactive
          # answer, which until this check had no coverage past evaluation.
          # Installs, asserts the ENCRYPTED initrd module list was pinned,
          # boots the result through the LUKS passphrase prompt on the serial
          # console, and proves autologin and the recovery secret on the ESP.
          # See tests/install-encrypted.nix for why the passphrase prompt is
          # not the obstacle tests/install.nix's header once took it for.
          install-encrypted = import ./tests/install-encrypted.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The #300 guarantee on a real disk: a dark substituter refused with
          # the target intact. installer-store-space covers the same function
          # with stubs; this is the only check that can fail if the installer
          # wipes anyway, because it is the only one holding a disk.
          installer-refusal = import ./tests/installer-refusal.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The dangerous one. Installs into free space on a disk that already
          # carries partitions and asserts those partitions are byte-identical
          # afterwards -- entry and content. See tests/free-space.nix; #47 is
          # the only item in the epic whose failure mode is destroying data
          # that is not ours, and this is the gate it sits behind.
          free-space = import ./tests/free-space.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The same question as checks.install, asked of the artefact people
          # download rather than of a test node: boots the ISO with no network
          # device at all and installs from what the image carries.
          install-iso = import ./tests/install-iso.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # The other image: the net ISO installing by FETCHING, from a
          # substituter stood up inside the test's own vlan. The image people
          # download for a network install had no install check at all until
          # this one; see the file header for what it proves and what no
          # sandboxed check can.
          install-iso-net = import ./tests/install-iso-net.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;

          # The installed machine, as opposed to the smoke-test guest: a real
          # bootloader, disko-provided filesystems, nothing faked. If this builds
          # and vm-toplevel builds, the extraction has not let the two drift.
          reference-toplevel = self.nixosConfigurations.reference.config.system.build.toplevel;

          # Builds a runner and reads it. Boots nothing -- see tests/microvm-template.nix
          # for what that can and cannot prove. Costs about what reference-toplevel
          # above does: a runCommand plus a ~1-1.5 GB guest closure from
          # cache.nixos.org. This step is also how the templates reach
          # nixarchy.cachix.org: cachix-action pushes what this job builds.
          microvm-template = import ./tests/microvm-template.nix {
            pkgs = pkgsFor.${system};
            inherit lib;
            templates = lib.mapAttrs (name: _: {
              kvm = self.packages.${system}."microvm-${name}";
              tcg = self.packages.${system}."microvm-${name}-tcg";
            }) (import ./data/microvm-templates.nix);
            nixarchyVm = self.packages.${system}.nixarchy-vm;
          };

          # The other half of that: a declared machine actually boots, on the
          # -tcg runner, and the ro-store mount is asserted from inside the
          # running guest. See tests/microvm-boot.nix for why the KVM runner --
          # the one nearly every user runs -- cannot be proved here.
          microvm-boot = import ./tests/microvm-boot.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Reads the box catalogue and `nixarchy box` structurally -- see
          # tests/box-template.nix for what that can and cannot prove. The
          # pins live in `boxImagePins` above, shared with checks.box-boot.
          box-template = import ./tests/box-template.nix {
            pkgs = pkgsFor.${system};
            inherit lib;
            templates = import ./data/box-templates.nix;
            nixarchyBox = self.packages.${system}.nixarchy-box;
            imagePins = boxImagePins;
          };

          # The half checks.box-template deliberately leaves alone: create a
          # real container from the default template's pinned image and enter
          # it, offline -- see tests/box-boot.nix.
          box-boot = import ./tests/box-boot.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            imagePin = boxImagePins.archlinux;
          };

          # The other disk mode, built so the cache has it: installer/cd.nix
          # bakes both onto the ISO, and an image built on a runner that has
          # only one of them compiles the difference from source.
          reference-unencrypted-toplevel =
            self.nixosConfigurations.reference-unencrypted.config.system.build.toplevel;

          # Why: docs/internals/flake.md#both-images-against-the-budgets-recorded-in-instal
          iso-budget =
            let
              pkgs = pkgsFor.${system};
              # MiB, as integers: nix has floats but this needs exact bytes, and
              # 6656 is less to get wrong than 6.5 * 1073741824.
              images = [
                {
                  name = "iso";
                  drv = self.packages.${system}.iso;
                  mib = 6656; # 6.5 GiB, over a measured 5.6 GB
                }
                {
                  name = "iso-net";
                  drv = self.packages.${system}.iso-net;
                  mib = 2048; # GitHub's release-asset limit, not a preference
                }
              ];
            in
            pkgs.runCommand "iso-budget" { } (
              "fail=0\n"
              + nixpkgs.lib.concatMapStrings (i: ''
                size=$(stat -Lc %s ${i.drv}/iso/*.iso)
                budget=$((${toString i.mib} * 1048576))
                awk -v n=${i.name} -v s="$size" -v b="$budget" \
                  'BEGIN { printf "%-8s %6.2f GiB   budget %5.2f GiB   %s\n", \
                     n, s/1073741824, b/1073741824, (s > b ? "OVER" : "ok") }'
                [ "$size" -le "$budget" ] || fail=1
              '') images
              + ''
                if [ "$fail" -ne 0 ]; then
                  echo
                  echo "An image outgrew its budget. Either something large joined the"
                  echo "closure by accident, or the budget in installer/cd.nix needs"
                  echo "raising on purpose -- but iso-net's 2 GiB is GitHub's limit on"
                  echo "a release asset, and cannot be raised, only worked around by"
                  echo "splitting the image the way release.yml splits the other one."
                  exit 1
                fi
                touch $out
              ''
            );
        }
      );
    };
}
