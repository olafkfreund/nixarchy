echo "FIDO2 login is declared here. Remove security.pam.u2f and the u2fAuth lines," >&2
echo "Apply changes, and only then delete the registration: sudo rm -rf /etc/fido2." >&2
echo "Nothing on this machine was changed." >&2
exit 1
