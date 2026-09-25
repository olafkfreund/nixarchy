# nixarchy patch (#948), spliced into omarchy-display-text-size.
#
# `omarchy display text size N` edits the terminal configs with `sed -i`. On
# Arch those are ordinary files in $HOME and it works. Here they can be Home
# Manager symlinks into the store, and sed dies with
#
#   sed: couldn't open temporary file /nix/store/sedXXXXXX: Read-only file system
#
# while the shell and GTK sizes still apply -- a partial result and an error
# nobody can act on. Ours, not upstream's: the port made the files read-only.
#
# NOT `sed --follow-symlinks` (writes to the store target, equally read-only --
# upstream's kitty branch already does this and it does not help), and NOT
# letting sed replace the link with a real file: that looks like it worked and
# quietly takes the file out of Home Manager's management, so the next rebuild
# fights it.
#
# In its own file rather than inline in the install phase, because that phase
# was 1,910 bytes from MAX_ARG_STRLEN when this was first attempted (#997).
local managed=() f
for f in ~/.config/alacritty/alacritty.toml ~/.config/ghostty/config ~/.config/foot/foot.ini ~/.config/kitty/kitty.conf; do
  [[ -L $f ]] || continue
  # readlink -f, not the link's text: Home Manager links through an
  # intermediate, so matching the first hop misses it.
  case "$(readlink -f "$f" 2>/dev/null)" in /nix/store/*) managed+=("$f") ;; esac
done
if ((${#managed[@]})); then
  echo "These terminal configs are declared, not edited:"
  printf '  %s\n' "${managed[@]}"
  echo "Change the font size where you declare them and rebuild."
  echo "The shell and GTK sizes are still applied."
  return 0
fi
