---
status: approved
issue: 1226
intent: intent/2026-10-09-1226-gliff-preinstall.md
---

# Spec: gliff installed by default

## Design

The approved intent's open questions are settled as follows:

- gliff goes into the **preinstalls** set, so `preinstallsExclude = [ "gliff" ]`
  removes it.
- **sshd stays off**, and the docs say the target machine needs it.
- The Setup > Remote desktop menu is **not touched** here; a follow-up handles it.

### 1. The package: `pkgs/gliff/default.nix`, from a non-flake input

gliff ships no `flake.nix`, so it cannot be re-exported the way hypr-rdp is.
Instead:

- `flake.nix` gains the input
  `gliff = { url = "github:omacom/gliff/v0.3.0"; flake = false; };`, with a
  `# Why:` pointer like every other input.
- The overlay gains
  `gliff = final.callPackage ./pkgs/gliff { src = inputs.gliff; };`, and
  `packages.gliff` re-exports it beside `packages.hypr-rdp`.
- `pkgs/gliff/default.nix` is a `rustPlatform.buildRustPackage` built from
  `cargoLock.lockFile = "${src}/Cargo.lock"`. The lock has no git sources,
  so no output hashes are needed, and the lock moves with the tag.
  - `nativeBuildInputs`: `pkg-config`, `nasm` (OpenH264 builds from source
    with its assembly), `wrapGAppsHook4`.
  - `buildInputs`: `gtk4`, `libadwaita`, `libva`, `libdrm`, `libgbm` (or
    `mesa`, whichever nixpkgs provides `gbm.pc` from), `wayland`,
    `libxkbcommon`, `dbus`, `vulkan-loader`.
- Install the three binaries plus `pkgbuild/gliff.desktop` and
  `pkgbuild/gliff.svg`, matching the PKGBUILD's `package()`.
- **The Vulkan loader must be on the binaries' RUNPATH.** `ash::Entry::load()`
  (`crates/gliff-vk/src/device.rs:66`) `dlopen`s `libvulkan.so.1` by name,
  and nothing links it. Without the RUNPATH entry the build succeeds,
  `gliff-probe gpu` fails at runtime, and gliff silently drops to the CPU
  tier. That is the failure the intent names.
  - Fix: `postFixup` runs `patchelf --add-rpath ${lib.makeLibraryPath [ vulkan-loader ]}`
    on all three binaries.
  - libva is linked through pkg-config (`crates/gliff-va/build.rs`), so it
    needs nothing extra. Its driver and the Vulkan ICDs come from
    `/run/opengl-driver`, which NixOS provides.
- **`ssh` is resolved by name** (`crates/gliff-transport/src/ssh.rs:40`), so
  the `gliff` binary gets `openssh` on its PATH through `gappsWrapperArgs`
  (`--prefix PATH`). `gliff-server` and `gliff-probe` need no wrapper. The
  server runs on the far side of an ssh login, where the system path
  already applies.
- `doCheck = true`. Upstream CI runs `cargo test --workspace` in a container
  with no compositor, so the unit tests are sandbox-safe. Any test that
  turns out not to be gets skipped by name, with the reason, rather than
  `doCheck = false` for the whole package.
- `meta`: `license = with lib.licenses; [ mit bsd2 ]` (OpenH264, per the
  PKGBUILD), `mainProgram = "gliff"`, `platforms = [ "x86_64-linux" ]`.

### 2. Preinstalled: `modules/nixos.nix`

- `inherit (pkgs) gliff;` joins the preinstalls attrset (`:1490-1518`), with
  a one-line note that `install/omarchy-base.packages` names it.
- `"gliff"` joins both copies of the `known` list in the
  `preinstallsExclude` assertion (`:924-951`), and the message's
  "The set is:" sentence.
- The `preinstalls` description (`:610-623`) gains a sentence: gliff is
  upstream's base package (#14712), included here, and the machine being
  connected *to* also needs `services.openssh.enable`.
- The package comes from `pkgs.gliff`, i.e. the overlay that nixarchy's
  module already applies. It is not a `(pkgs.extend …)` default, because no
  option exposes it.

**Mode A:** a user importing the module gets gliff only with
`preinstalls = true`, which is the default today for every other
preinstalled app. That is the same exposure, through the same switch.

### 3. Cache and CI

Because it is preinstalled, gliff is now in `vm-toplevel` and
`reference-toplevel`, so the `system` job's allowlisted toplevel pushes
carry it with **no new allowlist entry**. The difference from hypr-rdp,
which is off by default and needed its own (`cache-allowlist.sh:41-47`), is
the reason.

- `cache-budget.sh` reports the cost, and that number goes in the PR.
- The closure adds little: GTK4, libadwaita, libva, Vulkan and Wayland are
  already in the desktop closure.
- `iso-budget` (nightly) covers the offline image's growth.

### 4. Probes

- **`checks.gliff-runpath`**, a new `runCommand`, cheap. It asserts that
  each of the three binaries' RUNPATH (`patchelf --print-rpath`) names a
  `vulkan-loader` store path, and that the `gliff` wrapper puts `ssh` on
  PATH (it runs the wrapper with `PATH` stripped and checks that
  `command -v ssh` resolves through it, or greps the wrapper's PATH prefix
  for `openssh`).
  - This is what catches the silent CPU fallback, and it is the only layer
    that can: CI VMs have no GPU, so `gliff-probe gpu` cannot pass anywhere
    in CI. Picked up automatically by `generated-checks.sh` (§4).
