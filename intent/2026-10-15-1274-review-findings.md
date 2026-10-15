---
status: draft
issue: 1274
author: olafkfreund
---

# Intent: fix the findings from the 2026-10-15 three-model code review

## Problem

A read-only review on 2026-10-15 split the tree three ways. Codex took
`installer/`, agy took part of `modules/`, and Claude took the `pkgs/`
scripts, `.github/scripts` and `share/agent-bus`. Every claim was traced
against the source, and it found sixteen defects plus one plausible one. #1274
lists them. Grouped by what they cost:

**Can erase or break a machine (installer):**

1. An unattended answers file can name the USB the ISO booted from as
   `device`. Only the interactive picker and the `--from` path exclude the
   boot medium (`install.sh:1381`).
2. "Retry with the same answers" always restarts at `format_disk`
   (`install.sh:3285`). If `run_install` succeeded and a later phase failed,
   retrying wipes a working install.
3. The check that the recovery passphrase is not the login password compares
   two independently salted SHA-512 hashes (`install.sh:1441`), so it never
   catches the same passphrase. That passphrase's hash then sits in the initrd
   on the unencrypted ESP.
4. `write_password_hash` (`install.sh:2193`) ignores its writes' status. With
   no recovery hash its return value is the `if`'s, 0, so a failed write still
   passes the phase.
5. `--from` on a free-space host is always refused. Its `disk-config.nix`
   names `by-partlabel` partitions, and `remember_disk` wants whole disks
   (`install.sh:1581`).
6. On the `--from` existing-host path, `password_hash` is only checked for
   being non-empty (`install.sh:1352`).
7. If root-partition creation fails after the ESP was created
   (`install.sh:1704`), the next retry is blocked until the partition table is
   fixed by hand.
8. `try.sh:445`: the dry-run temp file's EXIT trap never fires, because the
   success path `exec`s qemu.

**Breaks a user's own configuration (modules), against Mode A and §14:**

9. `services/open-webui.nix`: `environment` values at plain priority, so a
   user's own `OLLAMA_API_BASE_URL` is a conflicting definition.
10. `fleet.nix`: `system.autoUpgrade` scalars at plain priority. `cfg.url` is
    unescaped in a root script. `url` has no default, so its own assertion
    cannot fire.
11. `auto-update.nix`: the dirty-tree guard tests `[ -d .git ]`, so a git
    worktree (whose `.git` is a file) skips it.
12. `services/tailscale.nix`: trusts a hard-coded `tailscale0`, not
    `services.tailscale.interfaceName`.
13. `services/microvm.nix:205` (plausible): `microvm.host.enable =
    mkDefault (vms != {})` beats upstream's option default even in Mode A, so a
    host running only imperative `microvm -c` VMs loses its host.

**Leaks or loses messages (agent bus):**

14. `hooks/bus-redact.sh`: with no room in a post and no `AGENT_BUS_ROOM` in
    the hook's environment, it assumes the private room and skips the
    network-identity rules. Meanwhile the server, configured as ONBOARDING
    says, posts to the public one.
15. `agent_bus_mcp.py`: `read_new` and `peek` with no cursor read from the
    start of the room, not recent history as documented. Measured live: a
    fresh session's first read returned six-week-old messages.

## Proposed outcome

- An unattended install refuses the boot medium, refuses a recovery
  passphrase equal to the login password, and refuses a malformed hash on
  every path, before anything is formatted.
- A retry after a successful `run_install` finishes the install rather than
  reformatting, and a half-made free-space partition does not block the retry.
- A failed secret write fails its phase.
- `--from` reinstalls a free-space host.
- Each module fix lets a user's own value win, or merge, without an
  evaluation error. The microvm behaviour is documented with the one-line
  escape.
- The redact hook applies the strict rules whenever it cannot prove the post
  is going to the private room.
- A first bus read returns the newest messages.
- Every fix has a check that was seen to fail without it (§1).

## Affected users and systems

Anyone installing from the ISO, especially with an answers file or `--from`.
Machines with `fleet`, `autoUpdate`, `open-webui` or `tailscale` on, and Mode A
users of microvm. Every agent using the bus. No host deploy is involved.

## Constraints

- Mode A untouched: no change may add config when an option is off.
- `mkDefault` on scalars, plain assignment on lists and attrsets
  (`modules/services/default.nix`).
- Cheap checks only, locally, one at a time under the build lock (§6). VM
  checks are left to CI.
- One PR. Codex, agy and Claude share the implementation, and the PR records
  who did which step.

## Open questions

None. The owner approved doing all of them in one PR on 2026-10-15.
