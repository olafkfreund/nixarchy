---
status: approved
issue: 1226
spec: spec/2026-10-09-1226-gliff-preinstall.md
---

# Plan: gliff installed by default

## Decisions carried from the approved spec

- Package gliff (omacom/gliff, MIT, Rust) from a **non-flake input pinned to
  `v0.3.0`**. Put it in the overlay as `gliff` and re-export it as
  `packages.gliff`. gliff ships no flake.nix, and its `Cargo.lock` has no git
  sources.
- **Preinstalled** in `modules/nixos.nix`'s preinstalls set, so
  `preinstallsExclude = [ "gliff" ]` removes it. Mode A exposure is the same
  as every other preinstall.
- **sshd stays off.** The docs say the machine being connected *to* needs it.
- **hypr-rdp, the Setup > Remote desktop menu and `nixarchy-remote` are not
  touched.** Pointing the menu at gliff is a follow-up.
- **Vulkan loader on the RUNPATH** of all three binaries.
  `ash::Entry::load()` dlopens `libvulkan.so.1` by name; without the RUNPATH
  entry gliff falls back silently to the CPU tier.
- **`ssh` on the `gliff` client's PATH.** `gliff-transport/src/ssh.rs:40`
  resolves it by name. `gliff-server` and `gliff-probe` are not wrapped.
- **`doCheck = true`.** Skip individual tests only by name, with the reason.
- **No new cache allowlist entry.** As a preinstall, gliff rides inside
  `vm-toplevel`/`reference-toplevel`. Its cost is what `cache-budget.sh`
  reports, and that number goes in the PR.
- **Probes:**
  - `checks.gliff-runpath`: cheap, the only CI layer that sees the RUNPATH;
  - a `checks.session` block: `gliff-server --listen` on loopback plus
    `gliff-probe serve-test` on the CPU tier;
  - a `pkgs/verify.sh` hardware row: `gliff-probe gpu`.
- **Docs:**
  - a `docs/internals/flake.md` entry for the input;
  - a gliff section at the top of `docs/manual/remote-desktop.md`, with the
    sshd requirement and the **clipboard warning** from the security review;
  - the RDP sections retitled "From Windows, macOS or a phone: RDP".
- `gliff-server --listen` (no authentication) is **never documented for
  users**. It appears only in the check.
- If the session VM cannot capture, the session block is dropped and **not
  shipped as a check that cannot pass**. Name the hole in `tests/AGENTS.md`
  and `tests/install-matrix.py` (§3), and record the deviation here.

## Steps

