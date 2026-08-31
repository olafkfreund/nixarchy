---
name: nixos-secrets
description: >
  REQUIRED whenever a password, API key, token, certificate, private key or any
  other secret has to reach this NixOS machine's configuration. Use when asked to
  store a secret, add an API key, set a service password, encrypt something in the
  config repo, set up sops-nix or agenix, rotate or share a key, give a systemd
  service a credential, or review a config for leaked secrets. Triggers: secret,
  password, API key, token, credential, agenix, sops, sops-nix, age, .age, SOPS,
  ssh key, private key, .env, environmentFile, hashedPasswordFile, "world-readable
  store", "don't commit the password", encrypt, decrypt, rotate, GPG, ACME key.
  For the service that consumes the secret, use the `nixos-services` skill.
---

# NixOS Secrets Skill

**The one fact everything here follows from: `/nix/store` is world-readable, and
every build input ends up in it.**

```nix
services.foo.password = "hunter2";        # WRONG. Always. No exceptions.
```

That string is now in a store path any user on the machine can `cat`, it is in
the closure, it is in every binary cache the machine pushes to, and if the flake
is a git repo it is in the history forever. Deleting the line does not undo any
of that.

The same applies to `builtins.readFile ./secret` — reading a file *into* Nix
copies it to the store. Reading it **from Nix**, by path, at runtime, is fine.

## The Decision, in Order

Stop at the first one that fits.

| Situation | Use |
|---|---|
| It is a password *hash* for a user account | `users.users.<n>.hashedPasswordFile` |
| A single machine, secret never needs to be in the repo | A file in `/var/lib/...`, referenced by path |
| Secrets live in the config repo, one or two machines, SSH-key based | **agenix** |
| Many machines/users, key rotation, partial-file encryption, non-Nix consumers too | **sops-nix** |
| A secret only one systemd service needs, at runtime | `LoadCredential=` |

Do not reach for an encryption framework for a single secret on a single laptop
that is never committed. A `0400` file in `/var/lib` and a `*File` option is a
complete, correct answer.

## Before Anything: Does the Option Take a File?

Almost every NixOS module that wants a secret offers a `*File` / `*Path` variant
precisely so the value never enters the store. **Look for it first** — it makes
the whole problem trivial.

```bash
nixarchy-search services.foo          # scan the option list for File/Path
man configuration.nix                 # /passwordFile
```

```nix
services.foo.passwordFile     = "/run/secrets/foo-password";
services.foo.environmentFile  = "/run/secrets/foo.env";
users.users.alice.hashedPasswordFile = "/run/secrets/alice";
```

If a module takes **only** a plain string, say so out loud rather than quietly
inlining the secret. The honest workarounds are, in order: a systemd
`LoadCredential` + a wrapper, an `environmentFile` on the generated unit, or
patching the module. Never "just this once" in a `.nix` file.

## agenix

Encrypts each secret to a set of **age or SSH public keys**. Decryption happens at
activation using the machine's SSH host key — so no passphrase, no unlock step,
and a machine can only read what it was encrypted to.

### Set up

```nix
# flake.nix
inputs.agenix.url = "github:ryantm/agenix";

# in the nixosSystem modules list
modules = [ inputs.agenix.nixosModules.default ];
environment.systemPackages = [ inputs.agenix.packages.${system}.default ];
```

`secrets.nix` at the root of the secrets directory declares who can read what.
**This file is not imported by the config** — it is read by the `agenix` CLI only:

```nix
let
  alice   = "ssh-ed25519 AAAAC3Nza...";           # from ~/.ssh/id_ed25519.pub
  machine = "ssh-ed25519 AAAAC3Nza...";           # from /etc/ssh/ssh_host_ed25519_key.pub
in
{
  "foo-password.age".publicKeys = [ alice machine ];
  "wifi.age".publicKeys         = [ alice machine ];
}
```

Get the host key with:

```bash
cat /etc/ssh/ssh_host_ed25519_key.pub                    # local
ssh-keyscan -t ed25519 <host>                            # remote
```

**Always include your own user key.** Encrypting only to the host key means the
secret can never be edited again from anywhere else, and is unrecoverable if the
machine dies.

### Use

```bash
agenix -e foo-password.age      # opens $EDITOR; encrypts on save
agenix -r                       # re-encrypt everything after changing secrets.nix
```

```nix
age.secrets.foo-password = {
  file  = ../secrets/foo-password.age;
  owner = "foo";          # default "0" (root)
  group = "foo";
  mode  = "0400";         # default
};

services.foo.passwordFile = config.age.secrets.foo-password.path;
```

- `.path` defaults to `/run/agenix/<name>` — **always reference `.path`**, never
  hardcode it.
- `age.identityPaths` sets which keys decrypt; it defaults to the host SSH keys.
  (It was renamed from `age.sshKeyPaths`; the old name still works with a warning.)
- The `.age` files are safe to commit. That is the entire point.

## sops-nix

Same job, more machinery — worth it for many machines, many contributors, key
rotation, or when non-Nix tooling reads the same secrets file.

```nix
inputs.sops-nix.url = "github:Mic92/sops-nix";
modules = [ inputs.sops-nix.nixosModules.sops ];
```

