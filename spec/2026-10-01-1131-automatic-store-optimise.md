---
status: draft
issue: 1131
intent: intent/2026-10-01-1131-automatic-store-optimise.md
---

# Spec: Deduplicate the store on installed machines

## Design

Set `nix.optimise.automatic = true` in `installer/host.nix`, beside the
installer-owned disk policy at lines 145-200. The generated host imports this
file through `installer/template/host/default.nix:15`, while Mode A does not.
Use a plain assignment for this installer-owned choice; add no new Nixarchy
option or module definition. Leave the 3/8 GiB `min-free`/`max-free` settings
and `programs.nh.clean` unchanged. Store optimisation hard-links identical
files; it does not collect paths or generations.

In the pinned nixpkgs revision (`flake.lock:1048`), the native
`nix.optimise.automatic` option starts `nix-optimise.service` daily at 03:45.
Its timer is persistent and has up to 30 minutes of random delay. The service
executes `nix-store --optimise` with `Nice = 19`, idle CPU and I/O scheduling,
and `ConditionACPower = true`. Keep those defaults: do not set
`nix.optimise.dates`, CPUWeight, IOWeight, or custom systemd units. A laptop
that misses the scheduled time may run the timer after waking, subject to the
AC power condition. This differs from nixbook's background upgrade weights of
20 but already gives the store scan idle priority.

Extend the existing `tests/options.nix:1455-1492` disk-policy assertions with
installed-host / Mode A assertions. The installed `vm` configuration must have
`nix.optimise.automatic == true` and the `nix-optimise` timer; both the
enabled `adopter` fixture and the disabled `modeAOff` fixture, which import
the Nixarchy module without `installer/host.nix`, must retain the nixpkgs
default `false` and have no active `nix-optimise` timer.
Assert the resolved option and timer state, not the presence of source text.
Keep the existing `checks.options` entry in `flake.nix:2373`; no workflow
change is needed.

## Alternatives rejected

- A `mkDefault` in `modules/nixos.nix`: it would apply to Mode A whenever the
  desktop is enabled, although those users own their system-wide disk policy.
  An `installerManaged` gate would duplicate the structural boundary already
  supplied by `installer/host.nix`.
- `nix.settings.auto-optimise-store = true`: it adds deduplication work to
  store writes and therefore to builds, instead of scheduling a low-priority
  background pass.
- A custom timer or CPUWeight/IOWeight of 20: the pinned NixOS service already
  uses idle CPU and I/O scheduling. Add more policy only after measured
  contention on an installed desktop.
- `nix.gc.automatic`: it collects garbage rather than deduplicating files and
  conflicts with the already-enabled `programs.nh.clean` generation policy.

## Risks

- The first full-store pass may perform substantial disk reads and write
  hard-links. Idle scheduling reduces competition but does not make the work
  free. Measure runtime and responsiveness on an installed machine after
  rollout; do not assume nixbook's reported saving applies here.
- The native service requires AC power. A laptop used only on battery may
  defer optimisation indefinitely; document this behavior rather than
  overriding the upstream safety condition without evidence.
- A future nixpkgs bump could change the native timer or priority defaults.
  This design intentionally follows the NixOS module; inspect its resolved
  service and timer during implementation, without pinning incidental details
  into nixarchy's configuration.

## Verification

1. Before setting the option in `installer/host.nix`, add the on/off assertion
   to `tests/options.nix` and run `nix build .#checks.x86_64-linux.options`.
   Confirm it fails specifically because the installed host's automatic
   optimisation is `false`; capture the red output and confirm the test edit
   actually landed (`git diff`). This is root `AGENTS.md` §1's red check.
2. Set the installer option and rerun the same check. It must pass with the
   installed timer enabled and both Mode A timers absent. A check that only
   searches source text does not satisfy this requirement.
3. Inspect the resolved installed-host service and timer options for the
   pinned nixpkgs defaults, and confirm `programs.nh.clean`, `min-free`, and
   `max-free` still evaluate as before. No manual `nix-store --optimise` run
   is needed to prove the declarative policy.