1. **Input, package, overlay, packages export.**
   - `flake.nix:126-130`: after the `hypr-rdp` input, add
     ```nix
     # Why: docs/internals/flake.md#<anchor of the step-6 entry>
     gliff = {
       url = "github:omacom/gliff/v0.3.0";
       flake = false;
     };
     ```
   - `flake.nix:884-893`: after the `hypr-rdp` overlay entry, add
     `gliff = final.callPackage ./pkgs/gliff { src = inputs.gliff; };`
     (check how `inputs` is in scope there; hypr-rdp uses `inputs.hypr-rdp`).
   - `flake.nix:1167`: add `gliff = pkgsFor.${system}.gliff;` beside
     `hypr-rdp`.
   - New `pkgs/gliff/default.nix`: `rustPlatform.buildRustPackage`.
     - `pname = "gliff"`; `version = "0.3.0"`; `src`;
       `cargoLock.lockFile = "${src}/Cargo.lock"`.
     - `nativeBuildInputs = [ pkg-config nasm wrapGAppsHook4 ]`.
     - `buildInputs = [ gtk4 libadwaita libva libdrm libgbm wayland libxkbcommon dbus vulkan-loader ]`.
     - `doCheck = true`.
     - `postInstall`: install `pkgbuild/gliff.desktop` to
       `share/applications/` and `pkgbuild/gliff.svg` to
       `share/icons/hicolor/scalable/apps/`. Cargo installs all three
       binaries; confirm with `ls result/bin`.
     - `dontWrapGApps = true`.
     - `postFixup`: first
       `patchelf --add-rpath ${lib.makeLibraryPath [ vulkan-loader ]}` on
       `$out/bin/{gliff,gliff-server,gliff-probe}`, then
       `wrapGApp $out/bin/gliff --prefix PATH : ${lib.makeBinPath [ openssh ]}`.
       Patch before wrapping, so the RUNPATH lands on the ELF that becomes
       `.gliff-wrapped`.
     - `meta`: `description`, `homepage`,
       `license = with lib.licenses; [ mit bsd2 ]`,
       `mainProgram = "gliff"`, `platforms = [ "x86_64-linux" ]`.
     - One short header comment: why not nixpkgs, and the RUNPATH note.
       The long reasoning goes in flake.md (§7).
   - `nix flake lock` adds only the new input. Then `git diff flake.lock`
     must show only a `gliff` node plus the root's `inputs.gliff`.
   - Verify:
     - `nix build .#gliff -L`. This is a package build that is not cheap,
       so it runs only when no p620 system build is running and the
       1-minute load is below 12 (§6 tiers).
     - Then, by hand on p620:
       - `result/bin/gliff-probe gpu` reports PASS;
       - `patchelf --print-rpath result/bin/.gliff-wrapped` names
         vulkan-loader;
       - `result/bin/gliff --help` runs.
     - If any upstream test fails in the sandbox, skip it by name with
       `checkFlags = [ "--skip=<name>" ]` and a comment giving the reason.
   - Traps:
     - a new file must be `git add`ed before the flake can see it (§5);
     - after the edit, run `nix fmt` and read `git diff --stat`, because
       the nixpkgs-fmt hook can reformat (§5, #897);
     - do not pipe `nix build` into `tail` (§1, pipefail).

2. **`checks.gliff-runpath`.**
   - New `tests/gliff-runpath.nix`, taking `{ inputs, pkgs }:` (the
     `uniformChecks` signature, `flake.nix:2681-2687`). It is a
     `pkgs.runCommand` using `pkgs.patchelf`.
     - For each of `gliff-server`, `gliff-probe` and `.gliff-wrapped`:
       `patchelf --print-rpath` must contain `${pkgs.vulkan-loader}/lib`.
     - The `gliff` wrapper text must name `${pkgs.openssh}/bin`.
     - Assert a floor of 3 binaries checked. A loop that reads none passes
       in silence (tests/AGENTS.md).
   - Register it in `uniformChecks` (`flake.nix:1842…`), alphabetically
     after `"generate-config-surface"`, with a two-line comment. It is
     picked up by `generated-checks.sh`, so no workflow edit is needed
     (§4).
   - Verify, under `flock /mnt/data/vmtest/codex-build.lock` (cheap tier):
     1. Evaluate the drvPath first (§5) and check it is the derivation you
        mean.
     2. `nix build '<drv>^*'` passes.
     3. **Break 1:** remove the `patchelf --add-rpath`. Prove the break
        landed (`git diff`), see red, and capture the output.
     4. **Break 2:** remove the `--prefix PATH`. See red.
     5. Restore with `git checkout HEAD -- pkgs/gliff` (HEAD, not the
        index: §5). Commit the step-1 baseline before starting.

3. **Preinstall.** In `modules/nixos.nix`:
   - `:1490-1518`: add `inherit (pkgs) gliff;` to the preinstalls attrset,
     with a one-line comment saying `install/omarchy-base.packages` names
     it, and pointing to omacom/omarchy#14712.
   - `:924-951`: add `"gliff"` to **both** `known` lists in the
     `preinstallsExclude` assertion, and to the "The set is:" message
     string.
   - `:610-623`: in the `preinstalls` description, add one sentence saying
     gliff is included, and that a machine connected *to* also needs
     `services.openssh.enable`.
   - Verify (evaluation, cheap tier):
     - `nix eval .#nixosConfigurations.vm.config.environment.systemPackages --apply 'ps: builtins.any (p: (p.pname or "") == "gliff") ps'`
       returns `true`;
     - the same with `preinstallsExclude = [ "gliff" ]` returns `false`.
       Use a small `--impure --expr` that extends the `vm` config.
     - `checks.options` is ~11.5 GB, so it is left to CI (§6).
   - Traps:
     - plain list assignment, no `mkDefault` on a list (§7);
     - run under `env -u NIXPKGS_ALLOW_UNFREE`, which is not needed here
       but harmless.

4. **`checks.session` gliff block.** In `tests/session.nix`, directly after
   the hypr-rdp block (`:678-706`), using its `on_desktop()` helper
   (`:687`):
   - Start the server detached in the user session, for example
     `systemd-run --user --unit=gliff-probe-server gliff-server --listen 127.0.0.1:9077 --headless`.
     Do not use a bare `&` inside `machine.succeed`, which can hang on the
     inherited file descriptors.
   - `wait_until_succeeds` on the port listening.
   - `out = machine.succeed(on_desktop("gliff-probe --video cpu serve-test --connect 127.0.0.1:9077 --frames 10 2>&1"))`.
     Check `gliff-probe --help` for where `--video` goes, since it is a
     global flag.
   - Assert that `HelloAck` and `StreamConfig` are in `out`, and whatever
     line serve-test prints for decoded frames. Read
     `crates/gliff-probe/src/main.rs:516-…`.
   - Stop the unit.
   - Add a comment on why loopback `--listen` is acceptable here: test-only,
     never documented.
   - Verify: this is a VM check, so run it locally only when
     `gh run list --limit 8 …` reports nothing in flight (§6). Otherwise CI
     runs it. Evaluate the drvPath first and build `'<drv>^*'` (§5).
     - **Break:** point `--connect` at a port with no server. See red,
       capture the output, restore.
   - **If capture cannot work in the VM** (serve-test fails with the server
     up):
     - remove the block;
     - add the hole to `tests/AGENTS.md`'s remote-desktop paragraph and to
       `tests/install-matrix.py` near `:199-215`;
     - record the deviation and the error text in this plan, in the same
       commit.

5. **`pkgs/verify.sh` row, and the `tests/AGENTS.md` drift.**
   - In `pkgs/verify.sh`, after the "Installed and launchable" section
     (`:1170-1183`), add a section `head_ "Remote desktop (gliff)"`:
     - when `gliff-probe` is on PATH, run `timeout 60 gliff-probe gpu` and
       report `ok` or `hmm`, with "CPU tier only" for NVIDIA;
     - when it is not on PATH, report `hmm "gliff" "not installed (preinstallsExclude?)"`.
     - Follow the file's own `ok`/`bad`/`hmm` helpers (`:30-44`).
   - `tests/AGENTS.md:331-334`: "What is left is a client connecting and
     seeing a desktop. That is a step in `pkgs/verify.sh` for a human" is
     false; verify.sh has no RDP step. Rewrite it to say:
     - an RDP client connecting is still untested anywhere, and is a
       documented hole;
     - gliff's server half is covered by `checks.session` (or the hole, if
       step 4 deviated);
     - the GPU tier is covered by verify.sh's new row.
   - Verify:
     - `bash -n pkgs/verify.sh`;
     - shellcheck, if the repo's lint runs it on this file;
     - run the new section on p620.

