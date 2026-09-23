# Two cuts from one master (#930, plan step 8).
#
# Scripted ffmpeg rather than kdenlive, because the point of this issue is that
# the SECOND recording should be cheap. A timeline somebody dragged by hand
# costs the same the next time; a filter graph in a file does not.
#
# The captions come from the same shots.nix that drove the take and the same
# beats.json the driver wrote, so a caption cannot describe a beat that did not
# happen -- it is placed at the beat's OBSERVED time, and the gate has already
# refused the master if that beat was not on screen.
{
  pkgs,
  shots ? import ./shots.nix,
}:
let
  # One drawtext per captioned beat, escaped for ffmpeg's filter parser.
  #
  # The COMMA is the one that bit. ffmpeg separates filters in a chain with
  # commas, so a caption reading "the Omarchy desktop, on NixOS" ended its
  # drawtext early and ffmpeg reported `No such filter: '6'` -- naming a
  # fragment of the next beat's timestamp rather than anything a reader would
  # connect to punctuation. ':' separates a filter's own options, and "'"
  # quotes a value.
  escape = s: builtins.replaceStrings [ "\\" ":" "'" "%" "," ] [ "\\\\" "\\:" "’" "\\%" "\\," ] s;

  captioned = builtins.filter (b: (b.caption or "") != "") shots.beats;

  # The label is carried so the shell can look the observed time up rather than
  # this file guessing when a beat landed.
  captionLines = pkgs.lib.concatMapStringsSep "\n" (
    b:
    builtins.concatStringsSep "\t" [
      b.label
      (toString b.hold)
      (if b.caption == "" then "-" else escape b.caption)
    ]
  ) captioned;

  captionFile = pkgs.writeText "screencast-captions.usv" captionLines;
in
{
  edit = pkgs.writeShellApplication {
    name = "screencast-edit";
    runtimeInputs = [
      pkgs.ffmpeg
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      dir=''${1:-$PWD}
      master="$dir/master.mkv"
      beats="$dir/beats.json"
      music=''${SCREENCAST_MUSIC:-}

      [ -f "$master" ] || { echo "screencast-edit: no master at $master" >&2; exit 1; }
      [ -f "$beats" ] || { echo "screencast-edit: no beats.json at $beats" >&2; exit 1; }

      font=$(fc-match -f '%{file}' 'DejaVu Sans' 2>/dev/null || true)
      [ -n "$font" ] || font=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf

      # ---- the clean cut -----------------------------------------------------
      # For the front page. NO audio stream at all rather than a silent one: a
      # muted track is still a track, and a hero video should carry nothing it
      # does not use. faststart so the moov atom is at the front and a browser
      # can start playing before the whole file arrives.
      echo "screencast-edit: clean cut"
      ffmpeg -v error -i "$master" -an \
        -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
        -movflags +faststart -y "$dir/nixarchy-clean.mp4"

      # A poster, so the page shows something before anyone presses play and
      # nothing downloads until they do.
      ffmpeg -v error -ss 1 -i "$master" -frames:v 1 -y "$dir/nixarchy-poster.jpg"

      # ---- the social cut ----------------------------------------------------
      # Captions placed at each beat's OBSERVED time, read from beats.json. A
      # caption timed from the shot list instead would drift by exactly the lag
      # the observed times exist to absorb.
      filter=""
      while IFS=$'\t' read -r label hold caption; do
        [ -n "$label" ] || continue
        [ "$caption" != "-" ] || continue
        at=$(jq -r --arg l "$label" '.beats[] | select(.label == $l) | .at' "$beats")
        [ -n "$at" ] && [ "$at" != "null" ] || continue
        # Lower third, fading in over the first third of the beat.
        end=$(awk -v a="$at" -v h="$hold" 'BEGIN { printf "%.2f", a + h }')
        [ -z "$filter" ] || filter="$filter,"
        filter="$filter""drawtext=fontfile=$font:text='$caption'"
        filter="$filter"":fontsize=34:fontcolor=white:borderw=3:bordercolor=black@0.6"
        filter="$filter"":x=(w-tw)/2:y=h-140:enable='between(t,$at,$end)'"
      done < ${captionFile}

      if [ -z "$filter" ]; then
        echo "screencast-edit: no captions could be placed -- beats.json and the" >&2
        echo "shot list share no labels. Refusing rather than shipping a silent cut." >&2
        exit 1
      fi

      echo "screencast-edit: social cut"
      if [ -n "$music" ] && [ -f "$music" ]; then
        # -shortest so the bed cannot outlast the picture; loudnorm to -14 LUFS,
        # which is what every social platform normalises to anyway, so mixing
        # louder only means being turned down with less headroom.
        ffmpeg -v error -i "$master" -stream_loop -1 -i "$music" \
          -filter_complex "[0:v]''${filter}[v];[1:a]volume=0.12,afade=t=in:d=1.5,loudnorm=I=-14:TP=-1.5[a]" \
          -map '[v]' -map '[a]' -shortest \
          -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -c:a aac -b:a 160k \
          -movflags +faststart -y "$dir/nixarchy-social.mp4"
      else
        echo "  (no SCREENCAST_MUSIC set -- captions only, no bed)"
        ffmpeg -v error -i "$master" -vf "$filter" -an \
          -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p \
          -movflags +faststart -y "$dir/nixarchy-social.mp4"
      fi

      echo "screencast-edit: wrote"
      for f in nixarchy-clean.mp4 nixarchy-poster.jpg nixarchy-social.mp4; do
        [ -f "$dir/$f" ] && printf '  %-24s %s\n' "$f" "$(du -h "$dir/$f" | cut -f1)"
      done
    '';
  };
}
