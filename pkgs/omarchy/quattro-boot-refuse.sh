# Sourced from the install phase on edge only (#1964): quattro's boot image
# commands operate on Arch's Limine, UKI and mkinitcpio state, so they refuse.
for name in omarchy-boot-backend omarchy-boot-rebuild omarchy-boot-switch omarchy-boot-sync omarchy-boot-sync-initcpio; do
  printf '%s\n' '#!/usr/bin/env bash' "echo '$name manages Arch boot images; configure the NixOS bootloader in your flake instead.' >&2" 'exit 1' > "$out/share/omarchy/bin/$name"
done
substituteInPlace "$out/share/omarchy/bin/omarchy-rollcall" \
  --replace-fail '[[ $fragment == /usr/lib/systemd/system/* ]]' '[[ $fragment == /nix/store/* ]]'
substituteInPlace "$out/share/omarchy/bin/omarchy-theme-bg-boot-intro" \
  --replace-fail '/usr/share/omarchy/themes' "$out/share/omarchy/themes"