6. **Docs.**
   - `docs/internals/flake.md`: a new `###` entry beside the hypr-rdp input
     entry (`:280`). It covers:
     - why it is a non-flake input (no flake.nix upstream);
     - why the tag;
     - the RUNPATH trap and the check that holds it;
     - why it is a preinstall rather than an `omarchy` runtime dependency
       (the remote-session plugin only `pgrep`s).

     Its heading's anchor is the one in step 1's `# Why:`. Generate it the
     way the existing ones are truncated, and check it matches.
   - `docs/manual/remote-desktop.md`: rewrite the intro (`:5-10`) to name
     both tools. Then a new `## Between two nixarchy machines: gliff`
     section before `## What it is not`, covering:
     - `gliff user@host`, `--output NAME`, `--headless`;
     - the target needs `services.openssh.enable = true` and a logged-in
       session;
     - removing gliff with `preinstallsExclude = [ "gliff" ];`;
     - the clipboard warning: while a tab is open, that host can read your
       local clipboard without a paste, so do not keep a tab open to a
       machine you do not trust while copying secrets.

     Retitle the RDP material under a `## From Windows, macOS or a phone: RDP`
     heading. Keep its existing subheadings so anchors only move, not
     vanish; grep `docs/` for links to them.
   - Verify:
     - build `checks.doc-options` (it runs `tests/rdp-docs.sh`, which holds
       required phrases from this page) under the lock;
     - `grep -rn 'remote-desktop.md#' docs README.md` shows links that
       still resolve.

