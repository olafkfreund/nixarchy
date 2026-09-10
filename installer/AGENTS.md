# installer/

The ISO, the wizard, and the flake it writes to `/etc/nixos`.

## Intent

Answer a few questions and hand back **a flake the user owns** — a git
repository holding the disk layout, the configuration and the app selection. A
rebuild straight after installing builds nothing, because everything the
installer did is written there rather than done behind it.

This is the least settled part of the project. It writes partition tables and
bootloaders on real disks, it is the hardest thing here to test, and it is where
the bugs have been. The README and the Pages docs say so to users.

| file | what it is |
|---|---|
| `install.sh` | the wizard and the phases; `@tokens@` substituted by `flake.nix` |
| `cd.nix` | the ISO — one module behind both `#iso` and `#iso-net` |
| `mkFlake.nix` | assembles the flake and lock written to the target |
| `template/` | that flake, with its `@tokens@` still in place |
| `host.nix` | the installed machine's own configuration |
| `lib/ui.sh`, `lib/dashboard.sh` | the screens; no gum widget without a pty |
| `try.sh` | `nix run …#try` — boots the real ISO in a local VM |
| `try-nixarchy.sh` | the same, for a machine with no nix — see below |

## The phase chain

```
format_disk → verify_subvolume_mounts → generate_hardware_config
  → install_flake_dir → write_password_hash → run_install
  → chown_flake_dir → take_factory_snapshot
```

Order is load-bearing. `chown_flake_dir` runs **after** `run_install` because
the user does not exist until `nixos-install` creates it, and chowning by name
before that resolves against the ISO's passwd, not the target's.

## Things that are true and easy to get wrong

- **The install log must never be written to the ESP.** FAT32 has no
  permissions, and the crypt hash would be offline-crackable.
- **No crypt hash may appear in `/etc/nixos`** — it is a git repository the user
  is expected to push. The hash goes to `/var/lib/nixarchy`, `chown 0:0`, `0600`,
  and `checks.install` asserts no `$6$` appears under the flake.
- **Verify disks by serial, never by letter.**
- **`/etc/nixos` belongs to the installed user**, and root without `SUDO_UID`
  cannot open a git repository it does not own — which is why `modules/nixos.nix`
  and `cd.nix` both ship a `safe.directory` entry. nix hits the same check and
  reports it as `could not find a flake.nix file`.
- **A flake in a git worktree sees only tracked or staged files.** The installer
  stages everything and deliberately makes no commit: git needs an identity, and
  choosing the user's is not the installer's business.

## An offline install COPIES a system; it does not evaluate one

This changed in #436 and the file described the old model until #507. If you
are reading `installer/` to understand how an install works, this is the part
that surprises people.

The image bakes the reference toplevel through **`isoImage.storeContents`**
(`cd.nix:657`) — outputs, not a build graph — and writes
`/etc/nixarchy-reference-$encrypt` naming it (`cd.nix:897`). `install.sh:2501`
reads that marker, validates the path with `nix path-info`, and hands it to
`nixos-install --system`, which **copies and never evaluates**
(`nixos-install.sh:266` skips the build entirely).

And it is asserted rather than hoped: when the system was copied rather than
built, `install.sh:2569` adds `--max-jobs 0`, so a single attempted build
fails loudly instead of quietly reaching for a compiler.

**`system.extraDependencies` cannot do this job**, and the file used to imply
it could. Its type is `listOf pathInStore` — it carries runtime OUTPUT paths
and cannot carry a build graph, which is why every probe said "present" while
nix still rebuilt the world.

Three things follow, and each is load-bearing:

- **The toplevel must be identical across machines**, or the copy has nothing
  to copy. `networking.hostName = ""` and a pinned `system.name`
  (`host.nix:209`) are what make that true — `systemd/initrd.nix:597` writes
  the hostname into the initrd unconditionally, so two machines differing only
  in name have two different initrds, and offline a different initrd is a
  build that ends in the stage0 source bootstrap.
- **The installed machine boots the REFERENCE's initrd**, so a storage driver
  the reference lacks is a machine that cannot find its root.
  `checks.reference-initrd` compares the two lists and fails on a gap.
- **The detected `hardware-configuration.nix` is still written** to
  `/etc/nixos` for the first ONLINE rebuild to pick up. It simply stops being
  an install-time input.

The password follows the same rule for the same reason: it is a **file**
(`/var/lib/nixarchy/password.hash`, `host.nix:181`), not an evaluation input,
so two machines with different passwords are still the same closure.

## Tests

| check | covers |
|---|---|
| `install` | blank disk, and the machine boots |
| `free-space` | installing beside an existing OS |
| `install-encrypted` | LUKS, unlocked over the serial console |
| `install-iso` / `-net` | the real published image; `-iso` with no network device at all |
| `installer-from-repo` | `--from-repo`, installing a host out of the user's own repo |
| `installer-wizard` | the questions themselves, answered over a serial line |
| `installer-ui` | gum widgets at every terminal width |
| `installer-refusal` | that it refuses, in sentences, rather than crashing |
| `installer-store-space` | the live store's ceiling, which `install` cannot see |
| `installer-lock` | the generated lock has the fields nix would have written |
| `dashboard-clock` | a clock that goes backwards mid-install |
| `try-preflight` | every refusal path of the `#try` front door |

<a id="try-nixarchy-sh"></a>
## `try-nixarchy.sh` — the front door with no nix behind it

`try.sh` is the better door and cannot serve everyone: it is a `nix run` app,
its qemu and OVMF paths are substituted from the store at build time, and it
makes fourteen `nix` calls. Somebody on Ubuntu who wants to look at nixarchy
has to install Nix first, which is a larger commitment than the thing they
were evaluating.

So this one needs `qemu` and `curl` from the distribution and nothing else. It
downloads the published release image, verifies it against the release's own
`SHA256SUMS`, and boots it in a UEFI VM.

What it does NOT do, and `try.sh` does: resolve the image from the commit you
asked for. This one can only take the latest release, because that is all a
machine without nix can fetch. Anybody who has nix is pointed at `#try`,
including from the missing-firmware refusal — telling a NixOS user to
`apt install ovmf` is the least useful thing it could say.

Three things it must keep doing:

- **Verify the download.** A truncated image does not announce itself; it boots
  halfway and fails as something else. The verdict is asserted as an explicit
  `: OK` line for that exact file, not by the exit status of a pipeline —
  `sha256sum -c … | grep "$iso"` matches the `FAILED` line just as happily as
  the `OK` one, and refuses only because `pipefail` carries the status out of
  the pipe. That is one `set` away from silently accepting a corrupt image.
- **Refuse in sentences, naming the number and the way out.** Missing tools
  name the package for four distributions, because "install qemu" is not one
  command anywhere. The memory refusal prints both numbers and a `--memory`
  value that would work.
- **Never silently reuse or wipe the disk.** It may hold an install somebody
  spent twenty minutes on; `--boot` and `--fresh` are offered instead.

`checks.try-nixarchy` drives every one of those refusals with stubs, in
seconds. It invokes the script as `bash ./try-nixarchy.sh` throughout: the
sandbox has no `/usr/bin/env`, so the shebang — which is correct for the
machines this script is actually for — cannot resolve there.
