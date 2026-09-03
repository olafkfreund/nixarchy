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
      url = "github:basecamp/omarchy/v4.0.2";
      flake = false;
    };

    # Declarative Flatpaks, for the software nixpkgs genuinely does not carry.
    #
    # nixpkgs' own services.flatpak is infrastructure only -- the daemon, the
    # portals, polkit, FUSE -- and manages no applications. It does not even
    # add the flathub remote. So the honest answer this repo has been giving
    # is data/arch-extras.nix's `note = "then: flatpak install flathub ..."`,
    # which is advice to do the one thing this project exists to prevent:
    # install something imperatively that will not survive a rebuild.
    #
    # This adds `services.flatpak.packages`, overloading the same option
    # namespace nixpkgs uses -- worth knowing, because a reader will look for
    # `packages` in nixpkgs' module and not find it.
    #
    # Declared, not reproducible, and the distinction is real: the app IDS are
    # in your configuration and travel to a new machine, but the BITS are
    # whatever Flathub serves that day unless every entry pins a commit.
    # Rollback restores the list, not the version. Upstream nixpkgs has
    # declined to bless the equivalent (PR #347605, open since October 2024)
    # on exactly that objection. We take it anyway, because the alternative on
    # offer is a shell command in a comment.
    #
    # No `follows`: v0.7.0 has no inputs at all, which makes this the cheapest
    # kind of dependency -- nothing to override, nothing to drift.
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

    # Zen is not in nixpkgs and upstream maintains its own flake, which tracks
    # Zen's releases far more closely than a derivation here ever would.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The RDP server behind the remote-desktop feature (#159). Not in nixpkgs
    # -- nothing under that name as of 2026-09 -- and the two RDP servers that
    # are there cannot serve Hyprland: krdp needs the
    # org.freedesktop.portal.RemoteDesktop interface, which
    # xdg-desktop-portal-hyprland 1.4.1 does not advertise, and xrdp only
    # reaches Wayland through a wayvnc chain built from an unreleased commit.
    # So nixarchy carries the package until nixpkgs does.
    #
    # The cost, stated rather than hidden: a flake input lands in EVERY user's
    # lock, including the Mode A machine that will never enable RDP. It is one
    # more ref `nix flake update` can move and one more repository that has to
    # keep existing. That is paid because the thing it buys -- reaching this
    # desktop from a Windows machine with nothing installed on it -- has no
    # other implementation at all, at any price. See the alternatives survey
    # on #159; every other route is closed, not merely worse.
    #
    # What this project is taking on: v0.1.5, six months old, one primary
    # author. The protocol stack is not theirs -- it is IronRDP, Devolutions'
    # maintained Rust implementation -- so what this author owns is the
    # Hyprland glue: capture, input, audio, clipboard. That is a real
    # dependency on a small project, and a bad rebuild here breaks the machine
    # you are remote to, from where you cannot fix it. Hence a tag. Never a
    # branch, and bump it deliberately.
    #
    # The input has a named exit: when hypr-rdp lands in nixpkgs, delete this
    # and point the module at pkgs.hypr-rdp.
    #
    # `follows` is right here and wrong for hyprland above -- upstream's
    # pkg/nix/package.nix is a plain rustPlatform.buildRustPackage whose
    # cargoHash does not depend on which nixpkgs supplies ffmpeg, and they
    # publish no binary cache to forfeit by overriding it.
    hypr-rdp = {
      url = "github:MuNeNiCK/hypr-rdp/v0.1.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative secrets, adopted for one concrete reason rather than as a
    # general capability. #121 deliberately did not take a secrets mechanism
    # ("a separate decision with a key-management story attached"), and #122
    # got away without one because `hashedPasswordFile` is consumed by NixOS
    # itself, so the cleartext could live outside git and be pointed at.
    #
    # hypr-rdp removes that dodge. It reads its password from exactly two
    # places -- an inline string in config.toml, or `-p` on the command line,
    # which is world-readable in /proc/*/cmdline. Verified against v0.1.5:
    # src/config.rs resolves `args.password.or(config.password)` and nothing
    # else, there is no `password_file`, and clap reads no environment
    # variable for it. So the secret has to end up INSIDE a config file, and
    # something has to put it there at runtime from material safe to commit.
    #
    # That requirement is what picks sops-nix over agenix. agenix delivers
    # files of raw secrets and has no templating, so composing one into a TOML
    # would mean a hand-rolled per-service ExecStartPre shim -- the exact hack
    # this is meant to avoid. `sops.templates` is that shim, upstreamed, with
    # the mode and owner declared. Everything else between the two is taste.
    #
    # Pinned to a COMMIT because sops-nix publishes no release tags at all --
    # its only tag, `assets`, is from 2021 and is not a release. master is the
    # release channel. This is the same call flake.nix already makes for
    # hyprland above: a commit is exactly as reproducible as a tag. Bump it
    # deliberately; never track a branch.
    #
    # What this costs a user's lock: ONE node. sops-nix declares exactly one
    # input, nixpkgs, which follows ours, so nothing transitive arrives. (Its
    # dev inputs live in a private flake under dev/ that consumers never see.)
    # Its nixConfig asks for cache.thalheim.io, which does NOT apply to us --
    # nixConfig is honoured only from the flake you invoke, not from inputs --
    # so no substituter and no trust is granted by taking this.
    #
    # Inert on import, which is what makes it safe for Mode A: both halves of
    # the upstream module are gated, `lib.mkIf (cfg.secrets != { })` and
    # `lib.mkIf (config.sops.templates != { })`. A machine that defines
    # neither gets no unit, no activation script and no package. nixarchy sets
    # no sops scalar of its own -- `sops.age.sshKeyPaths` already defaults to
    # the ed25519 keys from services.openssh.hostKeys upstream -- so the
    # mkDefault rule in modules/services/default.nix never even arises here.
    # tests/options.nix asserts the inertness rather than trusting this note.
    sops-nix = {
      url = "github:Mic92/sops-nix/a8627b21b9107c5711c96b84f32a9a4b3d45295f";
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

        # The RDP daemon, re-exported from its own flake so the module that
        # will run it (#156) can say `pkgs.hypr-rdp` and never mention an
        # input. Built by upstream's pkg/nix/package.nix against OUR nixpkgs,
        # through the `follows` on the input.
        #
        # This indirection is what makes the input's exit cheap: when nixpkgs
        # carries hypr-rdp, delete the input and this attribute, and every
        # `pkgs.hypr-rdp` in the tree keeps resolving -- to nixpkgs' own.
        #
        # Lazy, so a machine that never enables RDP never builds it. Being in
        # the overlay is not being on the system.
        hypr-rdp = inputs.hypr-rdp.packages.${final.stdenv.hostPlatform.system}.hypr-rdp;

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

        # The boot splash, and nothing else on the disk with it.
        #
        # The omarchy package already carries share/plymouth/themes/omarchy,
        # and on a desktop that is the right place for it: the machine has the
        # package anyway. The live image does not. It deliberately does not
        # import nixosModules.nixarchy (see installer/cd.nix), so naming the
        # desktop package in boot.plymouth.themePackages would be the only
        # reason it were there -- and nixpkgs' plymouth module puts
        # themePackages into environment.etc, so the named package joins the
        # system closure whole: 411.9 MiB on an image budgeted at 2.00 GiB,
        # which is GitHub's limit on a release asset rather than a preference.
        # These assets are 180 KiB.
        #
        # Copied out of the same package rather than assembled again, so the
        # theme is built in exactly one place and the image's splash cannot
        # differ from the installed one. Nothing is rewritten here:
        # omarchy.plymouth already points at /etc/plymouth/themes/omarchy, so
        # this output has no store references and costs only its own size.
        nixarchy-plymouth = final.runCommand "nixarchy-plymouth-theme" { } ''
          install -d $out/share/plymouth/themes
          cp -r ${final.omarchy}/share/plymouth/themes/omarchy \
            $out/share/plymouth/themes/omarchy
        '';
      };

      packages = eachSystem (system: {
        default = self.packages.${system}.omarchy;
        inherit (pkgsFor.${system}) omarchy nixarchy-plymouth;

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
          ];
          text = builtins.readFile ./pkgs/verify.sh;
        };

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

        # `nix run .#release-notes <from-tag> <to-ref>` -- what changed for
        # someone running nixarchy, between two releases. release.yml puts its
        # output above the download instructions on the release page.
        #
        # An app for the same reason `review` is one: it evaluates the option
        # set at two revisions and asks GitHub what upstream shipped, and a
        # check has neither a network nor a second checkout. The half that
        # needs neither is checks.release-notes, which drives this whole script
        # against a fixture repository.
        #
        # It carries omarchy-package-delta.sh rather than reimplementing it:
        # the question "what did this Omarchy release add and drop" already has
        # an answer here, and two of them would disagree eventually.
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

        # `nix run .#devenv-presets` -- scaffolds every preset in
        # data/devenv-presets.nix with the real `nixarchy dev init`, then asks a
        # real devenv to evaluate what it wrote.
        #
        # This is the whole safety net under that catalogue. `lines` is a
        # string, so a preset that names an option devenv renamed is a valid Nix
        # file and a broken project, and nothing in `nix flake check` would ever
        # say so. It runs the command rather than reproducing what it does,
        # because a check that scaffolds its own devenv.nix tests a copy.
        #
        # NOT in `checks`, and that is not an oversight. #150 proposed it as one
        # on the reasoning that a full `devenv shell` needs the network but
        # evaluation does not. That is wrong, twice over: evaluating a devenv
        # project fetches the inputs devenv.yaml names
        # (github:cachix/devenv-nixpkgs/rolling), and devenv's own flake reaches
        # them through import-from-derivation -- `nix flake show
        # github:cachix/devenv` fails with `allow-import-from-derivation is
        # disabled` before it prints anything. A sandboxed derivation has
        # neither, so `checks.devenv-presets` could not run at all. A workflow
        # job that has a network does, and build.yml has one.
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

        # The same installer, without the desktop on it. Small enough to
        # download over a hotel connection, and it fetches the closure from
        # the binary caches instead of carrying it. Needs a working network
        # before it can do anything, which is what the wizard's first screen
        # is for.
        iso-net = self.nixosConfigurations.iso-net.config.system.build.isoImage;

        # A VM that installs onto a blank disk, WITH a network -- which
        # checks.install cannot have, because it is a sandboxed derivation and
        # its whole point is that a rebuild afterwards cannot fetch anything.
        # See installer/vm.nix.
        #
        # Wrapped rather than exported raw: the generated run script creates
        # two sparse qcow2 images and only discovers they do not fit hours
        # later, from inside the guest. installer/vm-preflight.sh checks first
        # and says so. The sizes come from the configuration itself so the
        # check cannot drift away from what the VM actually asks for.
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

            # One module that imports the machine's own two, rather than two
            # entries in this list. It has to be shaped this way, because the
            # generated flake's hosts/<name>/default.nix is shaped this way:
            # `imports` inside a module and entries in `modules` are merged in
            # different orders, so the flat form gives a different
            # environment.systemPackages ORDER -- same packages, same closure,
            # different list -- and system-path hashes that order into
            # chosenOutputs. A different system-path is a different toplevel,
            # and on an ISO with no network the installed machine can no longer
            # copy the one baked here: it has to build it, which means stdenv,
            # which means the source bootstrap from hex0-seed.
            #
            # Nothing about the packages differs. Only the order does, and only
            # the order has to.
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

        # The installer's interactive screens, at every width worth caring
        # about. Nothing else draws them: every other harness passes
        # --answers, which is exactly how #133 shipped.
        installer-ui = import ./tests/installer-ui.nix {
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

        # Both images, against the budgets recorded in installer/cd.nix.
        #
        # A check rather than a comment because a number nobody enforces is a
        # number that drifts. The nightly runs this; it costs nothing beyond
        # the ISO builds it already does.
        #
        # The iso-net budget is the load-bearing one, and it is not a taste
        # question: GitHub refuses a release asset over 2 GiB, so an iso-net
        # that crosses it stops being publishable as a single file and
        # release.yml would have to start splitting it. Failing here says so
        # while there is still something to do about it, rather than at the
        # next tag.
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
      });
    };
}
