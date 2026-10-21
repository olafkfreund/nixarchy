#!/usr/bin/env bash
# Run by tests/menu-conditions.nix (#1303). Env: menu menuNoSnapper bin hxBinary zenBinary.
set -euo pipefail
fail=0
sect=0
bad() { echo "  FAILED  $*" >&2; fail=1; sect=1; }
# ok prints only when its section had no failure; each section starts with sect=0
ok() { [ "$sect" = 1 ] || echo "  ok      $*"; sect=0; }

# field <menu> <row-id> <key>: the value, "" if the key is absent, __absent__ if the row is.
field() {
  python3 - "$@" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
raw = re.sub(r",(\s*[}\]])", r"\1", raw)
rows = json.loads(raw)
print(rows[sys.argv[2]].get(sys.argv[3], "") if sys.argv[2] in rows else "__absent__")
PY
}

work=$(mktemp -d)
export HOME=$work/home
export XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state \
  XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
mkdir -p "$HOME" "$XDG_CACHE_HOME"
unset EDITOR VISUAL BROWSER
stubs=$work/stubs
mkdir -p "$stubs"
stub() { printf '#!%s\n%s\n' "$BASH" "$2" >"$stubs/$1"; chmod +x "$stubs/$1"; }
plain=$bin:$PATH
stubbed=$stubs:$bin:$PATH
# status <PATH> <expr>: the exit status of a menu expression under that PATH
status() { if env PATH="$1" bash -c "$2"; then echo 0; else echo 1; fi; }

# --- Helix: the row looks for the binary nixpkgs installs -----------------
when=$(field "$menu" setup.default.editor.helix when)
[ "$when" = "omarchy-cmd-present $hxBinary" ] || bad "setup.default.editor.helix: when is '$when', not omarchy-cmd-present $hxBinary"
[ "$(status "$plain" "$when")" = 1 ] || bad "setup.default.editor.helix: when is true with no $hxBinary on PATH"
stub "$hxBinary" 'echo hx >>"$HOME/launched"'
stub nvim 'echo nvim >>"$HOME/launched"'
stub omarchy-notification-send ':'
[ "$(status "$stubbed" "$when")" = 0 ] || bad "setup.default.editor.helix: when is false with $hxBinary on PATH"

# --- Helix: choosing it ticks the row and opens hx, not nvim --------------
PATH=$stubbed omarchy-default-editor helix || bad "omarchy-default-editor helix exited non-zero"
checked=$(field "$menu" setup.default.editor.helix checked)
[ "$(status "$stubbed" "$checked")" = 0 ] || bad "setup.default.editor.helix: not ticked after choosing it"
PATH=$stubbed omarchy-launch-editor --inline "$work/f" || bad "omarchy-launch-editor exited non-zero"
launched=$(cat "$HOME/launched" 2>/dev/null || echo nothing)
[ "$launched" = hx ] || bad "launched $launched, expected hx"
ok "Helix shows with hx, ticks, and opens hx"

# --- Zen: row, setter and reader agree with the package -------------------
[ "$zenBinary" = zen-beta ] || bad "the zen-browser package installs $zenBinary, and the patch and row name zen-beta"
when=$(field "$menu" setup.default.browser.zen when)
[ "$when" = "omarchy-cmd-present $zenBinary" ] || bad "setup.default.browser.zen: when is '$when'"
[ "$(status "$plain" "$when")" = 1 ] || bad "setup.default.browser.zen: when is true with no $zenBinary on PATH"
stub "$zenBinary" ':'
[ "$(status "$stubbed" "$when")" = 0 ] || bad "setup.default.browser.zen: when is false with $zenBinary on PATH"
stub xdg-settings 'if [ "$1" = set ]; then echo "$3" >"$HOME/xdg-set"; else cat "$HOME/xdg-get"; fi'
PATH=$stubbed omarchy-default-browser zen || bad "omarchy-default-browser zen exited non-zero"
wrote=$(cat "$HOME/xdg-set" 2>/dev/null || echo nothing)
[ "$wrote" = "$zenBinary.desktop" ] || bad "setter wrote $wrote, expected $zenBinary.desktop"
echo "$zenBinary.desktop" >"$HOME/xdg-get"
read_back=$(PATH=$stubbed omarchy-default-browser) || bad "omarchy-default-browser (read) exited non-zero"
[ "$read_back" = zen ] || bad "reader printed $read_back, expected zen"
checked=$(field "$menu" setup.default.browser.zen checked)
[ "$(status "$stubbed" "$checked")" = 0 ] || bad "setup.default.browser.zen: not ticked when $zenBinary.desktop is the default"
remove=$(cat "$bin/omarchy-remove-browser")
if grep -q 'zen\.desktop' <<<"$remove"; then bad "omarchy-remove-browser still names zen.desktop"; fi
ok "Zen shows with $zenBinary, and sets and reads $zenBinary.desktop"

# --- Hibernate: only yes or challenge from logind shows the row -----------
# upstream may add conditions after the availability probe (#1398)
case "$(field "$menu" system.hibernate when)" in
omarchy-hibernation-available | "omarchy-hibernation-available && "*) ;;
*) bad "system.hibernate no longer asks omarchy-hibernation-available" ;;
esac
avail=$(cat "$bin/omarchy-hibernation-available")
if grep -q mkinitcpio <<<"$avail"; then bad "omarchy-hibernation-available still names mkinitcpio"; fi
term=$(grep -o '\[\[ \$(busctl [^]]*\]\]' <<<"$avail" || true)
[ -n "$term" ] || bad "omarchy-hibernation-available has no busctl CanHibernate term"
for answer in yes challenge no na; do
  printf 's "%s"\n' "$answer" >"$HOME/busctl-answer"
  stub busctl 'cat "$HOME/busctl-answer"'
  want=1
  case $answer in yes | challenge) want=0 ;; esac
  [ "$(status "$stubbed" "$term")" = "$want" ] || bad "busctl said $answer, row shown=$([ $want = 0 ] && echo no || echo yes)"
done
stub busctl 'exit 1'
[ "$(status "$stubbed" "$term")" = 1 ] || bad "busctl failed, row shown"
ok "Hibernate shows only for yes and challenge"

# --- Snapshot rows: present with a home snapper config, absent without ----
for id in system.recovery.snapshot system.recovery.snapshot.restore; do
  [ "$(field "$menu" "$id" label)" != __absent__ ] || bad "$id absent with a home snapper config"
  [ "$(field "$menuNoSnapper" "$id" label)" = __absent__ ] || bad "$id present with no home snapper config"
done
ok "snapshot rows follow services.snapper.configs.home"

# --- Font list: the cursor glyph font is not a font ------------------------
all=$(fc-list :spacing=100 -f '%{family[0]}\n')
grep -qx 'cursor.pcf' <<<"$all" || bad "fixture: fc-list does not see cursor.pcf, so this case proves nothing"
list=$(PATH=$plain omarchy-font-list) || bad "omarchy-font-list exited non-zero"
grep -qx 'DejaVu Sans Mono' <<<"$list" || bad "DejaVu Sans Mono missing from the font list"
if grep -qx 'cursor.pcf' <<<"$list"; then bad "cursor.pcf listed as a font"; fi
ok "the font list drops cursor.pcf and keeps DejaVu Sans Mono"

[ "$fail" = 0 ] || exit 1
echo "menu conditions answer for the NixOS machine"
