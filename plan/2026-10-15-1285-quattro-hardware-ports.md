---
status: approved
issue: 1285
spec: spec/2026-10-15-1285-quattro-hardware-ports.md
---

# Plan: fprintd survives suspend, and the boot splash re-centres for a late display

## Approved decisions (from the spec; implement against these)

- **fprintd.** Inside `mkIf cfg.enable`, each gated on
  `config.services.fprintd.enable`:
  - `powerManagement.resumeCommands` gains
    `${config.systemd.package}/bin/systemctl --no-block try-restart
    fprintd.service || true`, with a plain assignment (`lines`);
  - `systemd.services.fprintd.serviceConfig.TimeoutStopSec = lib.mkDefault
    "3s"`.

  Nixarchy never turns fprintd on, and Mode A is untouched.
- **Splash.** In `pkgs/omarchy/nixarchy-plymouth.script`:
  - every positioning statement moves, unchanged and in order, into a
    `fun layout()`, which records `global.layout_width` and
    `global.layout_height`;
  - `layout()` is called once at top level after the sprites exist;
  - `refresh_callback()` calls `layout()` when `Window.GetWidth()`/
    `GetHeight()` differ from the recorded size;
  - bullets get `fun position_bullet(index)`, used at creation and from
    `layout()`.
- **Checks:**
  - `checks.options` covers both states, Mode A, and a user's
    `TimeoutStopSec` winning;
  - a new `checks.plymouth-layout` holds the script's structure.
- **Hardware-only parts are recorded in `tests/AGENTS.md`**: a real suspend
  with a reader, and a real late display. `pkgs/verify.sh` has no
  fingerprint section, and the note says so.
