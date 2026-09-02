# Secrets, and the convention a bundled service follows

This is the contributor-facing note. The copy-pasteable user instructions
belong in `docs/manual/`, which is not this file.

nixarchy carries a declarative secrets mechanism — sops-nix, imported by
`modules/nixos.nix` — and it is deliberately the smallest thing that works.
It exists so the services nixarchy *bundles* can consume a secret. It is not
a user-facing secrets product and there is no wizard.

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
an RDP daemon with no password, and it must assert with a message naming the
three commands (read the host pubkey → add it to `.sops.yaml` → `sops edit`)
rather than let a rebuild succeed into that state. Never make the service
start passwordless as a convenience for the first-boot case.

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
