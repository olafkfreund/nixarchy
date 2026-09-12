---
name: nixos-binaries
description: >
  REQUIRED when a program that is not built by Nix will not run on this NixOS
  machine — a downloaded release tarball, a vendor CLI, an AppImage, a pip wheel
  that imports and dies, a Node native module, an installer script. Use when asked
  why a binary that plainly exists reports "No such file or directory", why an
  import fails on a `.so`, how to add a library to nix-ld, whether something needs
  an FHS environment or a container, or how to package software that is in no
  repository. Triggers: nix-ld, NIX_LD, NIX_LD_LIBRARY_PATH, envfs, appimage,
  buildFHSEnv, steam-run, patchelf, autoPatchelfHook, ld-linux, "cannot open shared
  object file", libGL.so.1, libstdc++.so.6, "No such file or directory" on a file
  that exists, `#!/bin/bash`, `/usr/bin/env`, ImportError, downloaded binary,
  prebuilt, wheel, distrobox, `nixarchy pkg new`.
  For per-project toolchains use `devenv`; for the GPU driver underneath a
  graphics library use `nixos-gpu`.
---

# NixOS Prebuilt Binaries Skill

A user downloads an ordinary Linux binary and it dies before it starts:

```
bash: ./tool: No such file or directory
```

The file exists. What does not exist is what the binary asks for first: a loader
at `/lib64/ld-linux-x86-64.so.2`, libraries in `/usr/lib`, an interpreter at
`/bin/bash`. NixOS keeps all of that in `/nix/store` under versioned paths, and
only programs built by Nix know where. **The binary is asking a reasonable
question in a filesystem that answers it for nobody.**

The same defect wearing a different hat, from a pip wheel or a Node module:

```
ImportError: libGL.so.1: cannot open shared object file: No such file or directory
```

Read that error precisely before doing anything. The wheel is fine, pip is fine,
the venv is fine. A wheel with compiled code in it is an ordinary Linux binary,
and at import time the dynamic loader went looking in `/usr/lib`. **This is a
loader problem, not a packaging problem**, and the two have completely different
fixes.

## The ladder — cheapest rung first

This is the whole value of this skill. An agent that reaches for a container
because one library was missing has cost the user an afternoon.

| you have | reach for |
|---|---|
| anything in nixpkgs | nixpkgs — always first |
| a loose prebuilt binary missing a library | `programs.nix-ld.libraries` — one line |
| a script with `#!/bin/bash` or `/usr/bin/env` | `envfs`, already on — nothing to do |
| a downloaded AppImage | run it; binfmt registration is already on |
| pip compiling C against system headers | a `devenv` with the libraries, or `pkgs.buildFHSEnv` |
| software that wants a whole distribution | a box (distrobox) |
| software in no repository at all | `nixarchy pkg new <url>` |

Three of those rungs — nix-ld, envfs, AppImage binfmt — are **already on for
every nixarchy machine**. Most "it will not run" reports are answered by adding
one entry to a list, not by installing anything.

## Rung 1: nix-ld, the loader and its libraries

