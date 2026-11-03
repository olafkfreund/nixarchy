---
status: approved
issue: 1577
spec: spec/2026-11-03-1577-omarchy-local-ai.md
reviewers:
  - codex   # the owner asked for codex and agy on this task; read-only review of the diff
  - agy
---

# Plan: Omarchy's local model runner on nixarchy, on AMD and NVIDIA

Implementer: the `coder` agent for steps 1–6 and 8–9. The session runs every
build and check, keeps steps 7 and 10, and commits each step by path.

## Decisions carried from the approved spec

1. **Package.** `pkgs/apps/omarchy-local-ai.nix` packages
   [omacom/omarchy-local-ai](https://github.com/omacom/omarchy-local-ai) at
   tag `v0.4.0`, exported as `nixarchy-apps.omarchy-local-ai`.
   - The tree goes to `$out/share/omarchy-local-ai`, without `bench/` and
     `tools/`.
   - `$out/bin/omarchy-local-ai` is a symlink to upstream's entry script, the
     `omarchy-local-ai` file at the repo root. Its shebang
     (`#!/usr/bin/python3`) is patched to nixpkgs' `python3`.
   - No PATH wrapping: `podman` and `systemctl` must be the system's own.
   - `checkPhase` runs `tests/engine-test.sh` and `omarchy-local-ai validate`.
2. **System option**, rootless Podman with the GPU reachable, default off
   (Mode A). It turns on:
   - `virtualisation.podman.enable = lib.mkDefault true`;
   - `users.users.<user>.extraGroups = [ "render" "video" ]`, always, for
     both vendors;
   - memlock raised for the one user, both ways:
     `security.pam.loginLimits` and `systemd.services."user@".serviceConfig.LimitMEMLOCK
     = "infinity"`. A VM check decides whether both are needed;
   - `hardware.nvidia-container-toolkit.enable = lib.mkDefault true`, exactly
     when nixpkgs' own assertion would hold: `"nvidia"` in
     `services.xserver.videoDrivers`, or `hardware.nvidia.datacenter.enable`;
   - the engine package, `lib.lowPrio`.
   - **No** GPU override enum, **no** AMD detection, **no** host ROCm or
     CUDA.
3. **Upstream's install-on-first-use.** `bin/omarchy-agent-local`'s
   `omarchy-pkg-add` block is replaced with preflight checks that run before
   any download:
   - `podman` is on PATH;
   - the user manager's `DefaultLimitMEMLOCK` is `infinity`;
   - on NVIDIA (`/proc/driver/nvidia` exists), `/var/run/cdi` has
     `nvidia.com/gpu`.

   Each failure names the option and exits 1.
4. **The ledger row** for `omarchy-local-ai` goes from `skip` to `nix`, on
   edge only, because main's tag does not list the package.
5. **Out of scope.** Engine changes for x86_64 NVIDIA detection, and recipes
   for discrete cards: those belong upstream, and nothing is filed without
   the owner. Ollama (`programs.nixarchy.localAi`) stays the working path for
   models on razer's 8 GB card.

### One change from the spec, for approval here

The spec named the option `programs.nixarchy.agentLocal.enable`. The repo's
convention for a service that bundles several options is
`programs.nixarchy.services.<id>.enable`. That convention comes from
`modules/services/default.nix` and `data/services.nix`: a `kind = "bundled"`
entry, the generated template and the menu all read that path. So the plan
uses **`programs.nixarchy.services.agent-local.enable`**, in
`modules/services/agent-local.nix`, with a `data/services.nix` entry. What it
does is unchanged.

## Steps

1. **The package.** Files: `pkgs/apps/omarchy-local-ai.nix` (new), the
   `nixarchy-apps` set and `packages` export in `flake.nix`, `pkgs/review.sh`'s
   pin list, `tests/review-pins.nix`'s `expected`, and a `data/apps.nix` row
   (`ours = true; preinstall = true; arch = "omarchy-local-ai"`).
   - **Verify:**
     - `nix build .#omarchy-local-ai -L`; the checkPhase runs the engine
       tests;
     - `result/bin/omarchy-local-ai list` with `HOME=$(mktemp -d)` prints
       the three recipes;
     - `checks.review-pins` passes.
   - **Red proof:** in a scratch copy, drop `recipes/` from the install;
     `validate` must fail. Capture the output.
   - **Traps:**
     - `git add` the new file before any `nix` command (§5);
     - `nix fmt` after the edit, then read `git diff --stat` (the hook rewrites
       `.nix` files, §5);
     - `review-pins` wants the name in both lists;
     - `passthru.updateScript` is nix-update, like `pkgs/apps/hype.nix`.
2. **The module.** Files: `modules/services/agent-local.nix` (new), its import
   in `modules/services/default.nix`, and a `data/services.nix` entry
   (`kind = "bundled"`, a `note` saying that models need a large GPU and that
   Ollama is the path for small cards).
   - **Content:** decision 2. The user is `config.programs.nixarchy.user`,
     the way `boxes.nix` finds it. Add a `warnings` entry when the machine
     uses `nvidia` but `hardware.nvidia-container-toolkit.enable` ended up
     false: the user turned it off, so NVIDIA models cannot start.
   - **Verify:** `nix eval` of `config.virtualisation.podman.enable`, the
     user's `extraGroups`, `security.pam.loginLimits` and
     `hardware.nvidia-container-toolkit.enable` on the reference config, with
     the option on and off.
   - **Traps:**
     - lists and attrsets are plain assignments, scalars are `mkDefault`
       (`modules/services/default.nix`);
     - the package is `lib.lowPrio` (`checks.user-packages-win`, #1167);
     - no `mkForce`.
3. **`tests/options.nix` cases**, both states:
   - off: none of it;
   - on with `amdgpu`: groups and limits, no CDI generator;
   - on with `nvidia` in `videoDrivers`: groups, limits and the CDI
     generator;
   - on with `hardware.nvidia.datacenter.enable`: the CDI generator;
   - user sets `hardware.nvidia-container-toolkit.enable = false`: theirs
     wins, and the warning is emitted.

   Place each case in the right shard so `checks.options-shards` stays green.
   - **Verify:** the cases' shard check.
   - **Red proof:** remove one setting at a time; the case names it.
   - **Traps:**
     - a heredoc inside a `''` string reindents the whole file, so use
       `printf` (§5);
     - running the shard is a VM-tier local build (§6): only with CI idle,
       otherwise leave it to CI.
4. **Coexistence fixtures** in `tests/coexistence/fixtures.nix`, asserted in
   `tests/coexistence/default.nix`:
   - `podman-own-config`: the user sets `virtualisation.podman` with
     `dockerCompat = true`. It evaluates, and their settings stand;
   - `nvidia-ctk-own`: on NVIDIA, the user turns the toolkit off. Theirs
     wins.
   - **Verify:** `checks.coexistence`.
   - **Red proof:** make the module force the value, and watch it fail.
5. **Memlock, measured in a VM.** A new `tests/agent-local-memlock.nix`, in
   `uniformChecks`. A guest with the option on and a normal user asserts:
   - the user manager's `systemctl --user show -P DefaultLimitMEMLOCK` is
     `infinity`;
   - `ulimit -Hl` in a login shell (`su - user -c`) is `unlimited`.
   - **Red proof:** the guest without the option is red. Then remove
     `loginLimits` alone, and `user@`'s `LimitMEMLOCK` alone; record which
     red each removal gives.
   - **If one setting is redundant, delete it** and update decision 2 in this
     plan in the same commit.
   - **Traps:** a VM check runs only with CI idle (§6). Evaluate the
     `drvPath` once and build `'<drv>^*'` (§5's stale-evaluation trap).
6. **The wrapper's preflight.** Edit `pkgs/omarchy/default.nix`: when
   `bin/omarchy-agent-local` exists, `substituteInPlace --replace-fail` its
   `omarchy-pkg-add` block with decision 3's checks. The file exists only on
   quattro, so the `if [ -e … ]` keeps main's tag building, and
   `--replace-fail` still fails loudly if upstream changes the block.
   - **Verify:** on an edge tree, the built `omarchy-agent-local` contains
     the checks and no `omarchy-pkg-add`.
   - **Red proof:** change one word in the matched block; the build fails.
   - **Traps:**
     - no `| grep -q` anywhere: run `checks.grep-q-pipefail` before pushing;
     - `\$` is a literal backslash in a `''` string (§5);
     - this is a package-tier build, so check the §6 gates first.
7. **Edge carry** (session): after the PR merges, change the
   `omarchy-local-ai` ledger row on `edge-candidate` to
   `nix = "nixarchy-apps.omarchy-local-ai"`, push, and dispatch with
   `from_candidate=true`.
   - **Verify:** the edge run's `omarchy-package-ledger` is green, and so is
     verify.
8. **`pkgs/verify.sh` steps** for real hardware, run by the owner:
   - p620: `podman run --rm --device /dev/kfd --device /dev/dri --group-add
     keep-groups <rocm image> rocminfo` lists `gfx1100`;
   - razer: `podman run --rm --read-only --cap-drop all --security-opt
     no-new-privileges --ulimit memlock=-1:-1 --device nvidia.com/gpu=all
     <cuda base image> sh -c 'nvidia-smi && ls /dev/nvidia-uvm'`.

   Both images are pinned by digest.
   - **Verify:** `bash -n` and `shellcheck` on `verify.sh`.
9. **Docs:**
   - a section in `docs/manual/` beside the Ollama page, saying when to use
     which (catalog sizes, and Ollama for small cards);
   - `.github/scripts/readme-counts.sh --fix`, with `OMARCHY_TREE` set to the
     store path;
   - a `modules/AGENTS.md` line on why the option is not under `localAi`.
10. **Review** (session): the `reviewers:` above, codex then agy, each given
    this plan and `git diff origin/main`. Every claim is checked before
    anything changes, and the result goes in the PR.

## Tests

- `nix build .#omarchy-local-ai`.
- `checks.review-pins`, `user-packages-win`, `grep-q-pipefail`,
  `coexistence`, `options-shards`: the cheap tier, run locally under the
  lock.
- `checks.options-*`, `checks.agent-local-memlock`: the VM tier, local only
  with CI idle, otherwise CI.
- Edge: `omarchy-package-ledger` and the edge Omarchy package build, both
  after step 7.

## Rollback

Revert the PR. The option is off by default, so no machine changes unless it
turned it on. The edge ledger row goes back to `skip` with its issue
reference.

## Deviations

- **Step 1:** shebangs are patched in `postPatch`, not after install.
  `engine-test.sh` runs the source tree's entry script through a symlink, and
  `#!/usr/bin/python3` does not exist in the sandbox. `tests/` is dropped from
  the install with `bench/` and `tools/`, and the install check sets
  `PYTHONDONTWRITEBYTECODE`, so no `__pycache__` lands in `$out`.
  `tests/options.nix`'s hand-kept `omarchyAppPnames` gains
  `omarchy-local-ai`, so the `omarchyApps` case covers it.
- **Step 2:**
  - the module takes `inputs`, as `microvm.nix` does, because the engine comes
    from the overlay: `(pkgs.extend inputs.self.overlays.default).nixarchy-apps.omarchy-local-ai`,
    the way `modules/nixos.nix` reaches `owe`;
  - it asserts that `programs.nixarchy.user` is set, as `syncthing.nix`
    does. The groups and limits are that user's;
  - `docs/manual/configuration.md` gains the option's row in its services
    table ("All eleven entries"), here rather than in step 9, because
    `checks.docs-lists` fails without it.
