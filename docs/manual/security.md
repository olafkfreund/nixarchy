---
title: Security
---

# Security

Upstream's [security page](https://omarchy.org/manual/security/) lists five
things Omarchy does for you. Here is how each of them lands on NixOS.

| Upstream | nixarchy |
|---|---|
| Full-disk encryption, mandatory | The nixarchy installer encrypts by default — LUKS2 on btrfs, and you opt out with Ctrl+C rather than in. Installing the flake onto NixOS you already run cannot add it afterwards; that is a decision made when the disk was partitioned. |
| ufw, closed except 53317 | `networking.firewall`, closed except 53317. Same policy, different tool. |
| Arch rolling updates | `nix flake update` moves nixpkgs; security fixes arrive with the next `omarchy update`. |
| Omarchy's own package mirror | Everything comes from nixpkgs and this flake. There is no Omarchy repo and no AUR. |
| Cloudflare in front of the ISOs | The ISO is built from source with `nix build .#iso`, not downloaded — there is nothing in front of it because there is nothing hosted. Packages come from the nixarchy binary cache and cache.nixos.org, both signed. |

## The firewall

There is no `ufw` on NixOS. nixarchy sets

```nix
networking.firewall.enable = lib.mkDefault true;
networking.firewall.allowedTCPPorts = [ 53317 ];
networking.firewall.allowedUDPPorts = [ 53317 ];
```

which is a port of upstream's `install/config/firewall.sh` (`ufw default deny
incoming`, then `ufw allow 53317` on both protocols for
[LocalSend](https://localsend.org/)). Discovery over mDNS was never the
missing part; `services.avahi` already opens 5353. Only the transfer port was.

The `enable` is `mkDefault`, so a configuration that turns the firewall off
wins. The port lists are not, deliberately: list options merge, so a port you
open is added to LocalSend's rather than replacing it.

To open a port, add it in your flake and rebuild:

```nix
networking.firewall.allowedTCPPorts = [ 8080 ];
```

`sudo ufw allow 8080` does not exist here, and a port opened by hand with
`iptables` or `nft` is gone on the next rebuild, which is the point.

Nixarchy defaults to `virtualisation.docker.enable = false` and
`virtualisation.docker.rootless.enable = true`: Docker runs as a rootless user
daemon. Upstream's `ufw-docker` lockdown is not ported because it is a ufw
script. Check the bind address and network reachability of each published
container service. See
[Docker, rootless](development-tools.md#docker-rootless) for the default and how
to opt into the root-owned daemon.

## SSH

*Setup > Security > SSHD* in the menu is upstream's script, and it cannot
finish here: its first step is `omarchy-pkg-add openssh`, which exits 1 by
design (see [the philosophy](philosophy.md)), and the script runs under
`set -e`. Declare it instead:

```nix
services.openssh.enable = true;
users.users.you.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... you@host" ];
```

`services.openssh.openFirewall` defaults to `true`, so port 22 opens with it.
Upstream rate-limits port 22 with `ufw limit`; nothing equivalent is set here,
so keep password authentication off (`settings.PasswordAuthentication =
false`) rather than relying on rate limiting.

## Remote desktop

gliff, the remote desktop, goes over SSH and opens no port of its own: your SSH
key is the authentication, so the SSH advice above is the whole story.
[Remote desktop](remote-desktop) is that page.

## Fingerprint and FIDO2

*Setup > Security > Fingerprint* and *FIDO2* do the enrolment they always did:
`fprintd-enroll` really enrols a print, and `pamu2fcfg` really writes a
credential to `/etc/fido2/fido2`. What they cannot do is edit `/etc/pam.d`,
because on NixOS PAM is built, not edited. So the last step prints the lines
to add and exits non-zero:

```nix
security.pam.u2f.enable = true;
security.pam.u2f.settings.authfile = "/etc/fido2/fido2";
security.pam.u2f.settings.cue = true;
security.pam.services.sudo.u2fAuth = true;
security.pam.services.polkit-1.u2fAuth = true;
```

or, for fingerprint, `services.fprintd.enable = true` plus
`security.pam.services.sudo.fprintAuth = true` and the same for `polkit-1`.
Rebuild, and the enrolled key or print is accepted.

## Passwordless sudo

Not a toggle here, on purpose. Upstream's `omarchy-sudo-passwordless`
(*Setup > Security > Passwordless Sudo*) writes
`/etc/sudoers.d/99-omarchy-nopasswd-$USER` and a timer removes it after 15
minutes. NixOS's `/etc/sudoers` has no `#includedir`, so that file would never
be read, and upstream would still print that it was enabled. nixarchy
replaces the command with one that says so, prints the options below, and
exits non-zero. In Omarchy's newer releases the row becomes a toggle that
writes sudoers and tmpfiles rules. nixarchy hides it on both channels, in the
menu and, on edge, the bar indicator, rather than offer passwordless root one
click away: sudo is configuration here, so the toggle could not work (#1280, #1385).

If you want it, declare it, for your user only:

```nix
security.sudo.extraRules = [{
  users = [ "you" ];
  commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
}];
```

or for the whole `wheel` group, `security.sudo.wheelNeedsPassword = false;`.
There is no timer: it stays until you remove it and rebuild. While it is on,
anything running as your user is root.

## Changing your passwords

Your login password is `passwd`, or *Update > Password > User* in the menu.
The drive passphrase, if you encrypted, is `cryptsetup luksChangeKey` on the
LUKS device; NixOS does not manage that for you either.

If you declared `users.users.you.hashedPassword` or `initialPassword` in your
flake, that value is reapplied at every rebuild unless
`users.mutableUsers` is `true` (the default). Check before wondering why a
password change did not stick.

With autologin, no password is typed at boot, so the keyring named *login*
stays locked. The first time you unlock the lock screen with your password,
that unlocks it too.

If an app (Chromium, for one) asked you to *create* a keyring before that
first unlock, the keyring it made is a separate one. It is not *login*, so it
stays locked at every boot, whatever its password and even if it is the
default: login unlocks only the keyring named *login*. To stop the prompt,
open Seahorse (*Passwords and Keys*) and delete that keyring. Deleting it
destroys everything stored in it. If Chromium made it, that includes the key
for its saved passwords and cookies, so you sign in to sites again. Seahorse
is not installed; `nix run nixpkgs#seahorse` opens it once.

After `passwd`, the keyring keeps your old password. The next prompt asks for
it once. Seahorse's *Change password* on the keyring brings it in line.

The keyring stays encrypted; upstream Omarchy uses an unencrypted default
keyring instead (#1492). To turn this off, set
`security.pam.services.omarchy-lock-password.enableGnomeKeyring = false`.

## Passing on a machine, and signing keys

*Setup > Reset Computer* restores the baseline snapshot the Omarchy ISO takes,
so it needs an ISO install and does not work here. Hand a machine over by
reinstalling NixOS, or by deleting the user and their home from your flake and
rebuilding. Upstream's ISO and package signing key does not apply; nixarchy
has no packages to sign, and the flake lock pins the source by hash.
