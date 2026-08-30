# The installer's face: a palette, a wordmark, and one screen at a time.
#
# Upstream Omarchy draws a green wordmark centred at the top of every screen
# over a Tokyo Night console, and that -- not the questions, which are much the
# same anywhere -- is what makes an install look like Omarchy rather than like
# a shell script. This is the same shape with our own mark.
#
# shellcheck shell=bash

# Tokyo Night, set on the console itself rather than through per-string colour
# codes, so everything drawn afterwards inherits it: gum's widgets, nix's
# output, a kernel message that arrives mid-screen.
#
# \e]P<index><rrggbb> is the Linux framebuffer console's palette escape. It is
# silently ignored elsewhere, which is the desired behaviour when someone runs
# the installer from a terminal emulator that already has its own theme.
ui_palette() {
  printf '\e]P01a1b26'  # black          background
  printf '\e]P1f7768e'  # red
  printf '\e]P29ece6a'  # green          the wordmark
  printf '\e]P3e0af68'  # yellow         warnings
  printf '\e]P47aa2f7'  # blue
  printf '\e]P5bb9af7'  # magenta
  printf '\e]P67dcfff'  # cyan
  printf '\e]P7a9b1d6'  # white
  printf '\e]P8414868'  # bright black   dim hints
  printf '\e]P9f7768e'
  printf '\e]Pa9ece6a'
  printf '\e]Pbe0af68'
  printf '\e]Pc7aa2f7'
  printf '\e]Pdbb9af7'
  printf '\e]Pe7dcfff'
  printf '\e]Pfc0caf5'
  ui_init
  clear
}

# stty first, tput second.
#
# tput needs TERM, and a systemd service does not get one -- which is how the
# installer ended up drawing a 92-column wordmark into an assumed 80-column
# console, clipped at the left edge with everything else at column zero. stty
# asks the kernel about the terminal itself and does not care about TERM.
# How wide is the console, really?
#
# Three ways this has already gone wrong, all of which looked like success:
#
#   tput needs TERM, and a systemd service does not get one.
#   stty with no redirect reads whatever stdin happens to be.
#   stty can answer "0 0" -- not an error, not empty, just unknown. A check
#   for a non-empty answer accepts that happily and yields a width of zero,
#   which is how a 92-column wordmark ended up at column zero.
#
# So: ask several sources, and believe none of them without a positive number.
ui_dimension() {
  local field=$1 src size value
  for src in - /dev/tty /dev/tty1 /dev/console; do
    if [ "$src" = - ]; then
      size=$(stty size 2>/dev/null) || continue
    else
      # Readability first: a failed redirect reports itself in the CALLING
      # shell, so 2>/dev/null inside the substitution does not silence it and
      # "Permission denied" prints across the installer.
      [ -r "$src" ] || continue
      size=$(stty size <"$src" 2>/dev/null) || continue
    fi
    [ -n "$size" ] || continue
    if [ "$field" = cols ]; then value=${size#* }; else value=${size%% *}; fi
    case $value in
      '' | *[!0-9]*) continue ;;
    esac
    [ "$value" -gt 0 ] && {
      echo "$value"
      return
    }
  done

  # The framebuffer's geometry is a guess about the console, not a fact about
  # it: the VT may not use the whole framebuffer and the font may not be 8x16.
  # Guessing too WIDE truncates the wordmark, which is worse than guessing too
  # narrow, so anything derived from here is marked unconfirmed and the compact
  # mark is used instead of the wide one.
  if [ -r /sys/class/graphics/fb0/virtual_size ]; then
    local fb fw fh
    fb=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null) || fb=""
    fw=${fb%%,*}
    fh=${fb##*,}
    case $fw in '' | *[!0-9]*) fw=0 ;; esac
    case $fh in '' | *[!0-9]*) fh=0 ;; esac
    if [ "$fw" -gt 0 ] && [ "$fh" -gt 0 ]; then
      if [ "$field" = cols ]; then value=$((fw / 8)); else value=$((fh / 16)); fi
      [ "$value" -gt 0 ] && {
        UI_SIZE_UNCONFIRMED=1
        echo "$value"
        return
      }
    fi
  fi

  # tput last: it wants TERM and a terminfo database, and has neither to spare.
  value=$(TERM=${TERM:-linux} tput "$([ "$field" = cols ] && echo cols || echo lines)" 2>/dev/null) || value=0
  case $value in
    '' | *[!0-9]*) value=0 ;;
  esac
  [ "$value" -gt 0 ] && {
    echo "$value"
    return
  }

  [ "$field" = cols ] && echo 80 || echo 24
}

ui_cols() { ui_dimension cols; }
ui_rows() { ui_dimension rows; }

# Two marks, because one does not fit everywhere.
#
# The wide one is the same figlet delta_corps_priest_1 NIXARCHY the manual
# uses, at 92 columns. That is 24% wider than upstream's OMARCHY -- eight
# letters against seven -- and on a console around a hundred columns it fills
# the screen edge to edge, so centring it leaves four columns of margin and
# reads as "not centred" because it is not centred by much.
#
# The compact one is 61 columns and leaves room to breathe. Which one is drawn
# depends on how much space there is, which is the only sensible answer when
# the console can be anything from 80 columns to 240.
UI_LOGO_WIDE_COLS=92
UI_LOGO_COMPACT_COLS=61
UI_LOGO_COLS=92

