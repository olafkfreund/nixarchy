---
status: approved
issue: 1504
intent: intent/2026-10-29-1504-hyprland-ai-mirror-template.md
---

# Spec: a sandbox desktop an agent drives with ai-mirror

## Measured first (2026-10-29, p620, `origin/main` `85b84dd`)

I built a prototype with `lib.mkMicrovm`: the `hyprland` template plus the
module below. It booted with the KVM runner as the desktop user, and I drove
it from the host by speaking MCP JSON-RPC through
`socat - VSOCK-CONNECT:1504:7000`.

| Step | Result |
|---|---|
| vsock round trip, `shell` template, unprivileged | Works. `hello-from-guest` read on the host 15 s after start. `/dev/vhost-vsock` is `crw-rw-rw- root kvm` here |
| `initialize` | `serverInfo ai-mirror 3.1.0`, listener up 18 s after a cold start |
| `control agent` → `status` | Granted by the guest confirmer 9–19 s after the request on a cold boot (it waits for Hyprland), 2.5–3 s once Hyprland is up |
| `status` monitors | `Virtual-1` 1920x1080, scale 1 |
| `launch ["foot"]` | Window `foot`, `dev@nixos: ~` |
| `input` type + Return into that window | `acked 3`. The screenshot shows `echo typed-by-agent-in-sandbox` and its output |
| `control off` | `owner off`. The VM was then stopped |

Two things the prototype got wrong first, and the design avoids:

1. **A systemd path unit as the confirmer** missed the first request
   after a cold boot. Hyprland was not up yet, so the single confirm
   failed and nothing triggered it again. Run as a polling loop, the same
   confirm succeeds on the first request.
2. **The listener's `PATH`** must include the guest's system profile, or
   `launch` cannot find `foot` (`FileNotFoundError`).

## Design

### 1. The template: `modules/microvm/templates/hyprland-ai-mirror.nix`

`imports = [ ./hyprland.nix ];`. That template keeps its "plain NixOS, no
plugins" promise and is not edited. It adds:

- **ai-mirror in the guest:** `environment.systemPackages` gets
  `ai-mirror`, `ai-mirror-input` and `jq`. The packages come from
  `inputs.ai-mirror.packages.${system}`, the same input `modules/home.nix`
  installs from. That pins the guest to the lock's ai-mirror (3.1.0 today).
- **`microvm.vsock.cid = 1504`**, an option of the pinned microvm.nix
  (`lib/runners/qemu.nix:357` adds `vhost-vsock-pci,guest-cid=…`).
- **`systemd.user.services.ai-mirror-autoconfirm`** (`ConditionUser = "dev"`,
  `wantedBy default.target`, `Restart = always`). It runs this loop:

  ```sh
  while sleep 0.5; do
    id=$(jq -r 'select(.owner == "pending") | .request.id // empty' \
           "$XDG_RUNTIME_DIR/ai-mirror/state.json" 2>/dev/null || true)
    [ -z "$id" ] || ai-mirror control confirm "$id" || true
  done
  ```

  It reads the request id from the state file, not from `status`, because
  `status` needs Hyprland. A confirm that fails while Hyprland starts is
  tried again on the next pass. ai-mirror's own `_answer` stays the only
  code that grants (`src/ai_mirror/control.py:449`).
- **`systemd.user.services.ai-mirror-vsock`** (`ConditionUser = "dev"`,
  `after`/`wants` the confirmer and `hyprland.service`). It runs
  `socat VSOCK-LISTEN:7000,fork EXEC:'ai-mirror mcp'`, one MCP server per
  connection. `path = [ "/run/current-system/sw" ]` lets it see the guest's
  apps. As a user service it inherits `XDG_RUNTIME_DIR` and the session bus,
  so AT-SPI works.

### 2. Getting `inputs` to the template

`lib.mkMicrovm` (`flake.nix:1741`) calls `nixosSystem` with no
`specialArgs`, so a template cannot reach `inputs` today. Add
`specialArgs = { inherit inputs; };` there. `inputs` is already bound by
`outputs = { … }@inputs`. The existing templates take `{ pkgs, ... }` and
ignore the new argument.