- **`checks.session`** gains a gliff block beside the hypr-rdp one
  (`tests/session.nix:678-706`). On the running desktop it:
  - starts `gliff-server --listen 127.0.0.1:<port> --headless`. Loopback,
    test-only; the TCP mode is never documented for users;
  - runs `gliff-probe --video cpu serve-test --connect 127.0.0.1:<port> --frames 10`;
  - asserts the HelloAck and StreamConfig lines, and that frames decoded.

  This proves the server captures this Hyprland and encodes on the CPU
  tier, end to end, through the real protocol. It is nixarchy's first
  remote-desktop probe that sees pixels move. The ssh hop is not covered:
  the session VM runs no sshd, and the GUI client needs a window.
- **`pkgs/verify.sh`** gains a hardware row, `gliff-probe gpu` (and
  `gliff-probe all` when a session is up). That is the GPU tier, answerable
  only on real hardware (§2). The same edit fixes the drift the research
  found: `tests/AGENTS.md` says verify.sh has a manual RDP step, and it has
  none. That sentence is corrected to match what is actually there.

### 5. Docs

- `docs/internals/flake.md`: an entry for the `gliff` input (why a
  non-flake input, why a tag, the RUNPATH trap), which the `# Why:` pointer
  links to.
- `docs/manual/remote-desktop.md`: a section at the top, "Between two
  nixarchy machines: gliff". It covers:
  - `gliff user@host`, `--headless`, `--output`;
  - the target needs sshd and a logged-in session;
  - removing gliff with `preinstallsExclude`;
  - **the clipboard warning**: while a tab is open, that host can read your
    local clipboard without a paste, so do not keep a tab open to a machine
    you do not trust while copying secrets.

  The hypr-rdp sections stay below it, retitled "From Windows, macOS or a
  phone: RDP". `tests/rdp-docs.sh` holds required phrases from this page,
  so it is run after the edit.
- No README row change. The README feature table rows are per feature, and
  remote desktop already has its row.

## Alternatives rejected

- **Replace hypr-rdp.** Rejected by the intent: gliff cannot serve
  Windows, macOS or phone clients.
- **Opt-in app row in `data/apps.nix`**, like freerdp. This was the earlier
  proposal; the approved intent asks for default.
- **A runtime dependency of the `omarchy` package.** That would make it
  unremovable, and the shell's remote-session plugin only `pgrep`s for
  `gliff-server`, so nothing needs it as a hard dependency.
- **Wait for nixpkgs.** There is no nixpkgs PR, and upstream shipped it as
  default today.
- **Tracking `main`.** The constraint is a release tag; `v0.3.0` is today's.
- **A two-VM ssh test of the GUI client.** It needs a window and sshd on a
  second node, at roughly double the session check's cost, to cover the ssh
  hop that ssh itself already owns. The loopback probe covers the part that
  is gliff's.

## Risks

- **The VM cannot capture.** The probe relies on Hyprland's
  `ext-image-copy-capture` working on the headless aquamarine backend under
  software GL. hypr-rdp's headless output works in the same VM, which is
  encouraging but not proof.
  - If capture fails there, the session block is dropped.
  - The hole is then named in `tests/AGENTS.md` and `tests/install-matrix.py`
    (§3), and `verify.sh` carries the end-to-end check.
  - The plan records that as a deviation. A probe that cannot pass is not
    shipped.
- **Build size and time.** About 230 crates plus OpenH264 from source, on
  every PR until the toplevel lands in the cache, then substituted.
  hypr-rdp's 447 crates are the comparison. `options` evaluates the
  toplevel but does not build it.
- **gliff is four weeks old.** Pinning a tag bounds that, and
  `preinstallsExclude` is the user's escape.
- **Clipboard exposure while in use** (security review, HIGH, use-only).
  It is documented in the manual, not patched. It belongs upstream, and
  filing there is the owner's call (§11).
- **NVIDIA:** both ends use the CPU tier. It works, and is documented
  upstream; nothing to do here.
- **Coexistence (§14):** a user who also installs a gliff of their own
  through `environment.systemPackages` gets a silent `system.path` clash.
  `lib.lowPrio` already wraps the preinstalls list (`:1490`), so theirs
  wins. That is the existing behaviour for every preinstall, and no new
  fixture is needed.

## Verification

- `nix build .#gliff`: builds, with the unit tests run.
- `checks.gliff-runpath`, break proof: remove the `patchelf --add-rpath`,
  watch it go red, restore, watch it pass. Same for the ssh PATH prefix.
- `checks.options`: the existing `preinstallsExclude` case still passes, and
  `preinstallsExclude = [ "gliff" ]` evaluates without the assertion firing.
- `checks.session` gliff block, break proof: point the probe at a port with
  no server, or drop `--headless`, and see it fail. Run in CI, and locally
  only under §6's idle rule.
- `checks.doc-options` (which runs `rdp-docs.sh`) still passes after the manual edit.
- On p620 (AMD), by hand: `gliff-probe gpu` passes.
  `gliff --headless localhost` shows the session. The output of both goes
  in the PR.
