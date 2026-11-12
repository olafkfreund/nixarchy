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
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
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

    # Declarative runtime theme switching and application bridges. The input
    # stays pinned so the network image and installed systems agree on the
    # plugin manifest and module interface.
    nixarchy-omatheme = {
      url = "github:olafkfreund/nixarchy-omatheme/51fb12943b66389da778af42926e06e80691dd53";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Stable nixpkgs, carried so CI can prove this flake still evaluates
    # against it (#527).
    #
    # PINNED in the lock rather than resolved fresh, and the split is
    # deliberate. A moving ref would turn every open pull request red the
    # moment upstream moved, for a reason none of their authors could fix --
    # which is the failure that took the roadmap check off pull requests
    # earlier in this file's history. nightly.yml's canary already owns
    # upstream drift: it runs a bare `nix flake update` and its failure has
    # its own identity, "a canary failure means UPSTREAM moved under us".
    #
    # So: pull requests get a fixed answer, and the canary is what notices
    # 26.05 moving. Two questions, two places, neither pretending to be the
    # other.
    #
    # Nothing on a user's machine reads this. It is a check input, and the
    # only thing that evaluates it is tests/stable-eval.nix.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    # The same, on the release branch, for a machine whose nixpkgs is a
    # release rather than unstable (#525).
    #
    # home-manager and nixpkgs are developed as a pair, and home-manager says
    # so itself: point this flake's nixpkgs at nixos-26.05 and every
    # evaluation carries its warning that "using mismatched versions is
    # likely to cause errors and unexpected behavior" -- version 26.11
    # against nixpkgs 26.05. That is upstream's judgement, not ours.
    #
    # installer/template/flake.nix has told users to move the two together
    # since it was written. This is that advice applied to this flake, so the
    # advice is something the project follows rather than only prints.
    #
    # Worth being plain about the cost of NOT doing it, because it is not the
    # warning itself: modules/nixos.nix now emits a real warning on stable,
    # about screen sharing being gone. A second warning that every stable
    # evaluation prints and nobody can act on is what teaches a reader to
    # skip both.
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#hyprland-from-hyprwm-tracking-their-branch-not-a
    hyprland.url = "github:hyprwm/Hyprland";

    omarchy = {
      url = "github:basecamp/omarchy/36b70f1bce6c9b94b800a322d1fa317c7b4f139a";
      flake = false;
    };

    # Why: docs/internals/flake.md#declarative-flatpaks-for-the-software-nixpkgs-genu
    nix-flatpak.url = "github:gmodena/nix-flatpak/v0.8.0";

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
    # tarball the network image copies into inputSources for nothing.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#zen-is-not-in-nixpkgs-and-upstream-maintains-its-o
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake/7ae4b419e36f18fa5743556e379e4b0154171949";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#gliff-from-a-non-flake-input-pinned-to-a-tag
    gliff = {
      url = "github:omacom/gliff/v0.4.2";
      flake = false;
    };

    # Why: docs/internals/flake.md#declarative-secrets-adopted-for-one-concrete-reaso
    sops-nix = {
      url = "github:Mic92/sops-nix/b18e01ce148eb3efff5de2f2d3181ca53b2b2a54";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tracks nixi-nixarchy master; the lock is the pin (`nix flake update nixi`
    # moves it). Nixi's master needs 5 green checks (#1432).
    # Why: docs/internals/flake.md#nixi
    nixi = {
      url = "github:olafkfreund/nixi-nixarchy";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.omarchy.follows = "omarchy";
    };

    # Not in nixpkgs; tracks main like nixi. The fork has no CI, and it is built
    # only where services.nixi.companion.enable is on.
    nixi-companion = {
      url = "github:olafkfreund/nixoarchy-snowflake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Speech into desktop actions (#774). An input on every machine while the
    # app is on none, which is not a contradiction: data/apps.nix is data, and
    # this module only does anything once somebody sets
    # programs.nixarchy.voice.enable (programs.omarchy-voice upstream). It is
    # not in defaultPluginSet and must not be -- 7.2 GiB with whisper and the
    # Piper models, measured at this pin (#1147; 6.7 GiB before v2.4.0 shipped
    # a second whisper model), and the models
    # are IN the package, so an off switch would not shrink the machine or the
    # ISO.
    #
    # nixarchy overrides none of its defaults, deliberately. Desktop control,
    # the notification log and the wake word all start off upstream as of
    # nixarchy-voice#19 and #21, and the "Jenny (Dioco)" attribution is in the
    # built wrapper. Restating any of that here would be a second place to
    # change and would hide an upstream regression rather than catch it --
    # checks.options asserts the off state instead.
    #
    # Pinned to a COMMIT: a branch is not a version. (nixi above tracks its
    # branch by decision, #1432; this input has not been through that call.)
    nixarchy-voice = {
      url = "github:olafkfreund/nixarchy-voice/2bcba434b9fc402117db0c482fb9277bcbb8ea7d";
      inputs.nixpkgs.follows = "nixpkgs";
      # Voice types through ai-mirror's input helper; one ai-mirror, not two.
      inputs.ai-mirror.follows = "ai-mirror";
    };

    # ai-mirror (#773): the binary and its bar widget on every machine, no agent
    # connected to it unless programs.nixarchy.aiMirror.mcp says so. Tracks
    # ai-mirror master like nixi; the lock is the pin (`nix flake update ai-mirror`
    # moves it). Its master requires the check CI to merge.
    # ai-mirror#81: survives a Hyprland restart; revokes a grant whose Hyprland is gone
    # ai-mirror#83: typing into an overlay panel beside always-mapped surfaces;
    # ai-mirror#85: a confirm that cannot grant is no longer audited as confirmed
    # 3.1.0 (ai-mirror#78): Agent cursor badge + screen frame during a grant;
    # needs packages.cursor installed (modules/home.nix)
    # 3.0.0 (#1436): every mutating call needs generation;
    # a11y_act set_value/select, read back
    # Why: spec/2026-09-22-773-ai-mirror-default.md, docs/internals/flake.md#ai-mirror
    ai-mirror = {
      url = "github:olafkfreund/ai-mirror";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The Nix skills nixarchy's agents get alongside its own (#888). Pinned at
    # or after the commit that added the MIT licence (nix-skills#33): a
    # repository with no licence grants no right to ship it on every machine,
    # which is what ai-mirror needed too (#773).
    nix-skills = {
      url = "github:olafkfreund/nix-skills/0ef9aeb";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-package-manager-panel-on-by-default-766
    # A commit on main (no tags); bump it the way that page says.
    nixarchy-pkg = {
      url = "github:olafkfreund/nixarchy-pkg/b7786c244036ebf90b2c983768d2a0bd43a0d094";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-podman-panel-wherever-podman-is-on-766
    # A commit on master (that repo's default branch, no tags).
    nixarchy-podman = {
      url = "github:olafkfreund/nixarchy-podman/e1aaf126343eb0c408357cf86f5b5ae25a940c3e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#gliff-manager-from-a-nixos-ready-fork
    nixarchy-gliff-manager = {
      url = "github:olafkfreund/nixarchy-gliff-manager/5b868f6acf98cdfa9231ebec5c97a6326ca90222";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Why: docs/internals/flake.md#the-gitlab-pipelines-panel-on-by-default-770
    # A commit on main (no tags); bump it the way that page says.
    nixarchy-gltui = {
      url = "github:olafkfreund/nixarchy-gltui/8445d254c75450bdce3a9e52a9ecfafa0d164872";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-github-actions-panel-on-by-default-772
    # A commit on main (no tags); bump it the way that page says.
    nixarchy-ghtui = {
      url = "github:olafkfreund/nixarchy-ghtui/3fb9c8d91e923cf9a4c2871d14b13ad3557b0c0b";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-flatpak-and-snap-panel-on-by-default-912
    # A commit on main (no tags); bump it the way that page says. Its
    # nix-snapd is the only one nixarchy imports (modules/nixos.nix).
    nixarchy-flatsnap = {
      url = "github:olafkfreund/nixarchy-flatsnap/e9532c33f40b765b01d7fc683bc92a2364e45913";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-flatpak.follows = "nix-flatpak";
    };

    # Why: docs/internals/flake.md#nixarchy-menu-installed-and-off-by-default-946-1052-1283
    # A commit on main (no tags); bump it the way that page says. Its only
    # inputs are these two, so it adds nothing to the lock but itself.
    nixarchy-menu = {
      url = "github:olafkfreund/nixarchy-menu/cfb4fc1ee59d7397317ecab2eafbfef74ef42e1c";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.omarchy.follows = "omarchy";
    };

    # Why: docs/internals/flake.md#the-herdr-sessions-widget-on-by-default-771
    # No flake upstream, so nothing to follow; a commit on master, bumped the
    # way that page says.
    nixarchy-herdr = {
      url = "github:olafkfreund/nixarchy-herdr/affd9854cf184622380e5433b4003e3aa82593e0";
      flake = false;
    };

    # Why: docs/internals/flake.md#hyprforge-on-by-default-1059
    # Third-party (Aziz, MIT) via olafkfreund's fork, no flake upstream; a
    # reviewed commit, bumped the way that page says.
    nixarchy-hyprsettngs = {
      url = "github:olafkfreund/nixarchy-hyprsettngs/367ca99ea9bb0cb32be2241a9a38a3b1e3d2ff9d";
      flake = false;
    };

    # Why: docs/internals/flake.md#the-distrobox-panel-wherever-boxes-are-766
    # A commit on main (no tags); bump it the way that page says.
    nixarchy-distrobox = {
      url = "github:olafkfreund/nixarchy-distrobox/cfa684f21bdf7a896cd403d1a7b5bf32fefb6cdc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-dev-environments-panel-wherever-devenv-is-802
    # A commit on main (no tags); bump it the way that page says.
    nixarchy-devenv = {
      url = "github:olafkfreund/nixarchy-devenv/e1c718081d8de2bf72848a05a304a834a448b855";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-plugin-browser-on-by-default-913
    # A commit on master (no tags); bump it the way that page says.
    nixarchy-plugin-browser = {
      url = "github:olafkfreund/nixarchy-plugin-browser/1f21a1b3995b967d4792d78156808f5eec5bd770";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#the-microvms-panel-on-by-default-766
    # A commit on main (no tags); bump it the way that page says.
    nixarchy-microvm = {
      url = "github:olafkfreund/nixarchy-microvm/ca0bc01f11ac5438c1a174ea75559a869bd5616e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The MCP configuration framework, for #623 -- the NixOS MCP server the
    # coding agents on this desktop get so they stop guessing option names.
    #
    # Not carrying the server: `mcp-nixos` is in nixpkgs, and is taken from
    # there through this flake's own pkgs. What nixpkgs has none of is the
    # part that is actually hard -- three agents want the same server declared
    # three different ways. Claude Code wants `mcpServers` in JSON, Codex
    # wants `mcp_servers` in TOML, opencode wants `mcp` with the command as an
    # array and a `type` of "local". `lib.mkConfig` knows all three, and a
    # hand-rolled writer is how a config that works in one agent silently
    # writes a key the other two never read.
    #
    # `follows`, and it matters more here than usual: the server package is
    # resolved through `servers = nixpkgs.extend <their overlay>`, so with the
    # follows it is OUR mcp-nixos and without it a second one from a second
    # nixpkgs -- the buildEnv collision modules/AGENTS.md describes, arriving
    # by a new route.
    #
    # Pinned to a COMMIT because this repository publishes no tags at all
    # (`git ls-remote --tags` is empty), which is the situation sops-nix is
    # already in. Bump it deliberately; never track the branch.
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix/094e3ba3ee36c5c0bb2bfc4e97ad30d84041ff89";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The `nixos` MCP server itself, for #1166 -- a fork of mcp-nixos that
    # also answers from nixarchy's own options and manual
    # (`/etc/nixarchy/options.json`, `/etc/nixarchy/docs`), not just nixpkgs'.
    # `programs.nixos.package` in modules/home.nix points at it; the server
    # key stays `nixos`, so tool names and permissions are unchanged.
    #
    # `follows`, for the same reason as mcp-servers-nix above: the server
    # runs inside the `servers = nixpkgs.extend <overlay>` closure, so without
    # it this is a second nixpkgs and a second Python closure to build.
    #
    # Pinned to a release tag (release-please); the nightly review flags a newer
    # one. Bump it deliberately.
    mcp-nixarchy = {
      url = "github:olafkfreund/mcp-nixarchy/v3.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The prebuilt nix-index database, for #628 -- `command-not-found` that
    # answers, and `comma`.
    #
    # The reason this is an input rather than `pkgs.nix-index` is the whole
    # feature: nix-index's own database is built by running `nix-index`, which
    # walks every store path nixpkgs describes and takes hours. A tool that
    # answers "which package has this command" only after an afternoon of
    # indexing is a tool nobody on a fresh install ever gets an answer from.
    # This repository publishes that database, built weekly against
    # nixos-unstable, as a fetchable artifact.
    #
    # Pinned to one of its weekly TAGS rather than to `main`: the database is
    # dated by construction, so the pin should say which date, and a branch
    # would move the closure under every open pull request. The lock bump
    # moves it.
    #
    # `follows`, so the wrapper packages are built against the nixpkgs the
    # machine is on -- the database is a data file and does not care, but
    # `comma` and `nix-index` are binaries that would otherwise be a second
    # copy of what is already in the profile.
    nix-index-database = {
      url = "github:nix-community/nix-index-database/2026-09-06-071918";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Why: docs/internals/flake.md#221-222
    microvm = {
      url = "github:microvm-nix/microvm.nix/b7bd556974fa8a171b5b639200e81d52244dfde4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      home-manager,
      home-manager-stable,
      nixpkgs-stable,
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

      boxImages = eachSystem (
        system:
        lib.mapAttrs (
          _: pin:
          pkgsFor.${system}.dockerTools.pullImage {
            inherit (pin) imageName imageDigest sha256;
            finalImageTag = pin.tag or "latest";
          }
        ) boxImagePins
      );

      omarchyVersion = "edge-20261112-36b70f1";

      # home-manager, matched to whichever nixpkgs this is being evaluated
      # against (#525).
      #
      # The two are developed as a pair, and home-manager warns when they are
      # not: "Home Manager version 26.11 and Nixpkgs version 26.05 ... likely
      # to cause errors and unexpected behavior". Nothing here overrides a
      # user's choice -- it FOLLOWS it. Whatever nixpkgs the machine is on
      # picks the home-manager built for it.
      #
      # `lib.trivial.release` is nixpkgs' own release string ("26.05",
      # "26.11"), so this reads the package set actually in use rather than
      # any flag or option someone has to remember to set.
      #
      # The accepted weakness, stated rather than hidden: `stableRelease`
      # must name the same release as the home-manager-stable input's URL,
      # and nothing here can check that -- a flake input URL is not readable
      # from inside the flake. The two move together when NixOS cuts a
      # release. What makes that survivable is that being wrong is LOUD: if
      # they disagree, home-manager's own mismatch warning is exactly what
      # comes back, which is the thing this exists to remove.
      #
      # A machine on some third release (25.11, say) gets master and its
      # warning. That is honest -- this project carries one release branch,
      # not every one -- and the warning names the real situation.
      stableRelease = "26.05";
      homeManagerFor =
        release:
        if release == stableRelease then
          home-manager-stable.nixosModules.home-manager
        else
          home-manager.nixosModules.home-manager;
      homeManagerModule = homeManagerFor lib.trivial.release;

      # The smoke VM's module list, shared by the real configuration and by
      # the stable evaluation in tests/stable-eval.nix (#527).
      #
      # Shared rather than copied, because a check that proves "this
      # evaluates on stable" while evaluating a DIFFERENT set of modules
      # proves nothing about the thing it names -- and a copied list is one
      # somebody extends in exactly one of the two places. Same failure mode
      # config-warnings.nix avoids by deriving its configuration list instead
      # of writing one down.
      #
      # A function of the home-manager module rather than a plain list: the
      # two systems need different ones, and the ORDER has to stay exactly as
      # it was. environment.systemPackages order reaches buildEnv, so moving
      # a module is not free even when the resulting set is identical.
      vmModulesWith = inputs: hm: [
        inputs.self.nixosModules.nixarchy
        hm
        ./vm/configuration.nix
      ];

      # This flake, evaluated against stable nixpkgs. NOT a
      # nixosConfigurations entry, deliberately: config-warnings.nix maps over
      # every entry there, so adding one would pull a full stable evaluation
      # into an unrelated check -- and that check asserts on warnings, while
      # this configuration emits one on purpose (the screen-sharing note in
      # modules/nixos.nix). It would have gone red on arrival, for a reason
      # that is correct behaviour.
      #
      # Wired the way an installed stable machine is: installer/template's
      # `follows` makes nixarchy's own nixpkgs the user's 26.05, and the
      # 26.05 home-manager comes with it. Built from this flake's inputs
      # instead, every `inputs.nixpkgs` read inside the modules saw unstable,
      # and a stable machine that could not evaluate passed here (#1200).
      # `self` too: installer/host.nix takes the HM module from it.
      stableInputs = checkInputs // {
        nixpkgs = nixpkgs-stable;
        home-manager = home-manager-stable;
        self = checkInputs.self // {
          nixosModules = checkInputs.self.nixosModules // {
            nixarchy = import ./modules/nixos.nix stableInputs;
          };
          homeManagerModules = checkInputs.self.homeManagerModules // {
            nixarchy = import ./modules/home.nix stableInputs;
          };
        };
      };
      mkReferenceWith =
        inputs:
        {
          encrypt,
          hardware ? false,
        }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            inputs.self.nixosModules.nixarchy
            homeManagerModule
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

            # Answered, not muted. swraid.nix:16 accepts any mdadm.conf
            # matching MAILADDR|PROGRAM, and without one it warns that mdmon
            # will crash -- on every evaluation of this configuration, which
            # is every ISO build and every run of checks.iso-source.
            #
            # #472 answered the same question for the `iso` configuration and
            # verified ITS warnings were empty; this one was never checked and
            # went on warning. Hence checks.config-warnings below, so the next
            # one fails instead of accumulating.
            #
            # root is where NixOS mail goes with no MTA configured, which on a
            # configuration that exists only to put mdadm's packages on an
            # image is exactly right: the point is that mdmon starts, not that
            # anyone reads it.
            boot.swraid.mdadmConf = "MAILADDR root";
            virtualisation.hypervGuest.enable = true;
            virtualisation.virtualbox.guest.enable = true;

            # Every nixos-hardware module installer/hardware-modules.sh can
            # select. Keep this union for the hardware evaluation checks.
            #
            # The UNION, not a machine: no real machine has an Intel and an
            # AMD GPU and both microcode sets. Every entry is mkDefault config
            # and this host is never installed.
            #
            # checks.hardware-modules asserts these names exist.
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

      mkConfigurations =
        inputs:
        let
          withHelpers = rec {
            isoSource = {
              flake = inputs.self;
            };

            # The live network image. See installer/cd.nix.
            iso-net = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = {
                inherit inputs;
                source = isoSource;
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
              modules = vmModulesWith inputs homeManagerModule;
            };

            # Why: docs/internals/flake.md#the-same-vm-with-room-to-run-a-model
            vm-big = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = { inherit inputs; };
              modules = [
                inputs.self.nixosModules.nixarchy
                homeManagerModule
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

                    # This is the VM a person KEEPS (#817), so it matches a real
                    # machine rather than the smoke test. Both panels that follow
                    # a service are gated on that service, and with neither
                    # enabled nixarchy.podman and nixarchy.distrobox are invisible
                    # here -- the two panels most worth trying by hand. The cost
                    # is the image pulls, paid by whoever runs this VM.
                    virtualisation.podman.enable = true;
                    programs.nixarchy.services.boxes.enable = true;

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
            # Built in CI so the install path cannot rot between releases.
            #
            # `device` is a placeholder: nothing here formats a disk. What matters is
            # that the expensive derivations in this toplevel are the same ones a real
            # install needs, and the device string is not one of them.
            reference = mkReferenceWith inputs { encrypt = true; };

            # The same machine on an unencrypted disk.
            #
            # The installer offers encryption on or off; this evaluates the
            # unencrypted result for checks and cache population.
            reference-unencrypted = mkReferenceWith inputs { encrypt = false; };

            # The same machine again, with every hardware attribute
            # nixos-generate-config can emit that adds a package turned on.
            # tests/generate-config-surface.nix evaluates this configuration;
            # tests/config-warnings.nix checks its warnings.
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
            reference-hardware = mkReferenceWith inputs {
              encrypt = false;
              hardware = true;
            };
          };
        in
        builtins.removeAttrs withHelpers [ "isoSource" ];

      mkInstall =
        inputs: system:
        pkgsFor.${system}.writeShellApplication {
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
            # at the end of the install. writeShellApplication prepends these
            # inputs to the caller's PATH; an undeclared command might work
            # on one machine and fail at this final step on another.
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
            # Both are used by ask_network. `nix run .#install` on a stock
            # ISO needs them as runtime inputs.
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
                "@kbdmodelmap@"
                "@nonlatin@"
                "@reservedusers@"
                "@initrdmodules@"
                "@initrdforced@"
                "@initrdmodulesplain@"
                "@initrdforcedplain@"
                "@initrdkernel@"
                "@hardwaremodules@"
              ]
              [
                "${inputs.self.packages.${system}.flake-template}"
                "${./installer/gum-env.sh}"
                "${./installer/lib/ui.sh}"
                "${./installer/brand/logo.txt}"
                "${./installer/brand/logo-compact.txt}"
                "${./installer/brand/tips.txt}"
                "${./installer/brand/keymaps.txt}"
                "${./installer/lib/dashboard.sh}"
                "${pkgsFor.${system}.tzdata}"
                "${pkgsFor.${system}.kbd}"
                "${pkgsFor.${system}.systemd}/share/systemd/kbd-model-map"
                (builtins.head (
                  builtins.match ".*local non_latin_layouts =[[:space:]]*\"([^\"]*)\".*" (
                    builtins.readFile "${omarchy}/default/hypr/input.lua"
                  )
                ))
                (
                  let
                    users = builtins.attrValues inputs.self.nixosConfigurations.reference.config.users.users;
                  in
                  nixpkgs.lib.concatStringsSep " " (
                    builtins.map (user: user.name) (builtins.filter (user: !(user.isNormalUser or false)) users)
                    ++ [ "daemon" ]
                  )
                )
                # The initrd modules the reference host carries, and therefore
                # the ones already baked into any image built from this commit.
                # install.sh compares what it detected against this list to
                # decide whether the installed machine can reuse that initrd.
                (nixpkgs.lib.concatStringsSep " " inputs.self.nixosConfigurations.reference.config.boot.initrd.availableKernelModules)
                # And the ones it loads unconditionally, which the same pin has
                # to cover: an imported profile sets this list too.
                (nixpkgs.lib.concatStringsSep " " inputs.self.nixosConfigurations.reference.config.boot.initrd.kernelModules)
                # And the same two for an unencrypted install. They are not the
                # same lists: LUKS adds a dozen crypto modules to the initrd, so
                # a machine installed without encryption that pinned the
                # encrypted set would match neither baked initrd and build a
                # third.
                (nixpkgs.lib.concatStringsSep " " inputs.self.nixosConfigurations.reference-unencrypted.config.boot.initrd.availableKernelModules)
                (nixpkgs.lib.concatStringsSep " " inputs.self.nixosConfigurations.reference-unencrypted.config.boot.initrd.kernelModules)
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
                inputs.self.nixosConfigurations.reference-unencrypted.config.boot.kernelPackages.kernel.version

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

      mkTry =
        inputs: system:
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
                (inputs.self.rev or "")
                "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
                "${pkgs.qemu_kvm}/bin/qemu-img"
                "${pkgs.OVMF.firmware}"
                "${pkgs.OVMF.variables}"
              ]
              (builtins.readFile ./installer/try.sh);
        };

      # Why: docs/internals/flake.md#one-closure-per-template-shared-by-every-vm-a-user
      # An installable image carrying somebody else's machine (#478).
      #
      # The same installer/cd.nix as the published network image, with
      # `source` pointing at the caller's flake.
      #
      # Called from the generated flake (installer/template/flake.nix), which
      # is why it takes `flake` and `host` rather than reading anything here:
      # at that point `self` is the USER's repository and this repository is
      # one of its inputs.
      #
      # It is a reinstaller, not a backup. It carries the flake inputs, then
      # fetches the system from the network. It does not carry /home,
      # service state or secrets, and booting it erases the target disk. The
      # command that builds it says so; this is the machinery underneath.
      mkUserIsoWith =
        inputs:
        {
          flake,
          host,
          # Accept stale generated flakes that still pass offline.
          ...
        }:
        let
          machine =
            flake.nixosConfigurations.${host} or (throw ''
              mkUserIso: this flake has no machine called "${host}".
              It has: ${lib.concatStringsSep ", " (lib.attrNames flake.nixosConfigurations)}
            '');
          # host reaches the launcher, which is what makes the image this machine's (#1649).
          iso = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit inputs;
              source = { inherit flake host; };
            };
            modules = [ ./installer/cd.nix ];
          };
        in
        builtins.seq machine (
          iso.config.system.build.isoImage // { inherit (iso.config.system.build) installerLauncher; }
        );

      mkMicrovmWith =
        inputs:
        {
          template,
          system,
          modules ? [ ],
        }:
        (nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            inputs.microvm.nixosModules.microvm
            ./modules/microvm/guest.nix
            template
          ]
          ++ modules;
        }).config.microvm.declaredRunner;

      realInputs = inputs;
      commitBound = import ./data/commit-bound-checks.nix;
      checkInputs = realInputs // {
        self = self // {
          rev = "0000000000000000000000000000000000000000";
          shortRev = "0000000";
          lastModifiedDate = "19700101000000";
          lastModified = 0;
          # 32 zero bytes: a well-formed SRI hash that names no real tree.
          narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          lib = self.lib // {
            mkUserIso = mkUserIsoWith checkInputs;
          };
          nixosModules = self.nixosModules // {
            nixarchy = import ./modules/nixos.nix checkInputs;
          };
          homeManagerModules = self.homeManagerModules // {
            nixarchy = import ./modules/home.nix checkInputs;
          };
          nixosConfigurations = mkConfigurations checkInputs;
          packages =
            self.packages
            // lib.genAttrs (import systems) (
              system:
              self.packages.${system}
              // {
                flake-template = pkgsFor.${system}.callPackage ./installer/mkFlake.nix {
                  inherit (checkInputs) self;
                };
                install = mkInstall checkInputs system;
                try = mkTry checkInputs system;
                nixarchy-vm = pkgsFor.${system}.callPackage ./pkgs/microvm.nix { inherit (checkInputs) self; };
              }
              // lib.concatMapAttrs (name: template: {
                "microvm-${name}" = mkMicrovmWith checkInputs {
                  inherit system;
                  template = template.module;
                };
                "microvm-${name}-tcg" = mkMicrovmWith checkInputs {
                  inherit system;
                  template = template.module;
                  modules = [
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
                };
              }) (import ./data/microvm-templates.nix)
            );
        };
      };
      stableVm = nixpkgs-stable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inputs = stableInputs;
        };
        modules = [
          stableInputs.self.nixosModules.nixarchy
          ./vm/configuration.nix
        ];
      };

      # nixarchy's own pins, which a consumer's overrides never change (#1371)
      ownLock = builtins.fromJSON (builtins.readFile ./flake.lock);
    in
    {
      overlays.nixarchy = final: _prev: {

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
            xdg-utils
            # Why: docs/internals/flake.md#vainfo-for-the-graphics-section
            libva-utils
            # For reading the machine's flake.lock, which is JSON. Reaching for
            # sed on JSON is how a check starts reporting confidently wrong
            # things the first time nix reformats a lock.
            jq
            # ldd, for the dynamic-link section. Undeclared, every binary it
            # inspects would read as "could not be checked" -- the vainfo trap
            # again, one section down.
            glibc
            # --print-interpreter distinguishes "statically linked, fine" from
            # "asks for /lib64/ld-linux..., which nix-ld has not provided" --
            # ldd alone reports both as "not a dynamic executable".
            patchelf
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
                      # An explicit `binary` on the row wins, because the
                      # fallback below is right by luck and wrong in a way that
                      # is invisible: it answers with the ATTRIBUTE name when a
                      # package states no mainProgram, which was `zen` for one
                      # installing zen-beta and `hey-cli` for one installing
                      # hey -- both reported absent on machines that had them.
                      #
                      # android-tools is the case that made a field necessary
                      # rather than another special case: it ships adb,
                      # fastboot and a dozen others, so no single mainProgram
                      # is correct upstream, and the attribute is not a command
                      # at all.
                      app.binary or (if probe.success && probe.value != null then probe.value else name);
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

        # `nixarchy explain` -- reads a Nix failure and says what it is in the
        # vocabulary of the files the user wrote. In the overlay rather than
        # only under `packages` for the same reason the doctor is: the module
        # installs it, and a module cannot take a package from
        # inputs.self.packages without mixing nixpkgs instances.
        nixarchy-explain = final.writeShellApplication {
          name = "nixarchy-explain";
          runtimeInputs = with final; [
            coreutils
            # grep and sed do all of the recognising. Undeclared, every family
            # would read as "not recognised" rather than as a missing command
            # -- the vainfo trap in pkgs/AGENTS.md, and worse here, because
            # "nothing matched" is a legitimate answer this tool gives.
            gnugrep
            gnused
          ];
          text = builtins.readFile ./pkgs/explain.sh;
        };

        # `nixarchy-location` -- Home, Work and the Wi-Fi networks linked to
        # them, written into the weather.json the bar already reads. In the
        # overlay for the same reason as nixarchy-explain.
        nixarchy-location = final.writeShellApplication {
          name = "nixarchy-location";
          # jq for every JSON read and write, nmcli for the current network;
          # undeclared, a machine without them would report "no network", not
          # "missing command" (the vainfo trap in pkgs/AGENTS.md).
          runtimeInputs = with final; [
            coreutils
            jq
            networkmanager
          ];
          text = builtins.readFile ./pkgs/location.sh;
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
            # owe, for the #1153 section: an undeclared `owe` here would read
            # as "owe not on PATH" on a machine that simply has not rebuilt
            # since this row was added, rather than naming the real cause.
            # Declared unconditionally, so the row's `command -v owe` guard
            # always succeeds -- the CLI is always present, with
            # programs.nixarchy.owe or without it. What actually answers "off"
            # is `owe status` itself: with no owed socket to connect to, it
            # comes back empty and the row reports "owed is not running",
            # pointing at the option, rather than the CLI.
            nixarchy-apps.owe
          ];
          text = builtins.readFile ./pkgs/verify.sh;
        };

        # Apps Omarchy offers that nixpkgs does not carry. Packaged here so a
        # NixOS user gets the same menu Arch users do, rather than a menu with
        # holes in it.
        nixarchy-apps = {
          once = final.callPackage ./pkgs/apps/once.nix { };
          superwhisper = final.callPackage ./pkgs/apps/superwhisper.nix { };

          # nixpkgs' `hey` is an unrelated HTTP load generator, so this cannot
          # simply follow nixpkgs the way most apps here do.
          hey-cli = final.callPackage ./pkgs/apps/hey-cli.nix { };

          # Why: docs/internals/flake.md#not-built-here-upstreams-own-flake-re-exported-int
          zen-browser = zen-browser.packages.${final.stdenv.hostPlatform.system}.default;

          # The four applications Omarchy writes itself. nixpkgs has none of
          # them, which is why modules/nixos.nix cannot reproduce upstream's
          # preinstall set; these close that gap.
          omawrite = final.callPackage ./pkgs/apps/omawrite.nix { };
          omacalc = final.callPackage ./pkgs/apps/omacalc.nix { };
          omacut = final.callPackage ./pkgs/apps/omacut.nix { };
          omasnap = final.callPackage ./pkgs/apps/omasnap.nix { };

          # Omarchy 4.5's other default apps (#1572). On by default through
          # programs.nixarchy.omarchyApps.enable.
          hype = final.callPackage ./pkgs/apps/hype.nix { };
          monologue = final.callPackage ./pkgs/apps/monologue.nix { };
          omarchy-local-ai = final.callPackage ./pkgs/apps/omarchy-local-ai.nix { };
          signed = final.callPackage ./pkgs/apps/signed.nix { };
          disktree = final.callPackage ./pkgs/apps/disktree.nix { };
          # Against the flake's Hyprland, the one Omarchy's session runs; final.hyprland
          # is nixpkgs' and fails the plugin's commit check. The module builds its own (#1572).
          omarchy-hyprland-titlebars = final.callPackage ./pkgs/apps/omarchy-hyprland-titlebars.nix {
            inherit
              (final.hyprlandPlugins.override {
                inherit (hyprland.packages.${final.stdenv.hostPlatform.system}) hyprland;
              })
              mkHyprlandPlugin
              ;
          };

          # owe, omacom's wallpaper engine: video and GIF desktop backgrounds
          # and the lock screen's video feed. Not in nixpkgs. #1153.
          owe = final.callPackage ./pkgs/apps/owe.nix { };
          folio = final.callPackage ./pkgs/apps/folio.nix { };
          plain = final.callPackage ./pkgs/apps/plain.nix { };

          # The fourth, and the only one that is not a small script or a Qt
          # program: a Wails app, so a Go module set AND an npm tree to pin.
          aether = final.callPackage ./pkgs/apps/aether.nix { };

          # Not one of Omarchy's preinstalls -- a terminal-effects toy from the
          # same authors, packaged because it was asked for.
          ttfx = final.callPackage ./pkgs/apps/ttfx.nix { };
          omarchy-speedtest = final.callPackage ./pkgs/apps/omarchy-speedtest.nix { };
          omarchy-screensaver = final.callPackage ./pkgs/apps/omarchy-screensaver.nix { };

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

        gliff = final.callPackage ./pkgs/gliff { src = inputs.gliff; };

        omarchy = final.callPackage ./pkgs/omarchy {
          src = omarchy;
          version = import ./pkgs/omarchy/version-label.nix {
            version = omarchyVersion;
            pinnedRev = ownLock.nodes.${ownLock.nodes.root.inputs.omarchy}.locked.rev or null;
            input = omarchy;
          };
          # The compositor the Lua config is written against, not nixpkgs'.
          inherit (hyprland.packages.${final.stdenv.hostPlatform.system}) hyprland;

          # The desktop shell, and the one package here pinned to a FLOOR
          # rather than left to the machine's own nixpkgs (#528).
          #
          # quickshell 0.3.0's session lock reaches qFatal when screens sleep
          # and wake while locked, and the Wayland session-lock protocol
          # deliberately keeps the compositor locked when its lock client
          # disappears -- so the machine is left blank with nowhere to type a
          # password, and power-cycling is the only way back in. #35 records
          # it happening three times in one night on a real machine.
          #
          # The override that fixed it was dropped in #380 because nixpkgs
          # had reached 0.3.1 "from the same tag and the same URL the
          # override fetched", which made it a no-op. That was true of the
          # nixpkgs this repo is developed against and of no other: measured
          # 2026-09-10, nixos-26.05 ships 0.3.0 and unstable ships 0.3.1. So
          # a user following stable -- the channel that SOUNDS safer -- would
          # get the session lock that can strand them out of their laptop,
          # and would not find out until their screens next slept.
          #
          # Hence a floor rather than a no-op or a warning. A warning is the
          # wrong instrument for this one: what it costs to ignore is access
          # to your own machine, and it would be read months before it is
          # paid. On unstable that branch is not taken.
          #
          # Every branch then gains qtimageformats, Qt's WebP/TIFF decoder: without
          # it a WebP background never draws ("Unsupported image format", #1284).
          quickshell =
            (
              # 0.3.2's WlSessionLock::unlock() asks isLocked() after releasing the
              # lock, so lockStateChanged never fires and the lock screen's `locked`
              # stays true: every later lock request is a silent no-op. checks.session.
              if final.quickshell.version == "0.3.2" then
                final.quickshell.overrideAttrs (old: {
                  patches = (old.patches or [ ]) ++ [ ./pkgs/quickshell/unlock-signal.patch ];
                })
              else if lib.versionAtLeast final.quickshell.version "0.3.1" then
                final.quickshell
              else
                final.quickshell.overrideAttrs (_: rec {
                  version = "0.3.1";
                  src = final.fetchzip {
                    url = "https://git.outfoxxed.me/quickshell/quickshell/archive/refs/tags/v${version}.tar.gz";
                    hash = "sha256-CLX2Zp5i5BuLbOxNOkwRd9YY84IOrACNxBV79o9/F9Y=";
                  };
                })
            ).overrideAttrs
              (old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ final.qt6.qtimageformats ];
              });
          # The screensaver's text-effects engine, packaged in this repo rather
          # than nixpkgs. Passed explicitly for the same reason hyprland is: it
          # lives under nixarchy-apps, which callPackage does not search.
          inherit (final.nixarchy-apps)
            disktree
            ttfx
            folio
            plain
            omasnap
            omarchy-speedtest
            omarchy-screensaver
            ;
        };

        # Why: docs/internals/flake.md#the-boot-splash-and-nothing-else-on-the-disk-with-
        nixarchy-plymouth = final.runCommand "nixarchy-plymouth-theme" { } ''
          install -d $out/share/plymouth/themes
          cp -r ${final.omarchy}/share/plymouth/themes/omarchy \
            $out/share/plymouth/themes/omarchy
        '';
      };

      # The overlay above, plus the cargo carry, which must see `prev` and not
      # sit inside that attrset (nixfmt would reindent all of it).
      # Why: pkgs/AGENTS.md#cargo-system-libs-1722
      overlays.default = lib.composeExtensions self.overlays.nixarchy (
        _final: prev:
        (import ./pkgs/cargo-system-libs.nix {
          inherit (prev) lib;
          inherit prev;
        }).packages
      );

      packages = eachSystem (
        system:
        let
          # Imported once, and every scene it defines is exposed below without
          # anybody typing the name here. The list that used to live in this
          # file failed OPEN: three scenes added to tests/demo/default.nix were
          # not flake attributes, nothing went red, and the only detector was
          # demo-record failing an hour later with "does not provide attribute"
          # (#816, AGENTS.md section 4).
          demoOutputs = import ./tests/demo {
            inherit inputs;
            pkgs = pkgsFor.${system};
            microvmRunner = self.packages.${system}."microvm-shell-tcg";
          };
        in
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
          install = mkInstall inputs system;

          # The flake the installer writes to /etc/nixos: the template files with
          # their @tokens@ still in place, plus a lock derived from this repo's
          # own so the installed machine resolves to exactly what was built.
          # Requires a committed tree -- it pins nixarchy by commit.
          flake-template = pkgsFor.${system}.callPackage ./installer/mkFlake.nix { inherit self; };

          # Exposed at top level, rather than only reachable through
          # modules/apps.nix's callPackage, so checks.microvm-template can
          # build and read the exact command `nixarchy vm` execs -- same
          # reasoning as `verify` and `doctor` just below.
          # Re-exported so `nix build .#nixi` works from this flake and CI has
          # something to name, built against OUR nixpkgs through the `follows`
          # on the input.
          #
          # Deliberately NOT in the overlay, which is where zen-browser went. The overlay exists to let a module say
          # `pkgs.<name>` and never mention an input, and nothing here needs
          # that: nixi's own Home Manager module already defaults
          # `services.nixi.package` to its flake's package, and because that
          # flake follows this nixpkgs it is the same derivation this line
          # names, bar one thing: nixarchy overrides its `omarchySrc` (#1314),
          # so `checks.nixi` guards the pin while `checks.menu-model-merge`
          # builds the package users get. An overlay attribute would be a
          # second way to spell one package and a second thing to keep in step.
          #
          # Not in data/apps.nix either. That catalogue is for things that are
          # a package: install it and it is there. Nixi is a package plus a user
          # unit plus config files plus a bar plugin, and installing the package
          # alone gives a server nothing starts. It reaches users through
          # modules/home.nix instead.
          nixi = inputs.nixi.packages.${system}.nixi;

          # Re-exported for the same reasons as nixi: `nix build .#nixarchy-pkg`
          # works, and it is built against our nixpkgs through the `follows`.
          # modules/home.nix names it as a default plugin (#766).
          nixarchy-pkg = inputs.nixarchy-pkg.packages.${system}.default;
          nixarchy-podman = inputs.nixarchy-podman.packages.${system}.default;
          nixarchy-gliff-manager = inputs.nixarchy-gliff-manager.packages.${system}.default;
          nixarchy-microvm = inputs.nixarchy-microvm.packages.${system}.default;
          nixarchy-distrobox = inputs.nixarchy-distrobox.packages.${system}.default;

          gliff = pkgsFor.${system}.gliff;

          nixarchy-vm = pkgsFor.${system}.callPackage ./pkgs/microvm.nix { inherit self; };

          # Every pinned box image in one entry, so the main-only cache publisher
          # serves them all to cold box checks (#788, #800): its closure is each
          # tarball. `images` is the set, for checks.box-template's same-path check.
          box-test-image = pkgsFor.${system}.linkFarm "box-test-images" boxImages.${system} // {
            images = boxImages.${system};
          };

          # Same reason again: tests/menu-verbs.nix reads the verbs out of the
          # command the Secrets menu rows exec, and it can only do that if the
          # command is a package it can build.
          nixarchy-secret = pkgsFor.${system}.callPackage ./pkgs/secret.nix { };

          # The policy append that `nixarchy secret enroll` performs, lifted
          # out so checks.secret-enroll runs THIS code rather than a copy.
          # enroll itself cannot be driven in a sandbox: it reads the
          # hostname from /proc and the recipient from /etc/ssh, and a build
          # sandbox has neither.
          nixarchy-sops-policy-add = pkgsFor.${system}.callPackage ./pkgs/sops-policy-add.nix { };
          nixarchy-branch-guard = pkgsFor.${system}.callPackage ./pkgs/branch-guard.nix { };

          verify = pkgsFor.${system}.nixarchy-verify;

          # `nix run .#review` -- what needs updating, and what is quietly
          # broken. An app rather than a check because it asks GitHub what
          # upstream ships and what CI did last night, and a check has no
          # network. The half that needs neither is checks.review-pins.
          review = pkgsFor.${system}.writeShellApplication {
            name = "nixarchy-review";
            runtimeInputs = with pkgsFor.${system}; [
              gh
              jq
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
            text =
              builtins.replaceStrings
                [ "@delta@" "@walk@" ]
                [ "${./.github/scripts/omarchy-package-delta.sh}" "${./.github/scripts/release-notes-options.nix}" ]
                (builtins.readFile ./.github/scripts/release-notes.sh);
          };

          # `nix run github:olafkfreund/nixarchy#doctor` -- reads the running
          # system and prints the configuration it would need. Runnable before
          # nixarchy is an input anywhere, which is the only entry point someone
          # deciding whether to adopt it actually has.
          doctor = pkgsFor.${system}.nixarchy-doctor;

          # `nix run github:olafkfreund/nixarchy#explain` -- pipe a failing
          # rebuild into it. Runnable without nixarchy installed on purpose:
          # the moment someone needs it is the moment their rebuild will not
          # complete.
          explain = pkgsFor.${system}.nixarchy-explain;

          # `nixarchy-location` -- see pkgs/location.sh.
          location = pkgsFor.${system}.nixarchy-location;

          # `nix run .#devenv-presets` -- every template the Dev environments
          # plugin ships, scaffolded with a real devenv and evaluated (#802).
          #
          # The NAME is fixed: `devenv-presets` is a required status check on
          # main, and `build.yml`'s job of that name runs this attribute. The
          # catalogue moved to the plugin (nixarchy-devenv), so what the name
          # runs is now the plugin's own `templates-check`, over the eight ids
          # this repo used to carry. Renaming either would need a workflow and
          # a branch-protection change, which are a human's (AGENTS.md 4, 11).
          #
          # Not in `checks`: it needs the network, because devenv fetches the
          # inputs each devenv.yaml names.
          #
          # What the old runner got wrong, and why the plugin's replaces it:
          # it moved HOME but inherited XDG_DATA_HOME, and devenv keeps its
          # trust database at $XDG_DATA_HOME/devenv/allowed -- so every run
          # wrote its throwaway scaffolds into the trust list of whoever ran
          # it (80 dead entries on p620). The plugin's check puts HOME, every
          # XDG path and DEVENV_HOME inside one temporary root, and fails if
          # the caller's allow list changes while it runs.
          devenv-presets = pkgsFor.${system}.writeShellApplication {
            name = "devenv-presets";
            text = ''
              # The ids this repo's data/devenv-presets.nix used to hold. The
              # plugin has more (java, kotlin, dotnet, php, ruby, flutter and
              # the cloud generator); those are its own CI's business, and
              # `cloud` needs the network at create time, so this check keeps
              # the scope the required check has always had.
              exec ${inputs.nixarchy-devenv.apps.${system}.templates-check.program} \
                go jupyter ml node python react rust typescript
            '';
          };

          # Why: docs/internals/flake.md#screencasts-of-a-real-session-scene-by-scene-see
          inherit (demoOutputs)
            demo
            demo-record
            demo-verify
            ;

          inherit (pkgsFor.${system}.nixarchy-apps)
            once
            superwhisper
            retroarch
            hey-cli
            omawrite
            omacalc
            omacut
            omasnap
            owe
            folio
            plain
            aether
            ttfx
            omarchy-speedtest
            omarchy-screensaver
            hype
            monologue
            omarchy-local-ai
            signed
            disktree
            omarchy-hyprland-titlebars
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
              runtimeInputs = with pkgsFor.${system}; [
                git
                gnugrep
              ];
              # A failed updater can leave half a bump that still builds, so
              # whatever it changed goes back to HEAD (#1537).
              text = ''
                rc=0
                run() {
                  local before after f
                  before=$(git diff --name-only) || return 1
                  "$1" && return 0
                  after=$(git diff --name-only) || return 1
                  while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    grep -qxF -- "$f" <<<"$before" && continue
                    echo "reverting $f: $1 failed partway" >&2
                    git checkout HEAD -- "$f"
                  done <<<"$after"
                  return 1
                }
                ${lib.concatMapStrings (p: ''
                  run ${lib.getExe p.updateScript} || rc=1
                '') (lib.attrValues pinned)}
                exit "$rc"
              '';
              # `|| rc=1` rather than fail-fast: one upstream breaking its
              # release layout (hey-cli's 1.4.1 SBOMs did exactly that) must
              # not block every other package's bump for the night.
              derivationArgs.passthru.pinned = lib.attrNames pinned;
            };

          # The release asset for #1166: nixarchy's own options, read by the
          # `nixos` MCP tool and by anyone grepping the file by hand.
          # Re-exports system.build.nixarchyOptions (modules/nixos.nix)
          # rather than building a second catalogue, so the machine and the
          # release ship the same file.
          nixarchy-options = self.nixosConfigurations.reference.config.system.build.nixarchyOptions;

          # Boot the smoke test: `nix run .#vm`
          vm = self.nixosConfigurations.vm.config.system.build.vm;

          # The same machine with room for a model: `nix run .#vm-big`.
          # 32GB, 8 cores, and a real disk rather than a tmpfs root.
          vm-big = self.nixosConfigurations.vm-big.config.system.build.vm;

          # The bootable network image.
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
          try = mkTry inputs system;

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
        # Every scene, by construction. Adding one to tests/demo/default.nix is
        # now enough; there is no second place to forget.
        // lib.filterAttrs (name: _: lib.hasPrefix "demo-scene-" name) demoOutputs
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
      nixosConfigurations = mkConfigurations inputs;

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./shell.nix { };
      });
      # One attrset, not three `lib.x =` assignments: statix's repeated-keys
      # lint fails the build at three, and adding mkUserIso was the third.
      lib = {

        # Every flake in `flakes`, and every input of theirs, transitively, as
        # unique store paths. Not the top-level inputs: hyprland does not follow
        # nixpkgs and brings its own tree, and each of its inputs brings more, so
        # this is collected rather than listed -- a hand-written list goes stale
        # on the next bump, and staleness shows up only as a fetch on a machine
        # with no network. Shared by the install image (installer/cd.nix) and the
        # installed host (installer/host.nix), so the two cannot drift (#701).
        inputSources =
          flakes:
          let
            collect =
              flake:
              [ flake.outPath ] ++ nixpkgs.lib.concatMap collect (nixpkgs.lib.attrValues (flake.inputs or { }));
          in
          nixpkgs.lib.unique (nixpkgs.lib.concatMap collect (nixpkgs.lib.attrValues flakes));

        # The installed machine, as the installer would produce it. Both disk
        # modes come from here so they cannot drift apart, and so installer/cd.nix
        # can bake each one onto the image without restating the host.
        mkReference = mkReferenceWith inputs;

        mkUserIso = mkUserIsoWith inputs;
        mkMicrovm = mkMicrovmWith inputs;
      };

      formatter = eachSystem (system: pkgsFor.${system}.nixfmt-tree);

      checks = eachSystem (
        system:
        let
          inputs = checkInputs;
          images = boxImages.${system};
          # Checks whose file takes { inputs, pkgs } and whose name is the
          # file's. test-registration is handed this list (#1048), so a name
          # here counts as registered; one that needs other arguments stays
          # an explicit entry below.
          uniformChecks = [
            "agent-local-memlock"
            "app-selection"
            "apply-detach-interface"
            "apply-imports"
            "apply-staging"
            "home-activation-writes"
            "language-locale"
            "language-select"
            # The notification history keeps text for the newest rows only (#1663).
            "notification-store"
            # data/bin-ledger.nix, held to its own claim. Also the home of the
            # pacman allowlist that used to live inline in build.yml. See
            # tests/bin-ledger.nix and #447.
            "bin-ledger"
            "bluetooth-pairing"
            # A hung install-target boot fails fast with a monitor dump (#1594). Needs KVM.
            "boot-hang-detect"
            "branch-guard"
            # The cargo carry, against stand-in nixpkgs sets (#1722). See tests/cargo-system-libs.nix.
            "cargo-system-libs"
            # Boots the Omarchy session on a machine whose hyprland.lua belongs to
            # somebody else -- the case the session entry exists for.
            "coexist"
            "command-not-found"
            # The other two halves of that PR body. Same shape, same reason: both
            # report on a release by grepping upstream's file layout, and a grep
            # that has stopped matching prints what a quiet release prints. See
            # tests/config-delta.nix and tests/patched-files.nix.
            "config-delta"
            # Every configuration this repository ships evaluates without
            # warnings. See tests/config-warnings.nix for why that is a check
            # and not a preference.
            "config-warnings"
            # The dashboard the installer draws while it works, against a clock
            # that goes backwards -- which is what NTP does to a machine whose
            # RTC was wrong, mid-install. Not covered by the VM checks: their
            # clocks are stable, so every duration there is positive.
            "dashboard-clock"
            # The other half of that: every option path the README and the manual
            # quote, checked against the option set they claim to describe. See
            # tests/doc-options.nix and #214.
            "doc-options"
            "edge-carry"
            "edge-report"
            "edge-promote"
            # Proves btrfs subvolume and directory exchanges before the reset uses them (#1621).
            "factory-reset"
            "firmware-guard"
            # The dangerous one. Installs into free space on a disk that already
            # carries partitions and asserts those partitions are byte-identical
            # afterwards -- entry and content. See tests/free-space.nix; #47 is
            # the only item in the epic whose failure mode is destroying data
            # that is not ours, and this is the gate it sits behind.
            "free-space"
            "generate-config-surface"
            # gliff's Vulkan loader RUNPATH and ssh wrapper: losing either is silent
            # (CPU tier, or no client), and only this layer reads them. #1226.
            "gliff-runpath"
            # Every pipe into grep -q is rewritten or allowlisted with a reason (#1060).
            "grep-q-pipefail"
            "hardware-modules"
            # The Hibernate row's logind answer, in a VM with resume configured (#1303). Needs KVM.
            "hibernate-resume"
            # The profile a user with their own interpreter actually gets, built
            # rather than inspected: #809's collision only exists once something
            # calls buildEnv. See tests/home-profile.nix.
            "home-profile"
            "initrd-pin-guard"
            # No indented python -c program: 3.13 refuses what 3.14 dedents (#1205).
            # Why: tests/inline-python.nix
            "inline-python"
            "install"
            # The same question with encrypt=yes -- the DEFAULT interactive
            # answer, which until this check had no coverage past evaluation.
            # Installs, asserts the ENCRYPTED initrd module list was pinned,
            # boots the result through the LUKS passphrase prompt on the serial
            # console, and proves autologin and the recovery secret on the ESP.
            # See tests/install-encrypted.nix for why the passphrase prompt is
            # not the obstacle tests/install.nix's header once took it for.
            "install-encrypted"
            # The ISO installing by FETCHING, from a
            # substituter stood up inside the test's own vlan. The image people
            # download for a network install had no install check at all until
            # this one; see the file header for what it proves and what no
            # sandboxed check can.
            "install-iso-net"
            # The actual upstream minimal ISO, booted through its own GRUB.
            # Its large cache and VM run belong to the weekly job only.
            "install-stock-iso"
            # The #300 guarantee on a real disk: a dark substituter refused with
            # the target intact. installer-store-space covers the same function
            # with stubs; this is the only check that can fail if the installer
            # wipes anyway, because it is the only one holding a disk.
            "installer-refusal"
            "installer-ui"
            # The other half of the installer: the questions themselves, answered
            # over a serial line. checks.installer-ui proves a widget can be drawn;
            # this proves the wizard can be answered, which no harness passing
            # --answers has ever done. See tests/installer-wizard.nix.
            "installer-wizard"
            # Built, not evaluated, and onto a config that already exists. See
            # tests/integration.nix for the three bugs that shipped because every
            # other check here starts from a clean machine.
            "integration"
            "iso-wifi"
            "keybindings-lua-timeout"
            # Two machines differing only by name must build the same parts, or
            # an offline install has to build the difference. See #404.
            "machine-name-free"
            # Menu when/checked answers on NixOS, not Arch. See tests/menu-conditions.nix and #1303.
            "menu-conditions"
            # The menu's guards through its own model, absent and present (#1301).
            "menu-guards"
            "mise-free"
            # And the same idea aimed at the menu: every action string checked
            # against the subcommands the CLI it invokes actually has. See
            # tests/menu-verbs.nix and the `nixarchy-vm new` row that shipped.
            "menu-verbs"
            # The menu scripts patched to explain and exit 1 call no writer (#1304).
            "menu-guidance"
            # Removal asks fprintd first, then removes only the invoking account's files (#1620).
            "remove-fingerprint"
            # A font row run with no terminal reopens itself in one, when the font is missing (#1304).
            "install-font-terminal"
            # Every visible menu row's action, followed into its scripts (#1304).
            "menu-actions"
            # The other half of that: a declared machine actually boots, on the
            # -tcg runner, and the ro-store mount is asserted from inside the
            # running guest. See tests/microvm-boot.nix for why the KVM runner --
            # the one nearly every user runs -- cannot be proved here.
            "microvm-boot"
            # The per-VM vsock CID and the autoconfirm loop of hyprland-ai-mirror; boots nothing (#1508).
            "microvm-ai-mirror"
            # Evaluation against stable, ~20s and no VM (#527). `stableVm` is
            # passed in rather than reached through `inputs.self`, because it is
            # deliberately not a nixosConfigurations entry -- see its definition.
            # The per-package escape (#530-#532). Evaluation only, like
            # stable-eval beside it: it asks which closure would be built, and
            # that question does not require building one.
            "other-channel"
            # The package delta that goes in every Omarchy bump PR. Its dangerous
            # failure is silence, so this feeds it a known answer. See
            # tests/package-delta.nix.
            "package-delta"
            "patched-files"
            # Every package Omarchy installs has a decision in data/omarchy-packages.nix (#1572).
            "omarchy-package-ledger"
            # The pure modes of pin-fix.sh, and that each probe in data/pin-fix.nix exists.
            "pin-fix"
            # Adds a real third-party plugin from a real repo. The plugin system
            # is the one deliberately imperative corner of Omarchy, and the part
            # of it that could break here is the writable ~/.config/omarchy the
            # seed creates.
            "plugin"
            # The boot splash's positions all live in layout(), redone when a
            # display appears late. See tests/plymouth-layout.nix and #1285.
            "plymouth-layout"
            # A previewed config's desktop actually renders: the vmVariant
            # gains the software-GL fallbacks and sizing, only when nixarchy
            # is on, all of it overridable. See tests/preview-variant.nix
            # and #487.
            "preview-variant"
            # First login seeds only missing launchers and stubs (#1319).
            "provision-launchers"
            # The release notes, against a fixture repository whose diff is known.
            # Same dangerous failure as the delta above, over more scans: a release
            # note that reads calm because a grep stopped matching. See
            # tests/release-notes.nix.
            "release-notes"
            # Remove and Restore preinstalls delete only what Omarchy seeded (#1304).
            "remove-preinstalls"
            "retroarch-paths"
            # `nix run .#review` watches the pinned packages; this watches that
            # it can still see them. See tests/review-pins.nix.
            "review-pins"
            # The standalone Home Manager profile: the package plus every runtime
            # dependency, built with collisions refused (#1485).
            "runtime-profile"
            "session-journal-race"
            # A WebP loads through the plugin path the shell is launched with (#1284).
            "shell-image-formats"
            # data/skill-parity.nix, held to upstream's own SKILL.md. See
            # tests/skill-parity.nix and #643.
            "skill-parity"
            "sops-evaluates"
            "sshd-enable"
            # A real ssh login against the menu's sshd, and the plain line as control (#1611). Needs KVM.
            "sshd-login"
            # Store ownership follows Home Manager file and directory links (#1304).
            "store-owned"
            "swap-guard"
            "switch-indicator"
            "update-available"
            "user-unit-links"
            "verify-boxes"
            "verify-sections"
          ];
        in
        {
          omarchy = self.packages.${system}.omarchy;
          inherit (self.packages.${system}) omarchy-runtime;

          # Drives a real session and reports what it logged. See tests/session.nix
          # for why neither a serial console nor the smoke-test VM can do this.

          # Nixi's own package build, which runs its installCheckPhase --
          # py_compile on every program, `bash -n` on the launcher, and the
          # assertions that its assets are present.
          #
          # Here rather than left to nixi's CI because modules/home.nix now
          # names it: AGENTS.md's rule is that anything this repo ships which
          # names something else needs something saying that something exists.
          # The lock pins the input, so this only runs when the lock moves --
          # and a lock that moves to a broken nixi would otherwise be
          # discovered by whoever rebuilt first with services.nixi.enable on.
          # Cheap: nothing compiles, the derivation places files.
          nixi = self.packages.${system}.nixi;

          # Why: tests/AGENTS.md#a-test-script-over-128-kib-breaks-the-stable-driver
          session =
            let
              test = import ./tests/session.nix {
                inherit inputs;
                pkgs = pkgsFor.${system};
                inherit (self.packages.${system}) doctor;
              };
            in
            test.extend {
              modules = [
                { driver = lib.mkForce (test.driver.overrideAttrs { __structuredAttrs = true; }); }
              ];
            };
          # The installer's interactive screens, at every width worth caring
          # about. Nothing else draws them: every other harness passes
          # --answers, which is exactly how #133 shipped.
          # Why: tests/wifi-hwsim.nix
          wifi-hwsim = import ./tests/wifi-hwsim.nix {
            pkgs = pkgsFor.${system};
          };
          remove-fingerprint-vm = import ./tests/remove-fingerprint-vm.nix {
            pkgs = pkgsFor.${system};
          };

          # Why: tests/installer-failure-hints.nix
          installer-failure-hints = import ./tests/installer-failure-hints.nix {
            pkgs = pkgsFor.${system};
            dashboardScript = ./installer/lib/dashboard.sh;
            installScript = ./installer/install.sh;
          };

          # Why: tests/installer-network-profiles.nix
          installer-network-profiles = import ./tests/installer-network-profiles.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          # Why: tests/installer-network.nix
          installer-network = import ./tests/installer-network.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          # nixarchy-preview's preflights and its disk lifecycle, with a df,
          # meminfo and /dev/kvm that lie -- plus the #485 honesty strings.
          # See tests/preview.nix.
          preview = import ./tests/preview.nix {
            pkgs = pkgsFor.${system};
            previewScript = ./pkgs/omarchy/nix-bin/nixarchy-preview;
          };

          stale-scripts = import ./tests/stale-scripts.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # omarchy-default-agent's nixpkgs mapping, against this nixpkgs (#1452).
          agent-attrs = import ./tests/agent-attrs.nix { pkgs = pkgsFor.${system}; };

          # Every menu row's route in omarchy-default-agent, with no mise (#1622).
          default-agent-routes = import ./tests/default-agent-routes.nix {
            pkgs = pkgsFor.${system};
            omarchySrc = self.packages.${system}.omarchy.src;
          };

          # pi and omp start with no node on PATH. Its own check because their closures
          # are 2.4 GiB, and a proof keeps those off every script edit's run (#1622).
          agent-no-node = import ./tests/agent-no-node.nix { pkgs = pkgsFor.${system}; };

          # nixarchy-reinstall-iso's preflights, with a df, git and eval that
          # lie -- plus the #478 honesty strings. See tests/reinstall-iso.nix.
          reinstall-iso = import ./tests/reinstall-iso.nix {
            pkgs = pkgsFor.${system};
            reinstallScript = ./pkgs/omarchy/nix-bin/nixarchy-reinstall-iso;
          };

          superwhisper-choice = import ./tests/superwhisper-choice.nix {
            pkgs = pkgsFor.${system};
            installScript = ./pkgs/omarchy/nix-bin/omarchy-install-dictation-superwhisper;
            removeScript = ./pkgs/omarchy/nix-bin/omarchy-remove-dictation-superwhisper;
          };

          reinstall-image = import ./tests/reinstall-image.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          # nixarchy-try's lookup and probe expressions run against the REAL
          # data/apps.nix and nixpkgs, plus the binary fallback ladder, the
          # unfree seasoning, the honest footer and the try-to-keep hand-off
          # (#499, #503). See tests/try.nix.
          try = import ./tests/try.nix {
            pkgs = pkgsFor.${system};
            tryScript = ./pkgs/omarchy/nix-bin/nixarchy-try;
          };

          installer-store-space = import ./tests/installer-store-space.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
            dashboardScript = ./installer/lib/dashboard.sh;
          };

          installer-disk-identity = import ./tests/installer-disk-identity.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          installer-layout-eval = import ./tests/installer-layout-eval.nix {
            pkgs = pkgsFor.${system};
            inherit self;
          };

          # Why: tests/install-seed-shape.nix (#1176, #1179)
          install-seed-shape = import ./tests/install-seed-shape.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          # Why: tests/installer-answers.nix
          installer-answers = import ./tests/installer-answers.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          installer-input-validation = import ./tests/installer-input-validation.nix {
            pkgs = pkgsFor.${system};
            renderedInstallScript = "${inputs.self.packages.${system}.install}/bin/nixarchy-install";
          };

          installer-keymaps = import ./tests/installer-keymaps.nix {
            pkgs = pkgsFor.${system};
            menu = ./installer/brand/keymaps.txt;
            kbd = pkgsFor.${system}.kbd;
            inherit omarchy;
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

          # The plugin section (#959). Same argument as the Graphics one, and
          # the state is even further out of reach: it needs a user who cloned
          # a plugin by hand before nixarchy shipped one at that id, which no
          # VM and no installer here produces.
          doctor-plugins = import ./tests/doctor-plugins.nix {
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

          # The Omarchy-channel line (#1278): stable, edge, dev and custom
          # flakes, and a machine where nixarchy-channel is not installed.
          doctor-channel = import ./tests/doctor-channel.nix {
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) doctor;
            omarchy = self.packages.${system}.omarchy;
          };

          # The dynamic-link check, against binaries built broken on purpose.
          # No CI machine keeps a wheel missing libGL in ~/.local/bin, so
          # these branches exist nowhere else -- see tests/doctor-ldd.nix.
          doctor-ldd = import ./tests/doctor-ldd.nix {
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) doctor;
          };
          shell-runtime-inputs = import ./tests/shell-runtime-inputs.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) doctor;
          };

          # The error explainer, against errors produced in the check rather
          # than pasted into it -- nixpkgs has reworded two of these families
          # inside a year, and a pasted trace would keep the check green while
          # the explainer stopped recognising what a user's machine prints.
          # See tests/explain.nix.
          explain = import ./tests/explain.nix {
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) explain;
          };

          # The packaged nixarchy-verify reaches its summary on a machine with
          # nothing (#1416). See tests/verify-runs.nix.
          # The packaged nixarchy-location against a fake nmcli and a private
          # HOME. See tests/location.nix.
          location = import ./tests/location.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) location;
            omarchy = self.packages.${system}.omarchy;
          };

          verify-runs = import ./tests/verify-runs.nix {
            pkgs = pkgsFor.${system};
            inherit (self.packages.${system}) verify;
          };

          # nixarchy-channel edits a file the user owns, so the check is mostly
          # about what it refuses. See tests/channel.nix.
          channel = import ./tests/channel.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # Edge carry (#1289): Setup > Language records a missing locale for
          # the next rebuild instead of running locale-gen.
          language-edge = import ./tests/language-edge.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # Typed agents and their children route through Nix dispatch;
          # absent CLIs refuse without invoking mise.
          agent-account-routing = import ./tests/agent-account-routing.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # #1616: what a destination does with the receiver the sender generates, when
          # it has no envfs or no OMARCHY_PATH. checks.session has the working case.
          account-copy = import ./tests/account-copy.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # `nixarchy pkg new` against stub nix-init and nix: the draft is
          # kept when its build fails, the placeholder hash is filled in from
          # the failed build, and a reshaped apps.nix is printed at rather
          # than edited. See tests/pkg-new.nix.
          pkg-new = import ./tests/pkg-new.nix {
            pkgs = pkgsFor.${system};
          };

          # What a network install would have to build, before it formats
          # anything. See tests/substitutable.nix.
          substitutable = import ./tests/substitutable.nix {
            pkgs = pkgsFor.${system};
          };

          # Why: tests/unavailable-apps.nix
          unavailable-apps = import ./tests/unavailable-apps.nix {
            pkgs = pkgsFor.${system};
            vm = self.nixosConfigurations.vm;
          };

          stable-eval = import ./tests/stable-eval.nix {
            inherit inputs stableVm;
            pkgs = pkgsFor.${system};
          };

          # The gate that decides whether a PR runs the install VM. Both
          # questions it answers, and both directions. See tests/install-gate.nix.
          install-gate = import ./tests/install-gate.nix { pkgs = pkgsFor.${system}; };

          # The shipped images carry the reference machines, and the network
          # image carries none of them. Guards the `source` argument #479
          # added to installer/cd.nix. See tests/iso-source.nix.
          iso-source = import ./tests/iso-source.nix {
            inputs = realInputs;
            pkgs = pkgsFor.${system};
          };

          # nixarchy-android turns what the network says into a host:port, so
          # the parsing is the command. avahi-browse and adb are stubbed with
          # real output. See tests/android.nix.
          android = import ./tests/android.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # The `try` front door's refusals, each driven with a stubbed
          # environment that lies about KVM, RAM, disk and the build plan.
          # Building tryApp is itself half the assertion: the app evaluates
          # and its script passes shellcheck, by writeShellApplication's own
          # checkPhase. See tests/try-preflight.nix.
          try-preflight = import ./tests/try-preflight.nix {
            pkgs = pkgsFor.${system};
            tryScript = ./installer/try.sh;
            tryApp = inputs.self.packages.${system}.try;
          };

          # --from-repo's two branches -- host already in the repository, host
          # added to it -- against git repositories built in the check. The
          # mode touches a user's config repository and had never executed
          # under any test.
          installer-from-repo = import ./tests/installer-from-repo.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          installer-disk-list = import ./tests/installer-disk-list.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };

          installer-early-exit = import ./tests/installer-early-exit.nix {
            pkgs = pkgsFor.${system};
            renderedInstallScript = "${inputs.self.packages.${system}.install}/bin/nixarchy-install";
          };

          try-nixarchy = import ./tests/try-nixarchy.nix {
            pkgs = pkgsFor.${system};
            vmTargetMiB =
              (builtins.head self.nixosConfigurations.installer-vm.config.virtualisation.emptyDiskImages).size;
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

          # Why: tests/theme-set-zed.nix
          theme-set-zed = import ./tests/theme-set-zed.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          osaka-jade-theme = import ./tests/osaka-jade-theme.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          home-manager-writers = import ./tests/home-manager-writers.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Why: tests/mise-launchers.nix
          mise-launchers = import ./tests/mise-launchers.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # Why: tests/install-phase-budget.nix
          install-phase-budget = import ./tests/install-phase-budget.nix {
            omarchy = self.packages.${system}.omarchy;
            pkgs = pkgsFor.${system};
          };

          # enroll's policy append, against real age keys and real sops. It
          # runs pkgs/sops-policy-add.nix rather than the CLI, because the CLI
          # reads the hostname from /proc and its recipient from /etc/ssh and
          # a sandbox has neither. Carries its own self-test: before the rule
          # exists, sops must REFUSE to encrypt, or the check cannot show that
          # enrolling did anything.
          secret-enroll = import ./tests/secret-enroll.nix {
            pkgs = pkgsFor.${system};
            policyAdd = self.packages.${system}.nixarchy-sops-policy-add;
          };
          secret-new = import ./tests/secret-new.nix {
            pkgs = pkgsFor.${system};
            secret = self.packages.${system}.nixarchy-secret;
            policyAdd = self.packages.${system}.nixarchy-sops-policy-add;
          };

          # The QML injected into upstream's Quickshell tree is copied, never
          # compiled, so a syntax error ships as a bar element that silently is
          # not there (#810). See tests/qml.nix -- it carries its own broken
          # fixture so it proves on every run that it can go red.
          qml = import ./tests/qml.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
            menuPlugin =
              inputs.self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.menu.src;
          };

          # configuration.md names every default plugin and service by its line
          # (#1246); tests/docs-lists.nix says which is missing.
          docs-lists = import ./tests/docs-lists.nix {
            pkgs = pkgsFor.${system};
            pluginNames = builtins.attrNames self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet;
            services = import ./data/services.nix;
            doc = ./docs/manual/configuration.md;
          };

          # The Hyprland substituter key was wrong from the first commit and nothing
          # noticed, because our cache served the same paths (#1248).
          cache-keys = import ./tests/cache-keys.nix { pkgs = pkgsFor.${system}; };

          # A keep-loaded plugin lost its shell API at the first shell.json
          # change, because manifestHasKind tested kinds with Array.isArray and a
          # Qt sequence is not one (#877). Runs the built function in a real QML
          # engine, with upstream's as its negative control.
          # Turning programs.nixarchy.aiMirror.mcp off takes nixarchy's entry
          # back out of the three agent configs, and leaves one the user wrote
          # (#773). The real package against fixtures, both cases.
          ai-mirror-mcp-remove = import ./tests/ai-mirror-mcp-remove.nix { pkgs = pkgsFor.${system}; };
          # Run mirror-vm against a fake guest to check batch references and
          # control release without booting a VM (#1580).
          mirror-vm = import ./tests/mirror-vm.nix { pkgs = pkgsFor.${system}; };
          skills-relink = import ./tests/skills-relink.nix { pkgs = pkgsFor.${system}; };
          robustness-modules = import ./tests/robustness-modules.nix { pkgs = pkgsFor.${system}; };
          home-writers-dry-run = import ./tests/home-writers-dry-run.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          manifest-has-kind = import ./tests/manifest-has-kind.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
            omarchySrc = omarchy;
          };
          # #1157: the failing-log excerpt read to EOF instead of exiting
          # early under `head -100`, which SIGPIPEd an upstream pipeline
          # stage under `pipefail` and killed the handoff before it posted.
          # See tests/copilot-handoff.nix.
          copilot-handoff = import ./tests/copilot-handoff.nix {
            pkgs = pkgsFor.${system};
          };
          # #1384: a failed build job ends with the failing check and its error.
          # See tests/failure-digest.nix.
          failure-digest = import ./tests/failure-digest.nix {
            pkgs = pkgsFor.${system};
          };
          # #1711: a failed nightly's issue carries the failing log's excerpt.
          # See tests/nightly-digest.nix.
          nightly-digest = import ./tests/nightly-digest.nix {
            pkgs = pkgsFor.${system};
          };
          # #1719: commit-independent.sh refuses a shallow clone.
          # See tests/commit-independent-shallow.nix.
          commit-independent-shallow = import ./tests/commit-independent-shallow.nix {
            pkgs = pkgsFor.${system};
          };
          panel-loaders = import ./tests/panel-loaders.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
            omarchySrc = omarchy;
          };
          agent-local-detach = import ./tests/agent-local-detach.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };
          user-migrations = import ./tests/user-migrations.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
            omarchySrc = omarchy;
          };
          user-migrations-ledger = import ./tests/user-migrations-ledger.nix {
            pkgs = pkgsFor.${system};
            omarchySrc = omarchy;
          };
          # #1381: no shipped plugin reads Color unqualified (Qt 6.12 shadows it). The
          # defaults come from defaultPluginSet; nixi and voice install through their own
          # Home Manager modules (modules/home.nix), so they are named here.
          qml-color-qualified = import ./tests/qml-color-qualified.nix {
            pkgs = pkgsFor.${system};
            sources =
              builtins.mapAttrs (_: p: p.src)
                inputs.self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet
              // {
                inherit (inputs) nixi;
                voice = inputs.nixarchy-voice;
              };
          };
          # #1368: no shipped script may self-extract an AppImage; appimage-run passes the flag to the app.
          appimage-extract = import ./tests/appimage-extract.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };
          # #1385: the passwordless-sudo toggle is hidden in the menu and the bar.
          passwordless-sudo-hidden = import ./tests/passwordless-sudo-hidden.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };
          omarchy-version-label = import ./tests/omarchy-version-label.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
            inherit omarchyVersion;
            lock = builtins.fromJSON (builtins.readFile ./flake.lock);
          };
          # #1370: omarchy-restart-terminal must reach nixpkgs' wrapped kitty and ghostty.
          restart-terminal-wrapped = import ./tests/restart-terminal-wrapped.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };
          # #1370: a theme-engine machine's omarchy-theme-gnome unit re-applies the GTK theme.
          theme-gnome-gtk = import ./tests/theme-gnome-gtk.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # What reaches nixarchy.cachix.org and what it costs: the allowlist
          # budget, proofs pushed alone, closures from main only (#697). Against
          # a stubbed nix, curl and cachix. See tests/cache-budget.nix.
          cache-budget = import ./tests/cache-budget.nix {
            pkgs = pkgsFor.${system};
            reference = self.nixosConfigurations.reference;
          };

          # The release guard and the weekly release-candidate body, against a
          # fixture repository (#1199). See tests/release-scripts.nix.
          release-scripts = import ./tests/release-scripts.nix {
            pkgs = pkgsFor.${system};
          };

          # The nightly bump follows RCs and never goes backwards (#1403).
          # See tests/omarchy-newest.nix.
          omarchy-newest = import ./tests/omarchy-newest.nix {
            pkgs = pkgsFor.${system};
          };

          # Install and edge's VM checks never share p620 (#1365). See
          # tests/vm-host-free.nix.
          vm-host-free = import ./tests/vm-host-free.nix {
            pkgs = pkgsFor.${system};
          };

          # The omarchy-app skill's templates build as written (#1406). See
          # tests/omarchy-app-template.nix.
          omarchy-app-template =
            let
              isEdge = lib.hasPrefix "edge-" self.packages.${system}.omarchy.version;
            in
            import ./tests/omarchy-app-template.nix {
              pkgs = pkgsFor.${system};
              omarchy = self.packages.${system}.omarchy;
              inherit isEdge;
              patch =
                if isEdge then
                  ./pkgs/omarchy/1406-omarchy-app-nix-edge.patch
                else
                  ./pkgs/omarchy/1406-omarchy-app-nix.patch;
            };

          # The nightly's cache step: probe every allowlist entry, rebuild and
          # push what the cache dropped, and still fail when a push delivers
          # nothing. Against a stubbed nix, curl and cachix. See
          # tests/cache-entries.nix.
          cache-entries = import ./tests/cache-entries.nix {
            pkgs = pkgsFor.${system};
          };

          # #734: the "nothing imports it" warning resolves each mention against
          # the file it appears in, so a stale root-level nixarchy-apps.nix no
          # longer silences it on a hosts/<hostname> layout -- where the app set
          # froze rather than breaking, and apply reported success throughout.
          # See tests/apply-imports.nix.
          # #979: --status, --log and --expect-sha256, against stub systemd.
          # #982: a restarted shell runs the generation's tree, not the one it
          # logged in with.
          # #948: `display text size` skips a config it cannot edit, and says
          # where to change it, instead of printing a sed error.
          # #1000: every tests/*.nix is imported by some checks entry, or is
          # named exempt with its reason. The existing coverage gate asserts
          # the other direction and cannot see this one.
          test-registration = import ./tests/test-registration.nix {
            pkgs = pkgsFor.${system};
            flakeFile = ./flake.nix;
            testsDir = ./tests;
            uniform = uniformChecks;
          };

          text-size-managed = import ./tests/text-size-managed.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          shell-restart-tree = import ./tests/shell-restart-tree.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # #1062: every shipped plugin has a beat in the screencast's shot
          # list. Only the two files it compares are inputs, so it rebuilds
          # when one of them changes rather than on every commit.
          shot-coverage = pkgsFor.${system}.runCommand "nixarchy-shot-coverage" { } ''
            root=$TMPDIR/root
            mkdir -p "$root/modules" "$root/tests/demo/screencast"
            cp ${./modules/home.nix} "$root/modules/home.nix"
            cp ${./tests/demo/screencast/shots.nix} "$root/tests/demo/screencast/shots.nix"
            bash ${./tests/demo/screencast/shot-coverage.sh} "$root"
            touch $out
          '';
          # #1479: screencast-restore puts each hidden widget back where it was. The
          # placement extraction and a model of the restore run over a redacted p620 snapshot.
          screencast-placement =
            pkgsFor.${system}.runCommand "nixarchy-screencast-placement"
              {
                nativeBuildInputs = [ pkgsFor.${system}.jq ];
              }
              ''
                bash ${./tests/demo/screencast/placement-test.sh} \
                  ${./tests/demo/screencast/placement.jq} \
                  ${./tests/demo/screencast/fixtures/p620-shell.json} \
                  ${./tests/demo/screencast/restore-plugins.sh}
                touch $out
              '';
          # #1491: the Chromium launcher rewrites /usr/share/omarchy paths and merges --enable-features from chromium-flags.conf.
          chromium-flags = pkgsFor.${system}.runCommand "nixarchy-chromium-flags" { } ''
            bash ${./tests/chromium-flags-test.sh} ${./pkgs/omarchy/chromium-flags.sh}
            touch $out
          '';

          # #953: a restart never ends with zero shells, against stubs that make
          # teardown slower than upstream's `timeout 5`; upstream's own script is
          # the negative control.
          shell-restart-race = import ./tests/shell-restart-race.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # #1070: `omarchy-menu close` asks the menu to dismiss before hiding it, so a
          # scripted close never starts dictation; stubs stand in for omarchy-shell.
          menu-close = import ./tests/menu-close.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # #1305: a partial override in the user's menu file keeps the rest of the row.
          menu-model-merge = import ./tests/menu-model-merge.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
            menuPlugin =
              inputs.self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.menu.src;
            nixi = inputs.self.nixosConfigurations.vm.config.home-manager.users.omarchy.services.nixi.package;
          };

          # #1342: a default browser entry that runs the launcher itself is refused.
          launch-browser-self-call = import ./tests/launch-browser-self-call.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # #1342: the login hook seeds the mimeapps list only into nothing.
          seed-hyprland-mimeapps = import ./tests/seed-hyprland-mimeapps.nix {
            pkgs = pkgsFor.${system};
            script = ./pkgs/seed-hyprland-mimeapps.sh;
          };

          # #1305: Right never runs a menu row, and a displaced request releases its caller,
          # and the card fits its widest label (#1339).
          menu-keys = import ./tests/menu-keys.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          home-backup-restore = import ./tests/home-backup-restore.nix {
            pkgs = pkgsFor.${system};
            script = ./pkgs/omarchy/nix-bin/nixarchy-home-backup;
          };

          rollback-kernel = import ./tests/rollback-kernel.nix {
            pkgs = pkgsFor.${system};
            script = ./pkgs/omarchy/nix-bin/nixarchy-rollback;
          };

          config-repo-ownership = import ./tests/config-repo-ownership.nix {
            pkgs = pkgsFor.${system};
            script = ./pkgs/omarchy/nix-bin/nixarchy-config-repo;
          };

          # #963, and it was registered by NOTHING until #982 went looking --
          # the file shipped and `checks` never named it, so it had never run.
          # The coverage gate asserts every entry in `checks` is built by a
          # workflow; it cannot see a test file that is in no entry.
          shell-ipc-resolve = import ./tests/shell-ipc-resolve.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          shell-session-launch = import ./tests/shell-session-launch.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };
          shell-session = import ./tests/shell-session.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };
          sleep-lock-generation = import ./tests/sleep-lock-generation.nix {
            pkgs = pkgsFor.${system};
            omarchy = self.packages.${system}.omarchy;
          };

          # The proof push: a killed job keeps what it proved, a result too
          # large to BE a proof is skipped rather than failed, and a push that
          # genuinely fails still exits non-zero. All three were false on
          # 2026-09-16 (#727, #729). Against a stubbed nix and cachix. See
          # tests/proof-push.nix.
          proof-push = import ./tests/proof-push.nix {
            pkgs = pkgsFor.${system};
          };

          # Every option that adds something, checked with it turned off too --
          # see tests/options.nix for why that half is the one at risk.
          # Upstream's /etc overlay: data/etc-overlay.nix says what answers each
          # file here (and modules/nixos.nix installs the rows it classes
          # `installed`), and this fails when upstream adds or drops one. See
          # tests/etc-overlay.nix and #642.
          etc-overlay = import ./tests/etc-overlay.nix { pkgs = pkgsFor.${system}; };

          # Upstream's sysctl values against the rendered file, and a user's
          # own mkDefault against every key. See tests/etc-sysctl.nix and #1615.
          etc-sysctl = import ./tests/etc-sysctl.nix {
            pkgs = pkgsFor.${system};
            reference = self.nixosConfigurations.reference;
            upstream = omarchy;
          };

          # The reference initrd can mount a disk it was not built on, which is
          # a precondition for offline install stage 3. See
          # tests/reference-initrd.nix and #436.
          reference-initrd = import ./tests/reference-initrd.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
          };

          # Installs onto a blank disk, reboots into the result on the
          # bootloader the installer wrote, and asserts a rebuild builds
          # nothing. See tests/install.nix for why the second machine is not a
          # normal test node.
          install-teardown = import ./tests/install-teardown.nix {
            pkgs = pkgsFor.${system};
          };

          # wait_for_multi_user prints what systemd is stuck on, bounded, and
          # re-raises the original failure (#1365). Stub machines, no VM.
          boot-diagnostics = import ./tests/boot-diagnostics.nix { pkgs = pkgsFor.${system}; };

          vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;

          # The installed machine, as opposed to the smoke-test guest: a real
          # bootloader, disko-provided filesystems, nothing faked. If this builds
          # and vm-toplevel builds, the extraction has not let the two drift.
          reference-toplevel = self.nixosConfigurations.reference.config.system.build.toplevel;

          # The nightly's `nix run .#update`, EVALUATED on every pull request: an
          # updateScript that is not a derivation (owe's list) broke it at
          # evaluation. A value, not the app: building it was 537 MB, unproofable.
          update-app = pkgsFor.${system}.runCommand "nixarchy-update-app" {
            drvLength = builtins.stringLength (
              builtins.unsafeDiscardStringContext self.packages.${system}.update.drvPath
            );
          } "touch $out";

          # Hyprland loads its GPU drivers into its own process, so they must
          # share its glibc -- evaluation only, no boot. See
          # tests/graphics-glibc.nix and #1154, #1158.
          graphics-glibc = import ./tests/graphics-glibc.nix {
            pkgs = pkgsFor.${system};
            config = self.nixosConfigurations.reference.config;
          };

          # #1166: the /etc/nixarchy catalogue names real files (not store
          # paths), is Mode A inert, and ships the manual. See
          # tests/nixarchy-options.nix.
          nixarchy-options = import ./tests/nixarchy-options.nix {
            pkgs = pkgsFor.${system};
            reference = self.nixosConfigurations.reference;
            flatsnap = self.inputs.nixarchy-flatsnap.outPath;
            inherit self;
            revision = import ./modules/revision.nix self;
          };

          # #1163: a user's own Mesa in hardware.graphics.extraPackages(32)
          # collides with nixarchy's, in buildEnv, once both are force-set --
          # evaluation only, against modules/nixos.nix's assertions. See
          # tests/graphics-mesa-clash.nix.
          # A declared machine's directory modes are ours, not upstream's 10-microvm (#1549).
          microvm-tmpfiles-order = import ./tests/microvm-tmpfiles-order.nix {
            pkgs = pkgsFor.${system};
            reference = self.nixosConfigurations.reference;
          };

          graphics-mesa-clash = import ./tests/graphics-mesa-clash.nix {
            pkgs = pkgsFor.${system};
            reference = self.nixosConfigurations.reference;
            hyprMesa = inputs.hyprland.inputs.nixpkgs.legacyPackages.${system}.mesa;
          };

          # Every package nixarchy adds to environment.systemPackages unasked
          # must yield to a user's own copy -- evaluation only. See
          # tests/user-packages-win.nix and #1167.
          user-packages-win = import ./tests/user-packages-win.nix {
            pkgs = pkgsFor.${system};
            reference = self.nixosConfigurations.reference;
            inherit lib;
          };

          # A user's own config, beside nixarchy's: builds the graphics and
          # systemPackages envs fixtures.nix names and checks nixarchy still
          # produces a working machine. See tests/coexistence/default.nix and
          # AGENTS.md#14. Claimed by the `system` job (build.yml), after the
          # installed-machine closure: it needs the reference toplevel's
          # closure warm.
          coexistence = import ./tests/coexistence/default.nix {
            pkgs = pkgsFor.${system};
            reference = inputs.self.nixosConfigurations.reference;
          };
          input-methods = import ./tests/input-methods.nix {
            pkgs = pkgsFor.${system};
            reference = inputs.self.nixosConfigurations.reference;
          };

          # Builds a runner and reads it. Boots nothing -- see tests/microvm-template.nix
          # for what that can and cannot prove. Costs about what reference-toplevel
          # above does: a runCommand plus a ~1-1.5 GB guest closure from
          # cache.nixos.org. This step is also how the templates reach
          # nixarchy.cachix.org: cachix-action pushes what this job builds.
          microvm-template = import ./tests/microvm-template.nix {
            pkgs = pkgsFor.${system};
            inherit lib;
            templates = lib.mapAttrs (name: _: {
              kvm = inputs.self.packages.${system}."microvm-${name}";
              tcg = inputs.self.packages.${system}."microvm-${name}-tcg";
            }) (import ./data/microvm-templates.nix);
            nixarchyVm = pkgsFor.${system}.callPackage ./pkgs/microvm.nix { inherit (inputs) self; };
          };

          # Reads the box catalogue structurally -- see
          # tests/box-template.nix for what that can and cannot prove. The
          # pins and images are shared with checks.box-boot and the cache output.
          box-template = import ./tests/box-template.nix {
            pkgs = pkgsFor.${system};
            inherit lib;
            templates = import ./data/box-templates.nix;
            imagePins = boxImagePins;
            inherit images;
            cached = self.packages.${system}.box-test-image;
          };

          # The half checks.box-template deliberately leaves alone: create a
          # real container from the default template's pinned image and enter
          # it, offline -- see tests/box-boot.nix.
          box-boot = import ./tests/box-boot.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
            imagePin = boxImagePins.archlinux;
            image = images.archlinux;
          };

          keyboard-boot = import ./tests/keyboard-boot.nix {
            inherit inputs;
            pkgs = pkgsFor.${system};
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
              # MiB, as integers: the release asset limit is 2048 MiB.
              images = [
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
                  echo "raising on purpose -- but iso-net's 2 GiB is GitHub's"
                  echo "limit on a release asset."
                  exit 1
                fi
                touch $out
              ''
            );
        }
        // lib.genAttrs uniformChecks (
          n:
          import ./tests/${n}.nix {
            inputs = if builtins.hasAttr n commitBound then realInputs else inputs;
            pkgs = pkgsFor.${system};
          }
        )
        # checks.options as shards (#1463): tests/options.nix returns the
        # "files" derivation with the case shards and the guard as passthru.
        // (
          let
            options = import ./tests/options.nix {
              inherit inputs;
              pkgs = pkgsFor.${system};
            };
            optionsReal = import ./tests/options.nix {
              inputs = realInputs;
              pkgs = pkgsFor.${system};
            };
          in
          {
            options-system = options.optionShards.system;
            options-home = options.optionShards.home;
            options-microvm = options.optionShards.microvm;
            options-files = optionsReal;
            options-shards = options.optionShards.guard;
          }
        )
      );
    };
}
