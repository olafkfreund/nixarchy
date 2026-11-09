---
status: approved
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
| `reinstall-image` | `launcher` (`tests/reinstall-image.nix:32`) → `nixarchy-install` → `nixarchy-flake-template`: `rev`, `url`, `narHash`, `lastModified`. `publishedLauncher` (`:33`): `narHash`, `lastModified` only | `launcher` comes from `self.lib.mkUserIso`, which passes the real `inputs` into the ISO's `specialArgs` (`flake.nix:1773`), and `checkInputs.self` keeps the real `lib`. `publishedLauncher` comes from `checkInputs`' `iso-net`, so only D1's fields move it (agy) | D1 + D3: fix |
| `install-stock-iso` | the flake template's `narHash` and `lastModified`, **and** the nixarchy tree in `stock-iso-test-cache` | `tests/install-stock-iso.nix:15`: `inputSources = inputs.self.lib.inputSources { flake = inputs.self; }`, which collects `flake.outPath` (`flake.nix:1732`) into the offline cache the install evaluates from | D4: **your decision** |
| `stable-eval` | its derivation's `toplevel` environment string: the 26.05 toplevel's `drvPath`, whose input sources include the nixarchy tree | `tests/stable-eval.nix:54` puts `cfg.system.build.toplevel.drvPath` into the check's environment. The tree enters that toplevel through `vm/configuration.nix:173` (`path:${inputs.self}` in an activation script's text) | D5: fix |

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
  `installer-lock` requires a positive timestamp. It never sees 0: it
  reads the real `self.packages…flake-template` directly (D6), so the
  placeholder cannot reach it.
- **Where the placeholder template is consumed.** It is written by the
  `install` package that checks build.
  - The install VMs that run `nix` against the generated flake (`install`,
    `free-space`, `installer-refusal`, `install-encrypted`) are commit-bound,
    and get the real inputs.
  - That no other check verifies the placeholder lock is not assumed.
    Verification step 3 enumerates every consumer.

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

### D4. `install-stock-iso`: a decision for you

Your intent decision was that "the six installer checks are fixed, not
listed", and `install-stock-iso` is one of the six. D1 removes its
template's movement, but not the tree's:

- `tests/install-stock-iso.nix:15` collects `inputSources { flake =
  inputs.self; }` into the cache the stock ISO installs from offline.
  `inputSources` starts with `flake.outPath` (`flake.nix:1732`), the source
  tree itself.
- The offline install evaluates the user's flake against that tree. A
  placeholder tree would install something other than nixarchy. Keeping the
  real tree means the check follows every commit.

So the check cannot be both fixed and still test what it tests today. Two
options:

- **(a) List it (recommended):**
  `install-stock-iso = "tests/install-stock-iso.nix:15 collects inputSources, which starts with the source tree, into the cache it installs from offline";`.
  - This is the provenance `iso-source` is already listed for.
  - Listing switches its `inputs` to `realInputs` (`flake.nix:2926`), so
    its drvPath changes once, to the real rev (agy).
  - D1 still applies to every other check.
- **(b) Leave it unlisted.** The guard stays red on it, and the nightly
  cannot go green.

### D5. `stable-eval` keeps the toplevel's name, not its hash (`tests/stable-eval.nix:54`, `:101-102`)

`stable-eval` exists to prove that nixarchy evaluates against stable. It
forces `toplevel.drvPath`, then checks that the result is a system
derivation (`:101-102`). The hash in that path is incidental: it follows the
tree only because the VM's activation script names `${inputs.self}`. Nothing
evaluates the generated flake here (agy).

- `:54` keeps the store name without its hash:
  `toplevel = builtins.substring 44 (-1) (builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath);`.
  That is the store directory plus a 32-character hash plus `-`, so 44
  characters. This still forces the full evaluation.
- `:102`'s pattern becomes `nixos-system-*.drv`, so the floor still refuses
  an empty or malformed result.
- The name keeps nixpkgs' release string (`26.05.20260910.d58a46e`), which
  is a fact about the stable input, and the check prints it.

### D6. What already asserts the real values

The intent asks for this to be stated exactly (Codex, agy):

