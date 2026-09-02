---
name: devenv
description: >
  REQUIRED for per-project development environments on this Nixarchy machine —
  devenv.nix, devenv.yaml, devenv.lock, and deciding whether a requested tool
  belongs to a project or to the machine. Use when asked to set up a project,
  add a language or toolchain "for this repo", pin a compiler version per
  project, scaffold Node/Python/Go/Rust/TypeScript/React, fix an environment
  that does not activate on `cd`, or work out why a project has a different
  version of a tool than the shell outside it. Triggers: devenv, devenv.nix,
  devenv.yaml, devenv.lock, devenv allow, devenv shell, nixarchy dev init,
  per-project, project environment, direnv, mise, "for this project", "pin the
  toolchain", "activate on cd", "not allowed", languages.*. For installing a
  tool on the machine itself, use the `nixos` skill instead.
---

# devenv Skill

A Nixarchy machine has two independent toolchain systems, and almost every
mistake here is using one where the other belongs.

The system configuration defines the **machine**: one nixpkgs, one set of
versions, rebuilt as a whole, rolled back as a whole. A `devenv.nix` defines
**one directory**: its own nixpkgs, its own lockfile, its own update schedule,
activated when you `cd` in and gone when you leave.

The rule that follows: **a project's toolchain belongs to the project.** Adding
Go to the machine so that one repository can build is how a machine ends up
carrying six languages for four projects, none of them at the version their
repository actually needs.

## Which Rung

| The request | Route |
|---|---|
| A tool for **this project** | `devenv.nix` in the project directory — `nixarchy dev init <preset>` if there is none yet |
| A toolchain for **the machine** | The app selection — `nixarchy-app-enable`, `nixarchy-pkg-add`. That is the `nixos` skill |
| **Try it once** | `nix shell nixpkgs#<pkg>` — and say plainly that it leaves nothing behind |
| `mise use --global <lang>@latest` | Not on this machine. See below |

Rungs 1 and 2 coexist, and inside the project the project wins. Measured on this
machine, with Go both selected system-wide and set in a project's `devenv.nix`:

```
outside the project:  /etc/profiles/per-user/<you>/bin/go   go1.26.7
inside devenv shell:  /nix/store/...-go-1.26.5/bin/go       go1.26.5
```

So a system-wide toolchain is not a reason to skip `devenv.nix`, and a
`devenv.nix` is not a reason to remove the system one. They answer different
questions.

### Why not mise

Upstream Omarchy's Install menu sets languages up with `mise use --global`,
which fetches a prebuilt toolchain into `~/.local/share/mise`. `data/apps.nix`
in this repo rejects that for two reasons, and both still hold: nothing about it
survives into the configuration, and mise's prebuilt binaries are dynamically
linked against paths NixOS does not have, so several of them will not execute at
all. mise is still installed and still fine for anything not covered here — but
it is never the answer to "set up this project".

## Is devenv Even Here

```bash
command -v devenv
```

devenv is an opt-in catalogue entry, not a default — it bundles its own Nix and
is not a small closure. If it is missing:

```bash
nixarchy-service-enable devenv && nixarchy apply
```

or, in the user's own configuration:

```nix
programs.nixarchy.services.devenv.enable = true;
```

That single option installs devenv, adds the `devenv hook` line to bash, zsh and
fish, and trusts `devenv.cachix.org` so the first activation downloads a
toolchain instead of compiling one. Decline the cache with
`programs.nixarchy.services.devenv.binaryCache = false;`.

## Starting a Project

In an empty (or at least `devenv.nix`-less) project directory:

```bash
nixarchy dev init            # lists the presets and what each one costs
nixarchy dev init go
```

Presets: `go`, `node`, `python`, `react`, `rust`, `typescript`. Each one is a
small block of devenv's own option lines, folded into devenv's own scaffold.

It writes four files and runs `devenv allow` for you:

```
devenv.nix     the environment — the preset's lines are already in it
devenv.yaml    which nixpkgs it draws from
devenv.lock    written by the first activation, not by init
.gitignore     devenv's scratch directories
```

**Commit all four.** `devenv.lock` is the reproducibility; the `.gitignore`
devenv writes deliberately does not exclude it.

The first activation fetches `github:cachix/devenv-nixpkgs/rolling` and takes a
while. Once. Do not run it on a machine with no network and conclude something
is broken.

If the directory already has a `devenv.nix`, `nixarchy dev init` refuses and
prints the preset's lines for you to paste. That refusal is correct — do not
work around it by deleting the user's file.

## Editing devenv.nix

**It is the user's file, and it speaks devenv, not nixarchy.** Nothing this repo
ships appears in a project: no helper, no import, no vocabulary of ours. A
`devenv.nix` has to be readable by a teammate who has never heard of Nixarchy,
and editable from <https://devenv.sh/reference/options/> alone.

Common shapes:

```nix
languages.python = {
  enable = true;
  venv.enable = true;
};

packages = [ pkgs.ffmpeg pkgs.jq ];

env.DATABASE_URL = "postgres://localhost/dev";

services.postgres.enable = true;

scripts.test.exec = "pytest -q";
```

Anything that needs real Nix rather than an option is what devenv's examples
repository is for: <https://github.com/cachix/devenv/tree/main/examples>.

Check an edit without entering the shell:

