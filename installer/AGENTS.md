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
