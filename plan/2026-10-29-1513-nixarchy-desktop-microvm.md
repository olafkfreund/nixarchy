---
status: approved
issue: 1513
spec: spec/2026-10-29-1513-nixarchy-desktop-microvm.md
---

# Plan: a sandbox that runs the nixarchy desktop, for an agent to drive

The approved decisions from the spec, collected here so this plan can be
implemented on its own:

- **New catalogue template `nixarchy-desktop`.** It runs the stock nixarchy
  desktop for the guest's `dev` user and carries ai-mirror, reachable over
  vsock port 7000 the same way as `hyprland-ai-mirror`. Control is granted
  without asking, because starting the VM is the consent.
- **The template imports `inputs.self.nixosModules.nixarchy` and
  `inputs.home-manager.nixosModules.home-manager`.** It does not import
  `installer/host.nix`. The only lines carried over from host.nix are
  `programs.nixarchy` and `home-manager`. `lib.mkMicrovm` already passes
  `specialArgs.inputs` (#1505).
- **Session setup:**
  - SDDM autologin as `dev`.
  - `WLR_RENDERER_ALLOW_SOFTWARE=1` and `LIBGL_ALWAYS_SOFTWARE=1`.
  - at-spi2-core on.
  - `-device virtio-gpu-pci` with no host GL (#1506).
  - 8192 MiB of memory and 4 vCPUs.
- **The ai-mirror half moves into `ai-mirror-guest.nix`.** Both ai-mirror
  templates import it. `hyprland-ai-mirror`'s guest toplevel has to stay
  byte-identical.
- **`data/microvm-templates.nix` names this entry as the one exception** to
  "a template imports nothing else nixarchy ships", and says why.
- **Both runners (KVM and TCG) stay.** They share the guest closure, and the
  CLI falls back to TCG when there is no KVM.
- **Deferred:** running a nixarchy branch other than the one that built the
  CLI.

Coders:
- Steps 1, 2, 4 and 5 go to the `coder` agent, one agent, continued with
  SendMessage.
- Step 3 is a live boot on p620 and stays with the session. It decides any
  deviations.
- The review is a fresh Opus agent, given this plan and `git diff
  origin/main`.

## Steps

1. **Split out the ai-mirror half.**
   - Create `modules/microvm/templates/ai-mirror-guest.nix` with the whole
     body of the current `hyprland-ai-mirror.nix` except its `imports` line.
     That means the header comment, the `am`/`path`/`vsockCid` let-bindings,
     `microvm.extraArgsScript`, the three packages and both user services.
   - Reduce `hyprland-ai-mirror.nix` to its header plus
     `imports = [ ./ai-mirror-guest.nix ./hyprland.nix ];`.
   Deviation, made while implementing: this import order is required.
   The order sets the order of `environment.systemPackages`, which reaches
   buildEnv. With `./hyprland.nix` first, the toplevel changed.

   → Verify:
   - Before editing, run
     `readlink $(nix build --no-link --print-out-paths .#microvm-hyprland-ai-mirror)/share/microvm/system`.
     If the runner has no such link, find the toplevel path the runner
     references and use that instead.
   - After the edit, run the same command. The two outputs must be
     identical.

   Traps:
   - In a Nix `''` string, `\$` is a literal backslash. Copy the services
     byte for byte; don't re-escape them (AGENTS.md).
   - Check `nix build`'s exit status, not just the out-link, which may be
     stale.

2. **Add the template and its catalogue entry.**
   - Create `modules/microvm/templates/nixarchy-desktop.nix` as in the
     spec's Design section 2. Put a header comment in the style of
     `hyprland.nix`: what it is, #1513, why it does not import host.nix,
     and why software rendering.
   - In `data/microvm-templates.nix`, after the `hyprland-ai-mirror` entry,
     add `nixarchy-desktop = { label = "Nixarchy desktop + ai-mirror";
     module = ../modules/microvm/templates/nixarchy-desktop.nix; note = …; }`.
     Leave the note text as a placeholder sentence for now. Step 4 writes
     it with the numbers measured in step 3.

   → Verify:
   - `nix build .#microvm-nixarchy-desktop -o /tmp/<scratch>/nd-runner;
     echo $?` exits 0.
   - The same for `.#microvm-nixarchy-desktop-tcg`. Its `share/microvm/system`
     must be the same path as the KVM runner's.

   Traps:
   - The first build is large. Run it in the background and wait for it.
   - If evaluation fails on a NixOS option that conflicts with guest.nix
     (`users.users.dev`, getty autologin) or with microvm.nix (bootloader),
     fix it in the template with the narrowest override. Record each one in
     this plan in the same commit.

3. **Boot and measure on p620 (the session, not the coder).**
   - Create a run directory in the scratchpad with `share/` and `policy/`
     in it. Write `1513` into `vsock-cid`.
   - Run `nd-runner/bin/microvm-run` in the background, from that
     directory.
   - Probe with the session's `mcp-probe.py`, pointed at CID 1513.
   - Measure and record in the spec's Verification section (as Results):
     1. The time from start to `owner: agent`.
     2. That `index` lists nixarchy's keybindings and plugins.
     3. A screenshot showing the bar.
     4. That `launch` and `input` work in a terminal.
     5. That no confirm dialog is left in the layers after the grant.
     6. Any first-run surface covering the desktop.
     7. The monitor size.
     8. The number of new qemu core dumps after a stop.

   → Pass when all of these hold:
   - The grant needs no human.
   - The bar is visible.
   - Typing reaches the terminal.
   - Nothing covers the desktop.
   - There are 0 core dumps.

   **Stop condition:** if the session doesn't come up after two fix
   attempts, stop and report. Don't fall back silently. The spec's fallback
   is a user-service Hyprland, which is a deviation recorded here first.

   Traps:
   - Use `pkill -f '[m]icrovm@'` to stop the VM. A pattern that appears in
     your own command line kills your own shell (exit 144).
   - Don't touch the host's ai-mirror state. Compare `ai-mirror status` on
     the host before and after.

   **Deviations, made in step 3 (session, 2026-10-29):**
   1. `microvm.writableStoreOverlay = "/nix/.rw-store"`. With a read-only
      store, microvm.nix masks `nix-daemon`. Home Manager's activation then
      failed with `creating directory "/nix/var/nix/temproots": Permission
      denied`, so there was no `~/.config/hypr`, a `hypr.monitors` config
      error, and no bar.
   2. The auto-grant waits for the desktop to settle. A `preStart` on
      `ai-mirror-autoconfirm` waits for omarchy's
      `done/first-run-user` marker, then sets do-not-disturb on and
      dismisses all toasts. Before this, the first grant came at about 20 s,
      before the bar and the first-run toasts had mapped. ai-mirror then
      refused all typing (`wrong_target`, ai-mirror#78), and the toasts
      covered the top-right of the screen.

4. **Catalogue exception and docs.**
   - `data/microvm-templates.nix`, under "## The bar": add a paragraph
     naming `nixarchy-desktop` as the single exception. Its purpose *is* the
     nixarchy desktop, so it can't be plain NixOS. A user who outgrows it
     starts from the installer's generated flake.
   - Write the entry's note from step 3's numbers. Cover:
     - what it is, and the consent model;
     - the `claude mcp add` line, as in `hyprland-ai-mirror`;
     - software rendering;
     - the measured time to the first grant;
     - the closure size, from `nix path-info -Sh` on the guest toplevel.
   - `docs/manual/sandboxes.md`: add a table row after line 84 in the same
     shape as the `hyprland-ai-mirror` row. In the "Driving one with
     ai-mirror" section, add one sentence saying that `nixarchy-desktop`
     gives the agent nixarchy's own keybindings, bar and `omarchy-*`
     commands.

   → Verify by building `checks.x86_64-linux.microvm-template`. It requires
   the docs row.

   Traps: the check matches `` | `nixarchy-desktop` | `` literally.

5. **Formatting and lint.**
   - Run `nix fmt -- --ci`, `statix check` and `deadnix --fail`.
   - Open a PR that links the intent, spec and plan, and says which steps
     the coder did.
   - Wait for CI to pass, then merge with a merge commit.

   → Verify: everything is green.

## Tests

- Step 1: the toplevel paths are identical (the refactor changes nothing).
- Steps 2 and 3: the KVM and TCG runners build, and the live boot passes
  every check in step 3.
- Step 4: `checks.x86_64-linux.microvm-template` passes.
- Step 5: `nix fmt -- --ci`, statix and deadnix are clean, and CI is green.

## Rollback

Revert the merge commit. Nothing changes on any host until a nixarchy
bump, and existing VMs from other templates aren't affected. Any VMs
already created from `nixarchy-desktop` stop resolving their template, and
`nixarchy vm rm` removes them.
