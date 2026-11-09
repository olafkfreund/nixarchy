---
status: draft
issue: 1727
intent: intent/2026-11-09-1727-checks-follow-commit.md
---

# Spec: the installer's checks stop following the commit

## Evidence: what carries the commit, to the leaf

Measured on `main` `7fa60492` by evaluation only. The method is the guard's:
evaluate each check's `drvPath`, commit a tracked `.commit-probe` file two
days later, evaluate again, then `nix-diff` the pair (and the derivations it
names, until the leaf).

| check | leaf that moves | carrier | decision |
|---|---|---|---|
| `installer-input-validation` | `nixarchy-flake-template`: `narHash`, `lastModified` | `checkInputs.self` has no placeholder for either | D1: fix |
| `initrd-pin-guard` | same | same | D1: fix |
| `installer-wizard` | same, under its VM's closure | same | D1: fix |
| `installer-early-exit` | `nixarchy-flake-template`: `rev`, `url`, `narHash`, `lastModified` | `flake.nix:2326` reads the real `self.packages…install` | D1 + D2: fix |
| `reinstall-image` | both `nixarchy-installer-launcher`s → `nixarchy-install` → `nixarchy-flake-template`: `rev`, `url`, `narHash`, `lastModified` | `self.lib.mkUserIso` passes the real `inputs` into the ISO's `specialArgs` (`flake.nix:1773`). `checkInputs.self` keeps the real `lib` | D1 + D3: fix |
| `install-stock-iso` | the flake template's `narHash` and `lastModified`, **and** the input source `source` (the nixarchy tree) inside the `nixos-system-nixarchy-26.11` closure that `stock-iso-test-cache` carries | the install cache holds the installed machine's closure, and that closure holds the source tree | D4: list |
| `stable-eval` | the input source `source` (the nixarchy tree) in its 26.05 toplevel | `vm/configuration.nix:173` writes `inputs.nixarchy.url = "path:${inputs.self}"` into the VM's generated flake | D5: list |

How the source tree was identified: the two toplevels' `inputs.srcs` differ
in exactly one path each (`db3cd5p4…-source` → `52xsd0wh…-source`), and
both are the nixarchy tree (`AGENTS.md CLAUDE.md CONTRIBUTING.md data docs
…`). The guard's probe adds a file to the tree, so a check that carries the
tree itself moves whatever placeholder metadata it gets.

## Design

### D1. The placeholder `self` gains `narHash` and `lastModified` (`flake.nix:907-911`)

```nix
checkInputs = realInputs // {
  self = self // {
    rev = "0000000000000000000000000000000000000000";
    shortRev = "0000000";
    lastModifiedDate = "19700101000000";
    lastModified = 0;
    # 32 zero bytes: a well-formed SRI hash that names no real tree.
    narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    …
```

- `lastModified = 0` agrees with `lastModifiedDate = "19700101000000"`
  (agy). `mkFlake.nix:63` writes `toString self.lastModified`, and
  `installer-lock` requires a positive timestamp. `installer-lock` is
  commit-bound and gets the real inputs (`commitBound`), so it does not see
  0. That still has to be proven: break 4 below.
- **Where the placeholder template is consumed.** The placeholder lock is
  written by the `install` package that checks build. No check on
  `checkInputs` fetches the nixarchy input from it: the install VMs that
  run `nix` against the generated flake (`install`, `free-space`,
  `installer-refusal`, `install-encrypted`) are commit-bound, and get the
  real inputs. Verification step 3 proves this by grep and by running
  `installer-wizard`, the one VM on the placeholder.

### D2. `installer-early-exit` reads `inputs.self` (`flake.nix:2326`)

`renderedInstallScript = "${inputs.self.packages.${system}.install}/bin/nixarchy-install";`,
as its neighbour `installer-input-validation` does (`:2141`). The same
check's `self.nixosConfigurations.installer-vm…emptyDiskImages` (`:2332`) is
an integer, so it carries nothing, and it stays as it is.

### D3. `mkUserIso` takes its inputs as an argument (`flake.nix:1756-1780`)

- `mkUserIsoWith = inputs: { flake, host, ... }: …`, which is today's body
  with `inherit inputs` reading the argument.
- `lib.mkUserIso = mkUserIsoWith inputs`: the public function is unchanged.
- `checkInputs.self.lib = self.lib // { mkUserIso = mkUserIsoWith checkInputs; }`.