[nix-ld](https://github.com/nix-community/nix-ld) puts a shim at the path foreign
binaries expect the loader at. When one starts, the shim supplies the libraries
in `programs.nix-ld.libraries` — and nixarchy curates that list well beyond the
NixOS default: `libstdc++`/`libgcc_s`, `libGL`, the Wayland and X client stacks,
fontconfig and freetype, glib, NSS/NSPR (every Electron app dlopens `libnss3.so`
and exits without it), `libasound`, ffmpeg's libraries, zlib, openssl, libxml2.
The entries and the reason for each are in `modules/nixos.nix`.

When a binary wants something the list does not carry, the error names it. The
fix is one line in the user's own configuration — **their entries merge with
nixarchy's, they do not replace them**:

```nix
programs.nix-ld.libraries = with pkgs; [ libpulseaudio ];
```

Then rebuild and **log out and back in**. `NIX_LD_LIBRARY_PATH` is set at login,
so the session they are sitting in keeps the old list — a user who rebuilds,
retries in the same terminal and reports "it did not work" has hit this and
nothing else.

To go from a soname to the package that carries it:

```sh
nix-locate lib/libfoo.so.2          # nix-index, most direct
```

or search the file name at <https://search.nixos.org>.

### The correction that matters most: nix-ld does NOT help a nixpkgs Python

This is the single most common "I did exactly what the docs said and it still
failed" report, and guidance elsewhere — including the wiki — states the
opposite. **Say this before suggesting a `programs.nix-ld.libraries` entry for a
Python import error.**

nix-ld works by *being* the loader at `/lib64/ld-linux-x86-64.so.2`. Only a
binary whose ELF interpreter points at that path goes through it, and only that
loader reads `NIX_LD` and `NIX_LD_LIBRARY_PATH`. **Anything nixpkgs built is
patched to the glibc loader in the store**, so it never consults either
variable — no matter how long the library list is.

Check which one you have, and never assume:

```sh
patchelf --print-interpreter "$(readlink -f "$(command -v python3)")"
```

- `/nix/store/…-glibc-…/lib/ld-linux-x86-64.so.2` — nixpkgs' own. nix-ld is not
  in the picture.
- `/lib64/ld-linux-x86-64.so.2` — a foreign binary. nix-ld applies.

Measured on a nixarchy machine with `libGL` in the shipped nix-ld set:

```
$ python3 -c 'import ctypes; ctypes.CDLL("libGL.so.1")'
OSError: libGL.so.1: cannot open shared object file: No such file or directory

$ ~/.local/share/uv/python/cpython-3.12.14-.../bin/python3.12 \
    -c 'import ctypes; ctypes.CDLL("libGL.so.1")'
(no error)
```

Same machine, same library list, same second. The difference is entirely which
interpreter the binary declares.

So for a wheel that fails to import, there are four real fixes and one that only
looks like one:

1. **Run the venv on an unpatched interpreter.** `uv python install 3.12` fetches
   a generic-Linux CPython whose interpreter is `/lib64/ld-linux-x86-64.so.2`, so
   it goes through nix-ld and the curated set applies. This is why `uv`-managed
   Pythons "just work" while the system `python3` does not.
2. **Hand the libraries to the nixpkgs interpreter directly**, per command or per
   shell — not globally, which breaks other Nix programs:
   ```sh
   LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" python3 app.py
   ```
3. **A `devenv`** with the library in the environment — the right answer once the
   code is a project. See the `devenv` skill.
4. **`pkgs.buildFHSEnv`**, which fakes the whole `/usr` layout for anything that
   insists on it.

And the one that only looks like a fix: adding the library to
`programs.nix-ld.libraries` and rebuilding. It changes nothing for a nixpkgs
interpreter, costs a rebuild and a logout, and sends the user away convinced the
documentation lied to them.

**The two Python users are different people.** Someone following a tutorial has a
loader problem: venv plus wheels plus an interpreter that can find libraries, and
no flake is involved. Someone building a project wants `uv` with `uv.lock` as the
source of truth — and `uv2nix` only when Nix must *build* the project, which
uv2nix's own documentation says to skip day to day. Do not answer the first
person with the second person's tooling.

## Rung 2: envfs — shebangs and `/usr/bin`

A script starting `#!/bin/bash` or `#!/usr/bin/env python` fails with "no such
file or directory" on a bare NixOS: `/bin` holds only `sh` and `/usr/bin` only
`env`. [envfs](https://github.com/Mic92/envfs) mounts both as a FUSE view of the
current `PATH`, and it is **already on** — so every tutorial script and every
downloaded installer's shebang resolves.

Its limit is exact: it resolves a name to whatever that name means on the `PATH`
*right now*. A script that execs a command the user never installed still fails,
and the fix is installing that command, not touching the loader.

## Rung 3: AppImages

`programs.appimage` with `binfmt` is on, so the kernel recognises the format
itself:

```sh
chmod +x ./Tool.AppImage
./Tool.AppImage
```

That works from the file manager too, without knowing `appimage-run` exists.
Underneath, the wrapper unpacks the image and runs it against the nix-ld set. An
AppImage bundles most of what it needs by design, so this rung rarely needs
per-app work.

## Rung 4: an FHS environment

When something wants a `/usr` that is really there — pip compiling C against
system headers, a vendor installer, an old proprietary toolchain:

```nix
(pkgs.buildFHSEnv {
  name = "fhs";
  targetPkgs = pkgs: with pkgs; [ gcc zlib libGL ];
  runScript = "bash";
})
```

`steam-run` is a ready-made one from nixpkgs and is worth trying before writing
an env: `steam-run ./installer.sh`. Note the bound: an FHS env supplies headers
and layout at *build* time as well as run time, which is exactly what nix-ld
cannot do.

## Rung 5: a box

Software that wants a whole distribution — `/opt`, postinstall scripts, a package
manager of its own — is what distrobox is for. It is off by default and is **not
a sandbox**: it runs privileged, with the user's entire `$HOME` read-write. Reach
for it last, and say what it costs: a second package manager and a second update
cadence.

## Rung 6: package it

Software in no repository at all gets a first draft from:

```sh
nixarchy pkg new https://github.com/someone/tool
```

For a prebuilt release specifically, the derivation wants `autoPatchelfHook`,
which rewrites the binary's interpreter and RPATH to store paths — the permanent
version of what nix-ld does at run time, and the right answer once something is
worth keeping.

## The machine can diagnose it

```sh
nixarchy-doctor ~/.venv/lib/python3.12/site-packages/cv2/cv2.so
nixarchy-doctor some-downloaded-tool
```

It runs the loader's own resolution against the nix-ld set, names every missing
library, and for the common sonames prints the `programs.nix-ld.libraries` line
that fixes it.

**State its limits when you report a clean result**, because a clean report is
not a guarantee:

- It checks only the files it is given. The no-argument scan covers `~/.local/bin`
  and nothing else — it does not crawl venvs or `node_modules`. For a broken
  import, name the actual `.so` inside the package; the traceback usually names
  it.
- It answers "is every library findable", not "is every library right". A library
  that is present but the wrong ABI loads cleanly and misbehaves later.
- It resolves what the binary *declares*. A library the program `dlopen`s by hand
  is invisible until that moment, so a binary can pass and still fail with the
  same error. Bring it the library name from *that* error and add it the same way.

## Diagnosing by hand

```sh
file ./tool                                   # is it even ELF, and for this arch?
patchelf --print-interpreter ./tool           # nixpkgs' loader, or /lib64's?
ldd ./tool                                    # what is "not found"

# Ask the question the runtime will ask, with the nix-ld set in play:
LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd ./tool
```

| Symptom | Cause |
|---|---|
| `No such file or directory` on a file that exists | Its interpreter is missing — foreign binary, nix-ld not reached, or a wrong-arch build |
| `libfoo.so.2: cannot open shared object file` from a downloaded binary | Add `foo` to `programs.nix-ld.libraries`, rebuild, log out and in |
| Same error from a `python3`/`node` that nixpkgs built | nix-ld does not apply — see the correction above |
| Added the library, rebuilt, still failing | Still in the old session: `NIX_LD_LIBRARY_PATH` is set at login |
| `#!/bin/bash: bad interpreter` | envfs is off, or the command genuinely is not on `PATH` |
| Loads, then segfaults or misbehaves | Present-but-wrong-ABI library. No list entry fixes this; use an FHS env or package it |
| `pip install` fails compiling C | Not a loader problem at all. devenv or `buildFHSEnv` |

## Rules

- **Read the error before choosing a rung.** "cannot open shared object file" is
  rung 1; "bad interpreter" is rung 2; a compiler error is rung 4. They look
  alike in a bug report and have nothing in common.
- **Check the interpreter before promising a nix-ld fix.** One `patchelf
  --print-interpreter` decides whether the rebuild you are about to recommend can
  possibly work.
- **Never suggest replacing `programs.nix-ld.libraries`** — plain assignment
  merges with nixarchy's curated set; a user who writes `lib.mkForce` loses all
  of it.
- **Say "log out and back in" every time** you recommend a library addition.
- **Do not reach past rung 1 without a reason.** A container for one missing
  soname is the most common over-correction on this topic.
- **`nixpkgs` first, always.** If the thing is packaged, none of this ladder
  applies.
