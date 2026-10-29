---
status: approved
issue: 1513
intent: intent/2026-10-29-1513-nixarchy-desktop-microvm.md
---

# Spec: a sandbox that runs the nixarchy desktop, for an agent to drive

## Design

A new catalogue template, `nixarchy-desktop`. It is the stock nixarchy desktop
for the guest's `dev` user, plus the same ai-mirror plumbing as
`hyprland-ai-mirror`.

**1. Share the ai-mirror half.** Move everything in
`modules/microvm/templates/hyprland-ai-mirror.nix` except
`imports = [ ./hyprland.nix ]` into a new
`modules/microvm/templates/ai-mirror-guest.nix`. That covers the vsock CID
script, the ai-mirror, ai-mirror-input and jq packages, and the
`ai-mirror-autoconfirm` and `ai-mirror-vsock` user services.
`hyprland-ai-mirror.nix` becomes those two imports. Its runner's guest
toplevel stays identical, which is checked by comparing store paths.
`ai-mirror-vsock` keeps `after = [ "hyprland.service" … ]`. Ordering after a
unit that doesn't exist is a no-op, and `ai-mirror mcp` finds the compositor
on each call, so it doesn't matter who started Hyprland.

**2. `modules/microvm/templates/nixarchy-desktop.nix`.**

```nix
{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.nixarchy
    inputs.home-manager.nixosModules.home-manager
    ./ai-mirror-guest.nix
  ];
  programs.nixarchy = { enable = true; user = "dev"; };
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
    users.dev = { programs.nixarchy.enable = true; home.stateVersion = "25.05"; };
  };
  services.displayManager.autoLogin = { enable = true; user = "dev"; };
  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    LIBGL_ALWAYS_SOFTWARE = "1";
  };
  services.gnome.at-spi2-core.enable = true;
  microvm = { qemu.extraArgs = [ "-device" "virtio-gpu-pci" ]; mem = 8192; vcpu = 4; };
}
```

- It doesn't import `installer/host.nix`. That file is the installed
  machine: systemd-boot, `nh` pointed at `/etc/nixos`, `installerManaged`,
  nix GC floors and the initrd superset. `vm/configuration.nix` has to
  `mkForce` its way back out of it (two bootloaders, a password file). Only
  the `programs.nixarchy` and `home-manager` lines carry over.
