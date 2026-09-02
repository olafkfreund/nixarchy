---
title: Unattended installs
---

# Unattended installs

An image that boots, installs and reboots with nobody at the keyboard.

## The answers file

`nixarchy-install --answers <file>` takes every answer the wizard asks for.
One `key=value` per line, **parsed rather than sourced**, and every missing or
malformed key is named in one pass instead of one per attempt:

```ini
device=/dev/vda
encrypt=yes
luks_passphrase=correct horse
hostname=nixarchy
username=alice
password_hash=$6$...        # from `mkpasswd -m sha-512`; or
password=hunter2            # plaintext, hashed by the installer
timezone=Europe/London
keymap=us
```

It holds a password in clear. That is inherent to installing without being
asked, and nothing copies it onto the installed machine.

`<file>` may also be an **`https://` URL**, which is what makes it unattended
rather than merely unprompted — otherwise somebody had to put the file on the
machine first. Plain `http` is refused, because of that password. A URL that
cannot be fetched stops the install rather than falling back to asking: an
image that falls back to questions is an image waiting at a prompt nobody is
going to answer.

## Telling the image, without building an image

The ISO takes three parameters on the kernel command line:

```
nixarchy.answers=https://example.com/answers.txt
nixarchy.from=github:you/config
nixarchy.host=laptop
```

With none of them present it is an ordinary interactive install.

That is how qemu (`-append`), PXE and cloud metadata all inject parameters, so
a fleet of VMs is a netboot with three arguments and no bespoke image:

```
qemu-system-x86_64 -cdrom nixarchy-net.iso \
  -append "nixarchy.answers=https://example.com/answers.txt"
```

Combine them and the whole thing is one line: `--from` says which
configuration, `--answers` supplies the machine's secrets, and together they
are an enrolment with nothing typed. See
[many machines, one repo](many-machines).

**Scanning a labelled drive is deliberately absent.** Omarchy's ISO watches
for a second drive labelled `cidata`; nixarchy does not. The kernel command
line covers PXE and VM fleets, which is where unattended installs actually
happen, and the media path is worth adding when somebody with a physical fleet
asks for it rather than before.

## The other way, which is often the right one

Unattended provisioning is a NixOS problem with mature NixOS answers, and
nixarchy sits on top of whichever you pick:

- **[disko](https://github.com/nix-community/disko)** describes the disk
  layout declaratively. nixarchy's installer already uses it — the same
  `disk-config.nix` your machine imports is what formatted the disk.
- **[nixos-anywhere](https://github.com/nix-community/nixos-anywhere)**
  installs a flake configuration onto a remote machine over SSH, using disko
  for the disks. Point it at anything booted into Linux with SSH and it comes
  back as the system your flake describes — no ISO, no boot medium, nothing to
  write to a stick.

Add nixarchy as an input to that flake and the machine arrives with the
desktop already declared. There is no second step to automate, because the
flake is the whole description. How to add the input is on
[the getting-started page](getting-started).
