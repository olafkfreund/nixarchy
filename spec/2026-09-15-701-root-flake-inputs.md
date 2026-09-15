---
status: draft
issue: 701
intent: intent/2026-09-15-701-root-flake-inputs.md
---

# Spec: an installed machine keeps the sources it needs to rebuild itself

## Facts this design rests on

- **The installed host receives `inputs` from the generated flake**
  (`installer/template/flake.nix`) as
  `self.inputs // nixarchy.inputs // { self = nixarchy; }`. `inputs.self` there
  is nixarchy, never the user's flake, so no entry of `inputs` changes when
  `/etc/nixos` is edited. Entries change only when `flake.lock` does.
- **`vm/configuration.nix` imports the same `installer/host.nix`**, with
  nixarchy's own inputs. So `nixosConfigurations.vm` is an evaluation of the
  installed host that a cheap check can read.
- **`installer/cd.nix` already solves this for the install image** with
  `collectInputs` (every input, transitively, as a store path) passed to
  `system.extraDependencies`. That function is local to `cd.nix`.
- **The cost.** On `main` at a62e715, every transitive input is 34 source trees,
  835 MiB of NAR. The three largest (204, 203 and 196 MiB) are separate nixpkgs
  trees, which exist because some inputs do not follow nixpkgs. The generated
  flake has nixarchy follow the user's nixpkgs, so an installed machine is below
  this figure. The upper bound is what is accepted here.
- **Where it was found.** `tests/install.nix:824` evaluates `/etc/nixos`'s
  `nixosConfigurations` on the installed target, offline. On #698 that
  evaluation came after an automatic collection and failed on a download.

## Design

### 1. One `collectInputs`, shared

- **Move it.** `collectInputs` moves from `installer/cd.nix` into the flake's
  `lib` output as `lib.inputSources inputs`. It takes an attrset of flakes, the
  shape a module's `inputs` has, and returns the unique store paths of each
  flake and its inputs, transitively. `cd.nix` calls it as
  `inputSources { flake = source.flake; }`, which is the same walk it does
  today.
- **`cd.nix` calls the shared one.** Its behaviour is unchanged: the ISO's
  `inputSources` are the same paths, which the ISO checks already cover.
- **Why share it.** Two copies of the same walk drift apart, and a drifted walk
  shows up only as a fetch on an offline machine, which is exactly this bug.

### 2. The installed host roots its inputs

`installer/host.nix` adds:

```nix
system.extraDependencies = inputs.self.lib.inputSources inputs;
```

That is: every source reachable from the `inputs` the host was given, `self`
(nixarchy) included, and never the user's flake, which is not in `inputs`.
`extraDependencies` puts the paths in the system closure without installing
anything. A root collection then keeps them, and so does `min-free`'s.

**Answers to the intent's open questions:**

1. **Which inputs.** Everything in `inputs`, transitively. That includes the
   user's own extra inputs, such as `nixpkgs-other` since #693. It excludes the
   user flake's `self`, which never appears in `inputs`. So editing `/etc/nixos`
   does not change the closure, and "rebuilding stays a no-op" holds.
2. **Where.** `installer/host.nix`, which only installed machines import. Mode A
   machines never import it and gain nothing (§7). No option: a Mode A user
   owns their flake and their collection policy, and nothing in nixarchy put
   `min-free` on their machine.
3. **How to prove it.** Both a cheap check and the VM, because each misses what
   the other sees (§2, §3):
   - **`checks.options`, cheap, evaluation only.** The `vm` configuration's
     `system.extraDependencies` contains `inputs.nixpkgs.outPath` and
     `inputs.self.outPath`. A Mode A system (`loaderOff`) contains neither.
     This tests the arrangement, and it is what can run locally.
   - **`checks.install`, the property.** After the existing
     `nixosConfigurations` evaluation at `tests/install.nix:824`, the target
     runs a full `nix-collect-garbage` (not `-d`: generations stay) and then
     the same evaluation again, still offline. It must succeed. Without the
     fix it fails with `unable to download`, which is the #698 failure made
     deterministic instead of dependent on disk pressure.

### 3. The host.nix comment tells the truth

The `min-free`/`max-free` comment says the collection only removes paths
nothing references. That comment gains one sentence: flake input sources are
kept by `system.extraDependencies` above. Otherwise they would be garbage
too, and an offline machine could not evaluate itself (#701).

## Alternatives rejected

- **A bigger test disk.** It hides the case from CI and leaves it on every user
  machine (§3).
- **Re-running #698 until it passes.** The failure depends on free space, so a
  pass would mean nothing (§10).
- **Dropping `min-free`/`max-free`.** It removes real garbage that `nixarchy try`
  leaves behind, and the intent keeps collection.
- **Rooting only nixarchy and nixpkgs.** It reads cheaper, but any other input
  that evaluation needs (home-manager, hyprland's tree) still disappears. It is
  the same bug with a shorter list, and a hand-kept list goes stale on the next
  input added (the reason `cd.nix` collects instead of listing).
- **`nix.registry` or `nixPath` pins.** They root nixpkgs only, and only as a
  side effect of a different feature.
- **A module option for Mode A.** Nothing in the module causes the problem there,
  and an option is surface nobody asked for (YAGNI).
- **A new dedicated VM check.** `checks.install` already boots the installed
  machine offline and evaluates `/etc/nixos`. The collection is a few seconds
  added to that, not a new VM.

## Risks

- **The installed closure grows by up to 835 MiB.** Stated in the PR, and in
  the ISO budget if it moves: `checks.iso-budget` (nightly) measures the
  offline image, which already carries these same sources, so it should not
  move. If it does, that number goes in the PR.
- **`checks.install`'s "a rebuild builds nothing".** The rooted paths are fixed
  by the lock, so the rebuild matches. If it fails, the design is wrong about
  `inputs` and the change is revisited, not the assertion.
- **Evaluation cost.** `inputSources` walks 34 inputs, which the ISO
  evaluation already does. That is measured on `checks.options`' runtime, and
  the number goes in the PR.
- **`checks.reinstall-iso` / `mkUserIso`** use `cd.nix`, whose walk moves to
  the shared function. Covered by the ISO checks CI runs; `reinstall-iso` also
  runs locally and fast.
- **Hosts.** Every installed machine, on its next rebuild after updating
  nixarchy. p620's runners are unaffected: they are not nixarchy-installed.

## Verification

1. **`checks.options` (local).** The new case is green, and red with the
   `extraDependencies` line removed (§1).
2. **`checks.install` (CI).** The collect-then-evaluate step is green. It is
   seen red in CI once, on a commit with the host.nix line removed, and that
   failing output goes in the PR. This costs one extra install run, which is
   the price of a property no local check can reach.
3. **ISO walk unchanged.** Local `checks.reinstall-iso` and `checks.iso-source`
   stay green, and `cd.nix`'s `inputSources` evaluates to the same list before
   and after the move, compared in one tree (§5).
4. **Lint.** `nix fmt -- --ci`, statix and deadnix are clean.
5. **#698.** After merge, #698 is updated onto `main` and its install passes.
