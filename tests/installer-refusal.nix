{ inputs, pkgs }:
# The #300 guarantee, proved on a disk: a dark substituter is refused with the
# target INTACT.
#
# tests/installer-store-space.nix drives preflight_build with a curl and a nix
# that lie, and that is real coverage of the logic -- but it cannot fail if the
# installer wipes the disk anyway, because there is no disk. This is the other
# half: the real install.sh, the real main() ordering, a real blank /dev/vdb,
# and the assertion that a refusal leaves it bit-for-bit bare.
#
# ## The trap, and why this test is shaped the way it is
#
# A naive version of this test -- net-image marker present, no network at all
# -- tests the WRONG GUARD. With no network, ask_network (install.sh:295, the
# guard that predates #302) refuses in its unattended branch before
# preflight_build ever runs, and the test goes green having never executed a
# line of the code it exists to cover. The case #300 was filed about is
# narrower: the network is fine at question time and a substituter is dark at
# commit time -- the CDN outage shape, the window between ask_network and the
# wipe.
#
# So this machine answers as cache.nixos.org itself: an nginx behind a
# self-signed cert the VM trusts, plus a hosts entry, serving /nix-cache-info
# -- the exact probe network_ready runs. ask_network passes. The install
# proceeds to the point #302 guards. nixarchy.cachix.org resolves nowhere,
# preflight's own probe of it fails, and the refusal that follows must be
# preflight's -- ask_network's message is asserted ABSENT, so this test cannot
# quietly slide back to covering the old guard.
#
# Cheap on purpose: no seeded closure, because the refusal fires at the curl
# probe, before any evaluation or build. The node is base NixOS plus the
# install package and an nginx. Measured on first construction: 23s of test
# script, 2-3 minutes end to end -- against checks.install's ~20 minutes --
# which is why this runs per-PR rather than nightly-only.
let
  # One self-signed cert, used as the server cert and trusted as a CA: enough
  # for `curl -sfI https://cache.nixos.org/nix-cache-info` to say 200.
  cert = pkgs.runCommand "refusal-stub-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
      -keyout $out/key.pem -out $out/cert.pem \
      -subj "/CN=cache.nixos.org" \
      -addext "subjectAltName=DNS:cache.nixos.org"
  '';

  # The same test-only hash tests/install.nix uses; validate_answers wants a
  # crypt string, not a placeholder.
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-installer-refusal";

  nodes.machine =
    { pkgs, ... }:
    {
      environment = {
        systemPackages = [
          inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install
          pkgs.git
          pkgs.curl
        ];

        # The net-image marker. Both guards key on it: ask_network asks only
        # on this image, and preflight_build probes only on it.
        etc."nixarchy-iso-net".text = "";

        etc."nixarchy/answers".text = ''
          device=/dev/vdb
          encrypt=no
          recovery_passphrase=rescue-me
          hostname=installed
          username=omarchy
          password_hash=${passwordHash}
          timezone=UTC
          keymap=us
        '';
      };

      networking.hosts."127.0.0.1" = [ "cache.nixos.org" ];
      security.pki.certificateFiles = [ "${cert}/cert.pem" ];
      services.nginx = {
        enable = true;
        virtualHosts."cache.nixos.org" = {
          onlySSL = true;
          sslCertificate = "${cert}/cert.pem";
          sslCertificateKey = "${cert}/key.pem";
          locations."/nix-cache-info".return = "200 'StoreDir: /nix/store\\n'";
        };
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      virtualisation = {
        memorySize = 2048;
        cores = 2;
        # The installer refuses to run without /sys/firmware/efi, and is right
        # to; same reasoning as tests/install.nix.
        useEFIBoot = true;
        emptyDiskImages = [ 2048 ];
      };
    };

  # A machine that booted the way require_root_and_uefi refuses: SeaBIOS, no
  # /sys/firmware/efi. useEFIBoot deliberately absent -- every other node in
  # this repo sets it true, which is precisely why the BIOS refusal at
  # install.sh:221 had never executed under any test. No stubs and no
  # extraction here: qemu's default firmware IS the condition, so the real
  # guard runs against a real absent /sys/firmware/efi, as root, the way it
  # would on a user's machine. Same answers file and a spare disk, so "refused
  # AND the disk is bare" is assertable the same way as above.
  nodes.bios =
    { pkgs, ... }:
    {
      environment = {
        systemPackages = [
          inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install
        ];
        etc."nixarchy/answers".text = ''
          device=/dev/vdb
          encrypt=no
          recovery_passphrase=rescue-me
          hostname=installed
          username=omarchy
          password_hash=${passwordHash}
          timezone=UTC
          keymap=us
        '';
      };
      virtualisation.emptyDiskImages = [ 2048 ];
    };

  testScript = ''
    # The BIOS machine first: its whole test is one command, and a refusal
    # this early must not depend on anything the EFI machine sets up.
    bios.wait_for_unit("multi-user.target")
    bios.fail("test -d /sys/firmware/efi")
    rc_bios, out_bios = bios.execute(
        "nixarchy-install --answers /etc/nixarchy/answers 2>&1", timeout=120)
    print(out_bios)
    assert rc_bios != 0, "the install proceeded (rc=0) on a BIOS-booted machine"
    assert "booted in BIOS/legacy mode" in out_bios, (
        "the refusal does not say the machine booted BIOS:\n" + out_bios)
    # Refused at the door, before any question or wipe: the disk stays bare.
    bios.succeed("test -z \"$(blkid /dev/vdb 2>/dev/null)\"")
    bios.shutdown()

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("nginx.service")

    # The stub works: the exact probe network_ready runs.
    machine.succeed("curl -sfI --max-time 8 https://cache.nixos.org/nix-cache-info")

    # The disk before: bare, no partitions.
    before = machine.succeed("lsblk -no NAME /dev/vdb").strip()
    assert before == "vdb", f"vdb is not bare before the install:\n{before}"

    rc, out = machine.execute("nixarchy-install --answers /etc/nixarchy/answers 2>&1", timeout=600)
    print(out)

    # (a) THE GUARANTEE, checked first because it is the one #300 is about:
    # whatever else happened, the disk is intact. tests/installer-store-space
    # cannot make this assertion at all -- it has no disk -- and proving this
    # line can bite is the red that justifies the whole VM: delete the
    # iso-net marker above and the install proceeds to format_disk, and this
    # fails with partitions in the output.
    after = machine.succeed("lsblk -no NAME /dev/vdb").strip()
    assert after == "vdb", f"the disk was touched despite the refusal:\n{after}"
    machine.succeed("test -z \"$(blkid /dev/vdb 2>/dev/null)\"")

    # (b) refused, non-zero.
    assert rc != 0, "the install proceeded (rc=0) with a dark substituter"

    # (c) the refusal is preflight's, names the cache and the network, and
    # says the disk is intact -- not a dependency cascade...
    assert "cannot reach https://nixarchy.cachix.org" in out, (
        "the refusal does not name the unreachable substituter:\n" + out)
    assert "network" in out, "the refusal does not name the network:\n" + out
    assert "disk has not been touched" in out, (
        "the refusal does not say the disk is intact:\n" + out)
    # ...and not ask_network's, which is the wrong-guard trap the header
    # describes: if this fires, the test stopped covering #302's code.
    assert "this image installs over the network and there is none" not in out, (
        "ask_network refused before preflight ever ran -- wrong guard exercised")

    print("refused before the wipe; /dev/vdb untouched")
  '';
}
