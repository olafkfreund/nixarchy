---
status: approved
issue: 1485
intent: intent/2026-10-28-1485-omarchy-helpers.md
---

# Spec: package Omarchy's speed test client and native screensaver

## Design

Decision (b) from the intent: both packages on `main`. Only the screensaver's
launcher substitution and its probe are an edge carry.

### Two packages, in the `ttfx` shape

Both were trial-built on 2026-10-28 against this flake's nixpkgs, and both
build. The hashes below are the measured ones.

- **`pkgs/apps/omarchy-speedtest.nix`**: `buildGo127Module`, because go.mod
  says `go 1.27.0` and this nixpkgs' default `go` is 1.26.10.
  - Source: `fetchFromGitHub` omacom/omarchy-speedtest, tag `v0.2.1`, hash
    `sha256-q3KJ+FS2xuTNzgRal3rfhXot0aFUkD01+PZtq0sq+YQ=`.
  - `vendorHash = null`: the module has no dependencies and no go.sum.
  - It produces `bin/omarchy-speedtest`.
- **`pkgs/apps/omarchy-screensaver.nix`**: `rustPlatform.buildRustPackage`.
  - Source: omacom/omarchy-screensaver, tag `v1.3.1`, hash
    `sha256-9uvcYUXPExFEUZq2VdvSZz6n2foqiPqyD9CMphgBCTw=`.
  - `cargoHash = "sha256-GnXuI+ceJpNz9npfLE9KpoQHU7MgYD9SnUKgNwfmTgM="`. The
    vendor step fetches its `ttfx` git dependency (tag v0.5.1) itself.
  - `pkg-config` is a native input; `libxkbcommon` and `wayland` are build
    inputs.
  - It produces `bin/omarchy-launch-screensaver`, the crate's own name.
  - It is wrapped with `fontconfig` on `PATH`. The font lookup tries
    `/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf`, then
    `fc-match`, and on NixOS only the fallback can succeed, so the wrapper
    makes it independent of the caller's PATH.
  - The other commands it runs (`omarchy-toggle-enabled`, `omarchy-shell`,
    `timeout`, `walker`) are already on the session PATH that runs the
    launcher.
- Each package carries `meta` (MIT, linux, `mainProgram`) and an
  `updateScript` calling `nix-update --flake <attr>`, both exactly as
  `pkgs/apps/ttfx.nix` has them.

### Wiring

- **`flake.nix`**: `final.callPackage` entries beside `ttfx` (`flake.nix:763`),
  and both added to the `inherit (final.nixarchy-apps) ttfx omasnap;` line
  (`:859`), so `pkgs/omarchy/default.nix` receives them as arguments.
- **`pkgs/omarchy/default.nix`, on `main`**: add `omarchy-speedtest` as an
  argument, and a `substituteInPlace` on `bin/omarchy-network-speedtest`.
  `--replace-fail` turns `/usr/lib/omarchy/speedtest` into
  `${omarchy-speedtest}/bin/omarchy-speedtest`. The
  `${OMARCHY_SPEEDTEST_BINARY:-…}` override stays upstream's.
- **`modules/apps.nix`**: delete #1480's dimmed
  `trigger.tests.network-speedtest` row, so upstream's row is used as
  shipped.
- **`tests/session.nix`**: delete `"omarchy-network-speedtest"` and its
  comment from the `/usr` exceptions.
- **The edge carry, on `edge-candidate`**: add `omarchy-screensaver` as an
  argument, and `--replace-fail` turning `exec
  /usr/lib/omarchy-screensaver/omarchy-screensaver "$@"` into `exec
  ${omarchy-screensaver}/bin/omarchy-launch-screensaver "$@"` in
  `bin/omarchy-launch-screensaver`. `main` never sees this line until an
  Omarchy release ships it, and then it reaches `main` through the edge
  merge, as #1480's carries did.

### Probes (§2, at the highest layer that can see each)

- **Speed test, in `checks.session` on `main`.** The VM has no network, so
  the client cannot measure anything, but it can be reached. Run
  `omarchy-network-speedtest down` under a 20 s `timeout`, and assert that:
  - stderr does not contain `speed test client is missing`, which is the
    script's message when the binary is absent;
  - the exit status is neither 127 nor 126.
  That proves the script exec'd a real client, which then failed on the
  network.
