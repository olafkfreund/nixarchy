---
status: approved
issue: 1504
spec: spec/2026-10-29-1504-hyprland-ai-mirror-template.md
---

# Plan: a sandbox desktop an agent drives with ai-mirror

## Approved decisions, carried over

- **New template** `hyprland-ai-mirror`. It is `imports = [ ./hyprland.nix ]`
  plus ai-mirror. `hyprland.nix` is not edited.
- **No ai-mirror code change.** The guest's own ai-mirror grants through its
  CLI (`ai-mirror control confirm <id>`). Starting the VM is the consent.
- **The host reaches the guest over vsock only:** CID **1504**, port
  **7000**. There is no SSH (`guest.nix` stays as it is). Only one sandbox
  runs at a time, and the note says so.
- **The confirmer is a polling loop, not a path unit.** It reads the
  request id from `$XDG_RUNTIME_DIR/ai-mirror/state.json` with `jq`, and
  retries every 0.5 s until Hyprland is up. Measured: a path unit missed the
  first request after a cold boot.
- **The listener's `path` is `[ "/run/current-system/sw" ]`.** Measured:
  without it, `launch` cannot find guest apps.
- **`lib.mkMicrovm` gets `specialArgs = { inherit inputs; };`** so a template
  can use `inputs.ai-mirror`.
- **Chromium is kept**, inherited from `hyprland.nix`.
- The host MCP entry is a documented line, not an option:
  `claude mcp add ai-mirror-sandbox -- socat - VSOCK-CONNECT:1504:7000`.

**One wording deviation from the spec:** its Verification says
`nix flake check`. This repo builds checks one at a time by name (AGENTS.md
§6), so the steps below do that.

## Steps

