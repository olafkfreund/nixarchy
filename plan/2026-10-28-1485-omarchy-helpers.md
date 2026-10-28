---
status: approved
issue: 1485
spec: spec/2026-10-28-1485-omarchy-helpers.md
coders:
  1: codex   # two new package files from a measured template; no build needed to write them
  2: agy     # wiring across flake.nix, pkgs/omarchy, modules/apps.nix, tests/session.nix
  3: codex   # the speed test probe in tests/session.nix
  6: agy     # the edge carry: one substitution and the screensaver probe
reviewers:
  - codex    # owner's request (2026-10-28): independent read of the plan and each diff
  - agy
---

# Plan: package Omarchy's speed test client and native screensaver

## Approved decisions, carried over

- **Both packages on `main`** (intent decision 1, option b).
  `pkgs/apps/omarchy-speedtest.nix` and `pkgs/apps/omarchy-screensaver.nix`
  follow `pkgs/apps/ttfx.nix`'s shape, including `meta` and
  `passthru.updateScript` with `nix-update --flake <attr>`.
- **Measured inputs.** These were trial-built on 2026-10-28; both build.
  - Speed test: `buildGo127Module`, omacom/omarchy-speedtest tag `v0.2.1`,
    hash `sha256-q3KJ+FS2xuTNzgRal3rfhXot0aFUkD01+PZtq0sq+YQ=`,
    `vendorHash = null`. It produces `bin/omarchy-speedtest`.
  - Screensaver: `rustPlatform.buildRustPackage`, omacom/omarchy-screensaver
    tag `v1.3.1`, hash
    `sha256-9uvcYUXPExFEUZq2VdvSZz6n2foqiPqyD9CMphgBCTw=`, `cargoHash =
    "sha256-GnXuI+ceJpNz9npfLE9KpoQHU7MgYD9SnUKgNwfmTgM="`.
    - Native input `pkg-config` and `makeWrapper`; build inputs
      `libxkbcommon` and `wayland`.
    - `postFixup` wraps `bin/omarchy-launch-screensaver` with
      `--prefix PATH : ${lib.makeBinPath [ fontconfig ]}`.
- **The speed test path is substituted**, not set through
  `OMARCHY_SPEEDTEST_BINARY`. Upstream's `${OMARCHY_SPEEDTEST_BINARY:-…}`
  override stays.
- **Remove #1480's dimmed row and the `/usr` exception.** No new exception
  for either helper.
- **No option** (intent decision 2). Mode A unchanged, and no coexistence
  fixture.
- **The screensaver launcher's `--replace-fail` is an edge carry** on
  `edge-candidate`, never pushed to `edge` directly.
- **Team.** Codex and agy implement the steps named in `coders:`. Both
  review this plan and each PR's diff. Neither can build, so every build,
  check and §1 proof is run by the session (Claude) after each step.
- **Merging.** PRs are admin-merged once the local tiers pass, when the
  owner's permissions allow it; otherwise the owner runs the command. Then
  watch `main`'s CI and fix what it finds.

## Steps

1. **New `pkgs/apps/omarchy-speedtest.nix` and
   `pkgs/apps/omarchy-screensaver.nix`** (codex).
   - Use exactly the inputs above, in `ttfx.nix`'s structure.
   - Write a `meta` block for each: MIT, `lib.platforms.linux`, and
     `mainProgram` `omarchy-speedtest` or `omarchy-launch-screensaver`.
   - Give each an update script named `update-<pname>`.
   - Add a one-line comment on the screensaver wrapper: the font lookup's
     `/usr/share` path cannot hit on NixOS, so `fc-match` is the one that
     must be on PATH.
   - The screensaver file's argument set must name `fontconfig` and
     `makeWrapper` as well as `pkg-config`, `libxkbcommon` and `wayland`.

   **Verify (session):**
   - `git add` the new files first: a flake cannot see untracked files
     (§5), and `git diff --stat` does not list them.
   - Then `nix fmt`, and check `git diff --cached --stat` shows two small
     files (§5: a hook may nixpkgs-fmt them).

   **Traps:** `buildGo127Module`, not `buildGoModule`; this nixpkgs' `go` is
   1.26.10.

