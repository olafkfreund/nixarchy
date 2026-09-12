# Secrets, and the convention a bundled service follows

This is the contributor-facing note. The copy-pasteable user instructions
belong in `docs/manual/`, which is not this file.

nixarchy carries a declarative secrets mechanism -- sops-nix, imported by
`modules/nixos.nix` -- and the mechanism itself is deliberately the smallest
thing that works. It exists so the services nixarchy *bundles* can consume a
secret.

**This file used to end that paragraph with "it is not a user-facing secrets
product and there is no wizard". #611 made that false, deliberately, and the
sentence is replaced rather than left standing.** The reasoning for the change
is worth as much as the reasoning for the original position:

- The mechanism has now proved itself on a real service. hypr-rdp consumes a
  secret through `sops.templates` and has done since #154, which is the
  evidence the original scope cut was waiting for.
- The cost of using it was five manual steps in
  `docs/manual/remote-desktop.md`, of which two -- `ssh-keyscan | ssh-to-age`
  and hand-writing a `.sops.yaml` creation rule -- are ceremony a command can
  do exactly as well and more reliably. Neither `sops` nor `ssh-to-age` was
  even on PATH; the manual shelled them in with `nix-shell -p`.
- Five steps on a desktop is not a scope decision, it is a wall.

What #611 did NOT change: nixarchy still sets no sops option of its own, the
module is still imported inertly, and the mechanism underneath is exactly the
one described below. `nixarchy secret` (`pkgs/secret.nix`) is a command in
front of sops; it is not a second mechanism, and nothing in the module system
depends on it existing.

## Why there is one at all

There was not one for a long time, on purpose. #121 declined to adopt
declarative secrets, calling it "a separate decision with a key-management
story attached". #122 then got away without one because
`users.users.<name>.hashedPasswordFile` is consumed by NixOS itself, so the
cleartext could sit outside git and be pointed at.