7. **Finish.**
   - `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`.
   - `git merge-base origin/main HEAD` is the expected base.
   - PR:
     - link intent, spec and plan;
     - include the break outputs from steps 2 and 4;
     - include the `cache-budget.sh` number from the `system` job and the
       p620 `gliff-probe gpu` output;
     - say which steps the coder did;
     - mention the security review's upstream items (clipboard, `--` before
       the host, `--listen` not restricted to loopback, `StreamConfig`
       bounds) as not filed: the owner decides (§11).
   - Post to the bus only if a step taught something general.

## Tests

| Command | Expected |
|---|---|
| `nix build .#gliff -L` | builds, upstream unit tests pass |
| `nix build '<gliff-runpath drv>^*'` | passes; red with either break |
| the `nix eval` pair in step 3 | `true` / `false` |
| `checks.session` (CI, or local when idle) | the gliff block passes; red with the dead port |
| `checks.doc-options` | passes |
| p620: `gliff-probe gpu`, `gliff --headless localhost` | PASS; a window showing the session |

## Rollback

Revert the squash commit. Nothing is stateful: no service, no secret, no
migration. Users who already rebuilt lose the package on their next
rebuild. A single user can drop it at any time with
`preinstallsExclude = [ "gliff" ]`.

## Deviations

- **Step 6:** the RDP material is introduced by a new
  `## From Windows, macOS or a phone: RDP` section that sits before it.
  Its existing headings were not demoted under that section, so every anchor
  in the page stays where it was. The plan asked for them to move under the
  new heading.
  - A grep of `docs/` and `README.md` found no deep links into the page, so
    nothing depended on the anchors.
  - The cost is that "Letting an agent drive another machine", which is not
    RDP, still reads as a sibling of the RDP sections.
- **Step 3:** `inherit (pkgs) gliff;` fails with `attribute 'gliff' missing`.
  The spec was wrong to say this module's `pkgs` already has nixarchy's
  overlay applied: Mode A means it does not.
  - The fix is the pattern the module already uses for `omarchy` (`:400`) and
    `owe` (`:2200`): `inherit (pkgs.extend inputs.self.overlays.default) gliff;`.
  - Found by the step 3 evaluation, before any check that would have failed
    on it in CI.
- **Step 4:** in the session VM, capture fails, as the spec's risk said it
  might. The server came up, `HelloAck: headless=true output=gliff-26053` and
  `StreamConfig: 1920x1080 chroma Single420` arrived, and then:
  `gliff_server: session ended with error error=capture: io: No such file or directory (os error 2)`.
  - The cause is that hypr-capture allocates its capture buffers with GBM on
    `/dev/dri/renderD128` (`crates/hypr-capture/src/lib.rs:69`), even on the
    CPU tier, and the VM has no render node.
  - The plan said to drop the block. It is **narrowed instead**, to what the
    VM can answer: the server is on PATH, it reaches Hyprland, it creates its
    own headless output (`output=gliff-<pid>`) through the Lua config (#1031's
    failure class), and it negotiates a stream.
  - The dead-port break still turns it red, so it can fail (§1).
  - Frames move to hardware: `pkgs/verify.sh`'s row now also runs
    `gliff-probe all` and `gliff-probe pipeline`. Neither injects input.
    - Measured on p620: `captured 2560x1440 … from DP-1`,
      `PASS Dual420 4:4:4 GPU pipeline on a captured frame`, 41.5 dB PSNR
      against the CPU reference.
  - The hole is named in `tests/AGENTS.md` and `tests/install-matrix.py`
    (§3). The same edit corrects install-matrix.py's two sentences that
    claimed RDP steps in verify.sh, which do not exist.