- `installer-lock` reads the real `self.packages.${system}.flake-template`
  directly (`flake.nix`, its definition). It never sees `checkInputs`, and
  this spec does not change that. It asserts that every field `mkFlake`
  writes is present, that `lastModified` is a number, and that it is
  positive (`tests/installer-lock.nix:42-68`).
- `nixarchy-options` asserts the real rev.
- **No check asserts that `narHash` or `lastModified` equals the real
  commit's.** This spec does not add one, and does not claim one.

### D3, what it changes for `reinstall-image`

The check tests `mkUserIsoWith checkInputs`. The public `lib.mkUserIso` is
`mkUserIsoWith inputs`: the same body, with real inputs. So the check still
tests the function's code, the launcher's flake and host pairing, and its
command-line handling (`tests/reinstall-image.nix:35-55`). What it no longer
tests is the real rev inside the ISO's installer. The intent permits exactly
that (Codex). The public function's output is covered only by verification
step 2's drvPath comparison.

## Alternatives rejected

- **Listing the checks D1, D2, D3 and D5 fix.** It makes the nightly green while
  leaving them unable to reuse a proof. Your ruling, and the intent's
  constraint.
- **A placeholder source tree for `install-stock-iso`**, such as a fixed
  `outPath`. It changes what the check installs, which breaks "a check
  keeps testing what it tests today".
- **Listing `stable-eval`**, on the `options-files` precedent. Its carrier
  is incidental to what it checks, so the intent says fix it (D5).
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

1. **The guard on the six fixed checks, locally:**
   `.github/scripts/commit-independent.sh initrd-pin-guard installer-early-exit installer-input-validation installer-wizard reinstall-image stable-eval`.
   Expected: `none moved`.
2. **What ships is unchanged.** Compare in the same tree, with the old
   `flake.nix` checked out beside the new one (CLAUDE.md §5), and all
   outputs, not a sample (agy):
   - every `packages.x86_64-linux.*` drvPath;
   - every `nixosConfigurations.*.config.system.build.toplevel` drvPath;
   - `iso-net`'s `isoImage`;
   - `lib.mkUserIso { flake = self; host = "vm"; }`, both its image and its
     `installerLauncher`.

   An output that evaluated `checkInputs` would move under D1, so identical
   drvPaths also show that none does.
3. **The placeholder lock is never verified.** Enumerate it mechanically,
   not by grep (Codex, agy):
   - Every check not in `data/commit-bound-checks.nix` whose derivation
     closure contains a `nixarchy-flake-template`
     (`nix-store -qR <drv> | grep flake-template`).
   - For each, the spec's plan records whether it runs `nix`,
     `nixos-install` or `nixos-rebuild` against the generated flake.
   - A check that does goes on the list, with its reason. `installer-wizard`
     is built locally, as a VM.
4. **§1 breaks**, each in a detached worktree, with `git diff` proving it
   landed. Each makes the guard name exactly the checks given:
   1. drop D1's `narHash` → `installer-input-validation`, `initrd-pin-guard`,
      `installer-wizard`, `installer-early-exit`, `reinstall-image`;
   2. drop D1's `lastModified` → the same five;
   3. revert D2 → `installer-early-exit`;
   4. revert D3's `checkInputs.self.lib` → `reinstall-image`;
   5. revert D5 → `stable-eval`.
   - Also: D5's floor still refuses. Make `toplevel` an empty string, and
     `stable-eval` fails on build.
5. **Cheap tier:**
   - `nix fmt -- --ci`, statix, deadnix;
   - `installer-lock`, `nixarchy-options`, `iso-source`, `stable-eval`,
     `installer-input-validation`, `initrd-pin-guard`,
     `installer-early-exit`, `reinstall-image`;
   - every reachable target `generated-checks.sh` prints.
6. **VM tier:** `installer-wizard`, and `install-stock-iso` under its new
   inputs if D4(a) is chosen. Then the full guard, once, with no busy
   runner.
7. **After merge:** the next nightly's `commit-independent` is green, and
   #1685 closes.

## Decisions (owner, 2026-11-09)

- Approved with the recommendations.
- D4: option (a). `install-stock-iso` is listed in `data/commit-bound-checks.nix` with the `inputSources` reason. It is the one installer check listed, by your ruling, because its offline cache must carry the real source tree.
