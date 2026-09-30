---
status: draft
issue: 1076
author: olafkfreund
---

# Intent: Fix the code review's critical findings, and the highs in the same places, in one PR

## Problem

The 2026-09-30 code review (`Codereview` label) found three critical defects.

- **#1076: a declarative MicroVM guest can get root on the host.**
  - `modules/microvm/guest.nix` shares the VM's own state directory
    read-write as `hostdir`.
  - The guest owns `current` in that directory, and upstream's
    `ExecStopPost` runs `current/bin/microvm-unregister` as root.
- **#1077: `install.sh --from <repo> --host <new>` can run another machine's
  disk layout.**
  - In the interactive wizard, the typed hostname replaces `--host`.
  - `format_disk` then builds that name's disko script.
- **#1078: an offline-ISO install into free space does not boot.**
  - The baked reference system is chosen by encryption alone.
  - That system mounts whole-disk partition labels that a free-space
    install never creates.

Each one either compromises a host, wipes the wrong layout, or leaves a
machine that does not boot. Each was verified against the code. None has a
check that could see it: the #1078 path is never taken in CI, and nothing
boots a hostile guest.

The review also found highs in exactly the same code:

- **#1079, installer secrets:**
  - `#` truncates passwords;
  - secrets appear in argv;
  - an HTTPS answers URL can redirect to HTTP;
  - the answers file is left in `/tmp`.
- **#1084, installer robustness:**
  - a retry can never succeed;
  - `exit 1` skips the failure screen;
  - `--from` never names the disk.
- **#1082:** the install gate skips PRs that touch `vm-cleanup`.
- **#1083, Mode A and MicroVM isolation:**
  - `microvm.host.enable` is forced off;
  - the Hyprland module is imported unconditionally;
  - the agent template's egress can be bypassed;
  - SSH is set by plain assignment.

The owner wants as many as possible in one PR. Every fix to install
behaviour costs a self-hosted install run, and several PRs would queue them
one behind another for hours.

## Proposed outcome

One PR, which closes each issue it fully fixes:

- **No path from a MicroVM guest to host root.**
- **The installer only formats with the machine's own disk layout**, and on
  `--from` it names the disk before erasing it.
- **An offline free-space install boots.**
- **The installer's secrets:**
  - never appear in argv;
  - never travel over plain HTTP;
  - never survive a failed run in `/tmp`;
  - keep a `#` intact.
- **A retry works, and a failure always reaches the failure screen.**
- **CI runs the install check** whenever the install tests' own helpers
  change.
- **Mode A users keep their own MicroVM host and Hyprland**, and the agent
  template's egress filter holds.

Each fix has a check that fails without it (§1), at the cheapest layer that
can see it (§2, §3), or a named hole where nothing can.

## Affected users and systems

- Everyone who installs from the ISO (online and offline, whole-disk and
  free-space), or with `--from` and answers files.
- Everyone with declarative MicroVMs (`services.microvm`), and anyone using
  the `agent` template.
- Mode A users who import `nixosModules.nixarchy` into an existing
  configuration.
- The files involved: `installer/install.sh`, `modules/microvm/`,
  `modules/services/microvm.nix`, `modules/nixos.nix`,
  `.github/scripts/pr-touches-build.sh`, `tests/`, and possibly
  `installer/cd.nix` and `flake.nix` (the reference variants).

## Constraints

- **Destructive-disk code:** every change is proven on the VM install checks
  (`install`, `free-space`, `installer-refusal`). A change that cannot be
  exercised in a VM says so.
- **Mode A stays untouched** by anything opt-in, and `checks.options` stays
  green in both states.
- **`.github/scripts/pr-touches-build.sh` is CI-gate territory (§11).** The
  owner merges it, which this request covers.
- **Upstream microvm.nix is not patched.** The fix is in how nixarchy
  configures shares.
- **One PR is the goal, but not at any price.** If one fix turns out to need
  a design decision the others do not, it drops out to its own PR rather than
  holding the rest.

## Open questions

1. **Scope.** Default proposal: the three criticals, plus #1079, #1082,
   #1083 and #1084. #1085 (Bluetooth), #1086 (`nixarchy secret`) and the
   mediums stay out: they are different code and would widen the review
   without saving an install run.
2. **#1078: build or bake?** Default proposal: fall back to building when
   `disk_mode=free`. That is a one-line guard and correct now; offline
   free-space then needs the network or is slow. Baking free-space reference
   variants doubles the ISO's reference closures against the ~0.9 GiB
   headroom. Alternatively, refuse free-space on the offline image and say
   why.
3. **#1076: where the persistent share lives.** Default proposal:
   `/var/lib/microvms/<name>/share`, created by nixarchy and owned by the
   `microvm` user, mounted at the same `/mnt/host` in the guest so templates
   are unchanged. Existing VMs' files in the old location are not migrated;
   the release notes say where they were.