# One left edge for everything.
#
# The mark is centred, and every line under it -- headings, prompts, the bar,
# and gum's own widgets -- starts at the mark's LEFT edge rather than being
# centred on its own. That single rule is most of what makes upstream's screens
# look composed instead of scattered: centring each line individually gives a
# ragged middle column, which is what this looked like before.
#
# gum draws at column zero unless told otherwise, so its padding is set here
# from the same number. Every widget the installer uses takes it.
ui_init() {
  local cols
  UI_SIZE_UNCONFIRMED=""

  # Wait, briefly, for the console to know how big it is.
  #
  # The installer starts as soon as multi-user is up, and tty1 does not always
  # answer for its size yet. A single early reading of 80 is indistinguishable
  # from a genuinely narrow terminal, so the first screen drew the fallback
  # wordmark at column zero while every screen after it was centred correctly.
  #
  # Half a second of retrying costs nothing and removes the whole class of
  # problem. If it is still 80 after that, it really is a narrow console.
  for _ in 1 2 3 4 5; do
    cols=$(ui_cols)
    [ "$cols" -ge "$((UI_LOGO_COMPACT_COLS + 2))" ] && break
    sleep 0.1
  done

  # The wide mark only when there is room for it to look deliberate AND the
  # width came from the terminal itself. A framebuffer-derived width that is
  # too large draws a 92-column mark into a narrower console and truncates it
  # mid-word, which is what "NIXARC" on screen was.
  if [ "$cols" -ge $((UI_LOGO_WIDE_COLS + 24)) ] && [ -z "${UI_SIZE_UNCONFIRMED:-}" ]; then
    UI_LOGO=$UI_LOGO_WIDE
    UI_LOGO_COLS=$UI_LOGO_WIDE_COLS
  else
    UI_LOGO=$UI_LOGO_COMPACT
    UI_LOGO_COLS=$UI_LOGO_COMPACT_COLS
  fi
  export UI_LOGO UI_LOGO_COLS
  UI_PAD=$(((cols - UI_LOGO_COLS) / 2))
  [ "$UI_PAD" -lt 0 ] && UI_PAD=0
  export UI_PAD

  local pad="0 0 0 $UI_PAD"
  export GUM_CHOOSE_PADDING="$pad"
  export GUM_INPUT_PADDING="$pad"
  export GUM_FILTER_PADDING="$pad"
  export GUM_CONFIRM_PADDING="$pad"
  export GUM_TABLE_PADDING="$pad"
}

# How many rows a widget may use without pushing the wordmark off the top.
# gum takes as much of the screen as it likes otherwise, and a list that
# scrolls the mark away undoes the whole point of drawing it.
ui_widget_height() {
  local rows h
  rows=$(ui_rows)
  # 9 rows of mark, a blank, a heading, a blank, and gum's own footer.
  h=$((rows - 16))
  [ "$h" -lt 5 ] && h=5
  [ "$h" -gt 15 ] && h=15
  echo "$h"
}

# gum's padding flag, for the widgets that honour it. Passed explicitly rather
# than left to the environment: `gum confirm` picks up GUM_CONFIRM_PADDING and
# `gum choose` was observed not to, and an explicit flag is one less thing that
# has to be true.
ui_gum_pad() { echo "0 0 0 ${UI_PAD:-0}"; }

# Indent something that has already been rendered. gum table ignores padding
# entirely -- both the flag and the variable -- and it is the one widget whose
# output is printed rather than driven, so it can simply be shifted.
ui_indent() { sed "s/^/$(printf '%*s' "${UI_PAD:-0}" '')/"; }

# A line centred on the screen, for the few lines we draw ourselves.
#
# Only used where it helps: the install dashboard and the finish screen, which
# are three or four short lines each. The question screens stay aligned to the
# mark's left edge -- centring a 45-entry keyboard list line by line gives a
# ragged left edge that is harder to read, and gum cannot centre its widgets
# anyway, so a centred heading would sit above a left-aligned list. Upstream
# splits it the same way.
#
# The width has to be passed in: the text carries colour escapes, and counting
# those as characters is what puts a "centred" line off by ten columns.
ui_centre() {
  local text=$1 width=$2 cols pad
  cols=$(ui_cols)
  pad=$(((cols - width) / 2))
  [ "$pad" -lt 0 ] && pad=0
  printf '%*s%b\n' "$pad" "" "$text"
}

# A line at the shared left edge. %b so callers can pass colour escapes.
ui_left() { printf '%*s%b\n' "${UI_PAD:-0}" "" "$1"; }

# Indexed green, not truecolor. The framebuffer console crushes 24-bit colour
# to the nearest palette entry anyway, and upstream renders their mark with
# `gum style --foreground 2` for exactly this reason.
ui_logo() {
  # A console narrower than the mark would wrap it into nonsense, so draw
  # something that fits rather than rubbish.
  if [ "$(ui_cols)" -lt $((UI_LOGO_COLS + 2)) ]; then
    ui_left "\e[1;32mN I X A R C H Y\e[0m"
    echo
    return
  fi

  while IFS= read -r line; do
    printf '\e[32m%*s%s\e[0m\n' "${UI_PAD:-0}" "" "$line"
  done <"$UI_LOGO"
  echo
}

# One screen: clear it, draw the mark, then the single line saying what this
# screen is for. Every question the installer asks starts here, so a user is
# never looking at a scrollback of what came before.
ui_screen() {
  # Recomputed per screen rather than once at startup: an early wrong answer
  # about the console size would otherwise persist for the whole install, and
  # that is exactly what happened.
  ui_init
  clear
  echo
  ui_logo
  # Two tones, as upstream has: what we are doing in plain text, then the
  # question itself in blue. One line of context before a prompt is the
  # difference between a form and an interrogation.
  [ $# -gt 0 ] && {
    ui_left "$1"
    echo
  }
}
