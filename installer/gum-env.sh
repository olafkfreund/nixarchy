# gum's colours, matching the console palette in lib/ui.sh.
#
# Indexed, not hex: the framebuffer console has sixteen colours and maps
# anything else onto them, so naming them directly is both honest and what
# survives. 2 is the Tokyo Night green, 8 the dim grey, 3 the yellow.
#
# shellcheck shell=bash
export GUM_CHOOSE_CURSOR_FOREGROUND=2
export GUM_CHOOSE_SELECTED_FOREGROUND=2
export GUM_FILTER_INDICATOR_FOREGROUND=2
export GUM_FILTER_MATCH_FOREGROUND=2
export GUM_INPUT_CURSOR_FOREGROUND=2
export GUM_INPUT_PROMPT_FOREGROUND=2
export GUM_INPUT_PLACEHOLDER_FOREGROUND=8
export GUM_CONFIRM_SELECTED_BACKGROUND=2
export GUM_CONFIRM_SELECTED_FOREGROUND=0
export GUM_CONFIRM_PROMPT_FOREGROUND=3
export GUM_TABLE_HEADER_FOREGROUND=2
export GUM_TABLE_BORDER_FOREGROUND=8
