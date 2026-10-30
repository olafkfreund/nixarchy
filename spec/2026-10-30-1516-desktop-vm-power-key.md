---
status: approved
issue: 1516
intent: intent/2026-10-30-1516-desktop-vm-power-key.md
---

# Spec: nixarchy-desktop powers off on `nixarchy vm stop`, and a check sees it

## Design

**The fix**, in `modules/microvm/templates/nixarchy-desktop.nix`. #1517's
line stays: `services.logind.settings.Login.HandlePowerKey = "poweroff";` at
plain priority, which beats `modules/nixos.nix`'s `lib.mkDefault "ignore"`.
The file's three top-level `services.` assignments (`displayManager.autoLogin`,
`gnome.at-spi2-core.enable`, `logind…`) merge into one `services = { … }`
block, which is what statix's repeated-keys lint asks for. Each keeps its
existing comment. The values don't change, only the nesting.

**The probe**, in `tests/microvm-template.nix`. Add a block after the
`agent-claude` one, in the same shape:
`lib.optionalString (templates ? nixarchy-desktop) ''…''`. It resolves
`sys=$(readlink -f ${templates.nixarchy-desktop.kvm}/share/microvm/system)`
and requires `grep -qx 'HandlePowerKey=poweroff' "$sys/etc/systemd/logind.conf"`.
On a miss it prints the line that is there and sets `fail=1`. Logind renders
`settings.Login` as `KEY=value` lines, the same format the host's
`/etc/systemd/logind.conf` shows (`HandlePowerKey=ignore` on p620).

The probe reads the rendered file, not the option, so it would also catch a
later override that wins over ours, or a logind rendering change. It adds no
NixOS evaluation, because the check already takes every runner as an input.

## Alternatives rejected

- **Asserting the option in `checks.microvm-ai-mirror`** (codex's proposal).
  That check is a cheap `runCommand` over one plain-NixOS template. This
  probe would add a full nixarchy and Home Manager evaluation to it (about
  1.7 GB), and it would test the option rather than the file logind reads.
- **`mkForce "poweroff"`.** It's unnecessary, since plain priority already
  wins, and §7 keeps `mkForce` off anything a user might set.
- **Changing `modules/nixos.nix`** to skip the override inside a microvm. That
  puts a guest special case into the module every host runs. Only one
  template has this problem, so the fix belongs in that template.
- **Sending SIGTERM from `nixarchy vm stop` after a timeout.** That treats the
  symptom for every template, and it skips the guest's clean shutdown.

## Risks

- **The host desktop:** none. Only the template file and a test change.
- **`checks.microvm-template` needs the `nixarchy-desktop` runners built.** CI
  already builds them for the existing assertions. Locally, the runner isn't in
  p620's store, so the §1 proof is a package-tier build or larger. It runs only
  with `vm-host-free.sh` printing `free` for both sides and no CI in flight. If
  it can't run locally, the PR's CI run is the pass and the break proof is
  stated as not run locally.
- **The rendered path:** if nixpkgs moved logind's config away from
  `etc/systemd/logind.conf`, the probe fails loudly, because the file would be
  missing. It doesn't pass silently.

## Verification

1. `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`. Statix must be
   clean on the template, which is what fails #1517 today.
2. §1 break proof. Delete the `logind…HandlePowerKey` line, confirm with
   `git diff` that it's gone, build `checks.microvm-template`, and capture
   the red output naming `HandlePowerKey`. Restore it, build again, and see it
   pass.
3. #1517's CI is green, including `lint` and the generated-checks step that
   builds `microvm-template`.
4. Live, optional, CI idle: `nixarchy vm create`, `run --detach`, then
   `nixarchy vm stop` on a `nixarchy-desktop` VM returns within about 30 s,
   with no SIGTERM.
