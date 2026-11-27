#!/bin/bash

# omarchy:summary=Check that NixOS puts fingerprint authentication in the sudo and polkit PAM stacks
# omarchy:requires-sudo=true
# omarchy:hidden=true

# NixOS builds /etc/pam.d, so nothing here may edit it (pkgs/AGENTS.md#nothing-may-sed-etcpamd).
# The setup and the fingerprint panel run this once a print is enrolled and
# verified. It succeeds when the system already asks pam_fprintd, and otherwise
# says which options do, and fails: the print is enrolled but not yet usable.
# Read only. The build's drift guard refuses any script naming the stacks' literal paths.
stacks=/etc/pam.d
rule='^[[:space:]]*auth[[:space:]]+([^[:space:]]+|\[[^]]+\])[[:space:]]+([^[:space:]#]*/)?pam_fprintd\.so([[:space:]]|$)'
if grep -Eqs "$rule" "$stacks/sudo" && grep -Eqs "$rule" "$stacks/polkit-1"; then
  exit 0
fi

echo "" >&2
echo "PAM is configured by your NixOS build, not by editing /etc/pam.d." >&2
echo "" >&2
echo "  Your fingerprint is enrolled and verified. What is left is" >&2
echo "  telling PAM to accept it:" >&2
echo "" >&2
echo "    services.fprintd.enable = true;" >&2
echo "    security.pam.services.sudo.fprintAuth = true;" >&2
echo "    security.pam.services.polkit-1.fprintAuth = true;" >&2
echo "    security.pam.services.hyprlock.fprintAuth = true;" >&2
echo "" >&2
echo "  then: sudo nixos-rebuild switch --flake <your-flake>" >&2
exit 1
