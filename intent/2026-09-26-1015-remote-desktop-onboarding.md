---
status: approved
issue: 1015
author: olafkfreund
---

# Intent: Remote desktop you can turn on everywhere, and reach from the shell

## Problem

Remote desktop works on one machine and is a manual on the next.

Everything needed for a single host exists and is honest about itself.
`modules/services/hypr-rdp.nix` serves the running Hyprland session and refuses
twice -- at evaluation without a named secret, at runtime without a rendered
one -- because hypr-rdp fails open and will otherwise serve a desktop to
anyone. `data/services.nix:73` puts it in the menu.
`nixarchy secret new hypr-rdp-password` derives the host's age recipient from
its SSH host key and opens an editor. `docs/manual/remote-desktop.md` is 243
accurate lines.

What none of that answers is the second machine, or the moment you want to
connect.

**The second machine is a hand edit.** `ensure_policy` in `pkgs/secret.nix`
(lines 313-330) writes `.sops.yaml` whole only when the file is absent. On any
later host the file exists without a rule for `hosts/$HOST/secrets.yaml`, and
the command fails and prints a YAML block for the user to paste. The refusal is
right and should stay: a creation rule spliced in by pattern-matching is one
that can silently stop matching, and that failure is invisible until a secret
will not decrypt. But refusing is the whole of what we offer. There is no
supported way to say "add this machine", so a fleet of N is N passwords, N
`sops edit` sessions, and N-1 edits made by hand in a file whose syntax decides
whether anything can be decrypted at all.

**Connecting is a terminal exercise.** Turning the service on is one menu row;
everything after it is not. The secret, the two lines that must go in
`hosts/<host>/configuration.nix` rather than in the menu's own file -- because
a relative `./secrets.yaml` written there resolves one directory too deep once
`nixarchy apply` copies it -- then remembering which machine sits at which
tailnet address, and what the SSH forward was. Nothing in the shell knows which
of your machines serve RDP, and nothing opens one.

The result is a feature that a careful reader can use on their main desktop and
that nobody rolls out. The refusals are not the problem; the absence of a path
through them is.

## Proposed outcome

A person with several nixarchy machines can:

- run one command on a machine that is not the first and have it enrolled --
  policy updated, secret reachable -- instead of being handed YAML to paste
- open the omarchy shell on any of those machines, see which of their machines
  serve a desktop, and connect to one without knowing its address or the shape
  of an SSH forward
- turn incoming connections on from that same place, with the steps that need a
  rebuild or a password named as steps rather than met as errors

Observable: a second machine goes from "RDP is off" to "reachable from my
laptop" without opening an editor on `.sops.yaml` and without reading the
manual, and the manual stops being the only place the process exists.

## Affected users and systems

- anyone running nixarchy on more than one machine; on exactly one, nothing
  about today changes
- `pkgs/secret.nix` -- the CLI, its policy handling, and its refusals
- `.sops.yaml` and `hosts/<host>/secrets.yaml` in the user's own config repo,
  which is their file and not ours
- a new in-repo omarchy-shell plugin, alongside `pkgs/rebuild-panel/` -- the
  only plugin whose source already lives in this repository
- `modules/home.nix`, where `programs.nixarchy.defaultPluginSet` registers it
- `tests/qml.nix`, which is the only thing standing between a QML syntax error
  and a bar element that silently is not there
- `docs/manual/remote-desktop.md` and `docs/manual/secrets.md`

## Constraints

**Must not weaken either refusal.** The evaluation assertion and the
`ExecStartPre` guard exist because this daemon failed open once, verified in
v0.1.5 `src/config.rs:187-197`. Nothing added here may make it easier to reach
a running hypr-rdp with an empty password, and a shell plugin that offers to
"just turn it on" is exactly the shape that would.

**Must not edit `.sops.yaml` by pattern-matching.** The existing comment gives
the reason and it still holds. Enrollment has to produce a policy the user can
read and that sops itself agrees with, or refuse as it does now.

**Must not imply remote login.** hypr-rdp is a client of a compositor that is
already running. No session means nothing to connect to, and a machine rebooted
remotely is a machine you are locked out of. A list of machines in a shell
menu will read as "these are reachable"; it has to say what it actually knows.

**The host key does not exist until sshd has run.** Enrollment therefore has a
rebuild in the middle of it on a freshly installed machine, and cannot pretend
to be one step.

**The plugin is copied, not compiled.** Anything added under `pkgs/` in QML is
linted by `tests/qml.nix` or it is not checked at all.

**No credentials on screen or in a journal.** The existing guard prints nothing
from the rendered config for this reason.

**Mode A.** A machine importing `nixosModules.nixarchy` into its own
configuration must be untouched by all of this unless it opts in.

## Open questions

1. **One password or one per machine?** Per-host secrets are the smaller blast
   radius and what exists. A single shared secret encrypted to every host's
   recipient is one `sops edit` for the fleet and one password to rotate. Which
   is the default, and is the other supported?

2. **How much does the plugin do?** Three rungs: show state and print the
   commands; write `~/.config/nixarchy/services.nix` and hand off to
   `nixarchy apply`; or drive the whole thing including the secret. The third
   puts a password prompt in a QML panel, which I would rather not build.

3. **Where does the list of machines come from?** Tailscale already knows what
   is on the tailnet and is the recommended reach. Reading `tailscale status`
   is free and knows nothing about which hosts serve RDP; a list in the user's
   config repo knows, and drifts. Or probe 3389. Which is the source of truth?

4. **Bar widget, menu row, or both?** `rebuild-panel` is a bar widget that
   draws nothing until relevant. A remote-desktop entry is something you go
   looking for, which sounds like the menu -- but the menu is upstream's and
   `nixarchy.menu` is a separate opt-in plugin.

5. **Does connecting out belong here at all?** It needs an RDP client on the
   machine, which nothing currently installs, and the tunnel shape is one
   `ssh -L`. This may be two issues rather than one; splitting is a decision
   for the spec.

6. **Should the outbound half default to the SSH tunnel?** It needs no
   exposure, no firewall change and no new trust, and the authentication is the
   SSH key the user already has. Making it the only shape the plugin offers
   would be the safest default and would remove a decision from the user.
