---
status: draft
issue: 1646
intent: intent/2026-11-07-1646-stock-iso-install.md
---

# Spec: Install from the stock NixOS ISO, with no image of our own

Two parts, landed as two pull requests. **Part A** removes the preflight
hazard and stands alone: it is small, and today `nix run …#install` from a
stock ISO can wipe a disk and then fail. **Part B** adds the stock-ISO VM
check and the manual section, after the owner's current queue is clear.

## Decisions (the intent's open questions, as approved)

1. **Do it, in order.** Part A first and on its own. Part B waits for the queue.
2. **The switch is "this machine has no substituter configured", not the
   marker.** That is the condition that actually separates `checks.install`:
   `tests/install.nix:188`, `tests/free-space.nix:194` and
   `tests/install-encrypted.nix:191` each set `substituters = mkForce [ ]`,
   because there is no network. A stock ISO, `iso-net` and
   `installer-refusal` all have one. Both sides are tested (Verification).
3. **No manual section before the check exists.** It lands with Part B.
4. **Rescue from a stock ISO is out of scope.** The manual section tells
   rescuers to use our image, or to add the `safe.directory` entry by hand
   (`installer/cd.nix:440-457`).
5. **Dropping `iso-net` is not decided here.** It gets its own issue, after
   Part B's numbers and #1649.

## Design

### Part A: the preflight runs wherever a network is expected

`installer/install.sh`:

- **New gate**, replacing `on_net_image` (`:2509`, and its two-line comment
  above it):

  ```bash
  # No substituter configured means the machine says it has no network
  # (checks.install and its siblings), so there is nothing to probe or ask.
  offline_by_design() {
    local subs
    subs=$(nix "${NIX_FLAGS[@]}" config show substituters 2>/dev/null) || return 1
    [ -z "${subs//[[:space:]]/}" ]
  }
  ```

  It fails closed: if `nix config show` fails, the preflight runs. `nix` is
  the installer's own runtime input (`flake.nix:978`), so the subcommand
  exists whatever the medium ships. Measured on nix 2.34:
  `nix --option substituters '' config show substituters` prints an empty
  line and exits 0. `NIX_CONFIG` counts too, which `install-iso-net`'s
  override relies on (`tests/install-iso-net.nix:138-140`).

- **`ask_network` (`:464-465`) and `preflight_build` (`:2573`):**
  `on_net_image || return 0` becomes `offline_by_design && return 0`. The
  comment at `:2536-2537` is reworded to name the substituter condition.

- **Our caches on every nix call that plans or builds.** Today only
  `nixos-install` passes them (`:2732-2733`); the preflight dry-run
  (`:2594`), `run_install`'s dry-run (`:2628`) and the toplevel build
  (`:2708`) pass only `SUBSTITUTE_FLAGS`. On `iso-net` the image's `nix.conf`
  hides this (`installer/cd.nix:419-425`). On a stock ISO the preflight would
  report most of the desktop as "will be built", and the build would compile
  it. So `SUBSTITUTE_FLAGS` (`:71`) gains
  `--option extra-substituters "$SUBSTITUTERS" --option extra-trusted-public-keys "$TRUSTED_KEYS"`,
  and the two now-duplicate options on `nixos-install` go. The comment above
  `:71` gains one line saying why. The intent said the build already passes
  them; it does not, and this corrects that.

- **Wording.** The refusal and store-space messages say "This image downloads
  the desktop" (`:481`, `:2502`, `:2580`) and "this image installs over the network"
  (`:474`). They become "this install", which is true on both media.
  `installer-refusal`'s asserted strings (`cannot reach https://nixarchy.cachix.org`,
  `network`, `disk has not been touched`) are unchanged.

Tests in Part A (details under Verification): `tests/installer-store-space.nix`
drives the new gate; `tests/installer-network.nix:109` greps the new line;
`tests/installer-refusal.nix:62` loses the marker, which turns that VM into a
stock-shaped machine (base NixOS, default `cache.nixos.org`, no marker).

The marker file stays in `installer/cd.nix:458` with the commit it was built
from. No installer code reads it after Part A; `checks.iso-source` and
`install-iso-net`'s `MARKER` step still assert it, and the iso-net decision
(5) owns removing it.

### Part B: the stock-ISO check and the manual

- **`tests/install-stock-iso.nix`**, shaped like `tests/install-iso-net.nix`
  (a stub cache node on the test vlan serving this build's closure, the same
  committed stub cert, a driving script on an answers disk). The installer VM
  boots the NixOS minimal ISO of one release, fetched by URL and hash; the
  plan names the release. One boot, two cases in order:
  1. **Dark cache.** `nixarchy.cachix.org` resolves nowhere. Fetch the
     install package from the stub by store path, run it with `--answers`.
     Assert a non-zero exit, the preflight's `cannot reach` line, and a bare
     target (`lsblk` and `blkid` as `installer-refusal` does).
  2. **Install.** The stub answers every cache name. Run again with the same
     answers and assert the install finished (`/mnt/etc/nixos/.git`, the ESP,
     the fallback EFI binary, as in `install-iso-net`). Print three numbers:
     seconds from the command to the installer's first log line, bytes served
     by the stub (its access log), and the peak of the live store's overlay
     (`df` sampled in the background).

  The `github:` flake fetch in the manual's command is not exercised: the VM
  has no internet. Everything after it is.

- **CI placement is a human's call** (CLAUDE.md §4, §11). Without an entry in
  `nightly_only` in `.github/scripts/generated-checks.sh:77`, the generated
  step would build this multi-hour VM on every pull request. Part B's PR
  proposes that one-word edit and a `nightly.yml` entry beside
  `install-iso-net`, and says so in its body.

