{
  inputs,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  # A VM that installs nixarchy onto a blank disk, with a network.
  #
  # This is not checks.install and cannot be. That check is a Nix derivation,
  # so it builds in a sandbox with no network -- deliberately, and load-
  # bearingly: Invariant 1 says a rebuild straight after install must build
  # nothing, and with a substituter reachable a rebuild that should have failed
  # would quietly download instead and the assertion would pass while the
  # invariant was broken.
  #
  # This is a runnable script rather than a derivation, the same way
  # `nix run .#vm` is, so qemu gets user-mode networking for free. That makes
  # it the place to answer the question the hermetic check cannot ask: what
  # does an install actually need to build, and therefore what must be seeded
  # into the check's store.
  #
  # Watch it happen, in a window:
  #
  #   nix run .#installer-vm
  #
  # Capture it instead, with no display -- for a script, or over ssh:
  #
  #   QEMU_OPTS="-display none -serial mon:stdio" nix run .#installer-vm
  #
  # Both work at once: the install streams live to the graphical console AND
  # is written to a file that is dumped to the serial line at the end. Neither
  # audience is served by making the other read a 4 GB scrollback afterwards.
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  environment.systemPackages = [
    inputs.self.packages.${pkgs.system}.install
    pkgs.git
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # The same caches the installer passes to nixos-install, so a run here is
    # not an hour of compiling Hyprland.
    substituters = [
      "https://cache.nixos.org"
      "https://nixarchy.cachix.org"
      "https://hyprland.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
    ];
  };

  # The answers a person would have typed. password_hash rather than password so
  # the installed system is deterministic between runs -- a fresh salt would
  # change the toplevel every time and make "did anything need building?"
  # impossible to answer twice the same way.
  #
  # The hash is "omarchy". This VM is a disposable test harness reachable only
  # from the host that started it.
  #
  # /dev/vda, not /dev/vdb as in checks.install: this VM has an ephemeral tmpfs
  # root and therefore no root drive at all, so the empty disk is the first
  # virtio device rather than the second. The check's nodes have a real root
  # disk, which shifts theirs along by one.
  environment.etc."nixarchy/answers".text = ''
    device=/dev/vda
    encrypt=no
    hostname=installed
    username=omarchy
    password_hash=$6$rounds=100000$nixarchyvmsalt$Yd0hZ7WCrJt7VJnRhrY4jSjqCXqPWKzKQZWlZBHNbXCLLNlvBQTQpVQpBNXVAqEDDCyLnNlqOWx5Y6ivvNaJ11
    timezone=UTC
    keymap=us
  '';

  # Autologin root on tty1 and run the install from the login shell.
  #
  # Three attempts went the other way -- a systemd service writing to /dev/tty1
  # while something else owned it -- and all three produced a login prompt with
  # the install invisible behind it. Disabling `getty@tty1` did nothing (logind
  # spawns it under another name); NAutoVTs=0 did nothing either.
  #
  # The terminal you are watching should BE the installer's terminal. That is
  # what a live ISO does, and it is what upstream Omarchy does: archiso
  # autologins root and runs the wizard from the shell profile.
  services.getty.autologinUser = "root";

  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ] && [ ! -e /tmp/nixarchy-install-done ]; then
      touch /tmp/nixarchy-install-done
      log=/tmp/nixarchy-install.log
      echo
      echo "[nixarchy] installing onto /dev/vda"
      echo
      # PIPESTATUS, not the pipeline's status. `cmd | tee` reports tee's exit
      # code, which is 0 whatever cmd did -- so a plain `if` here printed
      # INSTALL OK over a 404 and a failed install. A harness that reports
      # success on failure is worse than no harness.
      nixarchy-install --answers /etc/nixarchy/answers 2>&1 | tee "$log"
      rc=''${PIPESTATUS[0]}
      if [ "$rc" -eq 0 ]; then
        echo "[nixarchy] INSTALL OK"
      else
        echo "[nixarchy] INSTALL FAILED (exit $rc)"
      fi

      # The same log on the serial line, for a headless run to capture.
      {
        echo "=============== nixarchy install log ==============="
        cat "$log"
        echo "=============== end ==============================="
      } >/dev/ttyS0 2>&1

      echo
      echo "[nixarchy] done. Powering off in 120s -- Ctrl+C to keep the shell."
      sleep 120
      systemctl poweroff
    fi
  '';

  # The installer refuses to run where /sys/firmware/efi does not exist, and is
  # right to: the layout is an ESP with systemd-boot and there is no BIOS path.
  virtualisation = {
    memorySize = 8192;
    cores = 4;
    useEFIBoot = true;
    # The blank target. With no root drive it appears as /dev/vda.
    emptyDiskImages = [ 20480 ];
    # nixos-install copies a whole desktop closure into the target, and this
    # VM's own store has to hold it first.
    diskSize = 32768;
    # Ephemeral, so every run starts from an unpartitioned disk. That is the
    # state a real install begins in and the only one worth testing from.
    diskImage = null;
  };

  # Stop logind spawning a getty on tty1 at all. tty1 is the qemu window and
  # the install writes there; a login prompt redrawing over it is exactly why
  # a watcher saw "nixos login:" and nothing else.
  services.logind.settings.Login = {
    NAutoVTs = 0;
    ReserveVT = 0;
  };

  users.users.root.password = "nixarchy"; # VM-only.
  boot = {
    kernelParams = [ "console=ttyS0" ];
    loader.grub.enable = lib.mkForce false;
  };

  networking.firewall.enable = false;
  system.stateVersion = "25.05";
}
