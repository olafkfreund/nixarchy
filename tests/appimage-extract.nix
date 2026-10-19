{ pkgs, omarchy }:
# #1368: an AppImage here runs through appimage-run (binfmt), which passes
# --appimage-extract on to the app, so a script that self-extracts one launches it.
pkgs.runCommand "nixarchy-appimage-extract" { } ''
  hits=$(grep -rn -- '--appimage-extract' ${omarchy}/share/omarchy/bin | grep -vE ':[0-9]+:[[:space:]]*#' || true)
  if [ -n "$hits" ]; then
    echo "these scripts self-extract an AppImage, which appimage-run passes to the app (#1368):" >&2
    echo "$hits" >&2
    exit 1
  fi
  touch "$out"
''
