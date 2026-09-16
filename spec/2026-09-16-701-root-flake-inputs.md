---
status: approved
issue: 701
intent: intent/2026-09-16-701-root-flake-inputs.md
---

# Spec: an installed machine keeps the inputs it needs to rebuild offline

## Design

Re-land #702 as it was proven, on a main where the disk constraint that
reverted it no longer exists.

- **D1. The shared walk.** `collectInputs` moves out of `installer/cd.nix` into
  `lib.inputSources`, and `cd.nix` calls it. It is the same recursion over
  every locked input, transitively: the ISO already depends on it, so this is a
  move rather than a new mechanism. `checks.iso-source` proves the ISO's set is
  unchanged by the move.

- **D2. The installed host roots them.** `installer/host.nix` sets
  `system.extraDependencies = inputs.self.lib.inputSources inputs;`.
  `inputs.self` is nixarchy, never `/etc/nixos`, so what the user edits does
  not change the closure.

- **D3. Root everything, not a subset.** Measured on today's main: 33 input
  sources, **836 MiB** of closure. A fresh 32 GiB install measured 18.4 GiB
  free (#708), so this costs about 4% of the headroom and leaves roughly
  17.6 GiB, far above `max-free` (8 GiB) and `min-free` (3 GiB).

  A subset would have to name which inputs evaluation reaches, and that list
  goes stale on the next bump — with the staleness showing up only as a network
  fetch on a machine that has no network, which is the failure this fixes.
  `cd.nix`'s own comment makes the same argument for the ISO.

- **D4. Two checks, as in #702.**
  - `tests/options.nix` gains `flakeInputsRooted`: on, the input sources are in
    the system closure; off, they are not.
  - `tests/install.nix` collects garbage and then evaluates `/etc/nixos` again,
    offline. That is the user-visible claim, and only a booted install can make
    it.

- **D5. The budget stays asserted.** `checks.install`'s existing free-space
  assertion (at least `max-free` free after install, #708) is what stops this
  from quietly eating the headroom. The measured figure goes in the PR, as
  before and after.

## Alternatives rejected

- **Root only nixpkgs, home-manager and nixarchy.** Smaller, but it is a
  hand-maintained list of what evaluation reaches (AGENTS.md §4: a hand list
  fails open), and it saves about 600 MiB out of 18 GiB. Not worth the
  staleness.
- **A bigger install-test disk.** That hides the case rather than fixing it
  (§3), and it is what the revert of #702 would have amounted to.
- **`keep-derivations`/`keep-outputs`, or a GC root in `/nix/var/nix/gcroots`.**
  Both keep far more than the sources, and a gcroot written at activation is
  state outside the closure — it does not travel with a rollback.
- **Turning automatic collection off.** That trades one failure (cannot rebuild
  offline) for a worse one (the disk fills), and #708 just sized the
  thresholds deliberately.

## Risks

- **Disk cost.** 836 MiB per generation's closure, shared between generations
  that pin the same inputs. Bounded by D5's assertion.
- **The revert's failure mode returns.** It cannot as it did: the floor is
  3 GiB rather than 5, the disk is 32 GiB rather than 20, and Nix 2.35 fixes
  the segfault that turned a collection into a crash.
- **`inputs.self` confusion.** If someone later passes the user's flake here,
  editing `/etc/nixos` would change the closure. The `flakeInputsRooted` case
  pins the attribute that is rooted.
- **Hosts:** every installed machine at its next rebuild. The ISO is unchanged.

## Verification

- `checks.options` `flakeInputsRooted`, red with D2 removed.
- `checks.install`: collect, then evaluate offline — red in CI with D2 removed,
  which #702 already demonstrated (run 34972125482) and this PR repeats on
  today's main.
- `checks.iso-source`: the ISO's input-source set is identical before and after
  the walk moves (34 paths, own source excluded).
- `checks.install`'s free-space assertion still passes, and the PR states the
  measured free space with rooting on.
- statix, deadnix and `nix fmt -- --ci` on the tree **with** the rooting line —
  #702 lost an hour to checking those on the broken tree.
