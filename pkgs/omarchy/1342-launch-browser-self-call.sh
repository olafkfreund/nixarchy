if [[ ${browser_exec##*/} == omarchy-launch-browser ]]; then
  omarchy-notification-send -u critical "No browser to open this in" "The default browser entry runs omarchy-launch-browser itself (#1342). Choose a browser with: omarchy default browser"
  exit 1
fi
if $browser_exec --help 2>/dev/null | grep -q MOZ_LOG; then
