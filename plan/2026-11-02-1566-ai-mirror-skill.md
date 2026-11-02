---
status: draft
issue: 1566
spec: spec/2026-11-02-1566-ai-mirror-skill.md
---

# Plan: an ai-mirror skill that asks "microVM or the real desktop?"

## Approved decisions (self-contained)

- A skill `ai-mirror` in `pkgs/omarchy/skills/ai-mirror/`. Every directory
  there is copied into the skills tree by `pkgs/omarchy/default.nix:1159`, and
  linked into `.agents`, `.claude` and `.pi` skill homes by `modules/home.nix`.
- **First step: ask** "disposable microVM (`nixarchy-desktop`) or this host's
  real desktop?", with one trade-off line each. Never start a VM or ask for
  control before the answer. Follow a standing preference the person states.
- **Host path:** ai-mirror's own loop:
  - `index`, then `control agent`, then poll `status`;
  - `shell_state`/`windows`/`a11y_find` before a screenshot;
  - `input` with the frame, `wait`, then `control off`;
  - the `not_owner`, `wrong_target` and partial-batch rules.
- **VM path:**
  - `nixarchy vm create <name> --template nixarchy-desktop`
    (`hyprland-ai-mirror` only if no shell is needed);
  - `run --detach`, then wait about 45 s for the vsock port;
  - build the app on the host and `launch` its store path (the guest shares the
    store);
  - files through `~/.local/state/nixarchy/microvm/<name>/share` ↔ `/mnt/host`;
  - drive the guest with `mirror-vm`;
  - cleanup: `stop` and `rm`, plus `claude mcp remove` of any `ai-mirror-<name>`
    entry.
- **Measured:** an MCP server added mid-session is not usable until Claude Code
  restarts, so the skill does not rely on `claude mcp add`.
- **The guest serves one `ai-mirror mcp` per vsock connection** and grants
  automatically. So `mirror-vm` runs a whole batch on one connection.
- **Template facts the skill repeats**, with `nixarchy vm templates` as the
  source of truth:
  - 1280x800 `Virtual-1`, software rendering;
  - DND on at start (`omarchy-shell notifications setDnd off`);
  - the 17.7 GiB first build;
  - the guest's ai-mirror still says "your real desktop".

## Steps

1. `pkgs/omarchy/skills/ai-mirror/mirror-vm` (new, executable, stdlib
   Python 3, `#!/usr/bin/env python3`):
   - **Usage:** `mirror-vm <name> <steps.json|-> [--out DIR]`, plus `--help`.
   - **CID:** read `~/.local/state/nixarchy/microvm/<name>/vsock-cid`. If it is
     missing, say "start the VM first: nixarchy vm run --detach <name>" and exit 2.
   - **Connection:** `Popen(['socat', '-', f'VSOCK-CONNECT:{cid}:7000'], stdin=PIPE, stdout=PIPE, text=True)`,
     then a line-delimited JSON-RPC `rpc(method, params)` and
     `call(tool, args) -> (body, isError)`, as ai-mirror's live checks do.
   - **Grant:** `initialize`, then `control {mode: agent}`, then poll `status`
     every 0.5 s until `owner == 'agent'`. If it is not reached within 30 s, exit 3.
   - **Steps:** each step is `{"tool": str, "args": {...}}`. Before each, replace
     any `args.frame == "@last"` with the last screenshot's frame id. For a
     `screenshot` result, take the `image` content, base64-decode it into
     `DIR/NN-screenshot.png`, and print the meta plus `"png": path`.
   - **Output:** print one JSON line per step:
     `{"step": n, "tool": t, "isError": b, "result": …}`.
   - **Errors:** on `isError` stop, run `control {mode: off}` in a `finally`, and
     exit 1. Always close socat.
   → verify `python3 -m py_compile` on it, `./mirror-vm --help`, and a run
   against a missing VM exits 2 with the message.
   Traps:
   - The guest's server writes JSON-RPC results with `content[0].text` as JSON
     text and an `image` item for screenshots.
   - Timeouts: wrap reads so a dead socat does not hang forever. Read with
     `select` and a 60 s limit per response.

2. `pkgs/omarchy/skills/ai-mirror/SKILL.md` (new). The front matter follows the
   other skills' style, with a description that has a REQUIRED-style first
   sentence and a `Triggers:` list:
   - test this app/application, try it on the desktop, click through, drive
     the UI;
   - ai-mirror, microvm, in a VM, screenshot the app.

   It hands off to `nixarchy` for desktop configuration. The body sections, in
   order:
   1. Ask first.
   2. Host path.
   3. VM path, with a minimal `steps.json` example: `status`, `windows`,
      `screenshot`, then `input` with `"frame": "@last"`.
   4. Cleanup.
   5. Limits: no GPU, the first build, the guest wording, and that MCP added
      mid-session needs a restart.

   Short. Facts only from the spec's measured list.
   → verify by reading it once against the spec, and `grep -c` that every command
   in it appears in `nixarchy vm --help` or the template notes.

3. `tests/session.nix:1253`: add `"ai-mirror"` to `skills`.
   → verify `nix build .#omarchy` (or the package attr that builds
   `pkgs/omarchy`), and `ls result/share/omarchy/default/agents/skills/ai-mirror`
   shows both files, with `mirror-vm` executable. `checks.session` is a VM test.
   Run it if feasible, else CI covers it on the PR.
   Traps: `cp -r --no-preserve=mode` drops the executable bit. Check it, and if
   it is lost, add `chmod +x $skills/ai-mirror/mirror-vm` right after the `cp`
   at `default.nix:1160`.

4. Live on p620 (me):
   - `nixarchy vm create mirror-test --template nixarchy-desktop`, then
     `run --detach`, then wait.
   - `mirror-vm mirror-test steps.json` with `status`, `windows`, `screenshot`,
     and `input` `{"actions":[{"type":"move","x":10,"y":10}],"frame":"@last"}`.
     The grant arrives, a PNG is written, `input` is ok, and `control off` runs.
   - `nixarchy vm rm mirror-test`.

   Record the result here. Remove the stale `ai-mirror-ai-mirror` MCP entry on
   p620 (found during the intent) as part of the cleanup check.

## Implementation

Two new files plus one list line, three files. The steps are mostly text, and
the script is about 100 lines. Per the model split, three files means a handoff
to the `coder` agent for steps 1–3. I review, commit each, and a fresh Opus
agent reviews the diff. Step 4 is mine.

## Tests

`py_compile` on `mirror-vm`; `nix build` of the omarchy package with the skill
present and executable; `checks.session` (CI); step 4 live.

## Rollback

Revert the merge commit; the skill directory disappears at the next rebuild.
Nothing else depends on it.
