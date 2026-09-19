---
status: draft
issue: 772
author: olafkfreund
---

# Intent: the GitHub Actions panel ships with nixarchy and is on by default

Closes #772.

## Problem

[nixarchy-ghtui](https://github.com/olafkfreund/nixarchy-ghtui) is the panel
that gltui (#770) was forked from. It shows GitHub Actions runs, and it has the
same gaps: nothing installs it, nothing installs `gh`, and it writes its own
menu rows into the user's menu file.

It also has one gap of its own: **nixarchy cannot redistribute it yet.**
- The repo was made public on 2026-09-19.
- As of that day it had **no licence** that GitHub detects
  (`gh repo view --json licenseInfo` reports none).

Code without a licence cannot be shipped to other people's machines, whatever
the repo's visibility.

## Proposed outcome

- Once the repo carries a licence that GitHub detects, the panel is installed
  and on by default, exactly like gltui:
  - panel-only, with `gh` and Python on the session's PATH;
  - nixarchy owns its menu rows;
  - Super+Alt+A for new installs.
- A user not logged in to `gh` sees the panel say so, and it stops polling.

## Affected users and systems

Every nixarchy desktop. It's the same nixarchy surface as #770 and reuses
what #770 adds. The plugin repo needs a LICENSE, a package that ships it, and
a way to turn off self-registration. The owner's machine has a hand-copied
checkout that is behind upstream.

## Constraints

- **Blocked until a licence is committed and detected.** A public repo is not
  a licensed one.
- It follows #770, which adds panel-only placement and runtime packages to the
  plugin set.
- Mode A stays inert.
- Every new check is proven to fail first (§1).

## Open questions

None. The owner decided the default and the key on 2026-09-19. The owner is
adding the MIT licence.
