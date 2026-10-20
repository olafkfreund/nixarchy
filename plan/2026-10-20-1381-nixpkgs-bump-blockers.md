---
status: approved
issue: 1381
spec: spec/2026-10-20-1381-nixpkgs-bump-blockers.md
---

# Plan: the nightly nixpkgs bump merges when nothing it changes is broken

Approved decisions, carried from the spec:

- **Three independent PRs, A, B and C,** each `Refs #1381`. The last to
  merge says `Closes #1381`. #1378 is left to the bot, and the next
  nightly bump opens a fresh PR.
- **A, `copilot-handoff`:** the stub log goes from 500 to 20 000 lines, so
  the `head -100` control gets SIGPIPE by size, not timing. The comments
  and the failure message are updated to match.
- **B, nixi on Qt 6.12:**
  - first, a QML repro proves or refutes the shadowing of the `Color`
    singleton (by `QtQuick.Controls`);
  - then nixi's QML gains `import qs.Commons as Commons` and uses
    `Commons.Color` and `Commons.Style`;
  - the fix is released in `olafkfreund/nixi-nixarchy`, and the pin moves
    in `flake.nix:258` and `flake.lock`;
  - the `session` assertion is not touched;
  - if the repro refutes the hypothesis, **stop and revise the spec**.
- **C, the VirtualBox collision:** first, list what guest additions puts
  under `lib/modules`. Then:
  - **(i)** if it is depmod output, an overlay strips it in `postInstall`,
    applied only where `virtualisation.virtualbox.guest` uses it, and a
    nixpkgs issue is drafted for approval;
  - **(ii)** if nixpkgs has already fixed it, do nothing;
  - **(iii)** anything else: stop and revise.
- **Who implements:**
  - A is one stub plus comments, so the lead does it;
  - B's nixi edit spans several QML files in another repository, so the
    `coder` agent does it;
  - C is decided after measuring, and the lead does it.
- **No builds or runs start while the owner's local build is running.**
  Every step that builds waits for the owner's go-ahead.

## Steps

**A. `copilot-handoff`** (lead; branch `ci/1381-copilot-handoff` off `main`)

1. `tests/copilot-handoff/gh:31-35`:
   - `seq 1 500` becomes `seq 1 20000`;
   - the comment explains that the size exceeds every pipe buffer between
     the stages, so SIGPIPE is certain whatever the speed (#1381).

   `tests/copilot-handoff.nix`:
   - lines 11, 67 and 74: "500-line" becomes "20 000-line";
   - line 69: the message says the stub must exceed the pipe buffers and
     names #1381, instead of "raise the line count".

   → verify: `nix fmt`, `git diff`.
2. **Prove it** (cheap tier, under the lock):
   - the check is green;
   - run the control alone 20 times, with `nix build --rebuild` on the
     check, and none of the runs may pass the control;
   - with the stub back at 500 lines, a passing control on #1378's run is
     the recorded red. Locally, try 20 runs and record whether the flake
     reproduces.
3. Commit, open the PR, and set auto-merge.

**B. nixi** (`coder` for B2; lead for B1, B3 and B4)

1. **The repro** (lead), on the bumped nixpkgs's Qt 6.12 `qml` tool,
   offscreen. A `Commons/qmldir` with a `Color` singleton, plus a file
   that imports `QtQuick`, `QtQuick.Controls` and `Commons` and prints
   `Color.menu`. Run it:
   - with `QtQuick.Controls`;
   - without it;
   - and on Qt 6.11.

   Record the three results. If they do not show `QtQuick.Controls`
   shadowing on 6.12 alone, **stop**.
2. **The fix** (coder), in a clone of `olafkfreund/nixi-nixarchy` under
   `/mnt/data/vmtest`, on a branch: in every `.qml` that references
   `Color.` or `Style.` and imports `qs.Commons`, add
   `import qs.Commons as Commons` and qualify every reference.
   - Verify by grepping: no unqualified `Color.` or `Style.` remains in
     those files.
   - Trap: do not touch identifiers that merely contain the letters, such
     as `textColor`. Match `\bColor\.` and `\bStyle\.`.
3. **Release** (lead): open the PR in nixi-nixarchy, and its maintainer
   (the owner) merges it.
4. **Pin** (lead): `flake.nix:258` points at the merged commit, plus one
   line on the comment's change list, then `nix flake update nixi`.
   **Prove:** `checks.session` is green on today's nixpkgs (Qt 6.11), and
   green on a scratch tree with the bumped nixpkgs (Qt 6.12). The red is
   #1378's run with the old pin. `session` is a VM check, so run it only
   when CI is idle.

**C. VirtualBox** (lead)

1. `nix path-info` / `nix build` (substitution only) on the bumped
   nixpkgs's `linuxPackages.virtualboxGuestAdditions`, then
   `find -L result/lib/modules`. Compare its `modules.builtin.alias.bin`
   with the kernel's (`cmp`).
2. **(i):** an overlay in the module that enables guest additions (find
   it with `grep -rn virtualboxGuestAdditions modules/`), deleting
   `$out/lib/modules/*/modules.{builtin,alias,dep,symbols}*` in
   `postInstall`. Prove `checks.offline-hardware-packages` is green on the
   bumped scratch tree; #1378's run is the red. Draft the nixpkgs issue
   in the PR body, and post nothing (§11).
   **(ii) or (iii):** as above.

## Tests

- A: green, and the control is never green across 20 runs.
- B: the repro shows shadowing; `session` is green on Qt 6.11 and 6.12,
  and red with the old pin (#1378).
- C: `offline-hardware-packages` is green on the bump, red before.
- The next nightly bump PR is green.

## Rollback

Each PR reverts on its own: A's stub, B's pin (nixi stays fixed upstream),
C's overlay.

## Deviations

- **A goes on the artifacts branch** (`ci/1381-nixpkgs-bump-blockers`),
  not on a separate `ci/1381-copilot-handoff` branch. That way its PR
  carries intent, spec and plan; B and C get their own branches.
- **A's red proof:** on p620, the old 500-line stub's control failed
  correctly in 20 of 20 rebuilds, as did the 20 000-line one. The race
  shows only on the CI runner (#1378's `omarchy` job, where the control
  passed). The fix removes the dependence on timing rather than
  reproducing it locally. Both loops are recorded in the PR.
- **C1 measured case (i).** On nixpkgs 09063bd,
  `VirtualBox-GuestAdditions-7.2.20-7.2.11` ships depmod's index
  (`modules.alias`, `modules.dep`, `modules.builtin.alias.bin` and the rest)
  beside `vboxguest.ko.xz` and `vboxsf.ko.xz`. The 7.2.10 build on the
  current pin ships only the two `.ko` files.
- **C2 is `.extend` on the default kernel set, not an overlay.**
  `modules/nixos.nix`'s `boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest`
  becomes `linuxPackages_latest.extend` replacing only
  `virtualboxGuestAdditions` (`postInstall` removes
  `$out/lib/modules/*/modules.*`). It is smaller than an overlay, and it
  leaves the kernel derivation byte-identical (`drvPath` compared in one
  tree). A user who sets their own `boot.kernelPackages` does not get it.
  That is acceptable until nixpkgs fixes the package.
- **C2 proved locally:** `checks.offline-hardware-packages` on a scratch
  tree with nixpkgs 09063bd is green with the change, and red without it,
  with the same `conflicting subpath ... modules.builtin.bin` CI showed
  on #1378.
