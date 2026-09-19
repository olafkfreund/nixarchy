---
status: draft
issue: 770
author: olafkfreund
---

# Intent: the GitLab pipelines panel ships with nixarchy and is on by default

Closes #770.

## Problem

[nixarchy-gltui](https://github.com/olafkfreund/nixarchy-gltui) shows GitLab
pipelines in an Omarchy panel. No nixarchy user gets it unless they find the
repo, add a flake input, install `glab` and wire a key by hand. On the owner's
own machine it is a symlink to a development checkout.

The #766 mechanism (#775) can turn a plugin on once, but it only knows one
kind of plugin: a bar widget placed in the right-hand section. gltui is a
panel with no bar slot, and it needs a command (`glab`) that nixarchy does not
install. Something that can place a panel-only plugin, and bring the tools it
calls, does not exist yet.

The plugin also writes its own menu rows into the user's
`~/.config/omarchy/extensions/omarchy-menu.jsonc` whenever the panel loads. A
row the user deletes comes back, and nothing coordinates that writer with
anyone else.

## Proposed outcome

- A fresh install has the GitLab pipelines panel installed and enabled, and an
  existing install gets it once at its next update. Turned off in Setup >
  Plugins, it stays off.
- `glab` and the Python the panel runs are there, on the session's PATH.
- Its menu rows come from nixarchy. A row the user removes stays removed.
- New installs get Super+Alt+P for the panel.
- Someone not logged in to GitLab sees the panel say so, not a stream of
  errors.

## Affected users and systems

Every nixarchy desktop. On the nixarchy side:

- `flake.nix` (the input);
- the default-plugin set in `modules/home.nix`, which gains a way to say "panel
  only" and "these runtime packages";
- `modules/apps.nix` (the menu rows);
- the seeded binds in `pkgs/omarchy/default.nix`;
- tests and docs.

In the plugin repo, the package has to ship its licence, and
self-registration has to be switchable off.

## Constraints

- Mode A stays inert: importing the module with nothing enabled adds no
  package, hook, row or bind.
- The plugin set stays a set of shell plugins. Only a panel-only placement and
  runtime packages are added to it, not services or credentials.
- The MIT licence ships with the plugin, because the package redistributes it.
- The owner's machine carries a symlinked checkout, which the declarative
  install refuses to replace, so the change says how to move it.
- Every new check is proven to fail first (§1). A new `checks.<name>` needs a
  human's workflow edit (§4, §11).

## Open questions

None. The owner decided the default and the key on 2026-09-19.
