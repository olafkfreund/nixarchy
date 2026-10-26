---
title: Remote desktop
---

# Remote desktop

Between two nixarchy machines, [gliff](#between-two-nixarchy-machines-gliff)
reaches the desktop you are not sitting at. It is installed by default and goes
over SSH. In the menu: Setup > Remote desktop > Connect with gliff.

## Between two nixarchy machines: gliff

gliff is a remote desktop over SSH for Hyprland. It needs nothing enabled on
the machine you sit at, and no password of its own: your SSH key is the
authentication.

```sh
gliff you@desk
```

opens the desk's session in a window. Two options change what you get:

- `--output NAME` mirrors one of its monitors, for example `--output DP-1`.
- `--headless` gives the session a dedicated virtual output that follows the
  size of your window, so the physical monitors keep showing what they showed.

**Setup → Remote desktop → Connect with gliff** opens the same window without a
terminal. The first time, its address bar takes `you@desk`; after that it opens
with a tab for each machine you have used, and `+` adds another.

The machine you connect *to* needs:

```nix
services.openssh.enable = true;
```

and somebody logged into a Hyprland session, because
gliff is a client of a compositor that is already running.

### Your first session

The steps below take two machines, called `desk` (the one you connect to) and
your own, from nothing to a connected window.

1. **On `desk`,** set `services.openssh.enable = true;`, rebuild, and log into
   Hyprland there. gliff is already installed unless
   `programs.nixarchy.preinstallsExclude` lists it.
2. **On the machine you sit at,** make a key if `~/.ssh/id_ed25519` does not
   exist (`ssh-keygen -t ed25519`), then copy it over with
   `ssh-copy-id you@desk`. This step is required: the widget checks each
   machine with ssh `BatchMode=yes`, so one that would ask for a password reads
   as "Login refused".
3. **Pick a name.** `desk.local` works on the same LAN. With Tailscale, use
   the tailnet name; the widget lists tailnet machines under "ON YOUR
   TAILNET".
4. **Run `ssh you@desk` once** to save its host key.
5. **Open the widget** from the bar, or **Setup → Remote desktop → Manage gliff
   machines**, type `you@desk` into the field (it says `user@host`) and press
   Enter or **Add machine**.
6. **Read the status** on the machine's row. The table below says what each
   one means.
7. **Choose a mode** by clicking the mode chip, which cycles Auto → Headless →
   Mirror → each screen the machine reported. Auto means headless when nothing
   is plugged in there, and mirror when a display is. Use headless to work
   beside someone at that desk, and mirror to see its screen.
8. **Connect** with the play button (its tooltip says Connect) or Enter. On a
   row with a warning, they run the fix instead. Once the row says "Connected"
   the same button disconnects. **Shift+Esc** inside a gliff window gives the
   keyboard back to your own desktop.

| The widget says | Meaning | Fix |
|---|---|---|
| Connected · *mode* | a session is open | — |
| Not checked yet / Checking… | no answer yet | wait, or press R |
| Tailscale wants you to sign in again | Tailscale SSH needs a fresh login | the widget's fix opens the sign-in |
| Offline or not answering ssh | no ssh reply | the machine is off, asleep, or has no `services.openssh.enable` |
| Login refused for *user* | ssh refused your key | step 2, or the wrong user name |
| Host key not saved yet | first contact | step 4; the widget offers it |
| Host key changed — booted into another OS? | the key no longer matches | find out why first; then the widget's fix re-saves it |
| Hyprland runs as *A*, not *B* | someone else is logged in there | the fix switches to `A@host` |
| No Hyprland session running | nobody is logged in there | log in on that machine |
| gliff is not installed there | gliff is missing on that machine | on nixarchy it is installed unless `preinstallsExclude` lists it |
| Ready · *arch* · *channel* | ready | — |
| Ready · gliff *x* there, *y* here | the versions differ | update the older machine |

### Managing your machines

**Setup → Remote desktop → Manage gliff machines** (also a bar widget) lists
your machines, checks each over ssh, and connects them the right way; see
[Gliff-Manager](plugins#gliff-manager). Turn the widget off alone with
`programs.nixarchy.defaultPlugins.gliff-manager = false;`.

gliff is installed by default. To remove it, and the widget with it:

```nix
programs.nixarchy.preinstallsExclude = [ "gliff" ];
```

**Mind the clipboard.** While a gliff tab is open, that host can read your
local clipboard, without you pasting anything into it. Do not keep a tab open
to a machine you do not trust while you copy secrets.

If something does not work, `gliff-probe all` on either machine checks the
protocols, the outputs, the GPU and the codec path, and prints PASS or FAIL for
each. On a machine without VA-API H.264 encode (NVIDIA, for one) gliff runs on
the CPU instead, which is slower and not an error.

## Letting an agent drive another machine

Not through a remote desktop. Accessibility does not cross it — the desktop
arrives as pixels, so an agent looking at a gliff window sees the client's own
chrome and nothing inside the session. It would be reduced to screenshots and
coordinates.

[ai-mirror](https://github.com/olafkfreund/ai-mirror), which nixarchy already
carries, is the surface that works. It is an MCP server spoken over stdin and
stdout, so an agent reaches a remote one by running it there:

```nix
command = "ssh";
args = [ "desk" "ai-mirror" "mcp" ];
```

That gives the agent the other machine's real accessibility tree and window
list — `a11y_find` by name, not a guess at a pixel.

### What that grants, before you paste it

**It is as strong as your SSH access to that machine, and no stronger.**

Locally, ai-mirror will not let an agent turn control on: it asks, and a
dialog on your screen is answered by whoever is at the keyboard. That gate
holds for an agent reaching ai-mirror through MCP alone. It does not hold
here. `ai-mirror control confirm` is an ordinary command, so an agent with a
shell on that account answers its own dialog — and `ssh desk ai-mirror mcp`
*is* a shell on that account.

A forced-command key in `authorized_keys` does not fix it either. It
restricts that key; it does not remove the ordinary key you already have to
that machine, which is the same key gliff connects with.

So on the far machine the dialog is a **notice, not a gate**. Read it that
way.

### What actually helps

**Do not give the agent the key.** This is the only thing that changes the
picture, and it is not a setting: a key for your fleet that is not loaded
into `ssh-agent` and not readable by the account your agent runs as. An agent
that cannot reach the machine cannot drive it, and everything above stops
mattering.

**Ask for less.** Observation — the accessibility tree, the window list, a
screenshot — needs no control grant at all. An agent that only looks is a
much smaller thing to hand over, even though nothing enforces the difference.

**Read the log.** Every request, answer and stop is a line in
`$XDG_RUNTIME_DIR/ai-mirror/audit.jsonl` on the machine that was driven. It is
the one durable artifact here, and it is on the far machine, so:

```sh
ssh desk 'cat "$XDG_RUNTIME_DIR/ai-mirror/audit.jsonl"'
```

Single-quoted on purpose: the variable has to expand on the far machine,
and `ssh desk cat "$XDG_RUNTIME_DIR/..."` would expand it here instead and
look in the wrong place.

An empty file means one of two things — nothing happened, or that machine
rebooted, since `$XDG_RUNTIME_DIR` does not survive one. Do not read empty as
all-clear.

None of this is turned on for you. `programs.nixarchy.aiMirror.mcp` writes
ai-mirror's *local* entry and nothing remote, and there is deliberately no
option for the above: a switch named for remote agent control would promise a
control that is not there.

See also: [Security](security) for the firewall and SSH generally, and
[Many machines, one repo](many-machines) for where `hosts/<name>/` comes from.