`.sops.yaml` at the repo root maps paths to keys:

```yaml
keys:
  - &alice   age1xxxxxxxx...
  - &machine age1yyyyyyyy...
creation_rules:
  - path_regex: secrets/[^/]+\.yaml$
    key_groups:
      - age: [*alice, *machine]
```

Derive a machine's age key from its SSH host key:

```bash
nix shell nixpkgs#ssh-to-age -c \
  sh -c 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```

```bash
nix shell nixpkgs#sops -c sops secrets/example.yaml    # edit; encrypted on save
```

```nix
sops.defaultSopsFile = ./secrets/example.yaml;
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

sops.secrets."foo/password" = {
  owner = "foo";
  mode  = "0400";
};

# Or a whole env file for a service:
sops.templates."foo.env".content = ''
  API_KEY=${config.sops.placeholder."foo/api_key"}
'';

services.foo.passwordFile   = config.sops.secrets."foo/password".path;
services.foo.environmentFile = config.sops.templates."foo.env".path;
```

Secrets land under `/run/secrets/`. Reference `.path`, never the literal.

**sops encrypts values, not keys.** The YAML structure stays readable in git,
which is good for review and means a secret's *name* is public. Do not put
sensitive information in the key names.

## systemd Credentials

No framework, no flake input, and the secret is only visible to one service:

```nix
systemd.services.foo.serviceConfig = {
  LoadCredential = "password:/run/secrets/foo-password";
};
# the service reads $CREDENTIALS_DIRECTORY/password
```

The file is exposed in a per-service tmpfs, unreadable by every other unit, and
gone when the service stops. Combine it with agenix/sops for the at-rest half.

## Bootstrapping and Handling

The chicken-and-egg: agenix and sops decrypt with the SSH **host** key, which
exists only after the machine is installed. On a fresh install, either

- install first, take the new host key, encrypt to it, then rebuild; or
- copy a prepared host key into place during install (`nixos-anywhere` and
  `disko` do this), before the first activation.

Getting a secret onto a machine by hand, without leaving it in shell history or a
world-readable temp file:

```bash
sudo install -m 0400 -o foo -g foo /dev/stdin /var/lib/foo/password <<'EOF'
the-secret
EOF
```

The leading space before a command keeps it out of zsh history when
`HIST_IGNORE_SPACE` is set — do not rely on that for anything important.

## Auditing and Leaks

Check a config before committing, and check an inherited one:

```bash
# Anything secret-shaped assigned a literal string
grep -rnE '(password|secret|token|apiKey|api_key|key)\s*=\s*"' --include='*.nix' .

# What actually reached the store for a built system
nix eval --raw <flake>#nixosConfigurations.<host>.config.system.build.toplevel \
  && grep -rl 'suspected-secret' /nix/store/*-etc/ 2>/dev/null
```

**A leaked secret is rotated, not deleted.** If a secret was ever committed, ever
built, or ever pushed to a cache, treat it as public:

1. Rotate the credential at its source (revoke the token, change the password).
2. Only then clean up the repo, if you care to.

Rewriting git history does not un-leak it, and does not help at all if the value
was ever in a store path someone else fetched. Say this plainly to the user
rather than offering a history rewrite as if it were a fix.

## Troubleshooting

```bash
systemctl status agenix.service          # or sops-install-secrets
journalctl -u agenix -b --no-pager
ls -la /run/agenix/ /run/secrets/         # is it there, and who owns it
sudo cat /run/agenix/foo-password          # is it plausible plaintext
```

| Symptom | Cause |
|---|---|
| Activation fails: "no identity matched" | Host key not in `publicKeys`/`.sops.yaml`. Add it, `agenix -r` / re-encrypt |
| Secret file exists, service gets permission denied | `owner`/`mode` wrong. `DynamicUser` services need the right owner or `LoadCredential` |
| Secret empty after reboot, service starts too early | Order the unit `after = [ "agenix.service" ]` (or `sops-nix.service`) |
| `path '/nix/store/...' does not exist` for a `.age` file | Untracked in git. `git add` it |
| Editing a secret fails with no key | Your user key was never added. Someone with access must `agenix -r` after adding it |
| Secret changed but service still uses the old one | Nothing restarted it. `restartUnits` / `reloadUnits`, or restart by hand |

## Rules

- **Never write a secret literal into a `.nix` file**, not temporarily, not to
  "test it first". The store keeps it.
- **Never `builtins.readFile` a secret.** Reference it by path at runtime.
- **Look for a `*File` option before reaching for anything else.**
- **Reference `config.age.secrets.<n>.path` / `config.sops.secrets.<n>.path`**,
  never a hardcoded `/run/...` string.
- **Encrypt to your own key as well as the host's**, or the secret becomes
  unrecoverable and uneditable.
- **A leaked secret gets rotated.** Do not offer history rewriting as the fix.
- Secret *names* are public in both systems. Do not encode anything sensitive in
  the filename or YAML key.
- `.age`/sops-encrypted files belong in git. Plaintext secrets, `.env` files and
  private keys never do — check `.gitignore` before adding anything.
