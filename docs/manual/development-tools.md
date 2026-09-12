---
title: Development tools
---

# Development tools

## Alternative editors

Neovim ships by default. _Install > Editor_ offers VSCode, Cursor, Zed, Helix,
Vim and Emacs, each a row in the app selection like any other: pick it, then
_Install > Apply changes_. VSCode and Cursor are unfree; nixarchy allows
unfree packages by default, so they need nothing extra from you.

Sublime Text is listed but disabled. nixpkgs marks `sublimetext4` broken over
an insecure OpenSSL dependency, and enabling a broken package aborts the whole
rebuild rather than failing on its own, so the row says why instead of letting
you find out at build time.

Theme matching for VSCode, Cursor, VSCodium and Helix, and _Setup > Defaults >
Editor_ for the system-wide default, work as upstream describes.

## Environments: nixpkgs, not mise

Upstream installs its language runtimes with `mise use --global <lang>@latest`,
which downloads a prebuilt toolchain into `~/.local/share/mise`. That does
not fit NixOS twice over. Nothing about it survives into your configuration,
so a second machine built from the same flake does not have it. And mise's
prebuilt binaries are linked against loader paths NixOS does not have, so
several of them — Node is the usual example — do not execute at all.

So the thirteen toolchains in _Install > Development_ are rows in the app
selection, and the compiler comes from the same nixpkgs as the rest of the
system:

| Row | nixpkgs attribute | Note |
|---|---|---|
| Go | `go` | |
| Rust | `rustup` | Manages toolchains under `~/.rustup`, as upstream. Use `cargo` and `rustc` instead if you want Nix to pin the compiler |
| Node.js | `nodejs` | |
| Bun | `bun` | |
| Deno | `deno` | |
| Java | `jdk` | |
| Elixir | `elixir` | |
| Zig | `zig` | |
| Clojure | `clojure` | |
| Scala | `scala` | |
| .NET | `dotnet-sdk` | |
| OCaml | `ocaml` | |
| Python | `python3` | Already present as a dependency of Omarchy's own scripts; select it anyway so your configuration says so |

PHP and Symfony are rows too. Ruby on Rails, Laravel and Phoenix have no row
of their own because upstream's `omarchy install dev-env` scripts still drive
mise and `omarchy-pkg-add` for them.

mise itself is still installed, and `programs.nix-ld` is enabled so that its
downloads can run. It is fine for a tool that is not in the table; it is the
wrong place for a compiler your project depends on.

### Per-project environments: `nix develop`

`mise use` in a project directory has a NixOS equivalent that is strictly
more capable: a devShell. It pins not just the language version but every
tool the project needs, and it is checked in, so a colleague gets the same
shell from `git clone`.

