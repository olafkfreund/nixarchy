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
