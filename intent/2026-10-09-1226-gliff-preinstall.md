---
status: draft
issue: 1226
author: olafkfreund
---

# Intent: gliff installed by default

## Problem

Upstream Omarchy made gliff its remote desktop on 2026-10-09
(omacom/omarchy#14712). Three pieces landed together:

- `install/omarchy-base.packages` names `gliff`;
- a migration runs `omarchy-pkg-add gliff` on existing machines;
- a `remote-session` shell plugin shows a bar indicator while a
  `gliff-server` is serving this desktop.

gliff (omacom/gliff, MIT, Rust, v0.3.0) shows another machine's Hyprland
session in a window, over ssh only. That means no open port, no extra
account and no password. It sends full-colour 4:4:4 H.264, encoded on the
GPU through VA-API, and falls back to the CPU on NVIDIA or where no codec
is available.

nixarchy cannot use any of this, because gliff is not in nixpkgs and
nixarchy does not package it. Once the next Omarchy bump arrives, the bar
carries an indicator that can never light up. Users also have no way to
use the remote desktop that Omarchy now presents as standard.

Today nixarchy's remote desktop is hypr-rdp. It is opt-in, needs a sops
password, a certificate and a port, and exists so that RDP clients
(Windows `mstsc`, macOS, phones) can reach the desktop. gliff cannot do
that, because both ends must be Hyprland.

## Proposed outcome

- A fresh nixarchy machine has `gliff`, `gliff-server` and `gliff-probe` on
  its PATH, with **Gliff** in the app launcher, and no configuration is
  needed.
- `gliff user@host` from one nixarchy machine to another shows the remote
  session, provided the remote machine runs sshd and has a logged-in
  Hyprland session.
- Users who do not want gliff can drop it the way they drop any other
  preinstalled app.
- GPU encoding works on AMD and Intel. It does not quietly fall back to the
  CPU because of how the package was built.
- A check fails if `gliff-server` stops being reachable over ssh, or stops
  serving a picture.
- hypr-rdp, its options, its menu rows and `nixarchy-remote` are
  unchanged.

## Affected users and systems

- Every nixarchy machine gains one package (three binaries), with no
  service and no listening port.
- The flake gains one input, and the overlay and `packages` gain `gliff`.
- CI gains a build of about 230 crates, plus a cache entry so that users
  substitute the package rather than compile it.
- Mode A users, who import the module into a configuration they already
  run, get it only if they have preinstalls on, as with every other
  preinstalled app.

## Constraints

- Installing gliff must not start anything, listen on anything, or change
  any setting. Merely being installed has to be inert. A source review
  confirms this before the spec is approved.
- hypr-rdp stays as it is, and nothing in this task removes or demotes it.
- The cache allowlist stays within its 2 GB budget (§4, #697).
- Pin gliff to a release tag, not to a branch.

## Open questions

1. **Preinstall it, or always install it?** Putting gliff in the
   preinstalls set makes it removable with `preinstallsExclude = [ "gliff" ]`,
   but a machine with `preinstalls = false` will not have it. My
   recommendation is preinstalls, the same treatment as `moonlight-qt`.
2. **sshd.** The machine being connected *to* needs sshd, and nixarchy does
   not enable it by default. My recommendation is to leave it off and say
   so in the docs. Turning on sshd for every machine is a separate security
   decision, and gliff does not justify it.
3. **The Setup > Remote desktop menu.** Should "Connect to a machine" offer
   gliff now, or should that wait for a follow-up? My recommendation is a
   follow-up, which keeps this task to "the package is there and works".