1. **`flake.nix:1747-1755`** (`lib.mkMicrovm`): add `specialArgs = { inherit inputs; };`
   inside the `nixpkgs.lib.nixosSystem { … }` call, next to `inherit system;`.
   - Verify:
     - before and after the edit, compare
       `nix eval --raw .#packages.x86_64-linux.microvm-hyprland.outPath`.
       The output is identical, so the existing templates are untouched.
   - Traps:
     - `inputs` is bound by `outputs = { … }@inputs` (`flake.nix:376-389`);
       do not add a new binding.
     - Run `nix fmt` after the edit and read `git diff --stat`. An editor
       hook can reformat with nixpkgs-fmt, which this repo does not use
       (AGENTS.md, #897).

2. **New file `modules/microvm/templates/hyprland-ai-mirror.nix`.** It
   takes `{ pkgs, inputs, ... }`. Start with a header comment in the style
   of the other templates: what it is, and why each piece is there, citing
   #1504 and the spec's measurements. The body is the prototype that was
   measured on 2026-10-29:

   ```nix
   let
     am = inputs.ai-mirror.packages.${pkgs.stdenv.hostPlatform.system};
     path = [ "/run/current-system/sw" ];
   in
   {
     imports = [ ./hyprland.nix ];
     microvm.vsock.cid = 1504;
     environment.systemPackages = [ am.ai-mirror am.ai-mirror-input pkgs.jq ];
     systemd.user.services.ai-mirror-autoconfirm = {
       wantedBy = [ "default.target" ];
       unitConfig.ConditionUser = "dev";
       inherit path;
       script = ''
         while sleep 0.5; do
           id=$(jq -r 'select(.owner == "pending") | .request.id // empty' "$XDG_RUNTIME_DIR/ai-mirror/state.json" 2>/dev/null || true)
           [ -z "$id" ] || ai-mirror control confirm "$id" || true
         done
       '';
       serviceConfig.Restart = "always";
     };
     systemd.user.services.ai-mirror-vsock = {
       wantedBy = [ "default.target" ];
       after = [ "hyprland.service" "ai-mirror-autoconfirm.service" ];
       wants = [ "ai-mirror-autoconfirm.service" ];
       unitConfig.ConditionUser = "dev";
       inherit path;
       serviceConfig.ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:7000,fork EXEC:'ai-mirror mcp'";
     };
   }
   ```

   - Verify:
     - `nix build .#microvm-hyprland-ai-mirror` succeeds. It needs step 3's
       catalogue entry, so run this build after step 3.
     - `statix check` and `deadnix --fail` pass.
   - Traps:
     - In a Nix `''` string, write `$(…)` and `$VAR` bare. `\$` is a
       literal backslash, and it broke four prototype builds (a shell syntax
       error in the unit script, so the runner link silently never moved).
     - Check that `nix build` exited 0. Do not just look at the last line
       of its output.
     - Use `pkgs.stdenv.hostPlatform.system`, not `pkgs.system`, which is
       deprecated.

3. **`data/microvm-templates.nix:59-63`:** add a `hyprland-ai-mirror` entry
   after `hyprland`, with `label = "Hyprland + ai-mirror"` and
   `module = ../modules/microvm/templates/hyprland-ai-mirror.nix`.
   - The `note` must say, in this order:
     - it is the `hyprland` template with ai-mirror inside, and control is
       granted without asking, because starting the VM is the consent;
     - connect from the host with
       `claude mcp add ai-mirror-sandbox -- socat - VSOCK-CONNECT:1504:7000`;
     - one at a time (fixed vsock CID);
     - the first grant after a cold boot takes up to ~20 s, while
       Hyprland starts;
     - its ai-mirror still words things as "your real desktop" and
       "human-confirmed".
   - Verify:
     - `nix build .#microvm-hyprland-ai-mirror .#microvm-hyprland-ai-mirror-tcg`
     - `nix build .#checks.x86_64-linux.microvm-template --print-build-logs`
   - Traps: the check builds every entry both ways. Expect the ~5.2 GiB
     guest to come mostly from the local store or the cache.

4. **`docs/manual/sandboxes.md:68-87`:**
   - Add a table row for `hyprland-ai-mirror`, matching the note.
   - After the table, add a short subsection, "Driving one with ai-mirror".
     It covers:
     - the real desktop vs. the sandbox, as two MCP servers with the same
       tools;
     - the `claude mcp add` line;
     - stopping the VM is the kill switch;
     - one at a time;
     - any local user on the host can reach the vsock port.
   - Verify: read the rendered Markdown. The table's column count is
     unchanged.
   - Traps: none.

5. **Live check on p620** (Opus, not the coder):
   - `nixarchy vm create s hyprland-ai-mirror && nixarchy vm run s`, with
     the runner built from this branch.
   - Then run the measurement's MCP probe against `VSOCK-CONNECT:1504:7000`.
   - Expect: initialize, then a grant under 30 s, `launch foot`, typed text
     in the screenshot, and `control off`.
   - Also check:
     - a second `vm run` of another sandbox refuses to start (CID in use);
       record what it prints;
     - host `ai-mirror status` owner and generation are unchanged
       throughout.
   - Record the results here.
   - Traps:
     - The runner needs `share/` beside it. `nixarchy vm` creates it, but a
       hand-run runner fails on `Could not open 'share'`.
     - Stop the VM afterwards.

## Tests

```sh
nix fmt -- --ci
nix run --inputs-from . nixpkgs#statix -- check .
nix run --inputs-from . nixpkgs#deadnix -- --fail .
nix build .#checks.x86_64-linux.microvm-template --print-build-logs
```

Expected: all pass, and the `microvm-hyprland` outPath is unchanged by
step 1. Step 5 is the behavioural test. Nothing in CI boots a guest.

## Rollback

Revert the branch's commits. The template is new and only listed in the
catalogue. The `specialArgs` line changes no existing output (step 1's
check). A VM someone already created from the template keeps its runner
link until they run `nixarchy vm destroy` on it.

## Results

Steps 1-4 were implemented by the `coder` agent and committed after review
(`d5d0432`, `7eb051d`, `e02d68d`). One change from step 4's hand-off: the
"Driving one with ai-mirror" subsection sits below the table's closing
paragraph, so that paragraph stays with the table.

- **Step 1:** `microvm-hyprland` outPath is unchanged
  (`l7gisjic…-microvm-qemu-nixos`, before and after).
- **Steps 2-3:**
  - `nix fmt`, `statix` and `deadnix` are clean.
  - Both runners build.
  - `checks.microvm-template` failed only on the missing manual row until
    step 4, then passed.
- **Step 5 (2026-10-29, p620):** the branch's `nixarchy-vm` was built at
  `e02d68d`, with a scratch `XDG_STATE_HOME`.
  - `vm create s1 --template hyprland-ai-mirror`, then `vm run --detach s1`:
    the CLI returned after 13 s, and the vsock listener came up 13 s after
    that.
  - MCP probe:
    - `ai-mirror 3.1.0`;
    - granted 18.6 s after the request (cold boot);
    - `launch foot` opened the window `dev@s1: ~`;
    - `input` typed, `acked 3`, and the screenshot shows the echoed text;
    - `control off`.
  - A second sandbox (`s2`) refused to start, with exit 1:
    `vhost-vsock: unable to set guest cid: Address already in use`.
  - Host `ai-mirror status` was `{"owner":"off","generation":103}` before
    and after: the real desktop was untouched.
  - Both VMs were stopped and removed.

### Independent review (Opus, after steps 1-4)

Nothing blocking. Acted on:

- **The docs now say what "any local user can reach the port" means.** A
  connection is granted control as `dev`, with passwordless sudo, `share/`
  and the network. They also say not to run it on a shared machine.
- **The docs row** carries the catalogue note's "real desktop" /
  "human-confirmed" caveat, as step 4 asked.
- **SSH over vsock:** vsock port 22 resets the connection, the same answer
  as an unbound port, so nothing listens. Listing the guest's sockets
  through ai-mirror's clipboard came back empty, so that cross-check is
  inconclusive.

Left as they are:

- **Cold boot vs the 30 s request lifetime under TCG.** The note and docs
  state the ~20 s KVM figure, and TCG is unmeasured. A request that lapses
  is answered by asking again.
- **About 40 false `confirmed` audit lines during a cold boot.** ai-mirror's
  `_answer` audits before it checks the instance. That is an ai-mirror bug,
  for a separate ai-mirror issue. The audit dies with the VM.
- **The listener has no `Restart`**, matching `hyprland.nix`'s
  `Restart = "no"`.
- **Host socat** comes in through omarchy's runtime dependencies.
