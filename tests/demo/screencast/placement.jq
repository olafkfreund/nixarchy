# #1479: where each to-be-hidden plugin sits on the bar, read from a shell.json snapshot.
# Input: the snapshot. Arg: --argjson ids '[…]' (ids prep will disable, bar-kind ones left out).
# Output: {placement: [{id, section, index, widget}…], duplicates: [id…]}.
# Only top-level widgets of each section count; a folder's `widgets` list rides along inside
# the folder's own `widget` object.
[ "left", "centerBegin", "center", "centerEnd", "tray", "right" ] as $sections
| [ .bar.layout as $layout
    | $sections[] as $s
    | ($layout[$s] // []) | to_entries[]
    | select(.value.id as $id | $ids | index($id))
    | { id: .value.id, section: $s, index: .key, widget: .value }
  ] as $placement
| { placement: $placement,
    duplicates: ($placement | group_by(.id) | map(select(length > 1) | .[0].id)) }
