{ inputs, pkgs }:
# What the three install checks (checks.install, free-space,
# install-encrypted) seed as "the machine the installer is about to produce",
# shared so the three stop carrying their own copies of the same seed.
#
# diskConfig: the disk-config.nix module the caller has already applied
# (device, encrypt, mode -- whatever that test's disk looks like).
#
# reference: the `.config` of the nixosConfiguration whose initrd module
# lists are pinned -- reference-unencrypted for an unencrypted install,
# reference for an encrypted one.
#
# extraInstrumentationText: extra module BODY lines, as literal Nix source
# text, spliced into `etcInstrumentation` alongside the test backdoor import
# -- install-encrypted's console=ttyS0 and plymouth-off, say. Defaults to
# nothing. A string rather than a module: see `etcInstrumentation` below on
# why there is only one source of truth for this file's content.
#
# encrypt, recoverySecret: the template's own placeholders, substituted by
# install.sh's write_host_files (`@autologin@` follows `@encrypt@`, and
# `@recoverysecret@` is the initrd.secrets block when a recovery passphrase
# was given, `{ }` otherwise). Both default to what tests/install.nix and
# tests/free-space.nix want; install-encrypted sets both true.
{
  diskConfig,
  reference,
  extraInstrumentationText ? "",
  encrypt ? false,
  recoverySecret ? false,
}:
let
  # What nixos-generate-config writes on the target, as a module.
  #
  # This is the file the install generates INSIDE the VM, and #12 called it
  # unknowable from outside -- which is why this check could not pass. It is
  # not unknowable, it is just late: the machine is qemu, its devices are the
  # ones the test driver gives it, and the output is the same every run. What
  # is genuinely variable is one line, the host CPU's KVM module, so both
  # values are seeded and the install picks whichever it wrote.
  #
  # The file's TEXT does not have to match. It is imported as Nix source, not
  # copied to the store, so only the configuration it produces matters -- and
  # that is what this reproduces. If qemu's devices ever change, the install
  # falls back to building the difference, finds no network, and fails here
  # with the derivation it wanted; update this to match.
  hardwareConfig = cpuModule: {
    imports = [ "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];
    boot = {
      initrd.availableKernelModules = [
        "virtio_pci"
        "uhci_hcd"
        "ehci_pci"
        "ahci"
        "sr_mod"
        "virtio_blk"
      ];
      initrd.kernelModules = [ ];
      kernelModules = [ cpuModule ];
      extraModulePackages = [ ];
    };
    nixpkgs.hostPlatform = pkgs.lib.mkDefault pkgs.stdenv.hostPlatform.system;
  };

  # And the pin installer/install.sh adds underneath it.
  #
  # The installer forces both initrd lists to what the medium carries, so the
  # machine can reuse the initrd already there instead of building a
  # near-identical one -- see reuse_baked_initrd. That means the system this
  # test seeds has to carry the same force, or the installed system differs
  # from the seeded one by exactly an initrd and the install has to build it
  # with no network. Which is not a subtle failure: it is the source bootstrap,
  # and it ends by trying to download a patch from salsa.debian.org.
  #
  # `reference` is the caller's: reference-unencrypted for an unencrypted
  # install, since that test installs with encrypt=no and LUKS adds a dozen
  # crypto modules to the other one; reference itself for an encrypted one.
  initrdPin = {
    boot.initrd.availableKernelModules = pkgs.lib.mkForce reference.boot.initrd.availableKernelModules;
    boot.initrd.kernelModules = pkgs.lib.mkForce reference.boot.initrd.kernelModules;
  };

  # The NixOS test backdoor, as literal Nix SOURCE TEXT -- one source of
  # truth for both sides of the instrumented install, not a module evaluated
  # here and a separate heredoc on the installer node.
  #
  # An installed machine has no reason to carry it, and the installer is
  # right not to write it -- but without it the driver cannot run a single
  # command on the target: wait_for_unit, succeed and the rest all talk to a
  # root shell on /dev/hvc0 that only this module provides. So the installer
  # runs untouched and writes what it would write; then this text is copied
  # in as a file beside configuration.nix (see `instrumentScript`) and
  # nixos-install is run a second time, which is a copy rather than a build
  # because the SEED below imports this exact text too -- see
  # `targetSystemFor`. What boots is the disk the installer produced, plus a
  # serial shell.
  #
  # modulesPath and lib, not an absolute store path or a bare mkForce: the
  # generated flake evaluates in pure mode, where a path outside its own tree
  # is an error, and modulesPath/lib are supplied by the module system to
  # whatever imports this text -- both the real installed flake and the
  # seed's own `import (builtins.toFile ...)` below.
  #
  # extraInstrumentationText is install-encrypted's console=ttyS0 and
  # plymouth-off, spliced in as a second body line; `""` for every other
  # caller.
  etcInstrumentation = ''
    { modulesPath, lib, ... }:
    {
      imports = [ "''${modulesPath}/testing/test-instrumentation.nix" ];
      ${extraInstrumentationText}
    }
  '';

  # The exact cp/sed/grep the test script runs to add `etcInstrumentation`'s
  # text into the installed flake, as one string ready to interpolate into a
  # testScript. Into the machine's own directory, beside the
  # configuration.nix that imports it -- relative imports are why:
  # hosts/installed/configuration.nix says ./test-instrumentation.nix, and a
  # copy at the flake root is not that path.
  instrumentScript = ''
    installer.succeed(
        "cp /etc/nixarchy/test-instrumentation.nix /mnt/etc/nixos/hosts/installed/")
    installer.succeed(
        "sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\\n"
        "    ./test-instrumentation.nix|'"
        " /mnt/etc/nixos/hosts/installed/configuration.nix")
    installer.succeed(
        "grep -q test-instrumentation"
        " /mnt/etc/nixos/hosts/installed/configuration.nix")
  '';

  # The exact disko script the generated flake will evaluate to. The reference
  # host's is for /dev/vda -- its placeholder device -- and these tests install
  # to /dev/vdb (or free space on it), so they are different derivations and
  # the VM would have to build one with no network. Seeding it here is what
  # the ISO does for the whole closure in #15; the tests meet the same
  # requirement early.
  targetSystemFor =
    {
      cpuModule,
      instrumented ? false,
    }:
    let
      sys =
        (inputs.nixpkgs.lib.nixosSystem {
          # Not `inherit (pkgs) system`: pkgs.system is deprecated in favour of
          # stdenv.hostPlatform.system, and nixpkgs warns on every evaluation of
          # this check. Written out rather than inherited because the inherit form
          # is what hid it -- a grep for `pkgs.system` does not find it.
          system = pkgs.stdenv.hostPlatform.system;
          specialArgs = { inherit inputs; };
          modules = [
            inputs.self.nixosModules.nixarchy
            inputs.home-manager.nixosModules.home-manager
            inputs.disko.nixosModules.disko

            # The machine, as ONE module whose imports are the files
            # installer/template/host/default.nix imports -- not as flat entries
            # in this list.
            #
            # The shape is load-bearing and was not, before the hosts/ layout. A
            # module's `imports` and a nixosSystem's `modules` merge in different
            # orders, so listing these flat gives the same packages in a different
            # environment.systemPackages ORDER; system-path hashes that order into
            # chosenOutputs, so it is a different derivation, so the toplevel is,
            # and the install has to build what it can no longer copy -- offline,
            # which means stdenv, which means 459 derivations from hex0-seed and a
            # fetch of a Debian patch that never arrives.
            #
            # So this mirrors hosts/<name>/default.nix, and the inner block below
            # mirrors the configuration.nix that sits beside it, one level
            # DEEPER: default.nix imports host.nix, disk-config.nix and
            # configuration.nix (depth 1), and configuration.nix itself imports
            # hardware-configuration.nix -- which carries install.sh's initrd pin
            # -- and, in these tests, test-instrumentation.nix (depth 2). Before
            # #1176 all three seeds put hardwareConfig/initrdPin/instrumentation
            # at depth 0, flat in this very `modules` list, which is a different
            # merge order and a different chosenOutputs from the real install --
            # the gap checks.install-seed-shape now asserts closed. Keep both
            # depths in step with installer/template/host/ -- a mismatch shows up
            # as "cannot build", which is a clear enough signal.
            {
              imports = [
                (import ../../installer/host.nix {
                  hostname = "installed";
                  username = "omarchy";
                })
                diskConfig
                {
                  imports = [
                    (hardwareConfig cpuModule)
                    initrdPin
                  ]
                  # A store file, not a derivation: builtins.toFile hashes the
                  # string itself, so this is not IFD. Importing it rather than
                  # the `instrumentation` module tests/install.nix used to carry
                  # is what makes the seed and the generated flake import
                  # BYTE-IDENTICAL content -- see `etcInstrumentation` above.
                  ++ pkgs.lib.optional instrumented (
                    import (builtins.toFile "test-instrumentation.nix" etcInstrumentation)
                  );

                  time.timeZone = "UTC";
                  console.keyMap = "us";
                  nixpkgs.config.allowUnfree = true;
                  # Autologin follows encryption -- install.sh substitutes
                  # @autologin@ with the same $encrypt it substitutes @encrypt@
                  # with, because an encrypted disk has already authenticated the
                  # user by the time a greeter would ask.
                  services.displayManager.autoLogin = {
                    enable = encrypt;
                    user = "omarchy";
                  };
                  # hashedPasswordFile, as installer/template/host/configuration.nix
                  # sets it -- this block mirrors that file and the comment above
                  # says to keep them in step. It had drifted to `hashedPassword`,
                  # which nixpkgs now warns about: with both set, and mutableUsers
                  # true, the FILE wins, so the literal here was already dead and
                  # the machine was already logging in with what install.sh wrote.
                  #
                  # The warning appeared when installer/host.nix started setting
                  # the file too (#457), which is what made the drift visible
                  # rather than what caused it.
                  users.users.omarchy.hashedPasswordFile = "/var/lib/nixarchy/password.hash";

                  # @recoverysecret@'s substituted value: the initrd.secrets block
                  # when a recovery passphrase was given, `{ }` otherwise -- same
                  # depth as the keys above, because configuration.nix carries
                  # both as one file.
                  boot.initrd.secrets =
                    if recoverySecret then { "/etc/shadow" = "/var/lib/nixarchy/initrd-shadow"; } else { };
                }
              ];
            }
          ];
        }).config.system;
    in
    # Keep the old shape every caller (tests/install.nix, free-space.nix,
    # install-encrypted.nix) already uses -- `.toplevel`, `.diskoScript`,
    # `.initialRamdisk`, `.etc` -- and add `.path` beside them: `system.path`
    # is config.system's own sibling of config.system.build, not inside it,
    # and tests/install-seed-shape.nix needs it (#1176: `system.path` is the
    # property the depth bug moves, not `toplevel`, which can differ for
    # reasons unrelated to depth such as hostname-bearing initrd bits).
    sys.build // { inherit (sys) path; };
in
{
  inherit targetSystemFor etcInstrumentation instrumentScript;

  # Exposed for tests/install-seed-shape.nix, which has to reproduce the real
  # hardware-configuration.nix's CONTRIBUTION exactly -- mkForce and all -- on
  # the rendered-template side it compares against. Passed through
  # nixosSystem's specialArgs there rather than serialised to text: the same
  # Nix values both sides import, not a second encoding of them to keep in
  # step.
  inherit hardwareConfig initrdPin;
}
