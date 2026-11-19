# System: Environment, Toggles, Hardware, and Updates

Read this before setting environment variables or changing idle, power, language, network, audio, security, or update behavior.

## Environment Variables and Shell Setup

- Shell aliases, functions, and exports for terminals go in `~/.bashrc`. Updates never overwrite it.
- Variables the whole desktop should see go in a file in `~/.config/uwsm/env.d/` (e.g. `~/.config/uwsm/env.d/20-mine`, with `export NAME=value` lines). They take effect at the next login. These files run before the desktop starts, so a shell error in one sends the user back to the login screen: keep the syntax plain, and tell the user that moving the file out of `env.d` undoes it.
- A value the user wants permanent across machines belongs in Home Manager (`home.sessionVariables`, or `environment.sessionVariables` in the NixOS configuration — see the `nixos` skill).
- Omarchy's own session defaults (`TERMINAL=xdg-terminal-exec`, `EDITOR="omarchy-launch-editor --inline"`, and so on) are in `$OMARCHY_PATH/default/uwsm/default`; override them in `env.d` or `home.sessionVariables` rather than editing `~/.config/uwsm/default`.

## Toggles

```bash
omarchy toggle idle [stay-awake|allow-idle|status]   # Keep the machine awake (Super+Ctrl+I)
omarchy toggle notification silencing                # Do not disturb
omarchy toggle nightlight                            # Warm the screen now
omarchy toggle screensaver                           # Screensaver on idle
omarchy toggle suspend                               # Suspend in the system menu
omarchy toggle crash-capture                         # "Process crashed" notifications
omarchy crash mute <program> [on|off]                # ...for one program only
```

A scheduled night light needs hyprsunset running from login: set the profiles in `~/.config/hypr/hyprsunset.conf`, add `o.launch_on_start("hyprsunset")` to `~/.config/hypr/autostart.lua`, then `omarchy restart hyprsunset` to start it now.

## Language, Region, and Time

```bash
omarchy language [<code>|list]        # Display language of Omarchy and its apps
omarchy region [<code>|list|default]  # How dates, times, numbers, and units are written (quattro)
omarchy weather location --set <place>
```

If the chosen language's locale has not been built into the system yet, `omarchy language <code>` records `programs.nixarchy.language = "<code>";` in `~/.config/nixarchy/services.nix`; run `nixarchy-apply` (Install > Apply changes) to build the locale, then run `omarchy language <code>` again (for a separate region locale on quattro, add `"<locale>/UTF-8"` to `i18n.extraLocales`). Timezone is declared in the NixOS configuration (`time.timeZone = "Europe/Copenhagen";`) rather than changed imperatively.

## Power and Sleep

```bash
omarchy powerprofiles list
omarchy powerprofiles set [autodetect|ac|battery] [power-saver|balanced|performance]  # Remembered per power source
```

Idle and lock timing is in [`plugins.md`](plugins.md). Hibernation is configured declaratively in NixOS (`swapDevices` and `boot.resumeDevice` — see the `nixos` skill).

## Network, Bluetooth, and Audio

Network and Bluetooth panels are on Super+Ctrl+N and Super+Ctrl+B, and `nmtui` works for anything they don't cover.

```bash
omarchy network band [auto|2.4|5|6]          # Pin the Wi-Fi band
omarchy network password <interface>         # Print the Wi-Fi password
omarchy network speedtest [down|up]
omarchy bluetooth power <on|off|toggle>
omarchy audio output switch                  # Next output, keeping mute
omarchy audio input mute
omarchy restart audio|bluetooth|wifi|trackpad   # When one gets stuck
```

System-wide DNS servers are declared in the NixOS configuration (`networking.nameservers` and `services.resolved.fallbackDns`).

## Security

On NixOS, sudo and passwordless sudo (`security.sudo`), PAM authentication (`security.pam`, `services.fprintd`), the SSH daemon (`services.openssh`, or `nixarchy-service-enable openssh` in `~/.config/nixarchy/services.nix`), and the firewall (`networking.firewall`) are system configuration rather than runtime toggles — see the `nixos` and `nixos-security` skills.

Interactive enrollment and credential commands (run in a terminal the user can see):

```bash
omarchy setup security fingerprint     # Enroll a fingerprint (once services.fprintd.enable = true is applied); prints the security.pam lines to add
omarchy remove security fingerprint    # Delete your saved fingerprints
omarchy setup security fido2           # Register a security key into /etc/fido2/fido2; prints the security.pam.u2f lines to add
omarchy setup security ssh-agent       # Enable the gcr-ssh-agent user socket
omarchy drive password                 # Change the disk encryption password
```

## Updates, Snapshots, and Recovery

`omarchy update` updates the flake lock (`flake.lock`) and rebuilds the system (`nh os switch --update`). Every rebuild leaves the previous system on disk as a bootable NixOS generation:

```bash
omarchy update                        # Move flake inputs forward and rebuild
omarchy update --system               # Move nixpkgs only (packages and kernel, not the desktop)
omarchy update --nixarchy             # Move nixarchy only (the desktop, on your current packages)
sudo nixos-rebuild --rollback switch  # Roll back to the previous NixOS generation (or use nixarchy-rollback)
omarchy snapshot [create|list|restore]   # Snapshot /home with snapper, or copy files back out of one
omarchy channel set <stable|edge>     # Switch the Omarchy input channel in your flake.nix
```

The kernel (`boot.kernelPackages`) and firmware updates (`services.fwupd`) are declared in the NixOS configuration.

## AI Agents and Dictation

- `omarchy default agent <name>` picks the coding agent that `omarchy agent` and the bar's agents panel use (adding it to `~/.config/nixarchy/apps.nix` and rebuilding if needed, or declare `programs.nixarchy.defaultAgent` in the flake). Personal rules for every agent go in `~/.agents/AGENTS.md` (`omarchy agent instructions --edit` on quattro).
- `omarchy agent account list|add|use` manages Claude, Codex and Grok subscription accounts; `omarchy agent local use best` (quattro) runs an open model on this machine once `programs.nixarchy.services.agent-local.enable = true;` is enabled (or see the `nixos-ai` skill).
- Dictation is Alt+Space, or hold Right Alt to talk; `omarchy default dictation <superwhisper|voxtype|hex>` (`hex` on quattro) picks the backend (or enable `programs.nixarchy.dictation.enable = true;` for Voxtype). Superwhisper installs a `superwhisper` skill of its own for its settings.
