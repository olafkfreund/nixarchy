---
status: draft
issue: 771
author: olafkfreund
---

# Intent: the herdr sessions widget ships with nixarchy and is on by default

Closes #771.

## Problem

[nixarchy-herdr](https://github.com/olafkfreund/nixarchy-herdr) puts herdr's
agent sessions on the bar and in a menu. It reaches a nixarchy user only by a
`git clone` into `~/.config/omarchy/plugins`, and it does nothing without the
`herdr` binary, which nixarchy does not install. The repo has no flake, so
there is nothing to pin as-is.

Two things in the plugin make it unsafe to hand to everyone as it is:

- **Delete removes a session without asking**, on a keypress or a click.
- **A failed delete reports success**: `herdr session delete ... || true`
  swallows the error.

## Proposed outcome

- A fresh install has the herdr widget installed, enabled and in the right bar
  section, with `herdr` and the tools the widget calls. An existing install
  gets it once at its next update, and a user who turns it off keeps it off.
- Deleting a session asks first, and says when it failed.
- New installs get Super+Alt+H. The repo suggests Super+Shift+H, which does not
  follow the Super+Alt convention the other default plugins use.

## Affected users and systems

Every nixarchy desktop. On the nixarchy side:

- `flake.nix` (a non-flake input, wrapped by nixarchy);
- the default-plugin set, with its runtime packages (`herdr` from nixpkgs,
  `jq`, `iproute2`);
- menu rows, the seeded binds, tests and docs.

In the plugin repo, the Delete fix. On the owner's machine, a hand-copied
plugin directory and a `herdr` binary that comes from a different flake input.

## Constraints

- **The Delete confirmation and honest errors land upstream before this ships
  as a default.**
- **Both copyright holders** named in the MIT licence travel with the wrapped
  package.
- The `herdr` in nixpkgs (0.9.0 at the pin) is checked against the commands
  the widget sends.
- Mode A stays inert.
- Every new check is proven to fail first (§1). No new `checks.<name>` without
  a human's workflow edit (§4, §11).

## Open questions

- **Which `herdr` binary does the owner's machine keep?** Today it comes from
  `github:ogulcancelik/herdr` in `/etc/nixos`, while the default would install
  the nixpkgs one. The two can coexist on PATH, but only one wins.
