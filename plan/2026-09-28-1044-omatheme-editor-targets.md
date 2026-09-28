---
status: draft
issue: 1044
spec: spec/2026-09-28-1044-omatheme-editor-targets.md
---

# Plan: Pin omatheme editor targets into Nixarchy

Update Nixarchy's reproducible omatheme input from the Foot-only revision to
merged commit `935bb2b25f40cd735439e99b8d6b6ef1b6601b46`, preserving the current
module wiring and host configuration ownership.

## Steps

1. `flake.nix`: change only the `nixarchy-omatheme` URL to commit `935bb2b` →
   verify no host or module source files are changed.
2. `flake.lock`: refresh the `nixarchy-omatheme` lock node and its nested
   `omarchroma` revision → verify the lock diff is limited to those inputs.
3. Run the affected Nixarchy evaluation, build, install, and system checks →
   verify the new module evaluates and the offline/install outputs build.
4. Run formatting and repository validation → verify the branch is clean and
   all required checks pass.
5. Deploy the resulting flake to Razer with `nixos-rebuild switch` → verify
   the active generation, `hyprchromad`, editor bridge files, Foot parsing,
   and live theme switching.
6. Commit, push, open a PR closing #1044, and merge only after CI and Razer
   verification pass.

## Tests

```sh
nix flake check --system x86_64-linux --no-build --show-trace
nix build .#nixosConfigurations.razer.config.system.build.toplevel --no-link --print-build-logs
nix fmt -- --ci
```

On Razer:

```sh
sudo nixos-rebuild switch --flake /home/olafkfreund/.config/nixos#razer
systemctl --user is-active hyprchromad.service
foot --check-config --config="$HOME/.config/omarchy/runtime/foot.ini"
```

## Rollback

Revert the pin and lockfile commit, then rebuild the previous flake
generation. NixOS's prior generation remains available through the normal
rollback path if activation fails.
