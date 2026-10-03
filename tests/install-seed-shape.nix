{
  inputs,
  pkgs,
  installScript,
}:
# Does the seed tests/install.nix, tests/free-space.nix and
# tests/install-encrypted.nix carry (tests/lib/installed-target.nix) describe
# the SAME machine the real installer writes?
#
# #1176 found that it did not: all three seeds put hardwareConfig/initrdPin
# /instrumentation flat in the nixosSystem `modules` list (depth 0), while
# install.sh's own template nests them two levels deeper --
# hosts/<name>/default.nix imports host.nix, disk-config.nix and
# configuration.nix (depth 1), and configuration.nix imports
# hardware-configuration.nix, which carries the initrd pin, and
# test-instrumentation.nix (depth 2). A module's `imports` and a
# nixosSystem's `modules` merge in a different order, so the two shapes can
# describe the same packages in a different environment.systemPackages
# ORDER -- a different chosenOutputs, a different toplevel, and an offline
# install that has to BUILD what it can no longer copy.
#
# So this builds BOTH sides for the same six cases (install, free-space,
# install-encrypted, each plain and instrumented) and compares
# system.build.toplevel.drvPath:
#
#   seed  tests/lib/installed-target.nix's targetSystemFor, as each test
#         calls it.
#
#   VM    install.sh's own substitute_host_files/subst, run against
#         installer/template/host/ -- extracted with sed rather than
#         sourced, because sourcing install.sh starts the wizard (the same
#         pattern tests/installer-offline-rescue.nix:37 uses) -- then
#         imported as `installer/template/flake.nix`'s module list would
#         import it (IFD: this is a real derivation's output, not a toFile).
#
# hardware-configuration.nix is the one file nixos-generate-config writes
# that this cannot reproduce by substitution, because nothing here runs on a
# real machine to detect. Rather than re-encode hardwareConfig/initrdPin as
# TEXT -- a second copy of mkForce's shape to keep in step with the first --
# the VM side's stub takes them from specialArgs as the exact Nix VALUES the
# seed already computed. tests/lib/installed-target.nix exports them for
# exactly this.
#
# nixarchy-hardware.nix is `{ ... }: { }` on both sides for now -- #1176's
# step 6 tries the real content install.sh writes for a QEMU guest and
# records whether it changes anything.
let
  helper = import ./lib/installed-target.nix { inherit inputs pkgs; };

  cpuModule = "kvm-amd";

  # The three tests' own arguments to the helper -- kept in step with
  # tests/install.nix, tests/free-space.nix and tests/install-encrypted.nix
  # by hand; a mismatch here tests the wrong machine, silently.
  targets = [
    {
      name = "install";
      diskMode = "whole";
      encrypt = false;
      recoverySecret = false;
      extraInstrumentationText = "";
      diskConfig = import ../installer/disk-config.nix {
        device = "/dev/vdb";
        encrypt = false;
      };
      reference = inputs.self.nixosConfigurations.reference-unencrypted.config;
    }
    {
      name = "free-space";
      diskMode = "free";
      encrypt = false;
      recoverySecret = false;
      extraInstrumentationText = "";
      diskConfig = import ../installer/disk-config.nix {
        mode = "free";
        device = "/dev/vdb";
        encrypt = false;
      };
      reference = inputs.self.nixosConfigurations.reference-unencrypted.config;
    }
    {
      name = "install-encrypted";
      diskMode = "whole";
      encrypt = true;
      recoverySecret = true;
      extraInstrumentationText = ''
        boot.kernelParams = [ "console=ttyS0,115200" ];
        boot.plymouth.enable = lib.mkForce false;
      '';
      diskConfig = import ../installer/disk-config.nix {
        device = "/dev/vdb";
        encrypt = true;
      };
      reference = inputs.self.nixosConfigurations.reference.config;
    }
  ];

  # install.sh's own substitute_host_files/subst, then the installed-target
  # layout, rendered for one case. A real derivation, not builtins.toFile --
  # importing its `hosts/installed` is IFD, same as #1176's spec allows.
  #
  # recoveryHash is a stub, never a real hash: @recoverysecret@'s VALUE is
  # appended to the initrd by systemd-boot at bootloader-install time, not
  # baked into any derivation (installer/template/host/configuration.nix's
  # own comment on boot.initrd.secrets says so) -- so its text cannot move
  # system.build.toplevel.drvPath, which is the only thing this check reads
  # off either side.
  renderHost =
    {
      name,
      diskMode,
      encrypt,
      recoverySecret,
      etcInstrumentation,
      instrumented,
    }:
    pkgs.runCommand
      "nixarchy-install-seed-shape-${name}${pkgs.lib.optionalString instrumented "-instrumented"}"
      { }
      ''
        mkdir -p "$out/hosts/installed"
        cp ${../installer/template/host/default.nix} "$out/hosts/installed/default.nix"
        cp ${../installer/template/host/configuration.nix} "$out/hosts/installed/configuration.nix"
        cp ${../installer/disk-config.nix} "$out/disk-config.nix"
        # cp preserves the store's read-only mode; subst below writes in place.
        chmod -R u+w "$out"
        printf '{ ... }:\n{ }\n' > "$out/hosts/installed/nixarchy-apps.nix"
        printf '{ ... }:\n{ }\n' > "$out/hosts/installed/nixarchy-hardware.nix"

        # The stand-in for nixos-generate-config's output -- see the file
        # header on why this takes the seed's values through specialArgs
        # rather than carrying a second encoding of them.
        printf '%s\n' \
          '{ seedHardwareConfig, seedInitrdPin, seedCpuModule, ... }:' \
          '{' \
          '  imports = [ (seedHardwareConfig seedCpuModule) seedInitrdPin ];' \
          '}' \
          > "$out/hosts/installed/hardware-configuration.nix"

        # The functions on their own, extracted rather than sourced:
        # install.sh runs a wizard when sourced. Same pattern as
        # tests/installer-offline-rescue.nix:37.
        for fn in subst substitute_host_files; do
          sed -n "/^$fn()/,/^}/p" ${installScript} >> f.sh
          echo >> f.sh
        done
        for fn in subst substitute_host_files; do
          if ! grep -q "^$fn()" f.sh; then
            echo "install.sh: $fn is not there any more" >&2
            exit 1
          fi
        done
        . ./f.sh

        work=$out
        hostdir=$out/hosts/installed
        hostname=installed
        username=omarchy
        device=/dev/vdb
        disk_mode=${diskMode}
        timezone=UTC
        keymap=us
        encrypt=${if encrypt then "true" else "false"}
        recovery_hash=${if recoverySecret then "rescue-me-hash-stub" else ""}
        substitute_host_files

        ${pkgs.lib.optionalString instrumented ''
          printf '%s\n' '${etcInstrumentation}' > "$out/hosts/installed/test-instrumentation.nix"
          sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\n    ./test-instrumentation.nix|' \
            "$out/hosts/installed/configuration.nix"
          if ! grep -q test-instrumentation "$out/hosts/installed/configuration.nix"; then
            echo "the test-instrumentation sed did not land" >&2
            exit 1
          fi
        ''}
      '';

  # Both sides, for one (target, instrumented) pair.
  caseFor =
    target: instrumented:
    let
      seed = helper {
        inherit (target)
          diskConfig
          reference
          encrypt
          recoverySecret
          extraInstrumentationText
          ;
      };
      # system.path, not system.build.toplevel: #1176 is about the ORDER
      # environment.systemPackages is built in, which system.path's
      # buildEnv hashes directly into its own derivation. toplevel sits on
      # top of a great deal else (the initrd, the activation script,
      # hostname-bearing bits) that can legitimately differ for reasons
      # this check is not about -- system.path is the property.
      seedDrv = (seed.targetSystemFor { inherit cpuModule instrumented; }).path.drvPath;

      dir = renderHost {
        inherit (target)
          name
          diskMode
          encrypt
          recoverySecret
          ;
        inherit instrumented;
        inherit (seed) etcInstrumentation;
      };
      vm =
        (inputs.nixpkgs.lib.nixosSystem {
          system = pkgs.stdenv.hostPlatform.system;
          specialArgs = {
            inherit inputs;
            seedHardwareConfig = seed.hardwareConfig;
            seedInitrdPin = seed.initrdPin;
            seedCpuModule = cpuModule;
          };
          modules = [
            inputs.self.nixosModules.nixarchy
            inputs.home-manager.nixosModules.home-manager
            inputs.disko.nixosModules.disko
            "${dir}/hosts/installed"
          ];
        }).config.system.path.drvPath;
    in
    {
      name = target.name + pkgs.lib.optionalString instrumented "-instrumented";
      equal = seedDrv == vm;
      # unsafeDiscardStringContext: these are printed, not built. Keeping
      # the context would make REALISING this check's own derivation force
      # a build of system.path for all twelve systems -- the opposite of
      # the cheap, evaluation-only check this is meant to be.
      seedDrv = builtins.unsafeDiscardStringContext seedDrv;
      vmDrv = builtins.unsafeDiscardStringContext vm;
    };

  results = pkgs.lib.concatMap (
    target:
    map (caseFor target) [
      false
      true
    ]
  ) targets;
in
pkgs.runCommand "nixarchy-install-seed-shape" { } ''
  fails=0
  ${pkgs.lib.concatMapStringsSep "\n" (r: ''
    if [ ${if r.equal then "1" else "0"} -eq 1 ]; then
      echo "equal   ${r.name}"
    else
      echo "DIFFERS ${r.name} seed=${r.seedDrv} vm=${r.vmDrv}"
      fails=$((fails + 1))
    fi
  '') results}
  if [ "$fails" -ne 0 ]; then
    exit 1
  fi
  touch "$out"
''
