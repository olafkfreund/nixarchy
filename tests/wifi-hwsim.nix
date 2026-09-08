{ pkgs }:
# The ISO's wireless configuration, against a radio.
#
# The hole this fills, said plainly: no VM in this repo has ever had a
# wireless card. checks.install-iso boots -nic none, and every other install
# test uses a virtio NIC. So the whole Wi-Fi path -- NetworkManager, its
# supplicant, association -- had NO coverage of any kind, and that is exactly
# where the bug lived.
#
# installer/cd.nix forced networking.wireless.enable = false, believing the
# installation media's wpa_supplicant conflicted with NetworkManager. It does
# not: NetworkManager DRIVES wpa_supplicant, and its own module says so and
# sets it up (networkmanager.nix:694-698). The mkForce overrode that, so NM
# was configured for a backend it could not start, and on a ThinkPad T15 with
# a bound iwlwifi and an unblocked radio it retried every thirteen seconds,
# forever:
#
#   device (wlp0s20f3): Couldn't initialize supplicant interface:
#     Failed to D-Bus activate wpa_supplicant service
#
# The net image cannot install without a network, so for anyone without a
# cable it did not work at all.
#
# tests/iso-wifi.nix asserts the ISO's settings are the right ones. This
# asserts the settings actually WORK -- a configuration check cannot tell you
# that wpa_supplicant starts, that NM finds it, or that an interface
# associates, and all three failed here at once.
#
# mac80211_hwsim is the kernel's virtual radio (CONFIG_MAC80211_HWSIM=m in
# nixpkgs' kernel, verified). It creates two real wiphys the real cfg80211
# stack drives, so wpa_supplicant and hostapd are the genuine articles talking
# over a simulated medium. This is how the kernel and NetworkManager projects
# test wireless.
pkgs.testers.runNixOSTest {
  name = "nixarchy-wifi-hwsim";

  nodes.machine =
    { lib, ... }:
    {
      # Two radios from one module load: wlan0 for the client, wlan1 for the
      # access point. They see each other over hwsim's simulated medium.
      boot.kernelModules = [ "mac80211_hwsim" ];

      # EXACTLY what installer/cd.nix says, and nothing more. Not a copy of
      # the ISO -- a copy of the one line whose absence was the bug.
      networking = {
        networkmanager.enable = true;

        # qemu-vm.nix:1504 does `networking.wireless.enable = mkVMOverride false`,
        # so EVERY NixOS VM test force-disables wireless. Without this override
        # the node reproduces the exact production symptom
        #
        #   device (wlan0): Couldn't initialize supplicant interface:
        #     Failed to D-Bus activate wpa_supplicant service
        #
        # for a completely different reason, and that is not hypothetical: the
        # first version of this file did, and the identical message was read as
        # evidence that the production fix did not work. It was the test that did
        # not work. nixpkgs' own nixos/tests/wpa_supplicant.nix carries the same
        # line with the same explanation.
        #
        # mkOverride 0 rather than mkForce: mkVMOverride is priority 10, and
        # mkForce is 50 -- it loses.
        wireless.enable = lib.mkOverride 0 true;

        # NM manages wlan0. wlan1 belongs to hostapd, and without this NM takes
        # it too and fights the AP for the interface.
        networkmanager.unmanaged = [ "interface-name:wlan1" ];
      };

      # The regulatory database, or the radio comes up restricted and the
      # channel below may not be allowed.
      hardware.wirelessRegulatoryDatabase = true;

      services.hostapd = {
        enable = true;
        radios.wlan1 = {
          band = "2g";
          channel = 1;
          networks.wlan1 = {
            ssid = "nixarchy-test";
            authentication.saePasswords = [ { password = "supersecret"; } ];
            authentication.wpaPassword = "supersecret";
          };
        };
      };

      environment.systemPackages = [
        pkgs.iw
        # wpa_cli, to ask the supplicant directly rather than through NM.
        pkgs.wpa_supplicant
      ];
      # Small, and the default is not: this test only needs to associate.
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # The radios exist at all. If hwsim did not load there is nothing to test
    # and every assertion below would fail for the wrong reason.
    machine.succeed("iw dev | grep -q wlan0")
    machine.succeed("iw dev | grep -q wlan1")

    machine.wait_for_unit("NetworkManager.service")

    # wpa_supplicant is D-BUS ACTIVATED, not started at boot: dbusControlled
    # means NetworkManager brings it up when it first has a wireless device to
    # manage. A first draft of this waited for the unit straight after
    # multi-user.target and failed with "inactive and there are no pending
    # jobs" -- testing the right unit at the wrong moment, on a machine where
    # nothing had asked for it yet.
    #
    # Waiting for NM to see the device and THEN for the unit is not a
    # workaround; it is the exact sequence that broke. The tester's NM saw
    # wlp0s20f3, asked for the supplicant, and got nothing.
    machine.wait_until_succeeds("nmcli -t -f DEVICE,TYPE device | grep -q '^wlan0:wifi'", timeout=60)
    print(machine.execute("systemctl status wpa_supplicant.service")[1])
    print(machine.execute("journalctl -u wpa_supplicant --no-pager")[1])
    print(machine.execute("ls -l /run/current-system/sw/share/dbus-1/system-services/ 2>&1 | head -30")[1])
    print(machine.execute("cat /etc/dbus-1/system.d/wpa_supplicant.conf 2>&1 | head -5")[1])
    machine.wait_until_succeeds("systemctl is-active wpa_supplicant.service", timeout=30)

    # And that the activation never failed on the way. The tester's journal
    # filled with this line every thirteen seconds; its absence is the fix,
    # and the negative is worth asserting because everything else can look
    # healthy while it repeats.
    machine.fail("journalctl -u NetworkManager | grep -q 'Failed to D-Bus activate wpa_supplicant'")

    machine.wait_for_unit("hostapd.service")

    # Association, over the simulated medium, with the real supplicant. The
    # end of the path the ISO needs and could not walk.
    machine.wait_until_succeeds("nmcli device wifi list --rescan yes | grep -q nixarchy-test", timeout=60)

    # link-local, not DHCP. `nmcli device wifi connect` waits for a full IP
    # configuration and there is no DHCP server behind this AP, so the first
    # version of this associated perfectly -- hostapd logged
    # AP-STA-CONNECTED and EAPOL-4WAY-HS-COMPLETED -- and then failed with
    # exit 4 forty-six seconds later when addressing timed out, disconnecting
    # on the way out. That would have read as "wireless is broken" while the
    # wireless was the half that worked.
    #
    # Adding a DHCP server would test dnsmasq. What is under test is whether
    # the ISO's supplicant configuration can carry an association, so the IP
    # layer is taken out of the question rather than simulated.
    machine.succeed(
        "nmcli connection add type wifi ifname wlan0 con-name test "
        "ssid nixarchy-test "
        "wifi-sec.key-mgmt wpa-psk wifi-sec.psk supersecret "
        "ipv4.method link-local ipv6.method ignore"
    )
    machine.succeed("nmcli connection up test")

    # Asserted from BOTH ends of the link, and not with wpa_cli: dbusControlled
    # runs the supplicant with -u and no control socket, so wpa_cli only ever
    # answers "Failed to connect to non-global ctrl_ifname" -- it is the wrong
    # instrument for the configuration under test, which is the point of the
    # configuration.
    #
    # NetworkManager's own view of the device.
    machine.wait_until_succeeds(
        "nmcli -t -f DEVICE,STATE device | grep -q '^wlan0:connected'", timeout=60)

    # And the access point's, which is independent of everything on the client
    # side: hostapd only logs this after the four-way handshake completes, so
    # it cannot be satisfied by a client that merely thinks it is connected.
    machine.succeed("journalctl -u hostapd | grep -q AP-STA-CONNECTED")
    machine.succeed("journalctl -u hostapd | grep -q EAPOL-4WAY-HS-COMPLETED")

    print(machine.succeed("nmcli device status"))

    print(machine.succeed("nmcli device status"))
  '';
}
