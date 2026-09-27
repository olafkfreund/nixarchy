---
status: draft
issue: 1016
intent: intent/2026-09-26-1016-remote-connect-agent-drivable.md
---

# Spec: Connecting to another machine's desktop, from the menu

## Two calls made without an answer, reversible at this gate

The intent was approved without its open questions answered. Both had a stated
lean and both are taken here, prominently rather than quietly, because either
one is a reasonable thing to reject:

**Q1 — the agent half leaves.** It is now **#1018**. An agent driving a remote
machine wants that machine's accessibility tree, which is an MCP-over-SSH
config question with no RDP in it; keeping it here would have made the client
choice carry a requirement no client can meet. #1016 is now one sentence: **a
person picks a machine and a desktop opens.**

**Q3 — the consent-dialog question goes with it**, to #1018, since it is about
an agent's reach and not about a person's.

If either call is wrong, reject this spec; nothing downstream has been built
on them.

## Decisions carried in

From #1015's approved spec, unchanged: **the SSH tunnel is the only reach**,
no port is opened, and the menu is `omarchy-menu.jsonc` rows plus a `gum`
wizard, not QML. From #1015's implementation: the `setup.remote` group exists
with one child, and `nixarchy-remote` exists with a `serve` verb and a
dispatcher row.

## Design

### 1. The client: `freerdp`, and `sdl-freerdp` is the one to launch

Measured rather than chosen from documentation. `freerdp` 3.32.0 ships three
clients and **one of them is deprecated by upstream, which the binary says
itself**:

```
$ wlfreerdp --version
[WARN] wlfreerdp client has been deprecated
[WARN] As replacement there is a SDL3 based client available.
```

So the choice is `xfreerdp` (X11, through Xwayland) or `sdl-freerdp` (SDL3).
Their flag surface is identical -- FreeRDP 3 shares one command line, and both
help texts carry `dynamic-resolution`, `smart-sizing`, `clipboard` and
`multimon` -- so capability does not decide it. What decides it is that
upstream deprecated its Wayland client **in the SDL3 client's favour**, so
`sdl-freerdp` is the one that will still be there at the next bump, and it
needs no Xwayland hop on a Hyprland session.

`xfreerdp` stays available and documented as the fallback for anyone who
prefers X11: nixpkgs ships all three from the single `freerdp` package, so
this is a launch choice rather than a packaging one.

**`/dynamic-resolution` is the flag that makes this pleasant**, and it pairs
with a decision already made in the module: hypr-rdp creates a headless output
by default, which resizes to the client. So the session follows the window
rather than letterboxing, and `output` stays the opt-out it already is.

`freerdp` goes in `data/apps.nix` as an opt-in catalogue entry, not into
`pkgs/omarchy/default.nix`'s runtime list: it is needed only by the machine
doing the connecting, and the menu gate below makes its absence honest rather
than broken.

### 2. `nixarchy-remote connect`

A second verb on the command #1015 created, in the same `gum` shape.

**The machine list**, confirming #1015's answer now that it is offered to a
person rather than printed: `~/.ssh/config` `Host` entries plus, when
`tailscale` is on PATH, `tailscale status --json` peers, merged and
deduplicated. **Nothing is probed.** With tunnel-only as the reach, SSH
working is the precondition for connecting at all, so the SSH config is the
list of machines the user can actually reach, and the tailnet supplies names
for machines they have not given an SSH entry yet.

The list says what it knows. A machine on it is one you can *try*, not one
that is serving a desktop -- hypr-rdp serves a session that is already logged
in, so a machine with nobody at it has nothing to connect to, and the wizard
says so rather than letting the list imply otherwise.

**The tunnel** is `ssh -N -L <free port>:localhost:3389 <host>`, on a port
chosen free rather than 3389, so connecting to a second machine does not
collide with the first. It is torn down when the client exits; the wizard owns
both processes and does not leave a forward behind.

**The client** is then launched against `localhost:<port>` with
`/dynamic-resolution`, and the username defaulting to `nixarchy` -- the
module's own default, which is deliberately not the login name.

**The first connection shows a certificate warning and that is not a bug.**
hypr-rdp generates a self-signed pair once and reuses it, so the guarantee is
pinning: accept it on a connection you have reason to trust, and be suspicious
if it changes. The wizard says this before the client opens, because a warning
explained afterwards is a warning people learn to click through.

### 3. The menu row

`setup.remote.connect`, the second child of the group #1015 created, gated:

