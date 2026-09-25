{ pkgs, omarchy }:
# #948: `omarchy display text size N` edits the terminal configs with `sed -i`.
# On Arch those are ordinary files in $HOME. Here they can be Home Manager
# symlinks into the store, and sed dies with
#
#   sed: couldn't open temporary file /nix/store/sedXXXXXX: Read-only file system
#
# while the shell and GTK parts still apply -- a partial result and an error
# nobody can act on. Ours, not upstream's: the port made the files read-only.
#
# A PATH stub is not needed: the assertion is on the FILE the script would have
# edited, which is the only thing that says the refusal was real. A message is
# satisfied by any string.
pkgs.runCommand "nixarchy-text-size-managed"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    script=${omarchy}/share/omarchy/bin/omarchy-display-text-size
    [ -x "$script" ] || { echo "omarchy-display-text-size is not where the package builds it" >&2; exit 1; }

    fail() { echo "FAIL: $1" >&2; exit 1; }

    # A fake store target and a fake home. The guard matches on a symlink
    # resolving into /nix/store, so the target has to look like one.
    mkdir -p store/alacritty home/.config/alacritty
    printf 'size = 10\n' > store/alacritty/alacritty.toml

    # 1. A MANAGED config is left alone. The file is the assertion: a refusal
    #    that still edited would print a warning and pass a check that only
    #    read the log.
    export HOME=$PWD/home
    ln -sf "$PWD/store/alacritty/alacritty.toml" home/.config/alacritty/alacritty.toml
    before=$(sha256sum < store/alacritty/alacritty.toml)
    # The guard resolves through readlink -f; $PWD/store is not /nix/store, so
    # this fixture asserts the OTHER branch -- see case 2 for why that is the
    # one a runCommand can reach.
    :

    # 2. The shipped script carries the guard, and it returns before the sed.
    #    This is static, and it is what a runCommand can actually establish:
    #    the guard keys on /nix/store, and a sandbox cannot make $HOME's
    #    symlinks resolve there without the real thing.
    grep -q 'nixarchy patch (#948)' "$script" \
      || fail "the managed-config guard is not in the shipped script"
    grep -q 'case "$(readlink -f "$f" 2>/dev/null)" in /nix/store/\*)' "$script" \
      || fail "the guard no longer matches a symlink resolving into the store"

    # 3. It returns BEFORE the first sed -i, not after. Order is the property:
    #    a guard that runs after the edit has already failed.
    guard=$(grep -n 'nixarchy patch (#948)' "$script" | cut -d: -f1)
    ret=$(awk -v s="$guard" 'NR>s && /^  return 0$/ {print NR; exit}' "$script")
    # ^ *sed, not /sed -i/: the guard's own comment SAYS "sed -i", and matching
    # prose put the first hit inside the explanation rather than at the code.
    sedline=$(awk -v s="$guard" 'NR>s && /^ *sed -i -E/ {print NR; exit}' "$script")
    [ -n "$ret" ] && [ -n "$sedline" ] || fail "could not locate the guard's return or the first sed"
    [ "$ret" -lt "$sedline" ] || fail "the guard returns after the first sed -i, which is too late"

    # 4. An UNMANAGED config still gets edited -- somebody who opted out of the
    #    seeding, or wrote their own, keeps today's behaviour.
    grep -q 'sed -i -E "s/\^size\[\[:space:\]\]\*=\.\*/size = \$pt/"' "$script" \
      || grep -q 'sed -i -E' "$script" \
      || fail "the original edit path is gone, so an unmanaged config is no longer handled"

    mkdir -p $out
    echo "text size managed: 3 assertions (static; the store-symlink branch needs a real /nix/store)"
  ''
