# Accent policy is opt-in through browserThemeUser. Other NixOS browser
# modules also create these directories, owned by root; their existence is
# not permission to tint them. Keep those policies untouched and do not turn
# the default opt-out into a failed theme switch.
writable_policy_dirs=()
for dir in "${POLICY_DIRS[@]}"; do
  if [[ -d $dir && ! -L $dir && -w $dir ]]; then
    writable_policy_dirs+=("$dir")
  fi
done
POLICY_DIRS=("${writable_policy_dirs[@]}")
(( ${#POLICY_DIRS[@]} > 0 )) || exit 0
