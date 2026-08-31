---
name: nixos-config-repo
description: >
  REQUIRED for putting this machine's NixOS configuration under version control
  and keeping it there — git setup, .gitignore, first commit, GitHub/GitLab/other
  remotes, public vs private, CI that checks the config, and the workflow of
  committing config changes. Use when asked to back up the configuration, push it
  to GitHub or GitLab, set up CI for a flake, fix "dubious ownership" or a failed
  push from /etc/nixos, move the config out of /etc/nixos, or when a new .nix file
  is ignored by the build. Triggers: git, GitHub, GitLab, repo, repository, commit,
  push, remote, .gitignore, CI, GitHub Actions, flake check, back up my config,
  version control, "untracked", "does not exist", dubious ownership, nixarchy config repo.
  For encrypting secrets that live in that repo, use `nixos-secrets`.
---

# NixOS Config Repo Skill

A Nixarchy machine ships with `/etc/nixos` **already a git repository** — the
installer runs `git init` and `git add -A`, because a flake in a worktree cannot
see untracked files and the very first `nixos-install` would fail otherwise.

It stops there, on purpose: `git commit` needs a name and an email, and picking
the user's is not an installer's job. So the state you will usually find is:

- a repository, with
- one staged tree, and
- **no commit, no identity, no `.gitignore`, no remote.**

The gap is not "get this into git". It is that the machine's entire definition
has no history and exists on exactly one disk.

## The Short Version

There is a command that does all of this, interactively and idempotently:

```bash
nixarchy config repo          # or: nixarchy-config-repo
```

It detects what is already true and skips those steps, scans for secrets before
the first commit, asks about public vs private, creates the remote via `gh`/`glab`
(fetched on demand — neither is in the closure), and offers an eval-only CI
workflow. **Prefer it over doing the steps by hand**, and use this skill to
explain what it did, to handle a case it does not cover, or to fix something
afterwards.

`nixarchy-config-repo --check` exits 0 only when the nudge is worth showing. It
is what the post-boot hook calls.

## The Two Things That Actually Bite

### 1. Untracked files are invisible to the build

```
error: path '/nix/store/...-source/foo.nix' does not exist
```

or, worse, no error at all — the file is simply absent from the build and the
change appears to do nothing.

**A flake in a git repository sees only tracked or staged files.** A new `.nix`
file that has not been `git add`ed does not exist as far as Nix is concerned.

```bash
sudo git -C /etc/nixos add -A          # before every rebuild, after adding a file
```

This is the single most common reason a NixOS change "does nothing", and it is
worth checking first whenever someone says an edit had no effect.

### 2. `/etc/nixos` is root-owned

```
fatal: detected dubious ownership in repository at '/etc/nixos'
```

The installer leaves it root-owned deliberately, which splits every git command
in two: reads need `safe.directory`, writes need `sudo`.

```bash
git -c safe.directory=/etc/nixos -C /etc/nixos log        # read
sudo git -C /etc/nixos commit -m "..."                    # write
```

Root has no `user.name`/`user.email`, so a `sudo git commit` fails until an
identity is supplied. Pass the user's rather than creating a root one:

```bash
sudo git -C /etc/nixos \
  -c user.name="$(git config --global user.name)" \
  -c user.email="$(git config --global user.email)" \
  commit -m "..."
```

Or set `safe.directory` once and stop thinking about half of it:

```bash
git config --global --add safe.directory /etc/nixos
```

### Moving it out of `/etc/nixos`

Most of the friction above disappears if the config lives in the user's home,
which is what most people end up doing:

```bash
sudo mv /etc/nixos ~/nixos-config
sudo chown -R "$USER:users" ~/nixos-config
```

```nix
programs.nixarchy.flake = "/home/<user>/nixos-config";
```

Then `git` works normally and only `nixos-rebuild` needs `sudo`. Mention this
option when someone is fighting ownership repeatedly — but **do not move it
unprompted**; `NIXARCHY_FLAKE`, `nixarchy-apply` and any existing habit all point
at the old path, and a half-moved config is worse than either.

## .gitignore

The judgement call is what *not* to ignore.

```gitignore
# Build outputs — store symlinks, meaningless elsewhere
result
result-*

.direnv/
*.swp

# Plaintext secrets
*.key
*.pem
id_rsa
id_ed25519
.env
.env.*
secrets/*.txt
```

**Do not ignore `*.age` or sops-encrypted YAML.** Encrypted secrets are *meant*
to be committed — that is the entire point of agenix and sops-nix, and ignoring
them breaks the build on every other machine. See the `nixos-secrets` skill.

**Do not ignore `flake.lock`.** It is what makes the configuration reproducible;
an ignored lock file means a different system on every machine and every clone.

## Before Making It Public