### 3. The catalogue: `data/microvm-templates.nix`

Add a `hyprland-ai-mirror` entry next to `hyprland`. Its `note` says:

- It is the Hyprland template with ai-mirror inside, and control is granted
  without asking. Starting the VM is the consent.
- The host connects with
  `claude mcp add ai-mirror-sandbox -- socat - VSOCK-CONNECT:1504:7000`.
- Only one runs at a time, because the vsock CID is fixed.

`checks.microvm-template` builds every catalogue entry, KVM and TCG, so the
new template is built and pushed to the cache with no change to the test.

### 4. Docs: `docs/manual/sandboxes.md`

A short section: real desktop or sandbox, the one `claude mcp add` line,
the one-at-a-time limit, and that stopping the VM is the kill switch.

### 5. What does not change

- ai-mirror's code and its gate.
- The host's ai-mirror and its confirm dialog.
- The `hyprland` template.
- `guest.nix`: still no SSH.
- `programs.nixarchy.aiMirror.mcp`: the sandbox MCP entry is a documented
  command, not an option (see Alternatives).

## Alternatives rejected

- **A systemd path unit for the confirmer.** Measured above: it misses the
  first request after boot.
- **An ai-mirror setting that auto-grants** (`AI_MIRROR_SANDBOX=1`). It
  would be machinery in the gate that the real desktop also ships. The
  intent rules that out.
- **SSH with a key.** `guest.nix` rules out an SSH door, and vsock carries
  only MCP.
- **omabox, or a nested Hyprland on the host.** It is not a security
  boundary by its own docs, it assumes Arch (`/usr/bin/...`, pacman), and it
  carries a privately patched aquamarine. Codex and agy both reviewed it and
  reached the same conclusion.
- **Adding the sandbox to `programs.nixarchy.aiMirror.mcp` now.** That is a
  host option for a VM that may not be running. One documented line is
  enough until someone asks for more.
- **A CID per VM, so several sandboxes run at once.** The disposable runner
  shares one closure per template. Intent decision 2 accepts one at a time.

## Risks

- **Any local user on the host can drive the sandbox.** `/dev/vsock` is
  world-writable, and vsock carries no peer uid. On a single-user desktop
  that is the user. It never reaches the real desktop: the guest has no
  socket to the host compositor, and the host runs no listener.
- **A second sandbox will not start** while one runs, because the CID is
  already in use. It fails at start, not silently. *Expected, not yet
  measured.*
- **The 30 s request expiry vs. a cold boot.** The worst measured grant was
  19 s. On the TCG runner (no `/dev/kvm`) the boot may take longer than 30 s,
  and the first request would lapse. ai-mirror tells the agent to ask again,
  and the second request is fast.
- **Misleading wording from the guest's ai-mirror.** Its MCP instructions
  say "the user's REAL desktop … a dialog". The audit records the grant as
  `enabled_by: human-confirmed` with `via cli`. The note and docs say what
  it really is. Changing ai-mirror's wording would be a separate ai-mirror
  issue.
- **The first `launch` can report** "windows could not be read: hyprctl
  timed out". That was measured once, with the window present. It is
  ai-mirror's 0.4 s budget on a cold guest, and the note tells the agent to
  call `windows`.
- **Size.** The template inherits `hyprland`'s ~5.2 GiB (Chromium kept,
  intent decision 4). ai-mirror adds little.

## Verification

- `nix flake check` passes. In particular, `checks.microvm-template` builds
  `microvm-hyprland-ai-mirror` and its `-tcg` variant.
- `nix eval .#packages.x86_64-linux.microvm-hyprland` output path is
  unchanged by the `specialArgs` line. That proves the existing templates
  are untouched.
- **Live, on p620:** run `nixarchy vm create s hyprland-ai-mirror` and
  `nixarchy vm run s`. Then run the MCP script from the measurement against
  `VSOCK-CONNECT:1504:7000`:
  - Expect: initialize, then grant under 30 s, launch foot, typed text in
    the screenshot, and `control off`.
- **Live:** start a second sandbox while the first runs. It refuses to
  start.
- **Live:** with the sandbox running, host `ai-mirror status` is unchanged.
  The real desktop's owner and generation do not move.