- `lib.mkMicrovm` already passes `specialArgs = { inherit inputs; }` (#1505),
  and `inputs.self` is this flake, so the template sees the nixarchy that
  built the CLI. That pin is the intent's question 3, deferred.
- The session variables, at-spi2-core, the GPU device and memory follow
  `vm/configuration.nix` (8 GiB) and `hyprland.nix` (no host GL, #1506).

**3. The catalogue exception.** Add an entry to `data/microvm-templates.nix`:
label "Nixarchy desktop + ai-mirror" and a note. The note covers the
consent model, the `claude mcp add` line, software rendering and closure
size. Also add a paragraph under "The bar" naming this entry as the one
exception and why: its purpose *is* the nixarchy desktop, so it can't be
plain NixOS. The paragraph says a user who outgrows it starts from the
installer's generated flake, not from this template.

**4. Docs.** Add a row to `docs/manual/sandboxes.md`, which
`checks.microvm-template` requires for every entry. Add one sentence in
"Driving one with ai-mirror" saying this template gives the agent the real
nixarchy keybindings, bar and commands.

**CI: both runners stay.** The KVM and TCG runners differ only in qemu's
machine options. The guest toplevel is the same derivation, so the TCG
build costs one runner script. Dropping it would break `nixarchy vm run` on
hosts without KVM, where the CLI falls back to TCG by itself
(`pkgs/microvm.nix` `variant`). This changes the recommendation I gave
with the intent ("skip TCG"), which was based on a wrong cost estimate.
What CI actually pays for is the desktop closure once, and that closure
overlaps heavily with `checks.reference-toplevel`.

## Alternatives rejected

- **Import `installer/host.nix`, like the smoke VM.** That brings in the
  installer-only settings above, each needing a `mkForce` to undo it in a
  9p-store guest with no disk.
- **A microvm variant of `packages.vm`, outside the catalogue.** It wouldn't
  appear in `nixarchy vm templates` or the MicroVMs panel, and it would be a
  second way to start a VM.
- **Clone p620 (option B).** Rejected in conversation: secrets, host
  services, and drift.
- **Drive `packages.vm` with ai-mirror over its forwarded SSH port.** That
  needs a host display or SSH, and it isn't disposable through
  `nixarchy vm`. It also puts the agent in the "shell on the account" case
  ai-mirror's AGENTS.md warns about. That's no worse than vsock here, but
  it's a second transport to document.
- **Turn off the TCG runner for this entry.** See CI above.

## Risks

- **The session may not come up in a microvm.** SDDM autologin has to start
  Hyprland on a virtio-gpu-pci DRM device with no host GL, over a 9p store.
  The smoke VM proves this under qemu-vm.nix, not microvm.nix. This is
  measured first (verification 1), before anything else is built. If it
  fails, the fallback is a `systemd.user` Hyprland service the way
  `hyprland.nix` does it, started with nixarchy's session command. That would
  be recorded as a plan deviation.
- **Monitor rule.** `hyprland.nix` found that a catch-all `monitor = ,`
  doesn't match qemu's `Virtual-1`, and Hyprland picks its own size. If
  nixarchy's default config has the same problem, the guest gets a size
  nobody chose. It's measured, and if needed fixed with a monitor rule in the
  template.
- **First-run surfaces.** A welcome screen, the config-repo nudge or a
  notification could cover the desktop in every fresh VM. They're measured on
  the first boot, and any that appear are turned off in the template.
- **The confirm dialog and the auto-confirmer race.** The bar's ai-mirror
  widget opens its dialog on `pending` while the loop answers. The dialog
  should close on the state change. That's measured: no dialog should be
  left over after a grant.
- **Boot time and memory.** The full shell plus software GL takes longer than
  bare Hyprland's ~20 s. The measured figure goes into the note.
- **CI time.** One more desktop closure in `checks.microvm-template`. Most of
  it is shared with the reference toplevel and the cache.
- **Hosts.** Nothing changes on any host until a nixarchy bump. The template
  exists only when someone runs `nixarchy vm create --template
  nixarchy-desktop`.

## Verification

1. **The session comes up.** Build `.#microvm-nixarchy-desktop`, run it on
   p620 headless, and connect over vsock with the existing probe. Pass if
   `status` and `control agent` lead to `owner: agent` without a human.
   Report the time from start to grant.
2. **It is nixarchy.** `index` returns nixarchy's keybindings and plugins.
   A screenshot shows the bar. `launch` opens a terminal, and `input` types
   into it, both read back from a screenshot.
3. **Nothing left over.** After the grant there is no ai-mirror confirm
   dialog in `layers`, and no first-run surface covering the desktop.
4. **Refactor is neutral.** The guest toplevel of `microvm-hyprland-ai-mirror`
   is byte-identical before and after step 1 of the design.
5. **Clean exit.** No core dumps from qemu after `nixarchy vm stop` (#1506).
6. **CI.** `nix flake check`, or at minimum `checks.microvm-template`, plus
   fmt, statix and deadnix pass on the PR.

## Results (plan step 3, p620, 2026-10-29)

Cold boot, with a probe connecting as early as it can:

| Check | Result |
|---|---|
| vsock listener reachable | 42 s after start (it waits for the settle gate) |
| control granted, no human | 1.2 s after asking |
| `launch foot`, then `input` typing | delivered to the focused window, first time, no `wrong_target` |
| screenshot | omarchy bar, wallpaper, the ai-mirror agent frame, the typed text; no toasts; the DND icon is on the bar |
| `index` | nixarchy's own bindings (e.g. SUPER+ALT+N Packages) and plugins |
| leftover confirm dialog | none in `hyprctl layers` after the grant |
| monitor | `Virtual-1`, 1280x800 (nixarchy's default rule; nobody needs a different size yet) |
| qemu core dumps after stop | 0 (SIGTERM to qemu, 3 boots) |

Two fixes were needed to get there. Both are recorded in the plan as
deviations: the writable store overlay, which lets Home Manager activate,
and the settle gate before the auto-grant.
