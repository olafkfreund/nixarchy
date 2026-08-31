{
  description = "Nixarchy - Omarchy, vendored for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default-linux";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Omarchy 4.x configures Hyprland through the Lua API that landed in
    # 0.55; nixpkgs is still on 0.54.3.
    #
    # Pinned to a COMMIT, not the v0.56.2 tag, because that tag does not build
    # against its own flake.lock: its CMakeLists asks for
    # `find_package(glaze 7...<8)` while nix/overlays.nix feeds it the
    # glaze 8.0.0 from its locked nixpkgs. find_package fails, CMake falls
    # back to cloning glaze over the network, and the sandbox has none.
    # Upstream dropped the version bound after tagging, and v0.56.2 is the
    # newest tag, so there is no fixed tag to move to.
    #
    # A commit is just as reproducible as a tag. Bump it deliberately; never
    # track a branch here, or `nix flake update` could break the bar on its
    # own while the Lua bindings are still moving.
    #
    # Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`: hyprwm asks
    # consumers not to override it, and doing so forfeits their binary cache
    # and rebuilds the compositor from source. See nix.settings in
    # modules/nixos.nix for the matching substituter.
    hyprland.url = "github:hyprwm/Hyprland/0bd11c7a04a63d2785abd53363f09d552175d67d";

    omarchy = {
      url = "github:basecamp/omarchy/v4.0.1";
      flake = false;
    };

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

    # Zen is not in nixpkgs and upstream maintains its own flake, which tracks
    # Zen's releases far more closely than a derivation here ever would.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
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

      omarchyVersion = "4.0.1";
    in
    {
      overlays.default = final: _prev: {
        # Apps Omarchy offers that nixpkgs does not carry. Packaged here so a
        # NixOS user gets the same menu Arch users do, rather than a menu with
        # holes in it.
        nixarchy-apps = {
          once = final.callPackage ./pkgs/apps/once.nix { };
          grok-bot = final.callPackage ./pkgs/apps/grok-bot.nix { };

          # nixpkgs' `hey` is an unrelated HTTP load generator, so this cannot
          # simply follow nixpkgs the way most apps here do.
          hey-cli = final.callPackage ./pkgs/apps/hey-cli.nix { };

          # Not built here -- upstream's own flake, re-exported into the overlay
          # so nixarchy-doctor and the Install menu can find it.
          #
          # Both ask pkgs for an app's meta.mainProgram to learn which command it
          # puts on PATH, and fall back to the attribute name when the lookup
          # fails. zen-browser lived only in packages.<system>, so the lookup
          # returned null and the fallback answered "zen" -- a command that does
          # not exist, because this package installs bin/zen-beta. The doctor
          # could never report Zen as present and the menu never dimmed its row.
          #
          # Exactly the vscode/code trap the doctor was written to avoid, reached
          # by a different road: not a wrong mainProgram, but a package the probe
          # could not see.
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

          # nixpkgs' `retroarch` is `retroarch-with-cores` built with an
          # EMPTY core list, so installing it gives an emulator that can run
          # nothing. `retroarch-full` is the obvious fix and the wrong one:
          # it pulls unfree cores, and an unfree package in the app list
          # aborts the whole rebuild rather than failing on its own.
          #
          # So: every core Omarchy's own picker offers that nixpkgs ships
          # under a free licence, minus the two that dwarf the rest.
          # snes9x and genesis-plus-gx are unfree, hence bsnes and blastem
          # for those systems.
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

        omarchy = final.callPackage ./pkgs/omarchy {
          src = omarchy;
          version = omarchyVersion;
          # The compositor the Lua config is written against, not nixpkgs'.
          inherit (hyprland.packages.${final.stdenv.hostPlatform.system}) hyprland;

          # nixpkgs is on 0.3.0, whose session lock aborts on DPMS.
          #
          # WlSessionLock::updateSurfaces reached qFatal -- "Tried to show
          # lockscreen surfaces without active lock" -- when screens slept and
          # woke while locked. quickshell dies, and because the Wayland
          # session-lock protocol deliberately keeps the compositor locked when
          # its lock client disappears, the machine is left blank with nothing to
          # type a password into. Reboot is the only way out. Seen three times in
          # one night, ~65-70 MB of coredump each.
          #
          # v0.3.1 fixes it, and says so in as many words: "Fixed session lock
          # crashes on sleep, wake, DPMS, and unlocking." Three commits touch
          # wayland/lock; 897fcdaa is this one -- it null-checks the wayland
          # output and skips placeholder screens instead of asserting.
          #
          # overrideAttrs rather than a fork: nixpkgs keeps the build, the Qt
          # wrapper and the dependency set, and only the tag moves. Passed here
          # rather than set on the overlay, so a machine using quickshell for
          # something of its own keeps nixpkgs'.
          #
          # DELETE THIS once nixpkgs ships >= 0.3.1.
          quickshell = final.quickshell.overrideAttrs (_: rec {
            version = "0.3.1";
            src = final.fetchzip {
              url = "https://git.outfoxxed.me/quickshell/quickshell/archive/refs/tags/v${version}.tar.gz";
              hash = "sha256-CLX2Zp5i5BuLbOxNOkwRd9YY84IOrACNxBV79o9/F9Y=";
            };
          });
          # The screensaver's text-effects engine, packaged in this repo rather
          # than nixpkgs. Passed explicitly for the same reason hyprland is: it
          # lives under nixarchy-apps, which callPackage does not search.
          inherit (final.nixarchy-apps) ttfx;
        };
      };

      packages = eachSystem (system: {
        default = self.packages.${system}.omarchy;
        inherit (pkgsFor.${system}) omarchy;

        # `nix run github:olafkfreund/nixarchy#verify`, from inside a running
        # Omarchy session. Everything in checks/ runs in a machine with no GPU,
        # no Bluetooth radio, no network and no sound; this asks the questions
        # that leaves unanswered.
        # `nix run github:olafkfreund/nixarchy#install`, as root, from a NixOS
        # live ISO. Formats ONE disk with installer/disk-config.nix, writes the
        # generated flake to /mnt/etc/nixos and runs nixos-install against it.
        #
        # Every answer ends up as text in that flake: the machine it produces
        # belongs to the flake, not to this script.
        install = pkgsFor.${system}.writeShellApplication {
          name = "nixarchy-install";
          runtimeInputs = with pkgsFor.${system}; [
            gum
            coreutils
            gnused
            gnugrep
            gawk
            findutils
            util-linux # lsblk, findmnt
            git
            mkpasswd
            nixos-install-tools # nixos-install, nixos-generate-config
            nix
            ncurses # clear and tput, which the screens are drawn with
            kbd # loadkeys, and the keymap list
            tzdata # the timezone list
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
              ]
              (builtins.readFile ./installer/install.sh);
        };

        # The flake the installer writes to /etc/nixos: the template files with
        # their @tokens@ still in place, plus a lock derived from this repo's
        # own so the installed machine resolves to exactly what was built.
        # Requires a committed tree -- it pins nixarchy by commit.
        flake-template = pkgsFor.${system}.callPackage ./installer/mkFlake.nix { inherit self; };

        verify = pkgsFor.${system}.writeShellApplication {
          name = "nixarchy-verify";
          runtimeInputs = with pkgsFor.${system}; [
            systemd
            gnugrep
            gnused
            coreutils
            findutils
            glib
            bluez
          ];
          text = builtins.readFile ./pkgs/verify.sh;
        };

        # `nix run github:olafkfreund/nixarchy#doctor` -- reads the running
        # system and prints the configuration it would need. Runnable before
        # nixarchy is an input anywhere, which is the only entry point someone
        # deciding whether to adopt it actually has.
        doctor = pkgsFor.${system}.writeShellApplication {
          name = "nixarchy-doctor";
          runtimeInputs = with pkgsFor.${system}; [
            systemd
            gnused
            gnugrep
            gawk
            coreutils
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
              [ "@apps@" ]
              [
                (
                  let
                    pkgs = pkgsFor.${system};
                    apps = import ./data/apps.nix;
                    usable = nixpkgs.lib.filterAttrs (_: a: !(a ? unavailable)) apps;
                    binaryOf =
                      name: app:
                      let
                        probe = builtins.tryEval (
                          let
                            # nixarchy-apps first, then the top level. Apps
                            # this repo packages live under nixarchy-apps, so
                            # probing only the top level returned null for every
                            # one of them and the fallback answered with the
                            # attribute name. That is right by luck when the
                            # attribute matches the binary -- once, omacut,
                            # ttfx -- and wrong when it does not: `zen` for a
                            # package installing bin/zen-beta, `hey-cli` for one
                            # installing bin/hey. Both were reported as absent
                            # on machines that had them.
                            path = nixpkgs.lib.splitString "." (app.attr or name);
                            p = nixpkgs.lib.attrByPath path (nixpkgs.lib.attrByPath path null pkgs) pkgs.nixarchy-apps;
                          in
                          if p == null then null else (p.meta.mainProgram or null)
                        );
                      in
                      if probe.success && probe.value != null then probe.value else name;
                  in
                  nixpkgs.lib.concatStringsSep "\n" (
                    nixpkgs.lib.mapAttrsToList (n: a: "${binaryOf n a}\t${a.label or n}") usable
                  )
                )
              ]
              (builtins.readFile ./pkgs/doctor.sh);
        };

        # A screencast of a real session, plus the frames it was made from.
        # Not a check: it boots a desktop, drives a tour of it and encodes a
        # video, which is minutes of work nobody wants on every push. Build it
        # with `nix build .#demo` when the screencast needs refreshing.
        demo = import ./tests/demo.nix {
          inherit inputs;
          pkgs = pkgsFor.${system};
        };

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

        # `nix run .#update` -- rewrites the pinned version and hashes in
        # place. CI runs it weekly and opens a PR. Only `once` is pinned by
        # hand now; everything else follows nixpkgs or upstream's own flake.
        update = pkgsFor.${system}.nixarchy-apps.once.updateScript;

        # Boot the smoke test: `nix run .#vm`
        vm = self.nixosConfigurations.vm.config.system.build.vm;

        # The same machine with room for a model: `nix run .#vm-big`.
        # 32GB, 8 cores, and a real disk rather than a tmpfs root.
        vm-big = self.nixosConfigurations.vm-big.config.system.build.vm;

        # The bootable image: boot it and answer the questions. Still online
        # at this stage -- #15 bakes the closure onto it, #16 takes the
        # network away.
        iso = self.nixosConfigurations.iso.config.system.build.isoImage;

        # A VM that installs onto a blank disk, WITH a network -- which
        # checks.install cannot have, because it is a sandboxed derivation and
        # its whole point is that a rebuild afterwards cannot fetch anything.
        # See installer/vm.nix.
        installer-vm = self.nixosConfigurations.installer-vm.config.system.build.vm;

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
      });

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
          specialArgs = { inherit inputs; };
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

        # The same VM with room to run a model.
        #
        # `.#vm` is a smoke test and is sized like one: 8GB, and an ephemeral
        # root, which is right for catching a broken desktop and wrong for
        # anything to do with programs.nixarchy.localAi. Two reasons, and the
        # second is the one that is not obvious:
        #
        #   - 8GB does not hold a useful model. qwen3:8b is 5.2GB of weights
        #     before any cache.
        #
        #   - diskImage = null puts the root on a tmpfs, so the weights live in
        #     RAM. They are then paid for twice, once to store and once to load,
        #     out of the same pool -- and the service is OOM-killed while every
        #     visible number says it had room. Observed, not theorised.
        #
        # So this one has a real disk, which also means a pulled model survives
        # a restart rather than being re-downloaded every time.
        #
        #   nix run .#vm-big
        #   ssh -p 2224 omarchy@localhost      (password: omarchy)
        #
        # It writes nixarchy-vm-big.qcow2 into the working directory and REUSES
        # it, which is the point here and is exactly what .#vm avoids. Delete
        # that file to start clean.
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
      };

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./shell.nix { };
      });

      # The installed machine, as the installer would produce it. Both disk
      # modes come from here so they cannot drift apart, and so installer/cd.nix
      # can bake each one onto the image without restating the host.
      lib.mkReference =
        { encrypt }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.nixarchy
            home-manager.nixosModules.home-manager
            inputs.disko.nixosModules.disko
            (import ./installer/host.nix {
              hostname = "nixarchy";
              username = "omarchy";
            })
            (import ./installer/disk-config.nix {
              device = "/dev/vda";
              inherit encrypt;
            })
          ];
        };

      formatter = eachSystem (system: pkgsFor.${system}.nixfmt-tree);

      checks = eachSystem (system: {
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

        # Every option that adds something, checked with it turned off too --
        # see tests/options.nix for why that half is the one at risk.
        options = import ./tests/options.nix {
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

        # The same question as checks.install, asked of the artefact people
        # download rather than of a test node: boots the ISO with no network
        # device at all and installs from what the image carries.
        install-iso = import ./tests/install-iso.nix {
          inherit inputs;
          pkgs = pkgsFor.${system};
        };

        vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;

        # The installed machine, as opposed to the smoke-test guest: a real
        # bootloader, disko-provided filesystems, nothing faked. If this builds
        # and vm-toplevel builds, the extraction has not let the two drift.
        reference-toplevel = self.nixosConfigurations.reference.config.system.build.toplevel;

        # The other disk mode, built so the cache has it: installer/cd.nix
        # bakes both onto the ISO, and an image built on a runner that has
        # only one of them compiles the difference from source.
        reference-unencrypted-toplevel =
          self.nixosConfigurations.reference-unencrypted.config.system.build.toplevel;
      });
    };
}
