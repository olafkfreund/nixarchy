---
status: approved
issue: 1727
spec: spec/2026-11-09-1727-checks-follow-commit.md
coders:
  1: codex   # small, exact Nix edits in flake.nix where a wrong `inputs` changes what ships; needs no build
  2: codex   # two small edits (a substring and a case pattern, one table row); same agent's context
reviewers:
  - codex    # reads the diff natively; it caught D5's unsupported listing in the spec
  - agy      # given the diff inline; it caught the D6 wiring error and the reinstall-image split
---

# Plan: the installer's checks stop following the commit

Branch `fix/1727-checks-follow-commit`, worktree `/mnt/data/vmtest/wt-1727`.
Intent and spec are approved. This plan carries their decisions, so it can
be followed without them.

## Decisions carried from the spec

- **The guard** (`.github/scripts/commit-independent.sh`, #1644) evaluates
  every check that is not in `data/commit-bound-checks.nix`. It commits a
  tracked `.commit-probe` file two days later, evaluates again, and fails on
  any check whose output path moved.
- **The measured carriers:**
  - **Placeholder fields.** `installer/mkFlake.nix` reads `self.narHash` and
    `self.lastModified`, which the placeholder `self` (`flake.nix:907-911`)
    does not set. This moves `installer-input-validation`,
    `initrd-pin-guard`, `installer-wizard`, and part of the rest.
  - **`installer-early-exit`** reads the real `self` (`flake.nix:2326`).
  - **`reinstall-image`'s `launcher`** comes from `self.lib.mkUserIso`. It
    passes the real `inputs` to the ISO (`flake.nix:1773`), and
    `checkInputs.self` keeps the real `lib`.
  - **`stable-eval`** puts the stable toplevel's full `drvPath` into its
    environment (`tests/stable-eval.nix:54`). Its hash follows the tree,
    because `vm/configuration.nix:173` names `${inputs.self}`.
  - **`install-stock-iso`** carries the source tree itself, through
    `inputSources` (`tests/install-stock-iso.nix:15`).
- **D1.** `checkInputs.self` gains `lastModified = 0` (matching
  `lastModifiedDate = "19700101000000"`) and
  `narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="`, a
  well-formed SRI hash of 32 zero bytes.
- **D2.** `installer-early-exit` reads `inputs.self.packages…install`.
- **D3.** `mkUserIsoWith = inputs: { flake, host, ... }: …`.
  - `lib.mkUserIso = mkUserIsoWith inputs`, so the public function is
    unchanged.
  - `checkInputs.self.lib = self.lib // { mkUserIso = mkUserIsoWith checkInputs; }`.
- **D4 (owner, option a).** `install-stock-iso` is listed in
  `data/commit-bound-checks.nix` with the `inputSources` reason. Listing
  switches its `inputs` to `realInputs` (`flake.nix:2926`), so its drvPath
  changes once.
- **D5.** `stable-eval` keeps the toplevel's store name, not its hash, and
  its floor pattern follows.
- **D6.** Nothing here asserts that `narHash` or `lastModified` equals the
  real commit's, and the PR says so. `installer-lock` reads the real
  template directly and is unchanged.
- **Fixed, not listed (owner):** every other check above.

## Steps

### 1. `flake.nix`: D1, D2, D3 (coder: codex)

- **D1, `:907-911`.** After `lastModifiedDate = "19700101000000";`, add:

  ```nix
          lastModified = 0;
          # 32 zero bytes: a well-formed SRI hash that names no real tree.
          narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  ```

- **D2, `:2326`.**
  `renderedInstallScript = "${inputs.self.packages.${system}.install}/bin/nixarchy-install";`.
  Leave `:2332` (`self.nixosConfigurations.installer-vm…emptyDiskImages`)
  alone: it is an integer.
- **D3.**
  - Move the body of `lib.mkUserIso` (`:1756-1781`, including its comment
    block above, `:1740-1755`) into a `let` binding `mkUserIsoWith` beside
    `mkMicrovmWith` (`:887`). Give it an `inputs:` argument, so the
    `inherit inputs;` in its `specialArgs` (`:1773`) reads the argument.
  - In `lib`, write `mkUserIso = mkUserIsoWith inputs;`, beside
    `mkMicrovm = mkMicrovmWith inputs;` (`:1783`).
  - In `checkInputs.self` (`:908-958`), add
    `lib = self.lib // { mkUserIso = mkUserIsoWith checkInputs; };`.
  - The body's `lib.concatStringsSep` and `lib.attrNames` (`:1764-1769`)
    are the lexical nixpkgs `lib`, not `self.lib`, because the output
    attrset at `:1718` is not recursive. They stay as they are; do not
    rewrite them to `self.lib.*`, which has neither (Codex, agy).
    `nixpkgs` (`:1770`) and `./installer/cd.nix` (`:1776`) also resolve
    the same from the new position.
- **Not in this step:** builds, commits, other files. Codex's sandbox
  cannot reach the nix daemon.
- **Verify** (the lead):

  ```bash
  nix eval --raw .#lib.mkUserIso --apply 'f: builtins.typeOf f'   # lambda
  git diff --stat                                                  # flake.nix only
  ```

- **Traps:**
  - an editor hook may reformat with `nixpkgs-fmt`, so run `nix fmt` and
    read `git diff --stat` (§5);
  - `self` inside `checkInputs.self = self // { … }` is the outer real
    `self` (not `rec`), which is what the `lib` override needs.

### 2. `tests/stable-eval.nix` and `data/commit-bound-checks.nix`: D5, D4 (coder: codex)

- **`tests/stable-eval.nix:54`:**

  ```nix
  # The store name, not the hash: the hash follows the source tree through
  # the VM's activation script, which this check is not about (#1727).
  toplevel = builtins.substring 44 (-1) (
    builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath
  );
  ```

  Measured: on a real path this returns
  `nixos-system-nixarchy-26.05.20260910.d58a46e.drv`. It still forces the
  full evaluation.
- **`tests/stable-eval.nix:102-103`:** the floor refuses a name with a `/`
  or nothing after the prefix (Codex):

  ```bash
  case "$toplevel" in
    */*) ;;
    nixos-system-?*.drv) toplevel_ok=1 ;;
  esac
  ```

  - Written so that only the second branch passes. Keep the existing
    refusal block for every other case, as `[ "''${toplevel_ok:-}" = 1 ] ||
    { …refusal… }`, or as an equivalent `case` with `*/*` falling into the
    refusal.
  - The refusal text at `:105` changes from "derivation path" to
    "derivation name".
- **`data/commit-bound-checks.nix`:** add after `install-iso-net`:

  ```nix
  install-stock-iso = "tests/install-stock-iso.nix:15 collects inputSources, which starts with the source tree, into the cache it installs from offline";
  ```

- **Verify:** `git diff --stat` shows these two files.
- **Traps:**
  - inside a Nix `''` string, `${` must be `''${` (`:54` is outside one, so
    this applies only if the edit moves into a string);
  - no `| grep -q`.

### 3. Measure (lead)

1. **The guard on the six fixed checks**, under the codex-build lock (it is
   evaluation only):

   ```bash
   .github/scripts/commit-independent.sh initrd-pin-guard installer-early-exit installer-input-validation installer-wizard reinstall-image stable-eval
   ```

   It needs a clean, committed tree, so commit steps 1 and 2 first.
   Expected: `none moved`.
2. **What ships is unchanged** (spec verification 2). Both sides must see
   one source tree and differ only in `flake.nix` (Codex, agy):
   - In a detached scratch worktree of the branch, add
     `git show origin/main:flake.nix > flake-old.nix` and commit it. The
     tree is clean and committed, so `self` keeps a rev (§5).
   - Evaluate, with `nix eval --impure --expr`:
     - `new = builtins.getFlake "git+file://<scratch>?rev=<sha>"`;
     - `old = new.sourceInfo // ((import "${new}/flake-old.nix").outputs (new.inputs // { self = old; }))`.

     Each side ties its own knot, so the old `lib.mkUserIso` cannot resolve
     to the new one. Both read the same tree, so outputs that carry it are
     comparable.
   - Identical, with no fallback:
     - every `packages.x86_64-linux.*` drvPath;
     - every `nixosConfigurations.*.config.system.build.toplevel` drvPath;
     - `iso-net`'s `isoImage`;
     - `lib.mkUserIso { flake = new; host = "vm"; }`'s image and its
       `installerLauncher`.
   - A difference is investigated with `nix-diff` before anything else. If
     this method cannot evaluate, stop and report. It is not replaced by a
     weaker comparison.
3. **Placeholder consumers** (spec verification 3).
   - For every check not in `data/commit-bound-checks.nix`, run
     `nix-store -qR "$(nix eval --raw .#checks.x86_64-linux.<c>.drvPath)" | grep -c flake-template`.
   - For each check that has one, record whether its test runs `nix`,
     `nixos-install` or `nixos-rebuild` against the generated flake.
   - A check that does is listed with its reason, as a plan deviation.

### 4. Break proofs (lead)

Each break is made in a detached worktree (`git worktree add --detach`).
Prove it landed with `git diff`, commit it (the guard refuses a dirty tree),
then run the guard on the six. Each must name exactly the checks given:

1. drop D1's `narHash` → at least `installer-input-validation`,
   `initrd-pin-guard` and `installer-wizard`, which are measured to move
   through it;
2. drop D1's `lastModified` → at least the same three.

For breaks 1 and 2, `installer-early-exit` and `reinstall-image` are expected
to move too, through the same template. Any name beyond those five, or any of
the five missing, is checked with `nix-diff` before it is called a failure
of the fix (Codex).
3. revert D2 → `installer-early-exit`;
4. revert D3's `checkInputs.self.lib` line → `reinstall-image`;
5. revert D5's `:54` → `stable-eval`.

**Floor:** build `checks.stable-eval` with `toplevel = "";`, and again with
`toplevel = "nixos-system-.drv";`. Each must fail with "is not a system
derivation name".

### 5. Local checks before push (lead, §6 tiers)

- **Cheap**, one at a time under the lock:
  - `nix fmt -- --ci`, statix, deadnix;
  - `installer-lock`, `nixarchy-options`, `iso-source`, `stable-eval`;
  - `installer-input-validation`, `initrd-pin-guard`,
    `installer-early-exit`, `reinstall-image`;
  - `grep-q-pipefail`, `test-registration`;
  - every reachable target `.github/scripts/generated-checks.sh` prints.
- **VM tier**, with no self-hosted runner busy and no p620 system build:
  - `installer-wizard`, and `install-stock-iso` on its new real inputs;
  - then the full guard with no arguments, once: about 66 min and 13 GB, so
    it runs in its own `systemd-run --user --scope`.

### 6. Pull request (lead)

- The PR links the intent, spec and plan, and carries:
  - which steps Codex did;
  - the break outputs;
  - the same-tree comparison;
  - the consumer list;
  - D6's statement on what is not asserted.
- Comment `@codex review`, and verify its findings. The Opus review and the
  `reviewers:` reviews run on `git diff origin/main` before the push.
- Merge with `gh pr merge --auto --merge --delete-branch`, and only after
  step 3.2's full comparison is identical (Codex).
- After merge, dispatch the nightly (`gh workflow run nightly.yml --ref
  main`) when no install job is in flight. Close #1685 and #1727 on a green
  `commit-independent`.

## Tests

| check | expected |
|---|---|
| guard on the six | `none moved`; each step 4 break names exactly its checks |
| same-tree comparison | every listed shipped drvPath identical |
| `stable-eval` | green; floor break red |
| cheap tier, `installer-wizard`, `install-stock-iso` | green |
| full guard | `none moved` |

## Rollback

Revert the merge commit. The change touches only the check wiring, one test
and the commit-bound table. What ships is proven unchanged by step 3.2.
