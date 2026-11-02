---
status: draft
issue: 1566
intent: intent/2026-11-02-1566-ai-mirror-skill.md
---

# Spec: an ai-mirror skill that asks "microVM or the real desktop?"

## Measured before designing (p620, 2026-11-02)

- **An MCP server added mid-session is not usable until Claude Code restarts**
  (decision 2). `claude mcp add mirror-probe -- ai-mirror mcp` showed
  `✔ Connected` in `claude mcp list`, but no tool from it reached the running
  session. Removed again. So the VM path cannot rely on `claude mcp add`.
- **The guest serves one ai-mirror per connection.**
  `modules/microvm/templates/ai-mirror-guest.nix` runs
  `socat VSOCK-LISTEN:7000,fork EXEC:'ai-mirror mcp'`, and a user service
  confirms any pending request. So every connection is a fresh MCP server:
  it must ask for control, its frames exist only on that connection, and it
  revokes the grant when it exits.
- **The guest shares the host's store** (`modules/microvm/guest.nix`) and mounts
  the per-VM `share` directory at `/mnt/host`. So an app built on the host with
  `nix build` is a store path the guest can run.
- `nixarchy vm` subcommands: `templates`, `list`, `create <name> [--template t]`,
  `run [--detach] <name>`, `console`, `stop`, `rm`. The CID is in
  `~/.local/state/nixarchy/microvm/<name>/vsock-cid` after the first start.

## Design

Two files in `pkgs/omarchy/skills/ai-mirror/`. Every directory there is
already copied into the skills tree (`pkgs/omarchy/default.nix:1159`), so
nothing else installs them.

### `SKILL.md`

Front matter: `name: ai-mirror`, with a description that triggers on:
- "test this app/application", "try it on the desktop", "click through",
  "drive the UI";
- "use ai-mirror", "in a VM", "microvm".

It hands off to the `nixarchy` skill for desktop configuration. The body, in
this order:

1. **Ask first, one question** (the intent's constraint): *Test in a disposable
   microVM (`nixarchy-desktop`) or on this host's real desktop?*, with the two
   one-line trade-offs from the intent. A standing preference the person states
   is followed without asking again. The skill never starts a VM or asks for
   host control before the person answers.
2. **Host path.** The loop from ai-mirror's `AGENTS.md`:
   - `index` first;
   - `control agent`, then poll `status` until `agent` or `off`;
   - `shell_state`, `windows` or `a11y_find` before a screenshot;
   - `input` with the frame;
   - `wait` to confirm;
   - `control off`.

   It also gives the rules for `not_owner`, `wrong_target` and partial
   batches, in one line each.
3. **VM path.**
   - `nixarchy vm create <name> --template nixarchy-desktop`
     (`hyprland-ai-mirror` only when the app needs nothing from the shell,
     decision 3).
   - `nixarchy vm run --detach <name>`.
   - Wait: the vsock port opens about 45 s after a cold boot. The first build
     can be long; say so to the person rather than wait silently.
   - The app: build it on the host (`nix build … --print-out-paths`) and
     `launch` that store path in the guest. Files go through
     `~/.local/state/nixarchy/microvm/<name>/share` ↔ `/mnt/host`.
   - Drive it with `mirror-vm` (below), one session per batch of steps.
   - The template notes the skill repeats: 1280x800 `Virtual-1`, software
     rendering (GL apps slow), notifications start on DND
     (`omarchy-shell notifications setDnd off`), control is auto-granted
     because starting the VM is the consent, and the guest's ai-mirror still
     says "your real desktop".
4. **Cleanup.**
   - `nixarchy vm stop <name>` and `nixarchy vm rm <name>`, unless the person
     wants to keep it.
   - If anyone registered an `ai-mirror-<name>` MCP server for a later session,
     `claude mcp remove ai-mirror-<name>`.
   - `claude mcp list` shows stale entries (`✘ Failed to connect`).
5. **Not covered:** `mcp add` for later sessions is optional and described in one
   line, with the restart it needs.

### `mirror-vm` (a stdlib Python 3 script, executable, in the skill directory)

```
mirror-vm <name> <steps.json> [--out DIR]
```

- Reads the CID file, starts `socat - VSOCK-CONNECT:<cid>:7000`, and speaks
  JSON-RPC over its stdin/stdout, the way ai-mirror's own live checks do.
- One connection runs the whole batch:
  - `initialize`;
  - `control {mode: agent}`, then poll `status` until `owner` is `agent`
    (the guest auto-confirms), with a 30 s limit;
  - then each step `{"tool": …, "args": {…}}` in order;
  - then `control {mode: off}`.
- Frames work within the batch: a step may write `"frame": "@last"` and the
  script substitutes the last screenshot's frame id.
- Each screenshot's image is written to `DIR/NN-screenshot.png` (default: a new
  temp directory) and replaced in the printed result by its path. The output is
  one JSON line per step, so the agent can look at the PNGs with its own image
  reader.
- **A step error stops the batch.** The script still sends `control off` and
  exits non-zero.
- No dependency beyond `python3` and `socat`.

### `tests/session.nix`

Add `"ai-mirror"` to the skills list it checks, so the link into every agent home
(`.agents`, `.claude`, `.pi`) is asserted like the others.

## Alternatives rejected

- **`claude mcp add` then use its tools.** Measured: they do not reach the
  running session.
- **One `mirror-vm` call per tool call.** Each connection is a new server:
  re-ask, lose the frame, and the grant is revoked on exit. A batch keeps one
  session.
- **SSH into the guest and run the ai-mirror CLI.** The templates expose no SSH,
  and vsock is already the documented channel.
- **The skill in the ai-mirror repo.** Rejected by decision 1.
- **A new `nixarchy vm` subcommand** for driving the guest. More surface in a
  shared CLI for what a 100-line script in the skill does.

## Risks

- **Guest wording** ("your real desktop", "human-confirmed") can mislead an
  agent into thinking it is on the host. The skill says it plainly.
- **First run of `nixarchy-desktop`** realises a 17.7 GiB closure on a host that
  lacks it. On p620 and razer most of it is shared with the host system.
- **Template notes drift.** The skill repeats the timings, so it names
  `nixarchy vm templates` as the source of truth.
- **The skill mis-triggers** on a request that is not about the desktop. It only
  asks a question, so the cost is one extra prompt.

## Verification

- **`nix build`** of the omarchy package, and `checks` that include
  `tests/session.nix`: the `ai-mirror` skill is linked into all three agent
  homes.
- **`python3 -m py_compile mirror-vm`**, and `mirror-vm --help`.
- **Live on p620:**
  1. `nixarchy vm create mirror-test --template nixarchy-desktop`, then
     `run --detach`.
  2. `mirror-vm mirror-test steps.json` with `status`, `windows`, a
     `screenshot`, and `input` move with `"frame": "@last"`. The grant arrives,
     the PNG is written, and `control off` ends the session.
  3. `nixarchy vm rm mirror-test`.

  Then a fresh agent session asked "test foot" asks the question first.
