# Sourced from the install phase on edge only (#1964): quattro's boot image
# commands operate on Arch's Limine, UKI and mkinitcpio state, so they refuse.
# Each edit is guarded: edge's fallback pin (3642699) lacks these files or their /usr paths.
bin=$out/share/omarchy/bin
for name in omarchy-boot-backend omarchy-boot-rebuild omarchy-boot-switch omarchy-boot-sync omarchy-boot-sync-initcpio; do
  [ -e "$bin/$name" ] || continue
  # Keep upstream's `# omarchy:` header: `omarchy commands --check` reads it.
  header=$(grep '^# omarchy:' "$bin/$name" || true)
  printf '%s\n' '#!/usr/bin/env bash' "$header" "echo '$name manages Arch boot images; configure the NixOS bootloader in your flake instead.' >&2" 'exit 1' > "$bin/$name"
done
[ ! -e "$bin/omarchy-rollcall" ] || substituteInPlace "$bin/omarchy-rollcall" \
  --replace-fail '[[ $fragment == /usr/lib/systemd/system/* ]]' '[[ $fragment == /nix/store/* ]]'
if grep -qs /usr/share/omarchy/themes "$bin/omarchy-theme-bg-boot-intro"; then
  substituteInPlace "$bin/omarchy-theme-bg-boot-intro" --replace-fail '/usr/share/omarchy/themes' "$out/share/omarchy/themes"
fi
