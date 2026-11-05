"""Give a stock fcitx5 profile the layout the compositor is using (#1614)."""
import os
from pathlib import Path
import re

import configure as setup
import typing_setup

path = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "fcitx5/profile"
layout = typing_setup.keyboard_selection()[0].replace(":", "-")
if (layout != "us" and layout.split("-")[0] not in setup.NON_LATIN
    and re.fullmatch(r"[A-Za-z0-9_-]+", layout) and setup.stock_profile(setup.read(path))):
  setup.atomic_write(path, setup.profile_text(layout, "none"))
