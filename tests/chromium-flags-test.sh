#!/usr/bin/env bash
set -euo pipefail

launcher="${1:?usage: $0 <path-to-chromium-flags.sh>}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME"

stub="$tmp/chromium-stub"
printf '%s\n' "#!$BASH" 'printf "%s\n" "$@"' >"$stub"
chmod +x "$stub"
export CHROMIUM_REAL="$stub"

fail() {
  local case_id="$1"
  local msg="$2"
  local actual="$3"
  printf 'FAIL case (%s): %s\nActual output:\n%s\n' "$case_id" "$msg" "$actual" >&2
  exit 1
}

conf="$XDG_CONFIG_HOME/chromium-flags.conf"
printf '%s\n' \
  '# comment line' \
  '' \
  '--enable-features=FeatureA,FeatureB' \
  '--enable-features=FeatureB,FeatureC' \
  '--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url,/usr/share/omarchy/x' \
  >"$conf"

# Case (a): fixture with OMARCHY_PATH set, no Wayland env
out_a="$(OMARCHY_PATH="/custom/omarchy" NIXOS_OZONE_WL="" WAYLAND_DISPLAY="" bash "$launcher")"
if [[ "$out_a" == *"/usr/share/omarchy"* ]]; then
  fail "a" "/usr/share/omarchy survived in output" "$out_a"
fi
if ! grep -qxF -- "--load-extension=/custom/omarchy/default/chromium/extensions/copy-url,/custom/omarchy/x" <<<"$out_a"; then
  fail "a" "expected both extension paths to start with \$OMARCHY_PATH" "$out_a"
fi
ef_count_a="$(grep -c -- '^--enable-features=' <<<"$out_a" || true)"
if [[ "$ef_count_a" -ne 1 ]]; then
  fail "a" "expected exactly 1 --enable-features= line, got $ef_count_a" "$out_a"
fi
ef_line_a="$(grep -- '^--enable-features=' <<<"$out_a")"
if [[ "$ef_line_a" != "--enable-features=FeatureA,FeatureB,FeatureC" ]]; then
  fail "a" "expected merged features FeatureA,FeatureB,FeatureC, got $ef_line_a" "$out_a"
fi
echo "PASS (a): comments/blanks skipped, /usr/share/omarchy rewritten to \$OMARCHY_PATH, --enable-features merged"

# Case (b): same with NIXOS_OZONE_WL=1 WAYLAND_DISPLAY=w
out_b="$(OMARCHY_PATH="/custom/omarchy" NIXOS_OZONE_WL=1 WAYLAND_DISPLAY=w bash "$launcher")"
ef_count_b="$(grep -c -- '^--enable-features=' <<<"$out_b" || true)"
if [[ "$ef_count_b" -ne 1 ]]; then
  fail "b" "expected exactly 1 --enable-features= line, got $ef_count_b" "$out_b"
fi
ef_line_b="$(grep -- '^--enable-features=' <<<"$out_b")"
if [[ "$ef_line_b" != "--enable-features=FeatureA,FeatureB,FeatureC,WaylandWindowDecorations" ]]; then
  fail "b" "expected WaylandWindowDecorations in merged features, got $ef_line_b" "$out_b"
fi
echo "PASS (b): WaylandWindowDecorations appended when NIXOS_OZONE_WL and WAYLAND_DISPLAY are set"

# Case (c): caller argument --foo is the last line
out_c="$(OMARCHY_PATH="/custom/omarchy" NIXOS_OZONE_WL="" WAYLAND_DISPLAY="" bash "$launcher" --foo)"
last_c="${out_c##*$'\n'}"
if [[ "$last_c" != "--foo" ]]; then
  fail "c" "expected last line to be --foo, got $last_c" "$out_c"
fi
echo "PASS (c): caller argument --foo is the last line"

# Case (e): with OMARCHY_PATH unset, the path uses /run/current-system/sw/share/omarchy
out_e="$(env -u OMARCHY_PATH NIXOS_OZONE_WL="" WAYLAND_DISPLAY="" bash "$launcher")"
if ! grep -qxF -- "--load-extension=/run/current-system/sw/share/omarchy/default/chromium/extensions/copy-url,/run/current-system/sw/share/omarchy/x" <<<"$out_e"; then
  fail "e" "expected fallback /run/current-system/sw/share/omarchy when OMARCHY_PATH is unset" "$out_e"
fi
echo "PASS (e): unset OMARCHY_PATH falls back to /run/current-system/sw/share/omarchy"

# Case (d): with no file, the output is exactly --foo
rm -f "$conf"
out_d="$(OMARCHY_PATH="/custom/omarchy" NIXOS_OZONE_WL="" WAYLAND_DISPLAY="" bash "$launcher" --foo)"
if [[ "$out_d" != "--foo" ]]; then
  fail "d" "expected output with no file to be --foo" "$out_d"
fi
echo "PASS (d): missing file passes only caller arguments"