`reinstall-image` passes its own `flake` (`tests/reinstall-image.nix:18-24`).
The check tests that the launcher carries that flake and host, and that is
unchanged. Only the installer package inside the ISO now comes from the
placeholder.

### D4. `install-stock-iso` is commit-bound (`data/commit-bound-checks.nix`)

```nix
install-stock-iso = "its offline cache carries the installed machine's closure, which holds the source tree, as install does";
```

This check installs from a stock ISO and an offline cache of the machine it
installs, and that machine's closure contains the nixarchy tree. Removing the
tree would change what it installs. The reason is the same provenance as
`install`'s, and D1 does not move it.

### D5. `stable-eval` is commit-bound

```nix
stable-eval = "vm/configuration.nix:173 writes path: plus inputs.self into the VM's generated flake (evaluation only, as options-files)";
```

This is the carrier you ruled on for `options-files` on 2026-11-08: evaluation
only, so it stays commit-bound. `stable-eval` evaluates the same
`vm/configuration.nix` against stable. Giving it a placeholder tree would
change the flake the VM evaluates.

### D6. The guard and the flake read the new entries

`flake.nix` gives commit-bound checks the real inputs through `commitBound`.
Both new entries already evaluate against real inputs today, so they need no
other edit. Verification step 2 checks that their drvPaths do not change.

## Alternatives rejected

- **Listing the five fixable checks.** It makes the nightly green while
  leaving them unable to reuse a proof. Your ruling, and the intent's
  constraint.
- **A placeholder source tree for `stable-eval` and `install-stock-iso`**,
  such as a fixed `outPath`. It changes what each check evaluates or
  installs, which breaks "a check keeps testing what it tests today".
- **An arbitrary string for `narHash`**, such as `"0"`. A lock carrying it is
  not one a real flake could have (agy). The zero SRI hash is well-formed.

## Risks

- **A placeholder lock reaches something that verifies it.** If a check on
  `checkInputs` locks or fetches the generated flake's nixarchy input, a
  zero `narHash` fails with a hash mismatch. Mitigation: verification step 3.
  If one exists, it moves to the commit-bound list, with the reason.
- **What ships changes.** D1 and D3 touch `checkInputs` and `lib`.
  Mitigation: verification step 2 compares every shipped output's drvPath in
  the same tree.
- **The full guard is heavy.** #1644 measured about 66 minutes and a
  13.28 GB peak. It runs at the VM tier, with no busy runner, once, at the
  end.

## Verification

1. **The guard on the five fixed checks, locally:**
   `.github/scripts/commit-independent.sh initrd-pin-guard installer-early-exit installer-input-validation installer-wizard reinstall-image`.
   Expected: `none moved`. With no arguments, the guard skips the
   commit-bound names, so D4 and D5 are covered by step 6.
2. **What ships is unchanged**, compared in the same tree, old and new files
   side by side (CLAUDE.md §5). These must be identical:
   - `packages.x86_64-linux.{install,flake-template,omarchy}`;
   - `nixosConfigurations.{iso-net,vm,reference}.config.system.build.toplevel`;
   - `iso-net`'s `isoImage`;
   - `lib.mkUserIso { flake = self; host = "vm"; }`.
3. **The placeholder lock is never verified.**
   - `grep -rn 'flake.lock\|nix flake\|--offline' tests/` over the checks
     that use `checkInputs`;
   - `installer-wizard` built locally, as a VM.
4. **§1 breaks**, each in a detached worktree, with `git diff` proving it
   landed. Each makes the guard name the check, and nothing else changes:
   1. drop D1's `narHash` → `installer-input-validation`, `initrd-pin-guard`, `installer-wizard`;
   2. drop D1's `lastModified` → the same;
   3. revert D2 → `installer-early-exit`;
   4. revert D3's `checkInputs.self.lib` → `reinstall-image`;
   5. take `installer-lock` off the commit-bound list → `installer-lock` fails
      its positive-timestamp check. This proves the placeholder would be
      caught where the real value is asserted.
5. **Cheap tier:**
   - `nix fmt -- --ci`, statix, deadnix;
   - `installer-lock`, `nixarchy-options`, `iso-source`,
     `installer-input-validation`, `initrd-pin-guard`,
     `installer-early-exit`, `reinstall-image`;
   - every reachable target `generated-checks.sh` prints.
6. **VM tier:** `installer-wizard`, then the full guard, once, with no busy
   runner.
7. **After merge:** the next nightly's `commit-independent` is green, and
   #1685 closes.