- **The edge carry** (making `apply-lock`'s two installs no-ops) is not in
  this PR. It follows edge's merge of `main`.

## Steps

1. **`modules/nixos.nix`, beside the fprintd block (~:1751).** Add the two
   settings, each with a one-line comment (fprintd#173 for the restart;
   "a stale handle can make fprintd ignore SIGTERM" for the timeout).
   - If `powerManagement` or `systemd.services` already appear as keys in
     that attrset, statix rejects a second one, so fold into the existing
     key.
   - `modules/AGENTS.md`: one line under the fprintd/lock note, or the
     nearest fprintd section (grep `fprint`).

   **Verify:**
   - `nix eval` the vm config with `services.fprintd.enable = true` (an
     `extendModules`): `powerManagement.resumeCommands` contains
     `try-restart fprintd.service`, and `TimeoutStopSec` is `"3s"`;
   - without fprintd, neither is set.

   **Traps:**
   - Run `nix fmt`, then read `git diff --stat` (§5).
   - `mkDefault` on the scalar only; `lines` is a plain assignment (§7).

2. **`tests/options.nix`.** Add a case following the file's both-states
   pattern (`on`/`off`):
   - **on:** a fixture with nixarchy on and `services.fprintd.enable =
     true` has both settings;
   - **off:** nixarchy on with fprintd off has neither; Mode A (nixarchy
     off, fprintd on) has neither;
   - **plus:** a fixture setting `TimeoutStopSec = "10s"` keeps `"10s"`.

   Reuse an existing fixture constructor (the file binds them once; grep
   `configWith`/`configBeside`). Don't add evaluations needlessly: §12
   notes the check's memory.

   **Verify:** by `nix eval` of the case's attributes (via a scratch copy
   that returns the cases, as #1283 did). Build the full `checks.options`
   only when `gh run list` shows nothing in flight (§6).

   **Red proof:** remove the fprintd gate (always set), so the off case
   fails; or drop `mkDefault`, so the user-wins case fails.

3. **`pkgs/omarchy/nixarchy-plymouth.script`.** The refactor, as described
   above:
   - Move the statements, don't rewrite them.
   - Add `global.layout_width = 0; global.layout_height = 0;` before
     `refresh_callback`.
   - The guard at the top of `refresh_callback`:
     `if (Window.GetWidth() != global.layout_width || Window.GetHeight() !=
     global.layout_height) { layout(); }`.
   - Plymouth script scoping: inside functions, use `global.` for the
     recorded size. Sprites declared at top level (`logo.sprite`, …) are
     reachable as upstream's own `layout()` reaches them. Mirror
     upstream's code in quattro's `default/plymouth/omarchy.script`: read
     it from the edge input (`nix flake archive --json` on `wt-edge`, the
     omarchy path) or with `gh api …/contents/default/plymouth/omarchy.script?ref=quattro`.

   **Verify:** `nix build .#omarchy` (package tier: check the load and that
   no p620 build is running first). The script installs as
   `share/plymouth/themes/omarchy/omarchy.script`.

   **Traps:**
   - The script is plymouth's language, not JS: no `let`/`const`, and
     `fun` declares a function.
   - A missing sprite is silent, so read the diff line by line.

4. **`tests/plymouth-layout.nix` (new), registered in `uniformChecks`.** A
   `runCommand` that reads the script (from `../pkgs/omarchy/nixarchy-plymouth.script`)
   with a small Python or awk brace-depth walk, and asserts:
   - (a) no line at depth 0 calls `.SetX(`, `.SetY(` or `.SetPosition(`;
   - (b) a `fun layout()` exists and is called at depth 0;
   - (c) inside `fun refresh_callback()` there is an `if` comparing
     `Window.GetWidth()` and `Window.GetHeight()` with
     `global.layout_width`/`global.layout_height` that calls `layout()`.

   Strip `#` comments first. Each failure prints which rule broke and the
   line.

   **Verify:** `nix build .#checks.x86_64-linux.plymouth-layout`.

   **Red proofs:**
   - move one `SetPosition` back to top level, so (a) fails;
   - delete the guard, so (c) fails.

   Copy the script aside first and restore from the copy (§5).

5. **`tests/AGENTS.md`.** A short section at the end: "The hardware-only
   pair: fprintd after a real suspend, and a splash for a late display".
   - What each check holds, and what only hardware can show.
   - That `pkgs/verify.sh` has no fingerprint section to extend.
   - How to check by hand:
     - suspend, resume, unlock with a finger;
     - boot with a Thunderbolt dock and look at the splash.

   **Verify:** `checks.docs-lists` is unaffected (`tests/AGENTS.md` is not
   in the manual).

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.plymouth-layout` | green; red for each of the two breaks |
| `nix build .#omarchy` | builds, with the script installed |
| `nix build .#checks.x86_64-linux.options` (CI idle, or CI) | green; red with the gate or `mkDefault` removed |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Model split

Steps 1–4 edit four files, so they go to the `coder` agent (steps 1–2, then
3–4). Step 5 and the review stay with the lead. A fresh Opus agent reviews
the diff against this plan.

## Rollback

Revert the merge. fprintd goes back to staying wedged after some resumes,
and the splash goes back to centring once. Nothing else depends on either.

## Deviations recorded during implementation

- **Step 1.** `TimeoutStopSec` is added through `lib.optionalAttrs
  config.services.fprintd.enable` on the `systemd.services` attrset, not
  `lib.mkIf`. A `mkIf` on an `attrsOf` entry still creates a stub
  `fprintd.service` when fprintd is off; the eval showed it, and the PAM
  block's own comment says the same. Because `services = { … } //
  optionalAttrs …` cannot merge with a dotted `services.avahi-daemon`, the
  avahi block (#1276) moved, unchanged, into the `services` literal.
- **Step 2.** The cases are `fprintdResume` and `fprintdStopTimeoutUserWins`,
  through `extendModules` on the existing `adopter` and `modeAOff`, which is
  three evaluations. Red proofs ran by eval: with the gates set to `true`,
  `fprintdResume` reports `off=true`; with `mkDefault` dropped, the user-wins
  fixture fails on conflicting definitions.

