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

## Docker

Docker and Docker Compose are enabled by `virtualisation.docker.enable`,
which nixarchy sets by default, and Lazydocker is on `Super + Shift + D`.

As upstream, your user is not in the `docker` group, for the reason upstream
gives: the group is effectively passwordless root. Use `sudo docker`, and the
Docker TUI asks for authorisation through polkit when it needs the socket.
_Setup > Security > Sudoless Docker_ (`omarchy-setup-security-sudoless-docker`)
adds you to the group after its warning. To make that choice part of your
configuration rather than a one-off, the declarative form is:

```nix
users.users.<you>.extraGroups = [ "docker" ];
```

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
