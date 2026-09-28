---
status: approved
issue: 1031
intent: intent/2026-09-28-1031-hyprland-056-lua-fallback.md
---

# Spec: hypr-rdp's Lua fallback never fires on Hyprland 0.56

## Design

Two parts: the fix, carried as a patch, and the probe that would have seen the
bug (AGENTS.md §2 — a bug found by hand is not fixed until something can).

### 1. The patch

`pkgs/hypr-rdp/lua-fallback-on-unknown-request.patch` changes
`src/hyprland.rs` only:

- `is_non_legacy_parser_error()` (lines 250–254 of the pinned source) matches
  `"unknown request"` as well as `"non-legacy parsers"`. Nothing else in the
  fallback changes: `keyword_monitor()` already retries through
  `eval hl.monitor({...})`, and that Lua form was confirmed by hand on
  Hyprland 0.56.0 on p620.
- One unit test beside upstream's two (`:604`, `:611`), asserting that
  `"Hyprland IPC error: unknown request"` is detected. Upstream's negative test
  (`"monitor rule failed"` is not matched) is untouched and still passes.
- **Upstream's package sets `doCheck = false`** (`pkg/nix/package.nix`), so a
  unit test alone would never run. The override turns checks back on, scoped
  to the module the patch touches: `doCheck = true; checkFlags = [
  "hyprland::tests" ];`. Those tests are pure string functions -- no socket, no
  compositor -- so the sandbox cannot fail them for its own reasons, and the
  rest of upstream's suite, which it chose not to run, stays unrun. With that,
  **the package build is itself a cheap check**: a bump that drops the matcher
  change while the test survives fails the build.

The patch sits beside what it patches, as `pkgs/omarchy/901-*.patch` does.
The untracked `pkgs/patches/` directory from before the intent was approved
moves there; nothing else uses that path.

### 2. Applying it

`flake.nix:784` becomes:

```nix
# Why: docs/internals/flake.md#the-rdp-daemon-re-exported-from-its-own-flake-so-t
hypr-rdp =
  inputs.hypr-rdp.packages.${final.stdenv.hostPlatform.system}.hypr-rdp.overrideAttrs
    (old: {
      patches = (old.patches or [ ]) ++ [ ./pkgs/hypr-rdp/lua-fallback-on-unknown-request.patch ];
      doCheck = true;
      checkFlags = [ "hyprland::tests" ];
    });
```

The vendor hash does not move: upstream's package uses `cargoHash`, the patch
touches no `Cargo.*` file, and `cargoDeps` is computed from `src`, which
`overrideAttrs` does not change.

The existing section in `docs/internals/flake.md` gains a paragraph: what the
patch fixes, that it is the wrong way round (the fix belongs upstream), and
the **retirement condition** — drop it when a hypr-rdp tag carries a matcher
that accepts `unknown request`. The build says when: the patch stops applying.
The exit the section already describes (delete the input when nixpkgs carries
hypr-rdp) still costs one attribute, and takes the patch with it.

### 3. The probe: `checks.session` starts the daemon

`tests/session.nix` already boots Lua-era Hyprland on the headless aquamarine
backend and drives `hyprctl` against it (`:463–466`). That is exactly the
environment this bug needs, so the probe goes there rather than into a new VM:

- the session machine enables `programs.nixarchy.services.hypr-rdp`, with a
  password from a sops secret decrypted by a **test-only** age key committed
  under `tests/fixtures/hypr-rdp/` (labelled as such; it protects nothing —
  sops-nix's own tests do the same);
- the test script waits for the user unit, then asserts **both**
  `systemctl --user is-active hypr-rdp` and that `hyprctl monitors` lists a
  `HEADLESS-` output at the configured resolution. The second assertion is the
  one this bug breaks: the daemon dies after creating the output and before
  setting its mode.
- **Vary the variable (§3):** the probe first asserts that the VM's Hyprland
  answers `unknown request` to `hyprctl keyword monitor ...`. If a future
  nixpkgs brings a Hyprland that still accepts `keyword`, the probe says so
  instead of passing without exercising the fallback.

## Alternatives rejected

- **Split the probe into its own issue.** Recommended in my note on the
  intent; rejected here on re-reading §2, which says the bug is not fixed
  until something can see it. `checks.session` already has the compositor, so
  the probe is a few lines and one fixture, not a new VM.
- **A new VM check just for hypr-rdp.** Another 10–20 minutes on the four
  p620 runners, booting the same desktop `session` already boots.
- **Pin an older Hyprland.** Every nixarchy machine runs 0.56; a daemon that
  only works on the version nobody has is not a fix.
- **Fork hypr-rdp and point the input at the fork.** A second repository to
  keep in step with upstream, for a one-line change. A patch fails loudly when
  it stops applying; a fork drifts silently.
- **Patch the monitor rule into our module instead** (set the mode with
  `hyprctl eval` from `ExecStartPost`). Races the daemon, which dies on the
  failed `keyword` before any post-start hook matters.
- **Filing upstream.** Not rejected — not this spec's decision. Nothing is
  posted to `MuNeNiCK/hypr-rdp` without the owner's explicit word (§11).

## Risks

- **`checks.session` gets slower and gains a moving part.** One more user
  unit and a sops activation step. If the daemon's startup is slow in a
  software-rendered VM, the wait needs a timeout generous enough not to flake
  — measured on the first run, not guessed. A flake here would redden every
  PR, so the timeout is the thing to get right.
- **Upstream reword.** If Hyprland changes the error text again, the patch
  compiles and the fallback silently stops firing — which the session probe
  now catches, on the next nixpkgs bump.
- **Turning checks on costs a test build.** `cargo test` compiles a test
  binary on top of the release build. Measured when the plan runs it, and
  stated in the PR; if it is large, the scoped filter already keeps the run
  itself trivial, and the build is lazy -- only machines that enable RDP pay.
- **p620 and p510** pick this up at their next deploy; no host changes in
  this repository.

## Verification

1. **Red first (§1).** With the patch's matcher hunk removed and its test
   kept, `nix build .#hypr-rdp` fails in `cargo test` naming the new test.
   Restored: builds.
2. **Session probe red.** With the patch removed from the overlay,
   `checks.session` fails on the `HEADLESS-` assertion, and its journal shows
   `Hyprland IPC error: unknown request`. Restored: passes. Both outputs go in
   the PR. (Run only when `gh run list` shows no install in flight — §6.)
3. **The real machine.** On p620 after deploy: `systemctl --user status
   hypr-rdp` active, `hyprctl monitors` lists the headless output, and a
   `nixarchy remote connect` from razer reaches the desktop.
4. `nix fmt -- --ci`, `statix`, `deadnix`, and `git diff --stat` read after
   formatting (§5, the nixpkgs-fmt hook).

## Still open

- **Upstream report** (intent, question 1): unanswered. Default is not to
  file.