```bash
devenv info       # evaluates the whole module set and prints what you would get
devenv search jq  # packages, resolved against the project's own nixpkgs
```

`devenv info` is the cheap way to catch a renamed or misspelled option — an
option name that does not exist is a perfectly valid Nix string until something
evaluates it.

For something one machine needs and the repository must not carry — a local
path, a personal tool — `devenv.local.nix` is devenv's own escape hatch and is
already in the generated `.gitignore`.

## When the Environment "Does Not Work"

Three causes, in the order they actually occur. Two of them are not the config.

### 1. The session is older than the rebuild

The `devenv hook` line lands in `/etc/bashrc` (or `/etc/zshrc`, or fish's
config) when the rebuild runs. **A shell that was already open has never read
it**, and the hook is guarded, so nothing errors — `cd` into a project simply
does nothing and says nothing. This is the same rebuild-vs-session gap that
catches every other rc change here.

The doctor reports exactly this pair:

```bash
nix run github:olafkfreund/nixarchy#doctor
```

It checks whether the rc the current system installed has the hook, against
whether this session's PATH has `devenv`. "devenv is selected but not on this
session's PATH" means: log out and back in. Nothing is wrong with the project.

### 2. The directory is not trusted

A `devenv.nix` is code that runs on `cd`, so devenv will not activate a
directory nobody has allowed:

```bash
devenv allow      # trust this directory
devenv revoke     # take it back
```

Unlike cause 1, this one talks — the hook prints `<dir> is not allowed. Run
'devenv allow' to trust this directory.` to stderr once per entry into the
directory. If you see that line, the answer is the line.

The consent database is **per user and per machine**, a plain file at
`~/.local/share/devenv/allowed` (or under `$XDG_DATA_HOME`). It is not in the
repository and cannot be, so a fresh clone, a second machine or a second user
needs `devenv allow` again. That is not the project being broken; it is the
feature working.

### 3. Only now, the config

```bash
devenv info
```

If it evaluates and prints the packages you expected, the environment is fine
and the problem was one of the first two.

## Traps Specific to This Machine

- **Never delete `devenv.lock` to "fix" a broken clone.** The lock is the entire
  reproducibility claim; deleting it makes the failure go away by making the
  project non-reproducible. Read the error instead. If the pins genuinely need
  moving, `devenv update` moves them — deliberately, with a diff you can read.

- **`nixos-rebuild --rollback` does not touch project environments.** Generations
  are a property of the system profile; a devenv environment lives in the Nix
  store and in no generation at all. Rolling the system back leaves every
  project exactly where it was. The project's own undo is git:

  ```bash
  devenv update              # move this project's pins forward
  git checkout devenv.lock   # and back, because it is a tracked file
  ```

- **Project store paths are not collected with the system's.** devenv keeps its
  own GC roots under `~/.local/share/devenv/gc`, one per shell generation, and
  they accumulate. `devenv gc` is yours to run; `nix-collect-garbage` alone will
  not reclaim them.

- **devenv does not evaluate through the `nix` on your PATH.** It links its own
  Nix libraries — devenv 2.2.2 here carries Nix 2.34. So `devenv shell` failing
  while `nix build` works (or the reverse) is a question about two different
  Nixes, not evidence that anything is corrupt. `devenv version` and
  `nix --version` are the first two commands, not the last.

- **A project is a second nixpkgs.** `devenv.yaml` names
  `github:cachix/devenv-nixpkgs/rolling`, which moves on its own schedule and is
  not the one the system builds from. Expect the same package to differ by a
  patch version inside and outside — that is the design, not drift to correct.

## Hand-offs

- Installing something **on the machine** → the `nixos` skill.
- A **daemon or systemd unit** the machine runs → the `nixos-services` skill.
  A `services.postgres` inside `devenv.nix` is a process for this project only;
  it is not a system unit and will not start at boot.
- A **secret** in a project's `.env` → the `nixos-secrets` skill. Do not put a
  credential in `devenv.nix`: it is committed, and it is world-readable in the
  Nix store besides.
- **The machine misbehaving** rather than the project → the `nixos-doctor` skill.

## Rules

- **Read `devenv.nix` before editing it.** It is a file a team shares.
- **Never invent a nixarchy option in a project.** If the answer is not in
  devenv's reference or its examples, it is a Nix expression in their file, not
  a helper from ours.
- **Do not add a language to the system to fix one repository.** That is the
  whole point of rung 1.
- **Say which rung you chose and why**, in one line, before doing it. The choice
  is the part the user cannot easily undo later.

## Example Requests

- "Set up this project for Go" → `nixarchy dev init go` in the directory
- "Add ffmpeg to this project" → `packages = [ pkgs.ffmpeg ];` in `devenv.nix`
- "Install Node for me" → ask which rung. Machine-wide is the `nixos` skill; for a repository it is `nixarchy dev init node`
- "cd does nothing" → doctor first (stale session), then `devenv allow`, then `devenv info`
- "Just delete devenv.lock, it's broken" → no. Read the error; `devenv update` if the pins must move
- "Roll back, the project broke" → a system rollback will not touch it; `git checkout devenv.lock`
- "Use mise to install Python 3.12" → not on this machine; `nixarchy dev init python`, then `languages.python.version`
- "Why is `go version` different inside this folder?" → it is supposed to be; the project pins its own
- "Put the API key in devenv.nix" → NOT this skill. Use `nixos-secrets`
