# shellcheck shell=bash
# Sourced by the install phase with the Bash and jq executable paths.
# shellcheck disable=SC2154
# #1385: sudo is configuration on NixOS, so the bar's passwordless-sudo indicator is neutered and unoffered.
substituteInPlace "$out/share/omarchy/shell/plugins/bar/indicators/PasswordlessSudo.qml" \
  --replace-fail '  active: granted' '  visible: false; active: granted' \
  --replace-fail '    if (!root.bar) return' '    return'
if [ -f "$out/share/omarchy/bin/omarchy-setup-security-passwordless-login" ]; then
  # shellcheck disable=SC2016
  printf '%s\n' "#!$1" \
    '[[ "${1:-}" == --active ]] && exit 1' \
    'echo "Passwordless login is configured through your NixOS configuration." >&2' \
    'exit 1' > "$out/share/omarchy/bin/omarchy-setup-security-passwordless-login"
  printf '%s\n' 'import qs.Ui' 'BarIndicator { visible: false }' \
    > "$out/share/omarchy/shell/plugins/bar/indicators/PasswordlessLogin.qml"
  substituteInPlace "$out/share/omarchy/shell/plugins/bar/widgets/Indicators.qml" \
    --replace-fail '"PasswordlessLogin", ' ""
fi
"$2" 'del(.barWidget.schema[].options[]? | select(.value == "PasswordlessSudo" or .value == "PasswordlessLogin"))' \
  "$out/share/omarchy/shell/plugins/bar/widgets/Indicators.manifest.json" > indicators.manifest.tmp
cat indicators.manifest.tmp > "$out/share/omarchy/shell/plugins/bar/widgets/Indicators.manifest.json"
if grep -Eq 'Passwordless(Sudo|Login)' "$out/share/omarchy/shell/plugins/bar/widgets/Indicators.manifest.json"; then
  echo "A passwordless indicator is still offered in Indicators.manifest.json" >&2
  exit 1
fi

# udiskie still reads existing device rules and is on the Nixarchy runtime PATH.
autostart="$out/share/omarchy/default/hypr/autostart.lua"
if grep -qF 'o.launch("omarchy-drive-automount")' "$autostart"; then
  substituteInPlace "$autostart" \
    --replace-fail 'o.launch("omarchy-drive-automount")' \
    "o.launch(\"udiskie --automount --no-notify --no-tray --password-prompt 'omarchy-drive-unlock {device_file}'\")"
  # A failed password prompt tells udiskie the shell handles the unlock.
  printf '\nexit 1\n' >> "$out/share/omarchy/bin/omarchy-drive-unlock"
fi
if [ -f "$out/share/omarchy/bin/omarchy-agent-resume" ]; then
  substituteInPlace "$out/share/omarchy/bin/omarchy-agent-resume" \
    --replace-fail 'ExecStart=/bin/bash' 'ExecStart=/run/current-system/sw/bin/bash'
fi