2. **Wiring** (agy).
   - **`flake.nix:763`**: add
     `omarchy-speedtest = final.callPackage ./pkgs/apps/omarchy-speedtest.nix { };`
     and the same for `omarchy-screensaver`, beside `ttfx`.
   - **`flake.nix:859`**: the line becomes `inherit (final.nixarchy-apps)
     ttfx omasnap omarchy-speedtest omarchy-screensaver;`, as the spec says.
   - **`flake.nix:1208`**: add both names to the list that re-exports
     `ttfx`, so `packages.x86_64-linux.<name>` exists for local builds.
   - **`pkgs/omarchy/default.nix:117`**: add `omarchy-speedtest,` and
     `omarchy-screensaver,` to the arguments.
   - **The runtime list at `:338-348`**: add `omarchy-screensaver` beside
     `ttfx`, with a one-line note saying quattro's launcher execs it (#1485).
     That puts it in every system closure, so every system and session
     check on `main` builds it. A `packages` entry alone is built by no
     workflow (§4); both reviewers found this. It also leaves no unused
     argument for deadnix, and edge's carry shrinks to the substitution.
   - **`pkgs/omarchy/default.nix`**: add a substitution beside the
     version-channel one (`:632`), with a one-line `#` note naming #1485.
     It runs `substituteInPlace
     $out/share/omarchy/bin/omarchy-network-speedtest` with
     `--replace-fail '/usr/lib/omarchy/speedtest'
     '${omarchy-speedtest}/bin/omarchy-speedtest'`.
   - **`modules/apps.nix:912-916`**: delete the
     `"trigger.tests.network-speedtest"` block.
   - **`tests/session.nix:1890-1894`**: delete the three comment lines and
     `"omarchy-network-speedtest"`. Restore `"omarchy-kernel"]` as the
     list's last element.

   **Verify (session), package tier, gated by `vm-host-free.sh`:**
   - `nix build .#packages.x86_64-linux.{omarchy-speedtest,omarchy-screensaver}`;
   - `nix build .#packages.x86_64-linux.omarchy`;
   - then `grep -c /usr/lib/omarchy/speedtest
     result/share/omarchy/bin/omarchy-network-speedtest || true` prints
     `0` (`grep -c` exits 1 on no match, so read the count, not the
     status), and the store path it names exists.

   **Traps:**
   - `find` does not follow `result` (§5); use the full path or `find -L`.
   - Run `nix fmt`, then check `git diff --stat`.

