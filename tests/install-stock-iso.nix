{ inputs, pkgs }:
# Exercise the path a stock NixOS minimal ISO takes: its own UEFI GRUB, an
# installer copied from a cache, and preflight against the caches it will use.
# The stock image is deliberately fetched by hash, not assembled from this
# flake. See data/stock-iso.nix and plan/2026-11-08-1646-stock-iso-check.md.
let
  iso = pkgs.fetchurl (import ../data/stock-iso.nix);
  ca = ./fixtures/iso-net-stub-cert;
  install = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install;
  referenceConfigs = map (c: c.config) [
    inputs.self.nixosConfigurations.reference
    inputs.self.nixosConfigurations.reference-unencrypted
  ];
  reference = inputs.self.nixosConfigurations.reference-unencrypted.config.system.build.toplevel;
  inputSources = inputs.self.lib.inputSources { flake = inputs.self; };
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";

  # The toplevel closure alone does not contain build tools for the few
  # machine-specific assembly derivations; install-iso-net found this out by
  # trying to build disko in the guest. Keep those roots here as well.
  binaryCache = pkgs.mkBinaryCache {
    name = "stock-iso-test-cache";
    rootPaths =
      inputSources
      ++ [ install ]
      ++ map (c: c.system.build.toplevel) referenceConfigs
      ++ map (c: c.system.build.diskoScript) referenceConfigs
      ++ map (c: c.system.build.toplevel.inputDerivation) referenceConfigs
      ++ map (c: c.system.build.initialRamdisk.inputDerivation) referenceConfigs
      ++ map (c: c.system.build.etc.inputDerivation) referenceConfigs
      ++ map (c: c.system.modulesTree) referenceConfigs
      ++ [
        pkgs.kmod
        pkgs.kmod.dev
        pkgs.libcap
        pkgs.nukeReferences
        pkgs.libxslt.bin
        pkgs.lndir
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
  };

  # The driver types only this launch command on the ISO's graphical console.
  # All later steps, including the installer exit status, are reported on
  # ttyS0. This works even when the upstream default GRUB entry does not put
  # console=ttyS0 on the kernel command line.
  drive = pkgs.writeText "stock-iso-drive" ''
    #!/usr/bin/env bash
    step() {
      tag=$1
      shift
      "$@" > /tmp/stock-step.out 2>&1
      rc=$?
      cat /tmp/stock-step.out > /dev/ttyS0
      echo "$tag-$rc-X" > /dev/ttyS0
      if [ "$rc" -ne 0 ]; then
        if [ -f /var/log/nixarchy-install.log ]; then
          tail -80 /var/log/nixarchy-install.log > /dev/ttyS0
        fi
        exit 1
      fi
    }

    echo READY-0-X > /dev/ttyS0
    read -r go < /dev/ttyS0
    step HANDSHAKE test "$go" = GO
    step UEFI test -d /sys/firmware/efi
    step SHARE test -r /mnt/share/install-path

    # DNS is supplied by the server's DHCP; these names are also pinned here
    # so the cache probes cannot silently escape the two-machine test network.
    # NixOS may make /etc/hosts a link into the read-only store.
    cp -L /etc/hosts /tmp/stock-hosts
    printf '%s\n' '192.168.1.1 cache.nixos.org nixarchy.cachix.org hyprland.cachix.org' >> /tmp/stock-hosts
    rm /etc/hosts
    cp /tmp/stock-hosts /etc/hosts
    SSL_CERT_FILE=/mnt/share/ca.pem
    NIX_SSL_CERT_FILE=/mnt/share/ca.pem
    NIX_CONFIG='require-sigs = false
    ssl-cert-file = /mnt/share/ca.pem'
    export SSL_CERT_FILE NIX_SSL_CERT_FILE NIX_CONFIG

    # The flag a user types on a stock ISO (docs/manual/the-iso.md); not NIX_CONFIG,
    # which would also cover a nix call inside the installer that lacks its own.
    step CACHE nix --extra-experimental-features 'nix-command flakes' copy --from https://nixarchy.cachix.org --no-check-sigs "$(cat /mnt/share/install-path)"
    started=$(date +%s)
    (while [ ! -s /var/log/nixarchy-install.log ]; do sleep 1; done
     first=$(date +%s)
     echo "FIRSTLOG-$((first - started))-X" > /dev/ttyS0) &
    (peak=0
     while :; do
       used=$(df --output=used -B1 /nix/store | tail -1)
       if [ "$used" -gt "$peak" ]; then peak=$used; fi
       printf '%s\n' "$peak" > /tmp/stock-peak
       sleep 1
     done) &
    monitor=$!
    # The installer writes progress to its own log. Forward it so a stall has
    # a visible phase, while the exit marker comes from the command itself.
    (tail -F /var/log/nixarchy-install.log > /dev/ttyS0 2>/dev/null &)
    step INSTALLED "$(cat /mnt/share/install-path)"/bin/nixarchy-install --answers /mnt/share/answers
    kill "$monitor"
    echo "PEAK-$(cat /tmp/stock-peak)-X" > /dev/ttyS0
    step HOST test -d /mnt/etc/nixos/hosts/stocktest
    step NIXARCHY grep -Fxq stocktest /mnt/etc/nixarchy/hostname
  '';

  share = pkgs.runCommand "stock-iso-test-share" { } ''
    mkdir -p "$out"
    cp ${ca}/cert.pem "$out/ca.pem"
    cp ${drive} "$out/drive"
    printf '%s\n' '${install}' > "$out/install-path"
    cat > "$out/answers" <<'EOF'
    device=/dev/vda
    encrypt=no
    hostname=stocktest
    username=omarchy
    password_hash=${passwordHash}
    timezone=UTC
    keymap=us
    EOF
  '';

  qemuCommon = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };
  stockCommand = pkgs.lib.concatStringsSep " " [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-cpu max -m 8192 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
    "-device virtio-scsi-pci,id=scsi0"
    "-drive id=cd0,if=none,media=cdrom,readonly=on,format=raw,file=${iso}"
    "-device scsi-cd,bus=scsi0.0,drive=cd0,bootindex=0"
    "-virtfs local,path=${share},mount_tag=stockshare,security_model=none,readonly=on"
  ];
  referenceHash = builtins.substring 0 32 (builtins.baseNameOf reference);
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-install-stock-iso";
  globalTimeout = 4 * 60 * 60;
  enableOCR = true;

  nodes.server = { pkgs, ... }: {
    virtualisation.vlans = [ 1 ];
    networking.firewall.enable = false;
    environment.systemPackages = [ pkgs.curl ];
    services.dnsmasq = {
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
    services.nginx = {
      enable = true;
      appendHttpConfig = ''
        log_format stock_cache '$host $request $body_bytes_sent';
        access_log /var/log/nginx/stock-cache.log stock_cache;
      '';
      virtualHosts = {
        "cache.nixos.org" = {
          onlySSL = true;
          sslCertificate = "${ca}/cert.pem";
          sslCertificateKey = "${ca}/key.pem";
          locations."/nix-cache-info".return = "200 'StoreDir: /nix/store\\n'";
          locations."/".return = "404";
        };
        "nixarchy.cachix.org" = {
          serverAliases = [ "hyprland.cachix.org" ];
          onlySSL = true;
          sslCertificate = "${ca}/cert.pem";
          sslCertificateKey = "${ca}/key.pem";
          locations."/".root = "${binaryCache}";
        };
      };
    };
  };

  testScript = builtins.readFile ./vm-cleanup.py + ''
    import shutil
    import subprocess

    server.start()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("dnsmasq.service")
    server.wait_for_unit("nginx.service")
    # This is a client request over TLS, not merely a service-active check.
    server.succeed("curl --cacert ${ca}/cert.pem --resolve cache.nixos.org:443:127.0.0.1 -sfI https://cache.nixos.org/nix-cache-info")
    server.fail("curl --cacert ${ca}/cert.pem --resolve cache.nixos.org:443:127.0.0.1 -sf https://cache.nixos.org/${referenceHash}.narinfo")
    server.succeed("curl --cacert ${ca}/cert.pem --resolve nixarchy.cachix.org:443:127.0.0.1 -sfI https://nixarchy.cachix.org/${referenceHash}.narinfo")

    efi_vars = os.path.abspath("stock-efi-vars.fd")
    shutil.copyfile("${pkgs.OVMF.variables}", efi_vars)
    os.chmod(efi_vars, 0o644)
    disk = os.path.abspath("stock-target.qcow2")
    subprocess.check_call(["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "32G"])
    net = (" -netdev vde,id=n1,sock=" + os.path.abspath("vde1.ctl")
           + " -device virtio-net-pci,netdev=n1")
    drives = (" -drive if=pflash,format=raw,unit=1,readonly=off,file=" + efi_vars
              + f" -drive file={disk},if=none,id=target,format=qcow2,werror=report"
              + " -device virtio-blk-pci,drive=target,serial=stock-iso-target")
    vms = []
    started = time.monotonic()
    try:
        stock = create_machine("exec ${stockCommand}" + net + drives, name="stock")
        vms.append(stock)
        stock.start()
        # The default GRUB entry has no serial-console parameter. Its NixOS
        # auto-login appears on the display, then the share script reports on
        # ttyS0; this keeps the ISO and its boot parameters untouched.
        stock.wait_for_text(r"nixos@nixos|nixos.*login", timeout=900)
        print(f"stock ISO reached login in {time.monotonic() - started:.1f}s")
        stock.send_chars("sudo mkdir -p /mnt/share\n")
        time.sleep(2)
        stock.send_chars("sudo mount -t 9p -o trans=virtio stockshare /mnt/share\n")
        time.sleep(4)
        stock.send_chars("sudo bash /mnt/share/drive\n")
        # Wait for the step's marker with any exit code, then read the code: waiting
        # for -0- alone turns a failing step into a bare timeout (tests/AGENTS.md).
        def step_ok(tag, timeout):
            stock.wait_for_console_text(rf"{tag}-[0-9]+-X", timeout=timeout)
            rc = re.findall(rf"{tag}-([0-9]+)-X", stock.get_console_log())[-1]
            assert rc == "0", f"stock ISO step {tag} exited {rc}"

        step_ok("READY", 300)
        stock.send_console("GO\n")
        for tag, timeout in [("HANDSHAKE", 60), ("UEFI", 60), ("SHARE", 60),
                             ("CACHE", 900)]:
            step_ok(tag, timeout)
        stock.wait_for_console_text(r"FIRSTLOG-[0-9]+-X", timeout=900)
        step_ok("INSTALLED", 7200)
        stock.wait_for_console_text(r"PEAK-[0-9]+-X", timeout=60)
        for tag in ("HOST", "NIXARCHY"):
            step_ok(tag, 60)
        first = re.search(r"FIRSTLOG-([0-9]+)-X", stock.get_console_log())
        peak = re.search(r"PEAK-([0-9]+)-X", stock.get_console_log())
        assert first and peak, "the ISO did not report the install timing and overlay peak"
        print(f"time to first installer log line: {first.group(1)}s")
        served = server.succeed("awk '{sum += $NF} END {print sum+0}' /var/log/nginx/stock-cache.log").strip()
        print(f"cache bytes served: {served}; peak live-store overlay used: {peak.group(1)} bytes")
    finally:
        reap_owned_vms(vms)
  '';
}