```
"when":"command -v sdl-freerdp >/dev/null || command -v xfreerdp >/dev/null"
```

A row offering to connect with no client installed is something we ship naming
something that does not exist. The glyph is copied from a row that already
renders, as #1015's was -- a Private Use Area codepoint the shipped font lacks
is a literal empty box in the menu.

### Also changed

- `data/bin-ledger.nix` -- the `nixarchy-remote` row's reason gains the second
  verb; the `allow` field may need `ssh` or a process-spawn class, which the
  ledger check will state rather than me guessing here
- `tests/menu-verbs.nix` -- no change needed: `nixarchy-remote` is registered
  and `connect` joins its `case` block, so the existing scan covers the row
- `docs/manual/remote-desktop.md` -- the connecting section, replacing the
  hand-rolled `ssh -L` instructions with the row that does it

## Alternatives rejected

**`wlfreerdp`.** Deprecated by upstream, which the binary announces on every
run. Shipping a menu row onto a deprecated client is buying a migration.

**`xfreerdp` as the default.** Equally capable and more mature, and it needs
Xwayland for a session that is otherwise native. Kept as the documented
fallback rather than the default.

**Remmina or another GUI client.** It would bring saved connections, which is
the one thing this design genuinely lacks -- and a second place to configure
machines, which then disagrees with the SSH config. Worth revisiting if people
ask for saved connections specifically.

**Bundling `freerdp` into the omarchy runtime list.** It would land on every
machine including those only ever connected *to*.

**Probing 3389 to build the list.** It answers "something is listening", not
"there is a desktop there", and it turns opening a menu into a port scan of
the tailnet.

**A list of RDP machines in the config repo.** It is the only source that
would know which hosts actually serve RDP, and it is a hand-maintained list of
things that exist elsewhere, which fails open.

**Leaving the tunnel up after the client exits.** A forward nobody can see is
a forward nobody closes.

## Risks

- **The list implying reachability.** Carried as wording, which no check
  enforces. The mitigation is that the wizard states what the list is (machines
  you can SSH to) rather than what it is not.
- **A client that scales or letterboxes** makes the remote desktop subtly
  wrong in a way people work around rather than report. `/dynamic-resolution`
  against the headless output is the intended path and is the thing to verify
  by hand.
- **An orphaned `ssh -N`** if the wizard dies between starting the tunnel and
  the client. Owned by a trap rather than hoped away.
- **`freerdp` is a large-ish dependency** for a row most users never open;
  that is why it is a catalogue entry and the row is gated.
- **Upstream may deprecate again.** The reason `sdl-freerdp` was chosen is
  written down so the next person can re-read the argument rather than the
  conclusion.

## Verification

| what | how | break it by |
|---|---|---|
| the menu row names a verb the CLI has | `tests/menu-verbs.nix`, already registered for `nixarchy-remote` | misspelling `connect` in the row |
| the row is gated on a client existing | new assertion in `tests/options.nix`'s menu pass, alongside the existing "all N menu rows name commands that exist" | removing the `when` |
| `nixarchy remote connect` routes | `checks.options`' dispatcher assertion, already written, derives it from the `omarchy:examples=` header | the header and the dispatcher disagreeing |
| the command declares what it invokes | `runtimeInputs` / the omarchy runtime list, and the ledger's behaviour classes | removing `ssh` |
| the generated menu still parses | the build-time parse in `pkgs/omarchy/default.nix` | an unbalanced brace |

**What no layer here can reach, again and unchanged:** an actual connection.
`checks.session` boots one desktop and this needs two. The hole is already
named in `tests/install-matrix.py` and `tests/AGENTS.md` from #1015; this adds
the client and the tunnel to what that note covers, and a step to
`pkgs/verify.sh` for a human -- connect from one machine to another, confirm
the session resizes to the window, confirm the tunnel closes.

What *is* cheaply reachable and worth doing: **the tunnel teardown**, which
needs no second machine. A check can start the wizard's tunnel half against a
local listener, kill the client, and assert no `ssh -N` survives.

## Open questions

1. **Saved connections.** The SSH config is the list, which means "connect to
   the one I always use" is two keystrokes of `gum` filter rather than one
   row. Enough, or does the group want a per-machine row?
2. **Does `connect` belong on a machine that also serves?** Both verbs on one
   command is tidy; a laptop that only ever connects has no use for `serve`
   and vice versa. Nothing breaks either way, so this is a naming question
   rather than a design one.
