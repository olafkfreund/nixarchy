---
title: Prebuilt Binaries
---

# Prebuilt Binaries

You download an ordinary Linux binary -- a release tarball from GitHub, a
vendor CLI, an AppImage -- and on NixOS it dies before it starts:

```
bash: ./tool: No such file or directory
```

The file plainly exists. What does not exist is what the binary asks for
first: a loader at `/lib64/ld-linux-x86-64.so.2`, libraries in `/usr/lib`,
an interpreter at `/bin/bash`. NixOS keeps all of those in `/nix/store`
under versioned paths, and only programs built by Nix know where. The
binary is asking a reasonable question in a filesystem that answers it for
nobody.

Every nixarchy machine ships three answers to that, all on by default.
This page is what each one does -- and, just as important, where each one
stops.

## nix-ld: the loader and its libraries

[nix-ld](https://github.com/nix-community/nix-ld) puts a shim at the path
binaries expect the loader at. When a foreign binary starts, the shim
supplies the libraries in `programs.nix-ld.libraries` -- and nixarchy
curates that list beyond the NixOS default, covering what a desktop's
downloaded binaries actually load:

- **`libstdc++`/`libgcc_s`** -- nearly every prebuilt C++ or Rust binary
- **`libGL`** -- anything that renders: matplotlib and opencv wheels,
  downloaded games
- **the Wayland and X client stacks** (`libwayland-client`, `libxkbcommon`,
  `libX11` and friends) -- GUI binaries, Electron, SDL/GLFW games under
  XWayland
- **fontconfig and freetype** -- text on screen
- **glib, NSS/NSPR** -- every Electron app dlopens `libnss3.so` at startup
  and exits without it
- **`libasound`** -- sound; PipeWire serves the ALSA API but the client
  library still has to exist
- **ffmpeg's libraries** -- media wheels (pyav, torchaudio) link these
  rather than bundling them
- **zlib, openssl, libxml2** -- compressed assets, TLS, lxml

The list merges with nixpkgs' own base set rather than replacing it, and
the exact entries with the reason for each are in
[`modules/nixos.nix`](https://github.com/olafkfreund/nixarchy/blob/main/modules/nixos.nix).

When a binary wants a library the list does not carry, the error names it:

```
error while loading shared libraries: libfoo.so.2: cannot open shared object file
```

The fix is one line in your own configuration -- your entries merge with
nixarchy's, they do not replace them:

```nix
programs.nix-ld.libraries = with pkgs; [ foo ];
```

Then rebuild and **log out and back in**: `NIX_LD_LIBRARY_PATH` is set at
login, so a running session keeps the old list. To go from a soname to the
package that carries it, `nix-locate lib/libfoo.so.2` (from nix-index) or
search the file name at [search.nixos.org](https://search.nixos.org). And
`nixarchy-doctor <path-or-command>` does the whole diagnosis for you --
[Troubleshooting](troubleshooting) has the entry.

## envfs: shebangs and /usr/bin

A script starting `#!/bin/bash` or `#!/usr/bin/env python` fails with
"no such file or directory" on a bare NixOS, because `/bin` holds only `sh`
and `/usr/bin` only `env`. [envfs](https://github.com/Mic92/envfs) mounts
both directories as a FUSE view of your current `PATH`, so every tutorial
script and every downloaded installer's shebang resolves -- to whatever
that name means on your `PATH` right now. A name that is not on your
`PATH` still fails, because there is genuinely nothing to resolve it to.

## AppImages: double-clickable

`programs.appimage` is on, with binfmt registration -- the kernel
recognises the AppImage format itself, so a downloaded AppImage runs
directly:

```sh
chmod +x ./Tool.AppImage
./Tool.AppImage
```

or from the file manager, without knowing that `appimage-run` exists.
Underneath, NixOS's wrapper unpacks the image and runs it in an
environment that supplies the common libraries. An AppImage bundles most
of what it needs by design, which is why this rung is the least likely to
need any per-app work.

## Where the ladder stops

Honesty about the limits, so the failure you hit next is not a surprise:

- **Compiling from source.** All three mechanisms serve binaries at *run*
  time. `pip install` of a package with no wheel runs a C compiler against
  headers at *install* time, and no loader shim provides headers. That
  needs a [devenv](per-project-environments) with the packages added, or
  an FHS shell (`pkgs.buildFHSEnv`).
- **A library that exists but does not fit.** nix-ld can only hand over
  what nixpkgs has. A binary built against a different glibc era or a
  different ABI of the same soname loads and then misbehaves, and no list
  entry fixes that.
- **Installers that manage their own toolchains.** conda and friends
  download whole trees of foreign binaries; some run under nix-ld once the
  library list is grown far enough, none are supported.
- **Software that wants a whole distro** -- `/opt`, postinstall scripts, a
  package manager of its own. That is what a [box](boxes) is for, and the
  decision table on that page is the full ladder in one place.

The Python-specific version of this story -- venvs, wheels, and the
`libGL.so.1` import error -- is the [Python](python) page.
