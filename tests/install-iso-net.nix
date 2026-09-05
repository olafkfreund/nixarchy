{ inputs, pkgs }:
# Does the NET image install a desktop by FETCHING it?
#
# tests/install-iso.nix proves the offline artifact with -nic none. This is
# the other image -- the one people download for a network install, the one
# the NIXARCHY_4_0_2 tester was burned by, and the one #302's preflight
# exists to protect -- and until this check it had never been installed from,
# in CI or anywhere else. The offline path had a check; the net path had
# nothing.
#
# ## What "network" means here, and the honesty boundary
#
# A nix build sandbox has no internet, and this check does not pretend
# otherwise. installer/cd.nix bakes the flake SOURCES on both images
# ("inputSources stays on BOTH images"), so evaluation needs no GitHub; what
# the net image needs from its network is exactly one thing: REACHABLE
# SUBSTITUTERS. A substituter is a thing a second VM on this test's own vlan
# can be. So the "internet" is one declared node: dnsmasq handing the ISO its
# DHCP lease and resolving the three cache hostnames to itself, an nginx TLS
# stub answering the /nix-cache-info probes, and this build's own store
# served as a real binary cache over HTTP.
#
# What this therefore proves: the shipped net image boots, identifies itself,
# runs the preflight (observed on the wire, see below), fetches the closure
# it does not carry from a substituter, installs it, and the result boots.
# Hermetically -- a gate here does not depend on cache.nixos.org being up,
# which the CDN stall of 2026-09-04 made a requirement rather than a taste.
#
# What it deliberately does NOT prove: the real https path to the real
# caches -- certificate chains, CDN behaviour. No sandboxed check can; that
# half belongs to verify.sh-style runs on real hardware with real network.
#
# ## The two injections, and why they live where they live
#
# The image under test is untouched -- its own bootloader, kernel, store and
# /etc/nixarchy-iso-net marker. Two environment variables in the DRIVING
# SCRIPT on the answers disk (a thing a person could equally type) bend its
# run toward the stub internet:
#
#   SSL_CERT_FILE / NIX_SSL_CERT_FILE  the test CA, so the shipped curl
#       accepts the stub for network_ready and preflight's probes. The https
#       substituters themselves still fail TLS at the daemon (which reads no
#       such variable) and are disabled with a warning -- which is fine,
#       because:
#
#   NIX_CONFIG  adds the local http:// substituter and require-sigs=false.
#       root is a trusted user on the ISO, so the daemon accepts both; the
#       served paths are this build's own outputs, unsigned for the same
#       reason tests/install.nix gives.
#
# ## Preflight, observed rather than inferred
#
# preflight_build prints nothing when it passes, so "it ran" cannot be read
# off the install log -- a silent skip and a silent pass look identical
# (exactly the ambiguity the offline gate run could not resolve). But its
# probe loop is the only thing in the whole flow that asks
# nixarchy.cachix.org for /nix-cache-info -- network_ready asks only
# cache.nixos.org -- so the stub's access log, on a node the driver can
# read, IS the execution trace: a logged request for that host is preflight
# executing, counted on the wire.
let
  iso = inputs.self.nixosConfigurations.iso-net.config.system.build.isoImage;
  isoName = "${inputs.self.nixosConfigurations.iso-net.config.image.baseName}.iso";

  qemuCommon = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };

  # One cert, three SANs: every hostname the installer probes over https.
  ca = pkgs.runCommand "iso-net-stub-ca" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
      -keyout $out/key.pem -out $out/cert.pem \
      -subj "/CN=cache.nixos.org" \
      -addext "subjectAltName=DNS:cache.nixos.org,DNS:nixarchy.cachix.org,DNS:hyprland.cachix.org"
  '';

  # Same fixed hash as tests/install-iso.nix, same reason: mkpasswd salts
  # randomly and would make the installed system a different path every run.
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";

  referenceConfigs = map (c: c.config) [
    inputs.self.nixosConfigurations.reference
    inputs.self.nixosConfigurations.reference-unencrypted
  ];

  answersImage =
    pkgs.runCommand "nixarchy-net-test-answers.img"
      {
        nativeBuildInputs = [
          pkgs.dosfstools
          pkgs.mtools
        ];
      }
      ''
        # Quoted heredoc; the hash is mostly dollar signs. See
        # tests/install-iso.nix for what an unquoted one cost.
        cat > answers <<'EOF'
        device=/dev/vda
        encrypt=no
        hostname=nettest
        username=omarchy
        password_hash=${passwordHash}
        timezone=UTC
        keymap=us
        EOF

        cat > drive <<'EOF'
        #!/bin/sh
        # Run as `sudo sh /a/drive`. Same step/serial-marker shape as the
        # offline test; see there for why.
        step() {
          tag=$1
          shift
          "$@" > /tmp/out 2>&1
          rc=$?
          cat /tmp/out > /dev/ttyS0
          echo "$tag-$rc-X" > /dev/ttyS0
          [ $rc -eq 0 ] && return 0
          [ -f /var/log/nixarchy-install.log ] &&
            tail -80 /var/log/nixarchy-install.log > /dev/ttyS0
          exit 1
        }

        step STOPPED systemctl stop nixarchy-installer.service

        # THE marker: the one preflight_build and ask_network key on, absent
        # from the offline image and from every seeded gate VM -- presence
        # here is what makes this run exercise #302's code at all.
        step MARKER test -f /etc/nixarchy-iso-net

        # The stub internet is up before the installer asks: DHCP gave us a
        # lease and the probe network_ready runs answers 200.
        export SSL_CERT_FILE=/a/ca.pem NIX_SSL_CERT_FILE=/a/ca.pem
        step LEASED sh -c 'ip -4 addr show | grep -q "192\.168\.1\."'
        step PROBE curl -sfI --max-time 8 https://cache.nixos.org/nix-cache-info

        # The desktop is NOT on this image -- the half the offline test
        # cannot claim, asserted before the install rather than taken from
        # the image's name. The store on the ISO is the squashfs plus a
        # tmpfs overlay; the reference system path is on neither.
        step NOTBAKED sh -c '! test -e ${inputs.self.nixosConfigurations.reference-unencrypted.config.system.build.toplevel}'

        # The local substituter, and unsigned paths accepted from it: root is
        # trusted on the ISO, and the paths are this build's own outputs.
        # `substituters =`, an override rather than an extra: the https names
        # all resolve to the probe stub, and letting the daemon query three
        # 404-storming stubs for every path before the one real cache adds
        # thousands of useless requests and an HTTP/2-hang surface for zero
        # coverage. The probes above already proved the https path answers.
        NIX_CONFIG="require-sigs = false
        substituters = http://192.168.1.1:5000"
        export NIX_CONFIG

        # The install writes its progress to its log, not the console --
        # stream it to the serial line so a stall names its own location
        # instead of presenting as fifty silent minutes.
        (tail -f /var/log/nixarchy-install.log > /dev/ttyS0 2>/dev/null &)

        step INSTALLED nixarchy-install --answers /a/answers

        step FLAKE test -d /mnt/etc/nixos/.git
        step ESP test -d /mnt/boot/EFI

        # FETCHED, from the guest's side: paths were copied from the http
        # substituter. The wire-side half of this assertion -- narinfo/nar
        # requests in the cache's access log -- is made by the driver, which
        # can read the cache node.
        grep -q 'http://192.168.1.1:5000' /var/log/nixarchy-install.log
        step FETCHED test $? -eq 0

        step FALLBACK test -f /mnt/boot/EFI/BOOT/BOOTX64.EFI
        EOF

        truncate -s 1M $out
        mkfs.vfat -n NIXANSWERS $out
        mcopy -i $out answers ::answers
        mcopy -i $out drive ::drive
        mcopy -i $out ${ca}/cert.pem ::ca.pem
      '';

  commonFlags = [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-m 8192 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
  ];

  installerCommand = pkgs.lib.concatStringsSep " " (
    commonFlags
    ++ [
      # virtio-scsi CD, not IDE; see the offline test for the GRUB failure
      # IDE produces.
      "-device virtio-scsi-pci,id=scsi0"
      "-drive id=cd0,if=none,media=cdrom,readonly=on,format=raw,file=${iso}/iso/${isoName}"
      "-device scsi-cd,bus=scsi0.0,drive=cd0,bootindex=0"
    ]
  );

  # The installed machine needs no network to boot.
  targetCommand = pkgs.lib.concatStringsSep " " (commonFlags ++ [ "-nic none" ]);
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-install-iso-net";

  # The stub internet. A declared node on purpose: it is infrastructure, not
  # the thing under test, so the backdoor is fine here -- and declaring it is
  # what makes the driver bring up the vde switch the hand-built installer
  # attaches to.
  nodes.cache =
    { pkgs, ... }:
    {
      virtualisation.vlans = [ 1 ];
      # Serving the closure means holding it: these paths land in this
      # derivation's closure, on the host store the node sees over 9p.
      #
      # Not just the toplevels. The installer BUILDS things in the guest --
      # the diskoScript for the answered device, and the ~20 per-machine
      # derivations run_install's comment counts -- and on the net image
      # their parts arrive by FETCH, where the offline image bakes them
      # (installer/cd.nix's `lib.optionals offline` list; this mirrors it).
      # The first run of this test proved the gap the hard way: format_disk
      # tried to build disko from source in the guest, died at
      # make-binary-wrapper-hook, and the install failed before touching
      # the disk.
      virtualisation.additionalPaths =
        map (c: c.system.build.toplevel) referenceConfigs
        ++ map (c: c.system.build.diskoScript) referenceConfigs
        ++ map (c: c.system.build.toplevel.inputDerivation) referenceConfigs
        ++ map (c: c.system.build.initialRamdisk.inputDerivation) referenceConfigs
        ++ map (c: c.system.build.etc.inputDerivation) referenceConfigs
        ++ map (c: c.system.modulesTree) referenceConfigs
        ++ [
          # modules-shrunk is per-machine (the hardware config changes the
          # module list) and its build runs kmod; the toplevel's wrapper
          # check needs libcap. v3 of this test found each hole in turn:
          # missing disko parts, then a kmod build that walked back to
          # texinfo's tarball. This is cd.nix's offline toolchain, complete,
          # rather than the subset that happened to fail so far.
          pkgs.kmod
          pkgs.kmod.dev
          pkgs.libcap
          pkgs.nukeReferences
          pkgs.stdenv
          pkgs.stdenvNoCC
          pkgs.stdenv.cc
          pkgs.gnumake
          pkgs.gnutar
          pkgs.diffutils
          pkgs.patchelf
          pkgs.file
          pkgs.findutils
          pkgs.gawk
          pkgs.gnused
          pkgs.gnugrep
          pkgs.gzip
          pkgs.xz
          pkgs.bash
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.perl
          pkgs.python3
          pkgs.jq
        ];

      networking.firewall.enable = false;

      services = {
        # DHCP for the ISO, and the three cache hostnames resolved to this
        # node. The test framework gives this node 192.168.1.1 on eth1.
        dnsmasq = {
          enable = true;
          settings = {
            interface = "eth1";
            bind-interfaces = true;
            dhcp-range = "192.168.1.100,192.168.1.200,12h";
            address = [
              "/cache.nixos.org/192.168.1.1"
              "/nixarchy.cachix.org/192.168.1.1"
              "/hyprland.cachix.org/192.168.1.1"
            ];
          };
        };

        # The https stub the probes hit. $host in the log line is what turns
        # this log into the preflight execution trace: only preflight asks
        # nixarchy.cachix.org.
        nginx = {
          enable = true;
          appendHttpConfig = ''
            log_format probes '$host $request';
            access_log /var/log/nginx/probes.log probes;
          '';
          virtualHosts."cache.nixos.org" = {
            serverAliases = [
              "nixarchy.cachix.org"
              "hyprland.cachix.org"
            ];
            onlySSL = true;
            sslCertificate = "${ca}/cert.pem";
            sslCertificateKey = "${ca}/key.pem";
            locations."/nix-cache-info".return = "200 'StoreDir: /nix/store\\n'";
          };
        };

        # The binary cache itself, plain http on 5000: the daemon on the ISO
        # reads no SSL_CERT_FILE, so https would only add a failure mode.
        # harmonia, not nix-serve: the perl server was the prime suspect when
        # the first run of this test wedged mid-fetch with zero traffic on
        # the vlan for fifty minutes.
        harmonia = {
          enable = true;
          settings.bind = "0.0.0.0:5000";
        };
      };
    };

  testScript = ''
    import os
    import shutil
    import subprocess
    import time

    cache.start()
    cache.wait_for_unit("multi-user.target")
    cache.wait_for_unit("dnsmasq.service")
    cache.wait_for_unit("nginx.service")
    cache.wait_for_unit("harmonia.socket")
    # The framework's address for the first node on vlan 1; dnsmasq's
    # address= entries above hardcode it, so pin it here rather than let the
    # two drift apart silently.
    cache.succeed("ip -4 addr show eth1 | grep -q 192.168.1.1/")
    # The cache can serve what the installer will ask for.
    cache.succeed("curl -sf http://127.0.0.1:5000/nix-cache-info | grep -q StoreDir")

    # Same EFI variable-store arrangement as the offline test, same reasons.
    efi_vars = os.path.abspath("efi-vars.fd")
    shutil.copyfile("${pkgs.OVMF.variables}", efi_vars)
    os.chmod(efi_vars, 0o644)
    efi = f" -drive if=pflash,format=raw,unit=1,readonly=off,file={efi_vars}"

    # The vde switch the driver started for the cache node; the hand-built
    # installer joins the same wire.
    net = (" -netdev vde,id=n1,sock=" + os.path.abspath("vde1.ctl")
           + " -device virtio-net-pci,netdev=n1")

    vms = []

    def reap():
        for m in vms:
            try:
                m.send_monitor_command("quit")
            except Exception:
                pass

    try:
        disk = os.path.abspath("target.qcow2")
        subprocess.check_call(
            ["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "24G"])

        drives = (
            f" -drive file={disk},if=virtio,format=qcow2,werror=report"
            " -drive file=${answersImage},if=virtio,format=raw,readonly=on")

        installer = create_machine(
            "${installerCommand}" + efi + net + drives, name="installer")
        vms.append(installer)
        installer.start()

        installer.wait_for_console_text(r"login: nixos \(automatic login\)", timeout=900)
        print("the net image booted from its own bootloader")

        installer.send_key("alt-f2")
        time.sleep(8)
        installer.send_chars("\n")
        time.sleep(2)
        installer.send_chars("sudo mkdir -p /a\n")
        time.sleep(2)
        installer.send_chars("sudo mount -L NIXANSWERS /a\n")
        time.sleep(4)
        installer.send_chars("sudo sh /a/drive\n")

        def step(tag, timeout, note=None):
            installer.wait_for_console_text(rf"{tag}-0-X", timeout=timeout)
            if note:
                print(note)

        step("STOPPED", 300)
        step("MARKER", 120, "the image identifies itself as the NET image")
        step("LEASED", 300, "dnsmasq leased it an address")
        step("PROBE", 120, "the stub answers the probe network_ready runs")
        step("NOTBAKED", 120, "the desktop is not on the image -- it will have to be fetched")
        step("INSTALLED", 3600, "the install completed")

        # Preflight executed, read off the wire: only preflight_build asks
        # nixarchy.cachix.org for /nix-cache-info (network_ready asks only
        # cache.nixos.org), so this log line is #302's code running on the
        # shipped image -- the thing no offline gate run could show.
        cache.succeed("grep -q 'nixarchy.cachix.org GET /nix-cache-info' /var/log/nginx/probes.log")
        print("preflight_build executed: its probe of nixarchy.cachix.org is in the stub's log")

        # Fetched, wire side: the cache served real cache traffic, not just
        # probes. nix-serve answers .narinfo lookups and nar downloads;
        # either appearing means substitution happened from this node.
        cache.succeed("journalctl -u harmonia --no-pager | grep -qE 'narinfo|nar'")
        print("the closure came over the wire from the local substituter")

        step("FLAKE", 120)
        step("ESP", 120, "it wrote a flake and an ESP")
        step("FETCHED", 120, "and the install log names the substituter it fetched from")
        step("FALLBACK", 120)

        installer.send_chars("sudo poweroff\n")
        installer.wait_for_console_text(r"[Pp]ower(ing)? off|System is powering down|reboot: Power down",
                                        timeout=300)
        time.sleep(5)
        try:
            installer.send_monitor_command("quit")
        except Exception:
            pass
        time.sleep(3)

        target = create_machine(
            "${targetCommand}"
            + efi
            + f" -drive file={disk},if=virtio,format=qcow2,werror=report",
            name="target")
        vms.append(target)
        target.start()

        # The sd-boot menu, on OVMF's serial console: the bootloader the
        # installer wrote, running from the ESP it wrote, on the disk it
        # filled by FETCHING. No multi-user wait here, deliberately: that
        # needs a serial console in the installed system, which
        # tests/install-iso.nix obtains by rebuilding the flake in the guest
        # -- a step that cost this test two iterations to two different
        # substituter-flake failures while proving nothing about the net
        # path. The full boot-to-login story is the offline test's; this
        # test's claims all live upstream of it.
        # The FIRMWARE's own line, not sd-boot's menu. The menu is drawn with
        # escape-sequence redraws and no trailing newline, and
        # wait_for_console_text works in lines -- v6 of this test timed out
        # while "Reboot Into Firmware Interface" sat unflushed on the screen,
        # the same buffering trap install-iso's comments record for login
        # prompts. BdsDxe prints a real line, and a sharper one: the NVRAM
        # entry the installer created, loading systemd-boot from the GPT ESP
        # it wrote.
        target.wait_for_console_text(r'starting Boot.*"Linux Boot Manager"', timeout=300)
        print("the bootloader the installer wrote boots, from the disk the fetch filled")
    finally:
        reap()
  '';
}