- **Screensaver, in `checks.session` on edge.** It needs a compositor with
  layer-shell, which the session VM has. Run `omarchy-launch-screensaver
  force` in the background, then wait until `hyprctl layers -j` lists the
  namespace `org.omarchy.screensaver`, which upstream's README names as how
  Omarchy's tools find it. Then send a key and wait for the namespace to go.
  It draws with fontdue into shared memory, not the GPU, so llvmpipe is no
  obstacle.

### Ledgers

`data/bin-ledger.nix` lists commands that behave differently here. If its
check classifies a patched `/usr` reference as a difference, it gains a row
for `omarchy-network-speedtest` (and, on edge, `omarchy-launch-screensaver`).
The plan runs `checks.bin-ledger` to decide. Neither file is under `etc/`, so
`etc-overlay` is untouched.

### Coexistence (§14)

No option is added and no default changes. Both are runtime dependencies of
the Omarchy package, and Mode A gains nothing. No fixture.

### Team (owner, 2026-10-28)

Codex and agy implement plan steps through `handoff`, and both review the plan
and each diff through `second-opinion`. Every build, check and §1 proof runs in
this session. PRs are admin-merged once the local tiers pass, when the owner's
permissions allow it; otherwise the owner runs the merge.

## Alternatives rejected

- **A `/usr` exception for the screensaver**, the speed test's #1480 route.
  The screensaver starts on idle with no row to dim, so the exception would
  ship one that never appears.
- **Flake inputs, the gliff way.** Neither repo ships a flake, and the ttfx
  shape gives a one-command bump with `nix-update` recomputing the vendor
  hashes.
- **Prebuilt release binaries** (goreleaser publishes some). The repo builds
  from source, and fetching a prebuilt binary would pin a third party's
  build environment.
- **Setting `OMARCHY_SPEEDTEST_BINARY`** in the session environment, instead
  of substituting the path. Panels and the menu run from the shell's own
  environment, and a variable is one more thing a user's shell config can
  shadow. A substituted path cannot be shadowed.
- **The screensaver package only on edge** (option a). Rejected by
  decision 1.

## Risks

- **Toolchains.** A nixpkgs bump that drops `buildGo127Module`, or a Rust
  release that breaks edition 2024, fails `packages.omarchy`. That is loud,
  on the bump's own PR.
- **An unused derivation can rot.** The screensaver on `main` is referenced
  by nothing until edge's carry lands. The plan has CI build it anyway,
  through the generated check list or the cache allowlist, so a break is red
  on `main`, not discovered at the next release.
- **Probe flakiness.** The screensaver probe waits on a layer appearing.
  It uses `wait_until_succeeds` with a bound, and keeps the namespace string
  in one place.
- **Edge promotion.** The carry lands through `edge-candidate`. Edge's
  `verify` then needs a green `session` with the probe, plus `main`'s fixes
  from its merge. That run is what closes #1475.

## Verification

- **Packages:** `nix build .#packages.x86_64-linux.omarchy-speedtest` and
  `.#packages.x86_64-linux.omarchy-screensaver`, exposed the way `ttfx` is
  (package tier, behind `vm-host-free.sh`).
- **Wiring:** `nix build .#packages.x86_64-linux.omarchy`, then grep the
  built `omarchy-network-speedtest` for the store path and for no
  `/usr/lib/omarchy/speedtest`.
- **Cheap tier:** `nix fmt -- --ci`, statix, deadnix, `bin-ledger`,
  `menu-actions`, `menu-verbs`, `grep-q-pipefail`, `readme-counts.sh --check`.
- **§1, speed test probe:** in CI, red with the substitution removed (the
  script prints `client is missing`), green with it.
- **§1, screensaver probe:** on edge, red with the carry removed, which the
  `/usr` scan already shows (run 40677049412), and green with it.
- **Reviews:** Codex and agy on the plan and on each PR diff, with findings
  answered in the PR.
- **After merge:** `main` green. The next edge run promotes, with
  `verify` green, closing #1475, #1481 and #1485.