- **`docs/manual/the-iso.md`** gains one section, "From a stock NixOS ISO":
  join the network (`nmtui`), the `sudo nix --extra-experimental-features …
  run github:olafkfreund/nixarchy#install` command and its `--answers` form,
  that it is the advanced path, what it lacks (branding, tty1 autostart, the
  newest kernel during install, `#try`, rescue), and the NixOS release and
  nixarchy revision `install-stock-iso` last passed with.

## Coexistence

None. Nothing here sets a NixOS option: Part A changes the installer script
on live media, and Part B adds a test and a manual section. The installed
system's closure is unchanged.

## Alternatives rejected

- **Ask stock-ISO users to `touch /etc/nixarchy-iso-net` first.** A manual
  step whose omission is the disk-wiping hazard.
- **A test-only variable such as `NIXARCHY_OFFLINE=1` in the seeded VMs.** A
  second marker that a stock ISO happens to lack, which the intent rules out.
  The empty substituter list is already stated by those VMs for their own
  reason.
- **Gate on `network_ready`.** A stock ISO whose network is down would skip
  the preflight, which is the hazard itself.
- **Gate on the plan (skip the probes when the dry-run fetches nothing).** A
  dark cache also produces a plan with nothing to fetch, because nix disables
  the cache and plans builds instead. Telling the two apart needs
  `PLAN_TRIVIA` to match every per-machine build `checks.install` plans,
  which is unmeasured.
- **A new VM check for the stock-shaped refusal, keeping `installer-refusal`
  as it is.** Once the gate ignores the marker, the marker in that node tests
  nothing. Dropping it costs no new install slot.

## Risks

- **The offline checks now name our caches on the build.** `checks.install`,
  `free-space` and `install-encrypted` will try `nixarchy.cachix.org` on the
  `nix build` too. `nixos-install` already does this in the same VMs and
  passes, and with no route the connection fails at once. Watch: the elapsed
  time in `/run/nixarchy-install/state.json` against the install job's
  previous runs.
- **Someone installing with an empty substituter list** skips the preflight,
  as every markerless install does today. That user has said "no network".
- **Part B is unmeasured**: how the stock ISO reaches a serial shell (its
  boot-menu serial entry, or `-kernel`/`-initrd` taken from the ISO), and
  whether its overlay holds the closure without the `--store /mnt` fallback.
  The ISO is about 1.3 GB, fetched once per store from `channels.nixos.org`
  and kept out of the cachix allowlist (it is not ours, and the budget is
  2.5 GB).
- **A real `iso-net` install changes only in its wording**: its `nix.conf`
  already lists both caches. `checks.install-iso-net` does change. Its driver
  overrides `substituters` with the local http stub alone
  (`tests/install-iso-net.nix:132-140`), so the https names, which resolve to
  the probe stub, reach its toplevel build for the first time. `nixos-install`
  already passes them in that same run, and the daemon disables them on the
  TLS failure (`:35-38`). Watch: that check's next nightly, its `FETCHED`
  step and its run time.

## Verification

Each new assertion with the break that must turn it red (CLAUDE.md §1). Prove
each break landed with `git diff` before reading the result.

Part A, cheap tier:

- `checks.installer-store-space`. The test sources `SUBSTITUTERS`,
  `TRUSTED_KEYS`, `SUBSTITUTE_FLAGS` and `offline_by_design` from
  `install.sh` rather than setting them (today it sets
  `SUBSTITUTE_FLAGS=()`, `tests/installer-store-space.nix:306`). Its `nix`
  stub answers `config show substituters` from `$SUBS` (or fails when
  `SUBS_FAIL=1`), and records the dry-run's arguments. Cases:
  - substituters present, no marker, cache dark → refuse. **Break:**
    `offline_by_design() { return 0; }` → proceeds → red.
  - substituters empty, network dead → proceed, and neither `curl` nor the
    dry-run was called. **Break:** `offline_by_design() { return 1; }` → refuses → red.
  - `nix config show` fails → the preflight runs (fails closed). **Break:**
    drop `|| return 1` → proceeds → red.
  - the dry-run's arguments contain `extra-substituters` with both cache
    URLs. **Break:** take them out of `SUBSTITUTE_FLAGS` → red.
  - every `nix … build` in `run_install` carries `"${SUBSTITUTE_FLAGS[@]}"`,
    asserted on the extracted function, so the toplevel build fetches from
    the caches the preflight planned with. **Break:** drop it from the
    toplevel build (`:2708`) → red.
  - the existing cases keep their meaning, with "net image" spelled as
    "substituters present".
- `checks.installer-network`: the grep at `:109` matches
  `offline_by_design && return 0` in `ask_network`. **Break:** delete that
  line → red.
- `installer-from-repo` and the store-space line-order assertion still find
  `preflight_build` before `format_disk`. Every `installer-*` check is built
  (tests/AGENTS.md: moving code in `install.sh` reddens checks that look
  unrelated), plus `grep-q-pipefail`, `nix fmt -- --ci`, statix and deadnix.

Part A, VM tier (the install job, `install-check.yml:514`):

- `checks.installer-refusal`, marker removed. **Break:** restore
  `on_net_image || return 0` in both functions → the install reaches
  `format_disk` → `after == "vdb"` fails with partitions listed. That red is
  the stock-ISO hazard reproduced on a disk.
- `checks.install`, `free-space`, `install-encrypted` stay green: the other
  side of the gate. **Break (once, locally, VM tier):**
  `offline_by_design() { return 1; }` → `checks.install` refuses with
  `cannot reach https://cache.nixos.org`.

Part B:

- `checks.install-stock-iso` case 1. **Break:** restore the old gate → the
  target is partitioned → red. Case 2 green, with its three numbers in the
  PR and in the manual section.
- The manual section names the release and revision the check printed.