A minimal `flake.nix` in the project root:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ nodejs_22 pnpm sqlite ];
        shellHook = ''
          export DATABASE_URL=sqlite://./dev.db
        '';
      };
    };
}
```

Then:

```sh
nix develop          # drop into a shell with exactly those tools on PATH
nix develop -c npm test   # run one command inside it
```

Nothing is installed globally. Leave the directory and `nodejs_22` is gone
from your PATH; the global Node from the app selection, if you have one, is
untouched. Commit `flake.lock` and every checkout gets the same versions.

The global rows in the menu are for the tools you want everywhere — a
language server for your editor, `go` for one-off scripts. Anything a
project depends on belongs in that project's devShell.

### Or without writing a flake: devenv

The file above is the plain-Nix answer, and it is the right one when a
project's environment is a list of packages and an environment variable. When
it is not — a Postgres to run alongside, processes, git hooks — writing that
in `mkShell` is a lot of Nix.

`nixarchy dev init react` scaffolds a
[devenv](https://devenv.sh) project instead: one command, options rather than
derivations, and an environment that activates on `cd` in bash, zsh and fish
without direnv. It is off by default and it costs a second lockfile;
[Per-project environments](per-project-environments) is the whole story,
including when not to.

## Two tools that are not toolchains

Both are rows in _Install ▸ Development_, and neither is a language, so
neither is in the table above.

**Git LFS** is selected as a NixOS option rather than a bare package, and
the difference matters. Installing the binary alone is a trap: `git-lfs` only
does anything once its filter configuration is written, and until then a clone
of a repository using LFS **silently hands you pointer files instead of
content** — a few lines of text where the asset should be. Nothing errors. The
checkout looks corrupt rather than incomplete, which is why people lose an
afternoon to it. Selecting the row turns on `programs.git.lfs`, which installs
the package *and* writes `filter.lfs` into the system git configuration, so
`git lfs install` is never something you have to know about.

**`uv`** is the Python package and project manager. The `python` devenv preset
already pins its own copy per project, so this row is the machine-wide one —
for `uv tool install`, `uvx`, and the quick script that is not a project yet.
If what you want is a project with a pinned interpreter, use
[per-project environments](per-project-environments); if what you want is
`pip install` to work at all, [Python](python) is the page that explains why
it sometimes does not.

## Docker, rootless

Docker and Docker Compose are enabled by default and Lazydocker is on
`Super + Shift + D`, as upstream. What differs is **whose** daemon it is:
nixarchy runs Docker **rootless**, as a systemd user service under your own
account, rather than the usual root-owned daemon.

`docker build`, `docker run`, `docker compose` all work unprivileged, with no
`sudo` and no group.

The reason is the group that arrangement otherwise requires. A root-owned
socket means `docker ps` without `sudo` needs you in the `docker` group, and
**that group is equivalent to passwordless root** -- `docker run -v /:/host` is
the whole exploit. It is not that it grants something you lack; you are in
`wheel` already. It removes **the prompt**, for everything running as you: a
browser, an `npm install` postinstall script, a dependency in a shell you
opened for one afternoon. Rootless keeps the convenience and drops that.

An escape from a rootless container gets your user account, not the machine.

### What rootless costs

Not nothing, so it is worth knowing before you meet it:

| | |
|---|---|
| ports below 1024 | need `net.ipv4.ip_unprivileged_port_start` lowered, or a higher port |
| bind mounts | file ownership maps through user namespaces, which surprises people once |
| devcontainers, testcontainers | some assume a root-owned socket and fail to find one |
| containers after logout | it is a *user* service -- `loginctl enable-linger $USER` to keep them running |
| images you already had | live in root's `/var/lib/docker` and are not visible to your own daemon |

That last row is the one that bites on upgrade. If you were running nixarchy
before this changed, your existing images and containers are still there, under
the root daemon -- `sudo docker images` shows them. Re-pull or `docker save` /
`docker load` across, or turn the rooted daemon back on.

### Turning the rooted daemon back on

It is your machine. One line puts the classic arrangement back, group included:

```nix
virtualisation.docker.enable = true;
```

Rootless switches off when you do that, so `DOCKER_HOST` is not left pointing
at a second daemon. **You are then in the `docker` group, with the
root-equivalence described above** -- that is the trade you are making, and it
is a reasonable one to make deliberately for devcontainers or a low port.

To keep the rooted daemon and *not* the group, use `sudo docker` and say which
groups you keep:

```nix
virtualisation.docker.enable = true;
users.users.<you>.extraGroups = lib.mkForce [ "wheel" "video" "input" "i2c" ];
```

`mkForce`, because a plain assignment merges with what is there instead of
replacing it. **List the groups you keep** -- `mkForce [ ]` would take `wheel`
with it and leave you unable to `sudo`.

Upstream offers _Setup > Security > Sudoless Docker_
(`omarchy-setup-security-sudoless-docker`) for the same opt-in. It still works;
on a rootless machine there is no root socket for it to grant access to.

### Podman

Rootless [podman](https://podman.io) solves the same problem a different way --
no daemon at all. nixarchy already uses it: [boxes](boxes) are rootless podman
underneath, though podman is only switched on when you enable boxes.

If you prefer it as your container runtime, note that nixpkgs refuses to build
a machine where both `dockerCompat` and the rooted Docker daemon exist
(*"Option dockerCompat conflicts with docker"*). With nixarchy's default that
daemon is already off, so this is enough:

```nix
virtualisation.podman = {
  enable = true;
  dockerCompat = true;                      # provides a `docker` command
  defaultNetwork.settings.dns_enabled = true;
};
```

You will then want `virtualisation.docker.rootless.enable = false;` as well, so
only one thing is answering to the name `docker`.

Upstream's [Docker section](https://omarchy.org/manual/development-tools/)
covers the rest — including _Install > Development > Docker DB_ for local
databases — and none of it is Arch-specific.

## GitHub CLI

Upstream wires `gh` and `ghui` as lazy-loading mise stubs, and those stubs
are what you get here too: the first `gh` downloads it through mise into
`~/.local/share/mise`. That works, thanks to nix-ld, but it is the same
imperative state as any other mise install. If you want `gh` on every machine
you build from this flake, add `pkgs.gh` to `environment.systemPackages` and
it takes precedence over the stub.

`gh auth login`, `gh repo clone org/repo` and lazygit are as upstream.
