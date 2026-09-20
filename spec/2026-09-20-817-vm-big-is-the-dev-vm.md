---
status: approved
issue: 817
intent: intent/2026-09-20-817-vm-big-is-the-dev-vm.md
---

# Spec: vm-big keeps its name, gains the two panels, and says what it is for

## Design

Three changes, none of them to `.#vm`.

### 1. `flake.nix`: podman and boxes on in `vm-big`

Inside the existing `vm-big` module list, beside the `localAi` block:

```nix
# This is the VM a person keeps (#817), so it matches a real machine:
# both panels that follow a service are gated on that service, and with
# neither enabled nixarchy.podman and nixarchy.distrobox are invisible
# here -- the two panels most worth trying by hand.
virtualisation.podman.enable = true;
programs.nixarchy.services.boxes.enable = true;
```

Owner's decision: **on by default, not behind a flag.** The cost is the image
pulls, and it is paid by anyone running `vm-big`.

Disk: `vm-big` already declares 128 GB, which is ample — the `boxes` demo scene
needed 16 GB for one image, its layers and the container, and `.#vm` carries
16384 for the same reason. No change needed, which is worth saying because it is
the first thing a reviewer will check.

### 2. The docs say which VM is which

`vm-big`'s anchor is `#the-same-vm-with-room-to-run-a-model`, which describes
one of its two jobs. **The anchor stays** — it is linked from `flake.nix` and
renaming it breaks that pointer for a word — and the prose around it gains the
second job:

- `docs/internals/flake.md` (`:1018`–`:1046`): `vm-big` is the VM you keep. It
  has a disk, it reuses it, and clearing it is yours. `.#vm` is stateless **on
  purpose**, and the reason is repeated here rather than only in
  `vm/configuration.nix:127` — a stale disk replayed
  `~/.local/state/omarchy/notifications/history/` and made fixed failures
  reappear on screen.
- One line in the manual's development page pointing at it, so this is findable
  without reading the flake.

### 3. A cadence, written down

**Rebuild monthly**, the owner's decision, recorded where the disk is described
rather than in a comment nobody re-reads:

    nix run .#vm-big   # reuses ./nixarchy-vm-big.qcow2
    rm nixarchy-vm-big.qcow2 && nix run .#vm-big   # the monthly reset

With the disk under `/mnt/data/vmtest/`, never `/tmp` (§5: a 32 GB tmpfs
competing with the machine's RAM).

Monthly rather than "when it misbehaves", because the failure this guards
against is *not noticing* — `.#vm`'s comment is the account of exactly that,
with a shorter fuse.

## Alternatives rejected

- **A third VM variant.** What the investigation nearly produced, and wrong:
  `vm-big` is already persistent, already sized, already on its own port. A
  second persistent VM would double the disk and split attention.
- **Renaming `vm-big`.** Owner's decision. It is a public flake attribute; a
  rename costs every caller and every doc reference to make the name describe
  both jobs, when a sentence does that for free.
- **`diskImage` on `.#vm`.** The failure it causes is documented in the tree.
- **Podman and boxes behind a flag.** Owner's decision: a development VM that
  differs from a real machine in the two services whose panels ship on by
  default is not testing what ships.
- **A GC root or automatic cleanup for the qcow.** Tempting, and it would fight
  the owner: the file is meant to survive. The cadence is a human rule because
  the judgement is human.

## Risks

- **`vm-big` gets heavier.** Podman pulls images on first use, and the VM was
  already 32 GB and 8 cores. It remains unrunnable on a small machine — true
  before this change, and this does not improve it. Named, not fixed.
- **The monthly rebuild is a rule, not a check.** Nothing enforces it and
  nothing can: the disk is deliberately outside anything CI sees. If it is
  missed, the symptom is the one `.#vm`'s comment describes, which is why the
  reason travels with the rule.
- **Boxes needs a network.** `vm-big` run offline will have a Distrobox panel
  that lists templates and cannot pull one. That is honest behaviour rather than
  a fault, and the docs say it.

## Verification

1. **Red first** (§1): evaluate `vm-big` before the change and show
   `nixarchy.podman` and `nixarchy.distrobox` absent from the resolved default
   plugins; after, show both present. An evaluation, not a boot — cheapest layer
   that can answer it (§3), and it runs while the CI queue is busy.
2. Boot `vm-big` and confirm both panels open and list real state.
3. `nix fmt -- --ci`, statix, deadnix.
4. `nix build .#checks.x86_64-linux.options` — `vm-big` is evaluated by the
   flake, so a mistake here can break an unrelated check.
5. The docs change is read beside `vm/configuration.nix:127` to confirm the two
   accounts of statelessness agree.
