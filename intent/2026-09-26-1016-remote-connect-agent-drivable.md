---
status: approved
issue: 1016
author: olafkfreund
---

# Intent: Reaching another machine's desktop, by a person and by an agent

## Problem

#1015 made a machine easy to turn *on*. Reaching one is still a terminal
exercise, and the half of the request that motivated splitting this out --
that the thing be drivable by the ai-mirror plugin -- turns out not to mean
what it sounds like.

**For a person**, connecting today means knowing which machine is at which
tailnet address, remembering the shape of an SSH forward, and having an RDP
client installed. Nothing in the shell lists the machines, nothing opens one,
and no RDP client exists anywhere in this tree -- so a menu row offering to
connect would name something that does not exist.

**For an agent**, the obvious reading of "control it through the RDP client"
does not work, and it is better to say so now than to discover it after
choosing a client. **AT-SPI does not cross RDP.** The remote desktop arrives
as a pixel buffer, so `a11y_tree`, `a11y_find` and `a11y_act` would see the
freerdp window's own chrome and nothing inside the session. Through RDP an
agent is reduced to `screenshot` plus coordinate `input`, which makes exact
1:1 pixel mapping the property everything depends on -- and makes every
interaction a guess at where a widget is.

Meanwhile the thing that would work is already installed. ai-mirror is a
first-class nixarchy feature: `programs.nixarchy.aiMirror.mcp` writes its
server into three agent configs, as a **stdio** command
(`modules/home.nix:61` -- `command = ".../bin/ai-mirror"`, `args = ["mcp"]`).
A stdio MCP server is reachable over SSH by running it there, which is the
same tunnel this issue opens anyway. An agent on machine A that reaches
machine B's ai-mirror gets B's real accessibility tree and real window list.
Pixel-pushing through an RDP window gets coordinates and hope.

So this issue is really two things that share a tunnel, and the risk is
building the weaker one because it was the one that got asked for.

## Proposed outcome

From a machine on the tailnet:

- a person picks another machine from the shell, and a desktop opens, with no
  port exposed anywhere and no address memorised -- the authentication is the
  SSH key they already have
- an agent working on that machine can drive the remote desktop through the
  remote machine's own accessibility tree, not through pixels, and the person
  whose desktop it is still gets to refuse
- neither path requires the user to know what an SSH forward is

Observable: `nixarchy remote connect` opens a desktop, and an agent asked to
click something on a remote machine can name the widget rather than a
coordinate.

## Affected users and systems

- anyone with more than one nixarchy machine; on one machine nothing changes
- `pkgs/omarchy/nix-bin/nixarchy-remote`, which gains a `connect` verb
- `pkgs/omarchy/default.nix`, the `setup.remote` menu group #1015 created with
  one child, for the second
- `data/apps.nix`, for an RDP client -- there is none in the tree today
- `modules/home.nix`, if the agent half becomes a declared MCP entry
- the person at the far end, who may be sitting in front of the session being
  connected to, and who is not necessarily the person connecting

## Constraints

**The tunnel is the only reach.** Settled in #1015 and unchanged: no port is
opened, `bind` stays where it is, and the authentication that matters is the
user's existing SSH key. Anything here that would want a listening port is
out of scope rather than a trade to weigh.

**It is not remote login.** hypr-rdp serves a session that is already logged
in. A list of machines in a menu will read as "these are reachable"; it has to
say what it actually knows, which is "these are machines you can SSH to".

**An agent reaching another machine's desktop is a larger grant than it
looks.** ai-mirror drives the real desktop and asks for control with a dialog
*on that desktop*. Over SSH that dialog appears on a machine the requester may
not be sitting at, and may be answered by nobody or by somebody else. Whatever
is built must not turn a refusal into a timeout that reads as consent, and
must not make an agent's reach across machines quieter than its reach on one.

**No credentials on screen, in a journal, or in a process list.** Same rule as
the serve half.

**Mode A.** Nothing here may touch a machine that has not opted in.

**A row must not name what is absent.** No RDP client ships today, so the
`connect` row is gated on one being on PATH, as #1015's spec already set out.

## Open questions

1. **Is the agent half actually this issue's job?** If reaching a remote
   ai-mirror over SSH is right, it is a config entry and some documentation,
   and it has nothing to do with RDP except sharing a tunnel. It might be a
   better issue on its own, leaving this one as "a person connects". I lean
   that way and want it decided before anything is designed.

2. **Which freerdp client?** `freerdp` 3.32.0 ships `xfreerdp` (X11 via
   Xwayland, most geometry flags), `wlfreerdp` (native Wayland) and
   `sdl-freerdp` (upstream's actively developed one). None has AT-SPI, so if
   the agent half moves out, the criterion becomes what a *person* wants --
   which is a different answer from the 1:1 pixel fidelity an agent needs.

3. **Does the remote consent dialog make SSH-reached ai-mirror unusable, or
   is that the feature?** A dialog nobody answers is a refusal, which is safe
   and possibly useless. The honest answer may be that an agent may drive a
   remote desktop only when someone is at it.

4. **Where does the machine list come from?** #1015 settled this for its own
   purposes as `~/.ssh/config` plus `tailscale status --json`, nothing probed.
   Worth confirming it still holds when the list is offered to a person
   choosing a desktop rather than printed as information.

5. **What can be checked at all?** No check in this repo opens an RDP
   connection -- `checks.session` boots one desktop and this needs two. That
   hole is already named in `tests/install-matrix.py` and `tests/AGENTS.md`.
   The question for the spec is which parts *can* be reached cheaply: the
   client's pixel fidelity is measurable with two processes and no second
   machine, and an MCP-over-SSH entry is checkable as configuration.
