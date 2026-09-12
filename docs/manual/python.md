---
title: Python
---

# Python

Two different people open a Python guide on NixOS, and most guides answer
only one of them.

Someone **following a tutorial** wants `pip install` to work, right now, in
whatever directory the tutorial says. That is not a packaging problem and it
does not need a flake -- it needs a virtualenv, ordinary wheels from PyPI,
and a loader that can find the libraries those wheels were built against.
This page serves that person first.

Someone **building a project** wants the environment to be the same on every
machine, next year. That person gets the second half of the page: the
`python` preset from [per-project environments](per-project-environments),
`uv`, and where Nix-built Python actually earns its keep.

## I just want pip to work

`python3` is already on every nixarchy machine -- it is a dependency of
Omarchy's own scripts, and _Install ▸ Development ▸ Python_ makes it part of
your configuration explicitly. So the tutorial path is the tutorial path:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install requests
```

This works, unmodified, for most of PyPI. A pure-Python package -- requests,
flask, click, most of what a tutorial asks for -- installs and imports on
NixOS exactly as it does anywhere else. Nothing about the venv-and-wheels
workflow is wrong here, and nothing below asks you to give it up.

## The error this page exists for

Then you install a wheel with compiled code in it, `pip install`
succeeds -- and on a bare NixOS (or for a library nixarchy's shipped set
does not carry) the `import` dies:

```
ImportError: libGL.so.1: cannot open shared object file: No such file or directory
```

Read that error precisely, because it names the real problem. The wheel is
fine. pip is fine. Your venv is fine. A wheel with compiled code in it is an
ordinary Linux binary, built on an ordinary distro, and at import time the
dynamic loader goes looking for the shared libraries it was linked against --
`libGL.so.1`, `libstdc++.so.6`, `libz.so.1` -- in the places ordinary
distros keep them: `/usr/lib`, `/lib`. NixOS deliberately has no `/usr/lib`.
Every library lives in `/nix/store` under a versioned path, and only
programs built by Nix know where. The binary is asking a reasonable
question in a filesystem that answers it for nobody.

So this is a **loader** problem, not a Python problem. The same failure, with
a different library name in it, hits Node native modules, Electron apps,
PyTorch and Playwright -- anything that ships prebuilt compiled code.

## What fixes it

NixOS's answer to loose prebuilt binaries is
[nix-ld](https://github.com/nix-community/nix-ld): a shim at the path
binaries expect the loader at, which supplies a configured set of libraries.
It is already enabled on every nixarchy machine, and nixarchy curates
`programs.nix-ld.libraries` beyond the NixOS default -- `libGL`, `zlib`,
`libstdc++` and the rest of what common wheels load are in the shipped set.

**Which interpreter you are running decides whether that helps you**, and the
distinction is worth thirty seconds because getting it wrong costs a rebuild
and a logout for nothing. nix-ld works by *being* the loader at
`/lib64/ld-linux-x86-64.so.2`; only a binary whose ELF interpreter is that
path reaches the shim, and only the shim reads `NIX_LD_LIBRARY_PATH`. One
command tells you which you have:

```sh
patchelf --print-interpreter "$(readlink -f "$(command -v python3)")"
```

- `/lib64/ld-linux-x86-64.so.2` -- a foreign interpreter (the CPython **uv**
  downloads for itself is the one you are most likely to meet). nix-ld
  applies, and the shipped library set is what makes the import above work.
- `/nix/store/...-glibc-.../ld-linux-x86-64.so.2` -- a **nixpkgs** python3,
  which is what `python3` on this machine is. It uses the store's own loader
  and never consults `NIX_LD_LIBRARY_PATH`, so growing
  `programs.nix-ld.libraries` changes nothing about what it can import, no
  matter how long that list gets.

For the second case, hand the same libraries over for the one command that
needs them:

```sh
LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" python3 app.py
```

Per command, not exported globally -- a global `LD_LIBRARY_PATH` is how
unrelated Nix programs start failing. The durable answers are a devenv (below),
an FHS environment, or simply running the venv on uv's own Python.
[Prebuilt binaries](prebuilt-binaries) is the full story of that set.

When a wheel wants a library the set does not carry -- on an interpreter
nix-ld can actually reach -- the error names it, and the fix is one option in
your own configuration; your entries merge with nixarchy's rather than
replacing them:

```nix
programs.nix-ld.libraries = with pkgs; [ libpulseaudio ];
```

Rebuild, log out and back in (`NIX_LD_LIBRARY_PATH` is set at login), and
the same venv -- no reinstall -- imports. Each new
`cannot open shared object file` is one more entry in that list: the error
tells you the library, [search](other-packages) tells you the package, and
`nixarchy-doctor <path-or-command>` does the diagnosis for you.

## When the project matters more than the tutorial

Once the code is a project -- a repo, a colleague, a deadline -- pin the
environment instead of relying on whatever the machine has:

```sh
nixarchy dev init python
```

This is the `python` preset from
[per-project environments](per-project-environments) (the devenv service,
opt-in): a `devenv.nix` with `languages.python.enable` and
`venv.enable`, so devenv creates and enters a virtualenv for you and
`pip install` lands in the project rather than in your home directory. The
lock file makes it the same Python on every machine that clones the repo.

For dependency management itself, [uv](https://docs.astral.sh/uv/) is the
current answer -- `uv.lock` as the source of truth. And when you need Nix to
*build* the project from that lock,
[uv2nix](https://pyproject-nix.github.io/uv2nix/introduction.html) exists --
whose own documentation says to skip it for day-to-day development and just
use uv. That is a useful signal, not a criticism: reach for uv2nix when
something must consume the project as a Nix package, not before.

## Machine learning, CUDA, and the one thing nix-ld cannot do

PyTorch and friends are the hardest case of everything above, and they are
also the case where the advice above stops applying — so it is worth being
precise rather than general.

A CUDA or ROCm wheel from PyPI already contains its own CUDA runtime. The
only thing it needs from the machine is the *driver*, `libcuda.so.1`, which
on NixOS is in `/run/opengl-driver/lib`. That is a `LD_LIBRARY_PATH` problem,
not a nix-ld one.

And the distinction that trips most people:

> nix-ld helps an **unpatched** binary — one built on an ordinary distro,
> which asks for the loader at `/lib64/ld-linux-x86-64.so.2` and reads
> `NIX_LD_LIBRARY_PATH` from its environment. A `python3` out of nixpkgs is
> not such a binary. It is patched to use Nix's own loader and consults
> neither variable, so growing `programs.nix-ld.libraries` does nothing for
> what *it* imports.

The interpreter that does read them is the one **uv** downloads for itself.
So the working answer for an ML project is uv's own Python, and
[`nixarchy dev init ml`](per-project-environments#nixarchy-dev-init-ml) is
that in one command — uv, `UV_PYTHON_PREFERENCE = "only-managed"`, and the
driver path already set.

For notebooks, [`nixarchy dev init jupyter`](per-project-environments#nixarchy-dev-init-jupyter)
is an ordinary devshell built from `python3.withPackages`. Do not reach for
**jupyenv** (formerly jupyterWith), which every search puts first: it is
unmaintained and does not track current nixpkgs.

## What still will not work, and why

Honesty about the limits, so the failure you hit next is not a surprise:

- **pip compiling C from source.** nix-ld helps *prebuilt* binaries find
  libraries at run time. A package with no wheel for your platform runs a C
  compiler against headers at *install* time, and no loader shim provides
  headers. That needs the C libraries in the environment -- a devenv with the
  packages added, a `nix-shell` with them, or an FHS environment
  (`pkgs.buildFHSEnv`, plain nixpkgs) that fakes the whole `/usr` layout.
- **Hard-coded paths to a name that is not on your `PATH`.** `envfs` is
  shipped and on: it mounts `/bin` and `/usr/bin` as a view of your current
  `PATH`, so `#!/bin/bash` and `/usr/bin/env python` resolve
  ([Prebuilt binaries](prebuilt-binaries) covers it). But it can only
  resolve a name to something your `PATH` actually has -- a script that
  execs a command you never installed still fails, and the fix is
  installing that command, not the loader.
- **Installers that manage their own binaries.** conda and friends download
  whole toolchains of foreign binaries; some run under nix-ld once the
  library list is grown far enough, none are supported. If a tool insists on
  a whole distro's worth of assumptions, that is what a
  [box](boxes) is for.

The full ladder -- which rung for which failure -- is the decision table on
the [Boxes](boxes) page.
