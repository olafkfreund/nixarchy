---
status: approved
issue: 1217
author: olafkfreund
---

# Intent: a machine installed offline can still rebuild offline after a collection

## Outcome after measuring (2026-10-08) — premise false, closed as documented

The premise below does not hold. An offline install builds nothing: it copies
the reference toplevel with `nixos-install --system` (`installer/install.sh`,
the `/etc/nixarchy-reference-*` branch), and the per-machine initrd is identical
across machines since stage 1 (`networking.hostName = ""`, `installer/host.nix`).
The build environment the ISO seeds is in the *image's* closure, not the
installed system's: two local reference toplevels (rev 494ce7f, ~2,500 paths
each) contain no `stdenv-linux`, `kmod-*-dev`, `microcode-*` or `gnumake`. So
the parts never reach the target store, there is nothing for a collection to
remove, and `keep-derivations`/`keep-outputs` would keep nothing.

The real gap — no offline rebuild at all after an offline install — is by
design (the hardware configuration arrives with the first rebuild, #435). The
approver chose to document it rather than root a build environment in every
installed machine: one paragraph in `docs/manual/the-iso.md`. No spec or plan
follows; that change is below the workflow's threshold.

## Problem

The offline ISO installs a prebuilt reference closure (#436). Some derivations
are per machine, though: the systemd initrd embeds the hostname, and etc,
units and the toplevel follow the user's choices. Those are built on the target
during the install, from parts the image seeds for exactly this purpose:
stdenv, `kmod.dev`, both microcode packages, the module tree, and the reference
`inputDerivation`s (`installer/cd.nix`, `buildInputsOfWhatChanges`).

After the install, nothing references those parts. `installer/host.nix` sets
`min-free`/`max-free`, so the first time the disk is under pressure the
collection may delete them. From then on, an offline `nixos-rebuild` of even a
small change (a hostname, a toggle that touches etc) cannot find its build
inputs. Nix does not degrade; it builds them, walks back to the stage0 source
bootstrap, and fails. `cd.nix` measured that failure on the ISO itself.

#701 already solved the evaluation half: input sources are kept through
`system.extraDependencies`, so the machine can evaluate `/etc/nixos` offline.
Nothing keeps it able to build.

**This is a hypothesis, not yet measured.** It is unverified that the parts
really end up unrooted in the target store, that the GC removes them, and that
a rebuild then fails. Measuring that comes first; if the premise is false, the
task closes with that finding.

## Proposed outcome

A machine installed from the offline ISO, after a full garbage collection, can
`nixos-rebuild` a configuration change of the kind the installer itself
produces (hostname, user, disk-independent toggles) with no network, the same
way the install did.

A machine installed from the network image is unaffected, apart from a
negligible amount of disk.

## Affected users and systems

- Installed hosts: `installer/host.nix` (the generated machine's base config).
- Possibly `modules/nixos.nix`, if the setting belongs to every nixarchy
  machine rather than only to installed ones (Mode A says it must not, unless
  it is opt-in).
- Users on air-gapped or intermittently connected machines, which is who the
  offline ISO is for.

## Constraints

- Must not set `substitute = false` anywhere. `nixos-install` copies from the
  live store as a substituter (`cd.nix`, the `tarball-ttl` note).
- Must not change anything for a Mode A user who imports `nixosModules.nixarchy`
  into their own configuration (CLAUDE.md §7).
- Must fit the 32 GiB minimum disk (#708). The cost of `keep-outputs` on a
  machine that built locally is unmeasured and has to be measured before this
  ships.
- Must not grow the ISO beyond `checks.iso-budget`.
- Needs a check that fails without the fix (§1, §2), at the cheapest layer
  that can see it. A full install VM is the expensive end of that, and local VM
  runs are restricted to an idle CI (§6).

## Open questions

1. Scope: only machines installed from the offline ISO (gated on the
   `nixarchy-iso` marker or an installer option), or every installed machine?
   On a machine that substitutes everything the cost is close to zero, which
   argues for every installed machine.
2. Is `keep-derivations` + `keep-outputs` (the Discourse approach) the right
   mechanism, or should the seeded parts be rooted explicitly through
   `system.extraDependencies` on the installed host, the same way #701 roots
   the input sources? The second is narrower and has a known size; the first
   also keeps whatever the user builds locally later.
3. Is "offline rebuild after install" a goal the project wants to commit to,
   or only "offline install"? If only the latter, the right outcome is a
   sentence in the manual saying so, and closing #1217.
