---
title: Secrets
---

# Secrets

A password, an API key, a token, a certificate. Something the machine needs and
nobody else should have.

The rule everything here follows from is that **`/nix/store` is world-readable,
and every build input ends up in it**. Writing the value into your
configuration puts it in a store path any user on the machine can read, in the
closure, in every binary cache the machine pushes to, and — if the flake is a
git repository — in the history forever. Deleting the line afterwards undoes
none of that.

So the value is kept encrypted, in the repository, and decrypted on the machine
at the moment something needs it. nixarchy uses
[sops-nix](https://github.com/Mic92/sops-nix) for that, and
`nixarchy secret` is the command in front of it.

```sh
nixarchy secret new <name>      # create one, and open your editor
nixarchy secret list            # what exists, and what reads each one
nixarchy secret copy            # put one on the clipboard
nixarchy secret where <name>    # what names this one
nixarchy secret edit            # change them
nixarchy secret remove <name>
```

Everything below is also in the menu, under **Setup ▸ Secrets**.

## Two kinds, and why they are not one

This is the whole design, and it is worth thirty seconds before you use it.

| | **system** | **user** (`--user`) |
|---|---|---|
| decrypted by | root, at activation | you, when you ask |
| lands in | `/run/secrets/<name>`, mode `0400` | the clipboard, and nowhere else |
| encrypted to | this machine's SSH host key | an age identity of your own |
| for | a **service** to read | a **person** to paste |
| lives in | `hosts/<host>/secrets.yaml`, in your flake | `~/.local/share/nixarchy/secrets/` |

A system secret is `root:root 0400` on purpose. That is exactly right for a
daemon and useless for a person, and the tempting fix — making them readable by
your own user instead — would mean every process running as you can read every
secret on the machine. A browser. A dependency in a dev shell. An agent. So
there are two kinds: one the machine can use without you, and one you can use
without the machine.

`nixarchy secret copy` reads both. Copying a system secret asks for sudo, and
the picker says which kind each row is.

## A system secret, start to finish

### You need sshd first, and one reboot after it

A system secret is encrypted to `/etc/ssh/ssh_host_ed25519_key`, and NixOS
generates that key only when sshd is enabled — and only on the **first boot
after** that. On a machine installed from the ISO this is always the second
rebuild, never the first.

```nix
# hosts/<host>/configuration.nix
services.openssh.enable = true;
```

Rebuild, then carry on. Without it, `nixarchy secret` says so plainly, and
declaring a secret anyway fails the rebuild at evaluation time — loudly, before
anything starts.

If you would rather not run sshd, `nixarchy secret new --user <name>` needs
none of it. The trade is that a user secret cannot be handed to a system
service.

### Make it

```sh
nixarchy secret new hypr-rdp-password
```

That derives this host's age recipient, writes `.sops.yaml` at the root of your
flake if there is not one, and opens `hosts/<host>/secrets.yaml` in your
editor. The file is plain YAML while you are editing it and encrypted the
moment you save:

```yaml
hypr-rdp-password: something-long
```

### Declare it — this part is yours

The command prints the line and does not write it, because **where** it goes
matters:

```nix
# hosts/<host>/configuration.nix
sops.secrets.hypr-rdp-password.sopsFile = ./secrets.yaml;
```

Not in `~/.config/nixarchy/*.nix`. `nixarchy apply` copies those into
`hosts/<host>/nixarchy/`, so a relative `./secrets.yaml` written there resolves
one directory too deep, and the error you get names a missing path rather than
the reason.

### Stage it, and rebuild

```sh
sudo git -C /etc/nixos add hosts/<host>/secrets.yaml
nixarchy apply
```

A flake in a git worktree sees only tracked files. An unstaged `secrets.yaml`
does not exist as far as evaluation is concerned — the error says the path is
missing, not that it is untracked.

### Point something at it

A nixarchy service that takes a secret takes the **name**, not the value and
not a path:

```nix
programs.nixarchy.services.hypr-rdp = {
  enable = true;
  passwordSecret = "hypr-rdp-password";
};
```

Anything else that wants a file gets the path sops-nix decrypts it to:

```nix
services.something.passwordFile = config.sops.secrets.hypr-rdp-password.path;
```

## A user secret

```sh
nixarchy secret new --user openai-key
nixarchy secret copy openai-key
```

The first call makes an age identity at
`~/.local/share/nixarchy/secrets/identity.txt` if you have none, and encrypts a
store beside it. Nothing about a user secret touches your flake, so nothing
about it is committed, pushed, or visible to anyone with the repository.

**That identity file is the only thing that can read your user secrets.** It is
deliberately outside the configuration repository and outside
`nixarchy home backup`'s allowlist, because both of those get pushed to a git
remote. Copy it somewhere safe yourself. If you lose it, the store is
unreadable and there is no recovery.

### The clipboard is not private

`nixarchy secret copy` never writes the value to disk — it goes straight from
sops into the clipboard through a pipe, and the clipboard clears itself after
one paste.

Omarchy's own clipboard history does write it down. Every string you copy lands
in `~/.local/state/omarchy/clipboard-history.json` in plaintext, and a
clipboard watcher in the shell is not something this command can opt out of.
The command says so each time. Clear the history when you are done with a
secret, and treat that file as sensitive — `nixarchy home backup` already
excludes it for the same reason.

## What do I have, and what reads it?

```sh
nixarchy secret list
```

Two answers, kept apart because they can disagree:

- **Declared** comes from evaluating this machine's own configuration, so it
  cannot drift from what the machine actually does. For each secret it names
  what reads it — an option that names it, or a config file sops renders it
  into.
- **Present** comes from reading the encrypted files. sops encrypts *values*
  and leaves the *keys* in plaintext, so this works with no identity at all —
  and it is why a secret's **name** should not itself be sensitive.

A name declared and not present fails activation. A name present and not
declared is dead weight nothing reads. Neither is visible from one list alone,
so `list` calls out the difference.

`nixarchy secret where <name>` does the same for one secret, and adds a
straight text search of your configuration — that second answer catches a
reference you wrote yourself, which the derived one cannot see.

## One machine

`nixarchy secret` is deliberately about **this machine**. A system secret is
encrypted to this host's key and can be decrypted on this host and nowhere
else, which is the right default and an inconvenience the first time you want
to edit it from your laptop.

Sharing is sops' own job, and its sharpest edge. Add the other recipient to
`.sops.yaml` and rekey:

```sh
sops updatekeys hosts/<host>/secrets.yaml
```

See [sops on adding and removing keys](https://github.com/getsops/sops#adding-and-removing-keys).
nixarchy does not wrap this, because a half-implemented fleet story is worse
than none.

## Before you push

`nixarchy config repo` scans for secrets before it commits anything: values
that look like passwords written straight into `.nix` files, and a
`secrets.yaml` that sops never encrypted. It asks before committing either.

Once a secret is in git history, deleting it later does not remove it.

## See also

- [Remote Desktop](remote-desktop) — the service this mechanism was built for
- [Security](security) — the firewall, disk encryption, and what is exposed
- The `nixos-secrets` agent skill: *"how do I store an API key here?"*
