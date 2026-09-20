---
status: draft
issue: 817
spec: spec/2026-09-20-817-vm-big-is-the-dev-vm.md
---

# Plan: vm-big becomes the VM you keep

Its own branch off `main`, not the #816 branch — this lands first so #816's
pass A can borrow the node rather than invent a second one. One commit per step,
subjects as full sentences (§8).

## Approved decisions, copied so this file stands alone

- **Name unchanged.** `vm-big` is a public flake attribute; the docs carry the
  second meaning instead of a rename.
- **Podman and boxes on by default in it**, not behind a flag: a development VM
  that differs from a real machine in the two services whose panels ship on by
  default is not testing what ships.
- **Rebuild monthly**, written where the disk is described.
- **`.#vm` is not touched.** Its `diskImage = null` is load-bearing: a stale
  disk replayed Omarchy's notification history and made fixed failures reappear
  on screen.
- The 128 GB disk is already enough; no size change.

## Steps

1. **Red first, before any edit** (§1, §3 — an evaluation, the cheapest layer
   that can answer this). Read `vm-big`'s resolved default plugins today and
   capture that `nixarchy.podman` and `nixarchy.distrobox` are **absent**:

   ```
   nix eval --raw .#nixosConfigurations.vm-big.config.home-manager.users.omarchy\
     .programs.nixarchy.plugins --apply 'p: builtins.concatStringsSep " " (builtins.attrNames p)'
   ```

   If the attribute path is wrong the command says so rather than printing an
   empty string — check the output names other plugins, or the "red" proves
   nothing (§1: a break that stays green may be a break that never applied).
   → verify by the two ids being absent from a list that is otherwise populated.

2. **`flake.nix`: turn them on.** `virtualisation.podman.enable` and
   `programs.nixarchy.services.boxes.enable` in `vm-big`'s module list, beside
   `localAi`, with the comment saying this VM matches a real machine because it
   is the one people keep (#817).
   → verify by rerunning step 1's eval: both ids now present.

3. **`docs/internals/flake.md`: say which VM is which.** Around `:1018`–`:1046`,
   keeping the `#the-same-vm-with-room-to-run-a-model` anchor because `flake.nix`
   links it. `vm-big` has a disk, reuses it, and clearing it is yours; `.#vm` is
   stateless on purpose and the reason is repeated here, not only in
   `vm/configuration.nix:127`.
   → verify by reading both accounts side by side and confirming they agree.

4. **The cadence and the disk's home.** In the same place: rebuild monthly,
   `rm nixarchy-vm-big.qcow2 && nix run .#vm-big`, disk under
   `/mnt/data/vmtest/` and never `/tmp` (§5).
   → verify by `readme-counts.sh --check` still passing and the manual's three
   lists unchanged (no new page).

5. **One line in the manual** pointing at the development VM, so this is
   findable without reading the flake.
   → verify by the sidebar/llms.txt/index check, which only matters if a page
   is added — it is not, so this must stay a line in an existing page.

6. **Whole-branch verification.** `nix fmt -- --ci`, statix, deadnix, then
   `nix build .#checks.x86_64-linux.options` — `vm-big` is evaluated by the
   flake, so a mistake here can break a check that has nothing to do with it.
   → verify all green.

7. **Boot it once.** `nix run .#vm-big`, confirm the Podman and Distrobox panels
   open and list real state. This is the step that needs the CI queue empty
   (§6) — a 32 GB guest on the box that hosts all four runners.
   → verify by both panels opening; a panel that lists nothing because the
   service is off is the failure this whole change exists to remove.

8. **PR.** Against `main`, closing #817, `Refs #816`, linking the three
   artifacts, carrying step 1's red output and step 2's green.

## Tests

| Command | Expected |
| --- | --- |
| the step 1 eval, before | a populated list **without** `nixarchy.podman`, `nixarchy.distrobox` |
| the same, after | the same list **with** both |
| `nix build .#checks.x86_64-linux.options` | green |
| `nix fmt -- --ci`, statix, deadnix | clean |
| `nix run .#vm-big` | both panels open and list real state |

## Rollback

- **Before merge:** drop the branch.
- **After merge:** revert. The qcow is outside the repo and unaffected either
  way — which is the point of it, and also why nothing here can enforce the
  monthly rebuild.