A NixOS configuration is not a secret document, and plenty of people publish
theirs deliberately. What it does contain: hostname, username, SSH **public**
keys, network layout, which services run, and sometimes hashed passwords.

Private is the right default. Public should be a decision.

Scan before publishing, and before the first commit of an inherited config:

```bash
grep -rInE '(password|secret|token|api_?key)[[:space:]]*=[[:space:]]*"' --include='*.nix' .
grep -rn "hashedPassword\b" --include='*.nix' .     # prefer hashedPasswordFile
```

**A secret that was ever committed is leaked** — rotate it, do not just delete
the line. Rewriting history does not help once it has been pushed or built, and
`/nix/store` is world-readable regardless. Say this plainly rather than offering
a history rewrite as a fix.

## CI

Check the configuration on push. **Evaluation, not a full build** — a real system
build takes hours on a free runner and regularly exceeds its disk, while eval
catches renamed options, type errors and typos, which is the overwhelming
majority of what actually breaks.

```yaml
# .github/workflows/check.yml
name: check
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: DeterminateSystems/magic-nix-cache-action@main
      - run: nix flake check --all-systems --no-build
```

GitLab equivalent:

```yaml
check:
  image: nixos/nix:latest
  variables:
    NIX_CONFIG: "experimental-features = nix-command flakes"
  script:
    - nix flake check --all-systems --no-build
```

`--no-build` is doing real work in both: without it, `flake check` tries to
realise every derivation the flake defines.

To evaluate each host by name, so a failure says *which* one:

```bash
nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

That forces the whole module system to evaluate — every option, every assertion —
without building anything. It is the most value per second of CI time available
for a NixOS flake.

Offer a full build only when the user has a cache to push to (Cachix, Attic) or a
self-hosted runner. Without one it is slow, flaky, and usually abandoned.

## The Ongoing Workflow

```bash
cd /etc/nixos
sudo git add -A                       # BEFORE the rebuild — new files must be tracked
sudo nixos-rebuild switch --flake .
sudo git commit -m "what changed"     # after it works
sudo git push
```

Commit messages worth writing say what changed about the *machine*, not the file:
"Enable Tailscale", not "update configuration.nix".

The generation number and the commit are two different histories of the same
thing. Tying them together makes both more useful:

```bash
sudo git commit -m "Enable Tailscale (generation $(readlink /nix/var/nix/profiles/system | sed 's/.*-//'))"
```

Do not `git commit` a broken config to "save progress" and push it — CI will
catch it, but so will the next person who clones it. `nixos-rebuild build` first.

## Other Hosts in One Repo

The natural next step once a config is in git, and worth mentioning when someone
gets a second machine:

```nix
nixosConfigurations = {
  laptop  = nixpkgs.lib.nixosSystem { modules = [ ./hosts/laptop  ]; };
  desktop = nixpkgs.lib.nixosSystem { modules = [ ./hosts/desktop ]; };
};
```

```bash
sudo nixos-rebuild switch --flake .#laptop
```

Shared modules go in `./modules`, per-machine differences in `./hosts/<name>`.
Do not restructure someone's working single-host config into this shape unless
they ask.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `path '/nix/store/...' does not exist` | Untracked file. `sudo git add -A` |
| A new option had no effect at all | Same — the file was never staged |
| `detected dubious ownership` | Root-owned repo. `safe.directory`, or `sudo` |
| `Author identity unknown` under sudo | Root has no identity. Pass `-c user.name=... -c user.email=...` |
| `Permission denied (publickey)` on push | SSH key not on the provider, or you are pushing as root, whose keys are not yours |
| Push rejected, non-fast-forward | Remote has commits yours does not. `git pull --rebase` |
| CI fails, local rebuild works | Almost always an untracked file: it exists locally and not in the clone |
| `gh: command not found` | Not in the closure by design. `nix shell nixpkgs#gh -c gh ...` |

That second-to-last row is worth internalising: **CI is the thing that catches an
untracked file**, because a clone is the only place the missing file is actually
missing. A green local rebuild proves nothing about the repo.

## Rules

- **`sudo git add -A` before the rebuild, not after.** Untracked is invisible.
- **Prefer `nixarchy config repo`** to hand-rolling the setup; it is idempotent
  and it scans for secrets first.
- **Never commit a plaintext secret**, and treat one that was committed as leaked
  and needing rotation — not as something a history rewrite fixes.
- **Never ignore `flake.lock`** or encrypted `.age`/sops files.
- **Default to a private repository.** Public is fine and common, but deliberate.
- **Eval-only CI unless the user has a binary cache.** A full build on a free
  runner is a promise that will not be kept.
- Do not move the config out of `/etc/nixos` unprompted, and do not restructure a
  working single-host flake into a multi-host layout uninvited.