hypr-rdp (#154) removes that dodge, and it is worth being precise about how,
because the precision is what chooses the tool. Verified against v0.1.5:

- `src/config.rs` resolves the password as `args.password.or(config.password)`
  and from nowhere else.
- `-p/--password` is therefore a command-line argument, which is readable by
  every process on the machine via `/proc/*/cmdline`.
- The only other source is `password = "..."` inline in `config.toml`.
- There is no `password_file` option, and clap reads no environment variable
  for it. (The only environment variables the binary reads at all are VA-API
  and AVC444 debug knobs, `HOME`, `HYPRLAND_INSTANCE_SIGNATURE` and
  `XDG_RUNTIME_DIR`.)

So the secret has to end up **inside a config file**, not beside it, and
something has to put it there at runtime from material that is safe to commit.

That is what picks sops-nix over agenix. agenix delivers files containing raw
secrets and has no templating, so composing one into a TOML would need a
hand-rolled `ExecStartPre` shim per service — the exact hack this mechanism
exists to avoid. `sops.templates` is that shim, upstreamed, with owner and
mode declared. Everything else between the two is close enough to be taste.

## The convention

One policy file at the repository root, one encrypted file per host:

```
.sops.yaml                      creation rules: which recipients get which file
hosts/<name>/secrets.yaml       that host's secrets, encrypted
```

The layout matches the one #121 established for generated config repos. The
recipient is the host's own **SSH host key**: sops-nix converts
`/etc/ssh/ssh_host_ed25519_key` to an age identity itself, and
`sops.age.sshKeyPaths` already defaults to the ed25519 keys from
`services.openssh.hostKeys`. nixarchy sets no sops option of its own, and
should keep it that way — there is no separate keypair for anyone to mint,
shepherd or lose.

## The ordering constraint, which is real

A machine's SSH host key is generated on **first boot**, so a secret cannot be
encrypted to a machine that does not exist yet. An ISO install therefore
always has one rebuild in which the secret is not yet available. Two things
follow, and both have been checked rather than assumed:

**Without sshd there is no key at all.** `services.openssh` is a
`kind = "plain"` entry in `data/services.nix` — the user opts into it — so on
a default nixarchy machine `sops.age.sshKeyPaths` evaluates to `[]`. Declaring
a secret in that state fails the rebuild at evaluation time, with upstream's
own message:

```
No key source configured for sops. Either set services.openssh.enable
or set sops.age.keyFile or sops.gnupg.home
```

That is a good failure: it is loud, it is early, and nothing starts. With
`services.openssh.enable = true`, `sops.age.sshKeyPaths` becomes
`[/etc/ssh/ssh_host_ed25519_key]` and no assertion fires.

**A module that consumes a secret must assert, because the daemon will not.**
This matters more than it looks for hypr-rdp specifically. Given an empty
password it does *not* refuse to start — `src/config.rs` logs

```
No credentials set (-u/-p). Use -u <user> -p <pass> to require authentication.
```

and then serves the session **unauthenticated**. It fails open. So the module
in `modules/services/` is the only thing standing between a missing secret and
an RDP daemon with no password, and it must assert rather than let a rebuild
succeed into that state. The message says why the rebuild stopped and the
one-line shape of the fix, and points at `docs/manual/remote-desktop.md` for
the commands; it used to name them itself, and #215 is what that cost — two
copies of a workflow, of which the one in the module was the wrong one. Never
make the service start passwordless as a convenience for the first-boot case.

There is a second, sharper edge to this, and it is the one a future reader is
most likely to "simplify" away. The warning above and the actual enforcement
disagree about their operator. `src/config.rs` warns when

```rust
if username.is_empty() || password.is_empty() {
```

but `src/server/mod.rs` decides whether to require credentials at all with

```rust
fn credentials_from_config(username: &str, password: &str) -> Option<Credentials> {
    if username.is_empty() && password.is_empty() {
        None
```

`||` for the warning, `&&` for the enforcement. So the three states are not
two:

| username | password | what happens |
|---|---|---|
| set | set | authentication required, as intended |
| set | **empty** | warns, and still builds credentials -- with an empty password |
| empty | empty | warns, and authentication is switched off entirely |

Only the last of those is the fully open case, which is why it is tempting to
guard on it alone. Do not: the middle row is a login whose password is the
empty string, which is not meaningfully better, and it is exactly what a
secret that exists and renders empty produces. `modules/services/hypr-rdp.nix`
therefore requires BOTH fields to be non-empty, at runtime, in an
`ExecStartPre` that exits non-zero -- an assertion cannot see a secret that
rendered empty or a template sops-nix failed to write. If someone later
relaxes that guard to match upstream's `&&`, this table is the reason not to.

## What a machine that never uses this pays

Nothing, and `tests/options.nix` asserts it rather than trusting the claim.
sops-nix gates both halves of its module on `sops.secrets != { }` and
`sops.templates != { }`, so a machine that declares neither gets no systemd
unit, no activation script and no package. The toplevel derivation of a Mode A
machine is byte-for-byte identical with and without the import.

The lock cost is one node: sops-nix declares exactly one input, `nixpkgs`,
which follows ours. Its `nixConfig` asks for `cache.thalheim.io`, which does
not apply to us — `nixConfig` is honoured only from the flake you invoke, not
from its inputs — so taking this input grants no substituter and no trust.

## The two kinds, which is the whole of #611's design

`nixarchy secret` adds a second kind of secret beside the one above, and the
separation is the design rather than an implementation detail.

**System secrets** are what everything above describes: encrypted to the host's
SSH host key, decrypted by sops-nix into `/run/secrets` as `root:root 0400`,
declared in `hosts/<host>/configuration.nix`, and read by a *service*.

**User secrets** are new. They have their own age identity, live in
`~/.local/share/nixarchy/secrets/`, and are decrypted **to the clipboard**.

The reason they are separate rather than one kind made convenient: `0400
root:root` is correct for a daemon and useless for a person, and the obvious
fix — `sops.secrets.<n>.owner = "you"` on everything — would mean **every
process running as you can read every secret on the machine**. A browser. A
dependency in a dev shell. An agent with a shell tool. The two kinds exist so
that "a service can use it without me" and "I can use it without the service"
are different grants.

Three consequences worth writing down, because each is a place a later change
could quietly undo the design:

- **A user secret can never be handed to a system service.** That is not a
  gap to close; it is the property.
- **The user identity is outside the config repo and outside
  `nixarchy-home-backup`'s allowlist**, because both of those are pushed to a
  git remote. The command says so when it creates one, and the manual says so
  again. It also means losing it loses the store, which is the honest trade.
- **Plaintext reaches the clipboard through a pipe and nothing else.** No temp
  file, no shell variable, no argument. `tests/options.nix` asserts this
  against the built script, because it is a security property and a comment is
  not an assertion.

### The hole this leaves, named rather than papered over

Omarchy's shell records the clipboard in
`~/.local/state/omarchy/clipboard-history.json`, in plaintext. `nixarchy secret
copy` cannot opt out of that — the recorder is a Wayland clipboard watcher in
the shell, and `wl-copy` has no "do not record me" protocol that it honours.
`--paste-once` limits the clipboard to a single paste and does nothing about
the history file.

So the command warns every time, and `docs/manual/secrets.md` says it where a
user will read it. §3's rule applies: a documented hole gets tested by a human,
an undocumented one gets tested by a user. If Omarchy ever grows a sensitive
-content hint, honouring it is the fix.

## Discovery is derived, never declared

`nixarchy secret list` and `nixarchy secret where` answer "what exists" and
"what reads it" by evaluating `nixosConfigurations.<host>.config` and reading
`config.sops.secrets` out of it. Not from a list, and not from a grep — §4 is
this repository's own history of hand-maintained lists failing open.

Two things about how that is implemented, both of which cost time to find:

- **The walk is rooted at `programs.nixarchy.services`, not
  `programs.nixarchy`.** Walking the whole option tree forces
  `apps.nixpkgsConfig`, whose default is
  `{ inherit (pkgs.config) allowUnfree allowUnfreePredicate; }`, and that
  throws `attribute 'allowUnfreePredicate' missing` on a pkgs that sets no
  predicate. **`builtins.tryEval` does not catch that** — it catches `throw`
  and `assert`, not a missing attribute — so wrapping the access in `tryEval`
  is no protection at all. The expression aborted rather than returning
  anything, which is worth knowing before writing the next such walk.
- **A template reference is found by the placeholder, not by the name.**
  `sops.templates.<t>.content` carries `config.sops.placeholder.<name>`, which
  is a hash of the name and not the name, so a grep for the name finds
  nothing. Matching uses `builtins.split` rather than `builtins.match`, because
  a template's content is a whole config file and whether `.` matches a newline
  is not worth betting on.

What is deliberately **out of scope** is suggesting where a secret *could* go.
Scanning the options index for things that want a credential and proposing
wiring is the part most likely to be confidently wrong, and a wrong suggestion
about a secret is worse than no suggestion.
