---
title: Security
---

# Security

Upstream's [security page](https://omarchy.org/manual/security/) lists five
things Omarchy does for you. Here is how each of them lands on NixOS.

| Upstream | nixarchy |
|---|---|
| Full-disk encryption, mandatory | Chosen when you install NixOS. LUKS is a checkbox in the installer; nixarchy has no installer and cannot add it afterwards. |
| ufw, closed except 53317 | `networking.firewall`, closed except 53317. Same policy, different tool. |
| Arch rolling updates | `nix flake update` moves nixpkgs; security fixes arrive with the next `omarchy update`. |
| Omarchy's own package mirror | Everything comes from nixpkgs and this flake. There is no Omarchy repo and no AUR. |
| Cloudflare in front of the ISOs | There are no ISOs. Builds are served by the nixarchy binary cache and cache.nixos.org. |

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

Docker is enabled by default (`virtualisation.docker.enable = mkDefault true`)
but upstream's `ufw-docker` lockdown is not ported, because it is a ufw script.
A container published with `-p` is reachable through the firewall the way
Docker's own iptables rules make it. If that matters to you, bind published
ports to `127.0.0.1`.

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

Unchanged. `omarchy-sudo-passwordless` writes
`/etc/sudoers.d/99-omarchy-nopasswd-$USER` and a systemd timer removes it
after 15 minutes; pass a number of minutes to change that. NixOS manages
`/etc/sudoers` but leaves `sudoers.d` alone, so this works as upstream
describes. Upstream's warning applies in full: while it is on, anything
running as your user is root.

## Changing your passwords

Your login password is `passwd`, or *Update > Password > User* in the menu.
The drive passphrase, if you encrypted, is `cryptsetup luksChangeKey` on the
LUKS device; NixOS does not manage that for you either.

If you declared `users.users.you.hashedPassword` or `initialPassword` in your
flake, that value is reapplied at every rebuild unless
`users.mutableUsers` is `true` (the default). Check before wondering why a
password change did not stick.

## Passing on a machine, and signing keys

*Setup > Reset Computer* restores the baseline snapshot the Omarchy ISO takes,
so it needs an ISO install and does not work here. Hand a machine over by
reinstalling NixOS, or by deleting the user and their home from your flake and
rebuilding. Upstream's ISO and package signing key does not apply; nixarchy
has no packages to sign, and the flake lock pins the source by hash.
