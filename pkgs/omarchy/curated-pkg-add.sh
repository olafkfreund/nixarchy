#!/usr/bin/env bash
# omarchy:summary=Install packages curated by Omarchy
# omarchy:args=<packages...>
# omarchy:hidden=true

# Quattro's polkit/pacman route has no NixOS equivalent; use the existing
# declarative package guard so callers stop before configuring absent apps.
exec omarchy-pkg-add "$@"
