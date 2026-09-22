---
title: Try it in a VM
---

# Try it in a VM

Before you give nixarchy a disk, you can give it a window. `#try` boots the
same installer ISO a release ships, in a local UEFI VM, and you answer the
wizard yourself — the install you are practising is the install you will do.

This page is the one thing the repository explained and the site did not
(#831). If you are already installing for real,
[Getting Started](getting-started) and [The ISO in depth](the-iso) are the
pages you want.

## With Nix

```sh
nix run github:olafkfreund/nixarchy#try            # offline image, ~6.6 GB download
nix run github:olafkfreund/nixarchy#try -- --net   # network image, ~1.9 GB download
```

The **offline** image installs with no network at all — it carries its own
store paths and copies them from the medium. The **network** image is smaller
and fetches the rest from binary caches while installing. Both write a
`nixarchy-try.qcow2` in the current directory, up to 32 GB.

When the install finishes:

| | |
|---|---|
| `-- --boot` | start the system you just installed, from that disk |
| `-- --fresh` | wipe it and install again |
| `-- --memory` | shrink the 8 GB default |
| `-- --help` | the rest |

## What it refuses to do quietly

Everything heavy is announced before it starts, and the things that cannot
work are refused rather than attempted:

- **A download or a source build?** It says which. If the commit you are on
  has no cached image, it falls back to the latest release's prebuilt,
  install-tested one — verified against that release's checksums — instead of
  compiling for hours without telling you.
- **RAM and disk** are checked first: 8 GB by default, `--memory` to shrink.
- **`/dev/kvm`** is checked. Without it the VM still runs, with a loud
  warning, several times slower.
- **No display?** It serves the screen over VNC on `127.0.0.1:5900` rather
  than dying.

## Without Nix, from any Linux

`#try` is a `nix run` app, so it needs Nix. On Ubuntu, Fedora, Arch or
anything else, a script needs only `qemu` and `curl` from your own package
manager:

```sh
curl -fLO https://raw.githubusercontent.com/olafkfreund/nixarchy/main/installer/try-nixarchy.sh
less try-nixarchy.sh          # it is going to download an image and start a VM
bash try-nixarchy.sh
```

It fetches the latest release's installer image, checks it against that
release's own `SHA256SUMS`, and boots it in a UEFI VM. `--boot`, `--fresh`
and `--help` work as above.

It takes the **latest release** and cannot resolve a particular commit. If
you have Nix, `#try` is the better door and says so.

## After it is installed, on real hardware

A VM cannot answer the questions that need the machine itself. From inside a
running session:

```sh
nix run github:olafkfreund/nixarchy#verify
```

It asks what no VM check can — hardware rendering, Bluetooth pairing, the
RetroArch cores — and **prints what it found rather than a verdict**, because
the answers depend on hardware nobody else has.
[How this is tested](how-this-is-tested) explains which layer answers what,
and why some questions only a person can settle.

## Where to go next

- It worked and you want it for real: [Getting Started](getting-started)
- You want to keep Windows on the same disk:
  [Dual boot](dual-boot-install)
- You want the install to answer its own questions:
  [Unattended installs](unattended-installs)
- Something went wrong: [Troubleshooting](troubleshooting)
