---
status: approved
issue: 1549
author: olafkfreund
---

# Intent: a declarative sandbox's directories get the modes nixarchy declares

## Problem

The nightly's `checks.microvm-boot` failed on 2026-11-02:

```
AssertionError: #1076: the share is 'microvm:kvm 775', not microvm:kvm 770
```

The night before passed. In between, #1547 moved the `microvm` input from
`4876e2ae` to `b7bd5569`, which carries upstream `c60daaef` ("resolve
relative share paths for tmpfiles"). Our guest declares its share as the
relative `share` on purpose (#1076, `modules/microvm/guest.nix`). Upstream
used to write that literal relative path into tmpfiles, which matched
nothing. It now writes `/var/lib/microvms/<name>/share` with mode `:0775`
into `10-microvm.conf`.

`modules/services/microvm.nix` declares the same path `0770` in
`10-nixarchy-microvm.conf`. When two tmpfiles.d files name one path, the
lexically earliest file wins, and `10-microvm` sorts first. So upstream's
mode is applied and ours is ignored.

The same ordering has been hiding a second problem since before the bump.
Upstream also declares the VM directory, `/var/lib/microvms/<name>`, as
`0775`, and that has always beaten our `0750`. Nothing tests it. That
directory holds `current`, the runner upstream's `ExecStopPost` runs as
root. `programs.nixarchy.user` is in group `kvm`
(`modules/services/microvm.nix:208`), so that user can replace what root
runs. `policy/`, which should be readable but not writable by the guest's
side, sits in the same directory.

## Proposed outcome

- On a host with a declarative sandbox, `/var/lib/microvms/<name>` is
  `microvm:kvm 750`, `share/` is `770`, and `policy/` is `750`, whatever
  upstream's tmpfiles says.
- `checks.microvm-boot` asserts all three, so a later upstream change that
  wins again goes red rather than silent.
- The next nightly is green and #1549 closes. With it, #1550's only red row
  clears.

## Affected users and systems

- Hosts with `programs.nixarchy.services.microvm` machines declared.
  Existing directories are re-moded at the next boot or tmpfiles run.
- `nixarchy vm` user VMs are not affected: they live under
  `$XDG_STATE_HOME`, not `/var/lib/microvms` (`pkgs/microvm.nix:99`).

## Constraints

- No patch to upstream microvm.nix. Ordering our own file first is enough
  and stays in this repo.
- The check must be shown failing against the current ordering before the
  fix (§1).
- The `microvm@` service runs as `microvm`, the directory's owner, so `750`
  must not remove anything it needs. The VM boot in the check proves that.

## Open questions

- Should the VM directory's mode be tightened to `750` as part of this fix,
  or only the share's mode restored? Codex recommended only the share,
  because tightening the directory changes more than the failing check.
  agy recommended all three, for the reason in Problem. Proposed: all
  three, because the `750` was always the declared intent and the gap is a
  root-run file writable by group `kvm`.
