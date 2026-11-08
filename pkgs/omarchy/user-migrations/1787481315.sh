echo "Re-stage a theme installed from a repository so its staged code is dropped"
file="$HOME/.local/state/omarchy/current/theme.name"
[[ -f $file ]] || exit 0
name=$(<"$file")
name=${name//[[:space:]]/}
[[ -n $name ]] || exit 0
src="$HOME/.config/omarchy/themes/$name"
[[ ! -L $src && -d $src/.git ]] || exit 0
omarchy-theme-refresh
