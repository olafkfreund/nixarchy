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

          # Two of the four applications Omarchy writes itself. nixpkgs has
          # none of them, which is why modules/nixos.nix cannot reproduce
          # upstream's preinstall set; these two close half that gap.
          omawrite = final.callPackage ./pkgs/apps/omawrite.nix { };
          omacalc = final.callPackage ./pkgs/apps/omacalc.nix { };

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

        omarchy = final.callPackage ./pkgs/omarchy {
          src = omarchy;
          version = omarchyVersion;
          # The compositor the Lua config is written against, not nixpkgs'.
          inherit (hyprland.packages.${final.stdenv.hostPlatform.system}) hyprland;
        };
      };

      packages = eachSystem (system: {
        default = self.packages.${system}.omarchy;
        inherit (pkgsFor.${system}) omarchy;

        # `nix run github:olafkfreund/nixarchy#verify`, from inside a running
        # Omarchy session. Everything in checks/ runs in a machine with no GPU,
        # no Bluetooth radio, no network and no sound; this asks the questions
        # that leaves unanswered.
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
                            p = nixpkgs.lib.attrByPath (nixpkgs.lib.splitString "." (app.attr or name)) null pkgs;
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
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          self.nixosModules.nixarchy
          home-manager.nixosModules.home-manager
          ./vm/configuration.nix
        ];
      };

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./shell.nix { };
      });

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

        vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;
      });
    };
}
