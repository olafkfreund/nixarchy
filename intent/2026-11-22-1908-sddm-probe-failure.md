---
status: approved
issue: 1908
author: x
---

# Intent: the after-sleep SDDM recovery never ends a live session on a failed probe

## Problem

Since #1905, every sleep unit runs quattro's `omarchy-system-sddm-recover`. It
restarts `display-manager.service` when its `loginctl | awk` probe finds no
session on a seat. The test is `if awk …; then exit 0; fi`, so an awk that exits
non-zero for any reason reads as "no seat". `loginctl` output awk cannot read
(an error printed on stdout, a changed column layout) also reads as "no seat".
Either way the restart ends the user's live desktop session after resume.

## Proposed outcome

A restart happens only when the probe ran, read every line, and found no seated
session. A failing awk or unreadable output leaves the display manager alone.

## Affected users and systems

Edge users with SDDM on a quattro pin that ships the script (from ebd2974).
main's v4.5.0 tag ships no recovery script.

## Constraints

Hold under main's tag and older edge pins: patch only where the script exists, as
#1905's patch does. An empty session list must still restart, as upstream does.
Not filed upstream (owner).

## Open questions

None.