3. **The speed test probe in `tests/session.nix`** (codex).
   - Put it next to the `/usr` scan block, as a separate `with
     subtest("speed test reaches its client (#1485)")` block.
   - **Positive half**, so an upstream rewording cannot turn it into a
     no-op:
     - read the installed script with `machine.succeed("cat $(readlink -f
       /run/current-system/sw/bin/omarchy-network-speedtest)")`;
     - pull the client path out of its
       `client=${OMARCHY_SPEEDTEST_BINARY:-<path>}` line with a Python
       regex, and fail if the regex matches nothing;
     - `machine.succeed(f"test -x {path}")`.
   - **Run half:** `machine.execute(as_user("timeout 20
     omarchy-network-speedtest down 2>&1; echo rc=$?"))`.
     - **`2>&1` is required.** `machine.execute` returns stdout only, and
       the missing-client message goes to stderr. Without it, the probe is
       green when the client is missing (agy's finding).
     - Assert `speed test client is missing` is absent from the output.
     - Assert an `rc=` line is present and its value is neither 126 nor
       127.
     - 124 (the timeout) is accepted: it means a real client ran and waited
       on a network the VM does not have.
   - `as_user` wraps its argument in single quotes, so the command must
     contain none.
   - Capture into a variable and match in Python. No `| grep -q`
     (`checks.grep-q-pipefail`).

   **Verify (session):**
   - `nix eval --raw .#checks.x86_64-linux.session.drvPath` evaluates;
   - `checks.grep-q-pipefail` passes.

   The VM run itself is CI's (§6).

4. **Cheap tier and the §1 setup** (session).
   - Run each of these one at a time under the flock: `nix fmt -- --ci`,
     statix, deadnix, then the checks `bin-ledger`, `patched-files`,
     `menu-actions`, `menu-verbs`, `menu-guards`, `grep-q-pipefail` and
     `options-shards`,
     then `readme-counts.sh --check` with `OMARCHY_TREE` set.
   - If `bin-ledger` wants a row for `omarchy-network-speedtest`, add one in
     its file's shape, and record that here as a deviation.
   - §1 for the probe:
     - **Red:** in a scratch worktree (`git worktree add --detach`), remove
       the step 2 substitution. `git diff` must show it gone, and the built
       script must still contain `/usr/lib/omarchy/speedtest`. CI's session
       run on a throwaway draft PR from that tree must fail on the probe's
       assertion. Then close that PR.
     - **Green:** this PR's own CI run.

     Both reviewers flagged the earlier option to skip this red run as a
     §1 violation, and it is removed. To save wall time, open the red draft
     PR at the same moment as the real one, so the two CI runs overlap
     rather than queue.

5. **Reviews, then PR to `main`** (session; codex and agy review).
   - Run `second-opinion` with Codex and agy on `git diff origin/main`.
     Answer each finding in the PR, fixing the real ones before merge.
   - Commit with a full-sentence subject (§8).
   - Open the PR with the template. Its body links intent, spec and plan;
     says which steps Codex and agy wrote; and pastes the §1 evidence.
     `Closes #1481` and `Refs #1485`, each keyword written in full (§8).
   - Admin-merge, or hand the owner the command. Then watch `main`'s
     `build` and `install check`.

6. **The edge carry** (agy), on a branch from `origin/edge-candidate`, or
   from `origin/edge` if no candidate is open.
   - The package and the argument are already there from step 2.
   - Add `substituteInPlace $out/share/omarchy/bin/omarchy-launch-screensaver
     --replace-fail 'exec /usr/lib/omarchy-screensaver/omarchy-screensaver
     "$@"' 'exec ${omarchy-screensaver}/lib/omarchy-screensaver/omarchy-screensaver
     "$@"'` (the binary's path since step 5's review).
   - Add a session probe beside step 3's, using the shape the polkit probe
     already uses (`tests/session.nix:586-590`). `wait_until_succeeds`
     polls an exit status, not output. So each poll writes `hyprctl layers
     -j` to a file, then greps the file, which `grep-q-pipefail` allows,
     unlike a pipe.
     - **Precondition:** the namespace is absent before launch, so a stale
       layer cannot satisfy the probe.
     - **Launch** through the compositor, as the shell-restart probe at
       `:619-640` does with `hyprctl dispatch`, so the program inherits the
       session's Wayland environment. Background it with stdio closed
       (`</dev/null >/dev/null 2>&1`), or `machine.execute` blocks until it
       exits (agy's finding).
     - **Wait** for the namespace to be present (timeout 30), then
       `machine.send_key("esc")`, then wait for it to be absent (timeout
       15).
     - Hold the namespace string in one Python variable.
   - Run `checks.bin-ledger` on the carry branch, and add a row for
     `omarchy-launch-screensaver` if it asks, as step 4 does for the speed
     test.

   **Verify (session):**
   - package tier `nix build .#packages.x86_64-linux.omarchy`;
   - `grep -c /usr/lib/omarchy-screensaver` on the built launcher prints
     `0`;
   - the session check evaluates.

   **§1:** run 40677049412 proves only the `/usr` scan, not this probe
   (both reviewers). For the probe itself:
   - **Red:** a throwaway carry that substitutes a path which passes the
     scan but runs nothing, `${omarchy-screensaver}/bin/does-not-exist`.
     Its edge verify must fail on the layer probe, not on the scan.
   - **Green:** the real carry's verify.
   - Both runs overlap.

   Codex and agy review the diff. The PR goes to `edge-candidate`, or to
   `edge` if that is how the latest edge carries landed: check
   `git log origin/edge --merges -5` first and follow it. Then dispatch
   `omarchy-edge.yml` and confirm it promotes, which closes #1475.

7. **Close out** (session).
   - `main` and edge are green.
   - #1481, #1485 and #1475 are closed: check that each actually closed
     (§8).
   - TaskStop every agent, and remove the scratch worktrees.

## Tests

| command | expected |
|---|---|
| `nix build .#packages.x86_64-linux.omarchy-speedtest` | `bin/omarchy-speedtest` |
| `nix build .#packages.x86_64-linux.omarchy-screensaver` | `bin/omarchy-launch-screensaver`, wrapped |
| `grep -c /usr/lib/omarchy/speedtest …/bin/omarchy-network-speedtest` | `0` |
| cheap tier (step 4) | all exit 0 |
| CI `session` on `main` | the speed test probe passes; the `/usr` scan passes with no speed test exception |
| edge `verify` | `session` passes, with the screensaver probe and no screensaver exception |

## Rollback

`main`: revert the PR. The row returns to dimmed only if #1480's lines are
restored too, so revert the whole PR, not the substitution alone. Edge: revert
the carry on `edge-candidate`, and edge then goes red on the `/usr` scan
again, as before. That is safe, because edge stays on its last good pin.

## Deviations

- **Step 4:** `checks.bin-ledger` reported `omarchy-network-speedtest:
  shipped as \`patch\` and has no row`, the case step 4 provides for. The
  row is added in `data/bin-ledger.nix`, after `omarchy-mise-unshadow`.

- **Step 5, the PR diff review** (Codex gpt-6-sol P1, and agy #1,
  independently): the screensaver package's `bin/omarchy-launch-screensaver`
  collides with the Omarchy package's script of the same name in any
  profile that holds both. Standalone Home Manager adds the runtime list
  (`modules/home.nix:1074`), so `buildEnv` refuses. A probe `buildEnv`
  reproduced it.
  - Fix: install the binary at Arch's own path,
    `$out/lib/omarchy-screensaver/omarchy-screensaver`, with nothing in
    `bin/`.
  - The edge carry (step 6) therefore substitutes `exec
    ${omarchy-screensaver}/lib/omarchy-screensaver/omarchy-screensaver "$@"`.
  - §2: the new `checks.runtime-profile` builds that profile with
    collisions refused. It is green with the fix, and red (`conflicting
    subpath`) with the binary moved back to `bin/`.
- **Step 5** (agy #2): the probe also requires the client to be a store
  path, and runs a negative control with `OMARCHY_SPEEDTEST_BINARY=/nonexistent`.
  That proves the missing-client message it refuses is still upstream's
  wording.
- **Step 8, CI** (run 40687585459): `omarchy-speedtest`'s upstream
  `go test` suite flaked on a hosted runner. In
  `TestAWorkerThatEndsAfterTheWindowKeepsTheWindowsCount`, the counted
  bytes were off by about 1% from the TCP window. Almost every test there
  times real TCP over localhost, so the package sets `doCheck = false`,
  and the session probe stays the runtime evidence.
- **Step 8, CI** (red run 40687585459, `omarchy` job):
  `checks.review-pins` requires every `pkgs/apps` package with an
  `updateScript` to be in `pkgs/review.sh`'s pin table, and it holds a
  hand-written expected list. Both packages are now in both places. Step
  4's cheap tier had not listed `review-pins`; it passes locally now.
- **Refuted** (agy #3): nixos-26.05 has `buildGo127Module`, and
  `checks.stable-eval` evaluates on this branch.

## Review findings applied (Codex gpt-6-sol and agy, model not reported, 2026-10-28)

Both reviews reached the same conclusion: as first written, both probes could stay green with the thing broken. Verified against `tests/session.nix` and the driver, then fixed above:

- the speed test probe lacked `2>&1`, and `machine.execute` returns stdout only (agy);
- `wait_until_succeeds` polls an exit status, not output (both);
- a backgrounded launch with stdio open blocks `execute` (agy);
- both §1 red proofs were the wrong check, or skippable (both);
- a `packages` entry is built by no workflow (agy, §4);
- `grep -c` exits 1 on no match, and untracked files are invisible to a flake and to `git diff` (Codex, §5);
- missing `fontconfig` argument, `patched-files`, and the edge `bin-ledger` row (both).
