# #1479: put the plugins prep hid back. Inlined into screencast-restore's script and
# sourced by placement-test.sh, so the check runs the code restore runs.
# restore_plugins <manifest.json>; needs omarchy and omarchy-shell on PATH.
restore_plugins() {
  local manifest=$1 legacy=0 id kinds placed rec section index where answer key value
  local failed=" " arg

  # A take from before #1479 has no `placement`: every widget goes to the end of
  # the right section, the way it always did, and the verify says so.
  if ! jq -e 'has("placement")' "$manifest" >/dev/null; then
    legacy=1
    echo "screencast-restore: this take predates #1479; widget positions may differ." >&2
  fi

  # A plugin with a recorded bar widget is placed below, where it was. The rest
  # (services, overlays, panels) have no widget, and a bar-kind plugin takes no placement.
  while IFS=$'\t' read -r id kinds placed; do
    [ -n "$id" ] || continue
    arg=()
    case ",$kinds," in
      *,bar,*) ;;
      *)
        [ "$legacy" = 1 ] || [ "$placed" != 1 ] || continue
        [ "$legacy" = 0 ] || arg=(right)
        ;;
    esac
    echo "  restoring $id"
    omarchy plugin enable "$id" "${arg[@]}" >/dev/null 2>&1 || echo "  (could not enable $id)" >&2
  done < <(jq -r '(.placement // []) as $p | .disabled[]
    | "\(.id)\t\(.kinds | join(","))\t\(.id as $i | if any($p[]; .id == $i) then 1 else 0 end)"' "$manifest")

  [ "$legacy" = 0 ] || return 0

  # putBarWidget leaves a widget that is already on the bar alone, so a re-run
  # changes nothing. "not ready" means the registry is still scanning. After a
  # failure nothing more goes into that section: a later widget would land at
  # the wrong index, and a re-run can place the rest in order.
  while IFS= read -r rec; do
    id=$(jq -r '.id' <<<"$rec")
    section=$(jq -r '.section' <<<"$rec")
    index=$(jq -r '.index' <<<"$rec")
    case "$failed" in
      *" $section "*)
        echo "  (skipped $id: an earlier $section widget failed; re-run screencast-recover)" >&2
        continue
        ;;
    esac
    echo "  restoring $id"
    answer=""
    for _ in 1 2 3 4 5 6 7 8 9 10 11; do
      answer=$(omarchy-shell shell putBarWidget "$id" "{\"section\":\"$section\",\"index\":$index}" 2>&1 | tr -d '"' || true)
      case "$answer" in *"not ready"*) sleep 0.5 ;; *) break ;; esac
    done
    if [ "$answer" != "ok" ]; then
      echo "  (could not restore $id: $answer)" >&2
      failed="$failed$section "
      continue
    fi
    # Disabling dropped the widget object with its settings; put them back.
    where=$(jq -nc --arg s "$section" '{section: $s}')
    while IFS= read -r key; do
      value=$(jq -c --arg k "$key" '.widget[$k]' <<<"$rec")
      answer=$(omarchy-shell shell setBarWidget "$id" "$key" "$value" "$where" 2>&1 | tr -d '"' || true)
      [ "$answer" = "ok" ] || echo "  (could not restore $id $key: $answer)" >&2
    done < <(jq -r '.widget | keys_unsorted[] | select(. != "id")' <<<"$rec")
  done < <(jq -c '.placement | sort_by([.section, .index])[]' "$manifest")
}
