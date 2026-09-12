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

## A language server that already knows your machine

The question a person learning NixOS cannot answer is the same one the agents
above cannot: *what options exist?* For a human the structural fix is editor
completion, and the two Nix language servers are not equivalent about it.
`nil` does keywords, locals and builtins. `nixd` links the real evaluator, so it
completes NixOS and Home Manager option names **and their defaults** against
your actual configuration.

nixd's one real weakness is that it has to be told where the flake is and which
attribute to evaluate — which is precisely the thing a distribution knows and
you should not have to write down. nixarchy writes it for you, into whichever
of these editors you selected:

| editor | file | through |
|---|---|---|
| VSCode | `~/.config/Code/User/settings.json` | the Nix IDE extension's `nix.*` settings |
| Cursor | `~/.config/Cursor/User/settings.json` | the same |
| Zed | `~/.config/zed/settings.json` | `lsp.nixd.initialization_options` |
| Helix | `~/.config/helix/languages.toml` | `[language-server.nixd]` |
| Neovim | `~/.config/nvim/lua/plugins/nixd.lua` | an `nvim-lspconfig` spec |

VSCode and Cursor still need the Nix IDE extension itself — extensions are not
something a NixOS module can put in your editor — but every setting it needs is
already there when you install it.

An editor you have not selected gets nothing. The Helix and Neovim files are
written only when they do not already say something about nixd, and the three
JSON files are merged into rather than replaced, so your own settings survive.

Turn it off with:

```nix
programs.nixarchy.languageServer = false;
```

## When a command is not found

The Arch reflex is `pacman -S thing`, and on NixOS it is a dead end at exactly
the moment you are already stuck. NixOS has a `command-not-found` of its own and
it cannot help on a flake machine: it reads a database that only the channel
mechanism ships, so it is either missing or stale and your shell says nothing at
all.

nixarchy replaces it with one that answers:

```
$ rg
rg: command not found. In nixpkgs it comes from:
  ripgrep

  Run it once:      , rg
  Keep it:          nixarchy pkg add ripgrep    (then: nixarchy apply)
```

Both lines are real commands. `,` is [comma](https://github.com/nix-community/comma):
it fetches the package, runs the thing once, and leaves nothing behind — useful
when you are not sure you want it. `nixarchy pkg add` writes it into
`~/.config/nixarchy/apps.nix`, which is the permanent form on a machine whose
software lives in a file. (`nixarchy try` covers the same ground when you
already know the package exists; this is for when you do not.)

What makes the answer possible is a prebuilt index. `nix-index` builds its
database by walking nixpkgs, which takes hours, so nixarchy ships the one
[nix-index-database](https://github.com/nix-community/nix-index-database)
publishes weekly instead. `nix-locate` is therefore on your machine and works
immediately — which is also what `nixarchy doctor` has always assumed when it
tells you to run it.

Turn it off with:

```nix
programs.nixarchy.commandNotFound = false;
```

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
