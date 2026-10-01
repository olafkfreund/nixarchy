#!/usr/bin/env bash
# NixOS installs these user units with wantedBy. First-run runs inside the
# graphical session, after its targets have started them. Never enable a
# linked store unit here: that pins this user's unit to one generation.
exit 0
