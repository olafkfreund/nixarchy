# What every microvm template imports, and the whole reason a template can be
# as small as modules/microvm/templates/shell.nix. #221's argument for
# microvm.nix over a hand-rolled runner was "it carries the guest module that
# has already absorbed the boot-time trimming" -- this file is the nixarchy
# half of that: the four things every disposable guest needs that upstream's
# module does not decide for you, plus the one thing that makes "one closure,
# many VMs" true.
#
# NOT imported by nixosModules.nixarchy, and never will be: this is guest-side
# configuration for a NixOS system that boots INSIDE a microvm, not a module
# for the host that runs one. flake.nix's `lib.mkMicrovm` is what wires it
# into a `nixosSystem`, alongside `inputs.microvm.nixosModules.microvm`.
{ lib, pkgs, ... }:
{
  microvm = {
    # The whole argument from #221 in one field. A share with
    # `source = "/nix/store"` is what sets `microvm.storeOnDisk = false`
    # (nixos-modules/microvm/options.nix computes that default by scanning
    # `microvm.shares` for exactly this source) -- so no erofs or squashfs is
    # ever built for this guest, and the closure served is store paths the
    # host already had. `checks.microvm-template` (#224) is where that stays
    # asserted rather than trusted; nothing here can enforce it on its own.
    #
    # `mountPoint = "/nix/.ro-store"` is not a free choice -- it is where
    # microvm.nix's own boot-time code looks for the read-only store when
    # `storeOnDisk = false`, matching upstream's flake-template exactly.
    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "9p";
      }

      # The second half of "the name is a directory, never a Nix argument".
      # `source = "."` is a RELATIVE path, and microvm.nix's qemu runner
      # writes it into the `-fsdev local,...,path=${source}` argument
      # verbatim (lib/runners/qemu.nix in the pinned commit) -- no
      # resolution against the flake, only against whatever directory the
      # runner is `exec`'d from. That directory IS the VM: one runner per
      # template, and `~/.local/state/nixarchy/microvm/<name>/` is what makes
      # a given VM the one with that name, entirely outside the closure.
      #
      # Read-write, unlike ro-store: a template that wants to persist
      # anything (the `persistent` template, #225) writes into /mnt/host
      # rather than needing its own share.
      {
        tag = "hostdir";
        source = ".";
        mountPoint = "/mnt/host";
        proto = "9p";
      }
    ];

    # SLiRP user networking: outbound works, nothing reaches in, and none of
    # it touches the host -- no bridge, no tap device, no
    # `microvm.host.enable` wanted or needed for a machine that only ever
    # runs `nix build --out-link` for itself. The declarative half of the
    # epic (#223) is what earns a tap interface, for a machine with a port
    # worth forwarding permanently.
    interfaces = [
      {
        type = "user";
        id = "vmnet";
        mac = "02:00:00:00:00:01";
      }
    ];
  };

  # Serial autologin. microvm.nix's qemu runner attaches ttyS0 to the
  # terminal that started it by default (`qemu.serialConsole = true`,
  # lib/runners/qemu.nix), which is #221's "the console is the door, not
  # SSH" -- and NixOS's own getty module reuses the same `agetty --autologin`
  # arguments for `serial-getty@` as it does for a virtual console, so this
  # one option is the whole guest-side half of that decision.
  services.getty.autologinUser = "dev";

  users.users.dev = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # No password at all -- not merely a blank one accepted at a prompt.
    # There is no other way into this guest (no SSH, no host network
    # surgery), so a password gains nothing and a blank one is a NixOS
    # activation warning for every template that would otherwise carry it.
    hashedPassword = "";
  };
  security.sudo.wheelNeedsPassword = false;

  # The name is never a Nix argument (#221), so it cannot be
  # `networking.hostName` -- that option is baked into the closure at build
  # time, and one closure serves every VM of a template. Instead the runner's
  # own working directory -- already shared at /mnt/host above -- carries a
  # plain-text `hostname` file the caller drops there before launch, and this
  # unit is what turns it into the running hostname.
  #
  # A oneshot rather than an activation script: activation runs once, at the
  # toplevel this guest shares with every other VM of its template, and by
  # definition cannot see a per-VM file. This runs at boot, inside the VM
  # that actually has the share mounted.
  systemd.services.nixarchy-hostname-from-host = {
    description = "Set this guest's hostname from the host directory share";
    wantedBy = [ "multi-user.target" ];
    # The 9p mount is a systemd generated .mount unit keyed off mountPoint;
    # naming the path it serves is what lets this both wait for it and
    # order after it, without hard-coding microvm.nix's tag-to-unit-name
    # scheme.
    unitConfig.RequiresMountsFor = [ "/mnt/host" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # No file, no rename -- a template launched without a hostname file
      # (nothing in #222 writes one yet; #223's runner does) keeps whatever
      # networking.hostName the template built with, rather than failing to
      # start.
      if [ -r /mnt/host/hostname ]; then
        ${pkgs.nettools}/bin/hostname -F /mnt/host/hostname
      fi
    '';
  };

  # A third of the closure (#221's own measurement, via nix-tree, on this
  # guest before this line existed), for a machine with no display manager
  # and nobody at a `man` prompt. microvm.nix's own `microvm.optimize.enable`
  # already defaults `documentation.enable` to `false` at `mkDefault`
  # priority -- this restates it at plain priority so the saving holds even
  # if a template ever turns optimize off for something it needs from it.
  documentation.enable = false;

  system.stateVersion = lib.trivial.release;
}
