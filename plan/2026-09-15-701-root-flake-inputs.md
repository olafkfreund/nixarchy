---
status: draft
issue: 701
spec: spec/2026-09-15-701-root-flake-inputs.md
---

# Plan: an installed machine keeps the sources it needs to rebuild itself

## Approved decisions

This section carries the spec over so the plan stands on its own.

- **Why.** `installer/host.nix`'s `min-free = 5 GiB` collection can delete the
  installed machine's flake input sources. None of them are in the system
  closure (checked on `main` at a62e715). An offline machine then cannot
  evaluate its own configuration. #698's install hit it and is blocked.
- **D1. One shared walk.** `collectInputs` moves from `installer/cd.nix`
  (lines 96–99) into the flake's `lib` output as `inputSources`. It takes an
  attrset of flakes and returns the unique store paths of each and of their
  inputs, transitively. `cd.nix` calls
  `inputs.self.lib.inputSources { flake = source.flake; }`, which is the same
  walk it does today.
- **D2. The installed host roots them.** `installer/host.nix` sets
  `system.extraDependencies = inputs.self.lib.inputSources inputs;`.
  - **Everything in `inputs`.** `inputs.self` is nixarchy, never the user's
    flake, so editing `/etc/nixos` does not change the closure.
  - **Only installed machines.** Only they import `host.nix`; Mode A is untouched.
  - **No option.**
- **D3. The comment tells the truth.** The `min-free`/`max-free` comment in
  `host.nix` says flake sources are kept by `extraDependencies`.
- **D4. Proof in two layers.**
  - `checks.options`: the `vm` configuration's `system.extraDependencies`
    contains `inputs.nixpkgs.outPath` and `inputs.self.outPath`; `loaderOff`
    contains neither.
  - `checks.install`: after the `nixosConfigurations` evaluation
    (`tests/install.nix:824–830`), run `nix-collect-garbage` (not `-d`), then
    evaluate again, offline. It must succeed.
- **Cost accepted.** Up to 835 MiB of sources in the installed closure, less
  where the user's flake makes inputs follow its nixpkgs.
- **Rejected.** A bigger test disk, re-running #698, dropping `min-free`, a
  hand-kept list, registry pins, a Mode A option, and a new VM check.

## Steps

Each step is one commit with a full-sentence subject. A deviation updates this
file in the same commit.

0. **Baseline for step 1's comparison.** Before touching `cd.nix`, write the
   current `inputSources` list to a scratch file:
   `nix eval --json .#nixosConfigurations.iso.config.system.extraDependencies`
   (or the ISO attribute `flake.nix:1172–1180` names), sorted.
   → verify: the file is non-empty and holds about 34 or more `-source` paths.

1. **`flake.nix` `lib` (line 1302) and `installer/cd.nix`.**
   - Add `inputSources`, with a two-line comment on why it is shared.
   - In `cd.nix`, delete `collectInputs` and set
     `inputSources = inputs.self.lib.inputSources { flake = source.flake; };`.
   → verify:
   - the same `nix eval` as step 0 gives a list identical to the baseline,
     compared in one tree (AGENTS.md §5);
   - `checks.iso-source` and `checks.reinstall-iso` pass locally.

2. **`installer/host.nix`.**
   - Add the `extraDependencies` line (D2), next to `nix.settings` (line 145).
   - Add the sentence to the `min-free` comment (D3).
   → verify: `nix eval .#nixosConfigurations.vm.config.system.extraDependencies`
   contains nixarchy's and nixpkgs's source paths, and
   `checks.vm-toplevel` builds.

3. **`tests/options.nix`: a case `flakeInputsRooted`** in `cases` (line 377).
   - `on`: the `vm` configuration's `extraDependencies` contains both
     `inputs.nixpkgs.outPath` and `inputs.self.outPath`.
   - `off`: `loaderOff`'s contains either.
   → verify: `checks.options` passes; with the step 2 line removed it fails,
   naming `flakeInputsRooted`. The failing output goes in the PR.

4. **`tests/install.nix`: collect, then evaluate offline**, after line 830.
   ```python
   target.succeed("nix-collect-garbage")
   target.succeed(<the same eval as lines 824-827>)
   print("the flake still evaluates offline after a full collection (#701)")
   ```
   The comment above it says why: the collection deleted nixarchy's source on
   #698, and an offline machine could not evaluate itself.
   → verify: it cannot run locally (§6, and CI's install slots). Proven in CI
   by steps 5–6.

5. **Seen red in CI, once.** Push a commit that removes the step 2 line, and
   let `install` run.
   → verify: `install` fails at the new step with `unable to download`. Capture
   the failing output.

6. **Restore.** Revert step 5's commit and push.
   → verify: `install` passes, including the rebuild-builds-nothing assertion
   (`tests/install.nix:901`).

7. **Lint, write-back, PR.**
   - `nix fmt`, statix and deadnix.
   - AGENTS.md §3 gains one sentence: garbage collection is a variable no VM
     varied, which is how #701 hid until a nixpkgs bump tipped the disk.
   - One PR that links intent, spec and plan, says `Closes #701`, and includes
     the failing outputs from steps 3 and 5.
   - Before merge, squash away steps 5 and 6's commits so `main` never holds the
     broken state.
   → verify: all lint clean; the PR lists every piece of evidence.

8. **After merge: #698.**
   - `gh pr update-branch 698`, so it runs on `main` with the fix.
   - Its auto-merge (squash) is already armed.
   → verify: #698's `install` passes and it merges.

## Tests

| command | expected |
|---|---|
| `nix eval --json` of the ISO's `extraDependencies`, before and after step 1 | identical sorted lists |
| `nix build .#checks.x86_64-linux.options` | green; red naming `flakeInputsRooted` without the fix |
| `nix build .#checks.x86_64-linux.iso-source` and `.reinstall-iso` | green |
| `nix build .#checks.x86_64-linux.vm-toplevel` | builds |
| CI `install` on the step 5 commit | red at the collect-then-evaluate step |
| CI `install` on the step 6 commit | green, the rebuild still builds nothing |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

- **Revert.** Revert the squash commit: installed machines return to today's
  behaviour. The rooted sources become ordinary garbage and are collected, and
  nothing else depends on them.
- **Closure size.** If the extra space is a problem on real machines, D2 can
  narrow to a subset in a follow-up with its own intent. The test from step 4
  shows which inputs evaluation actually needs.
