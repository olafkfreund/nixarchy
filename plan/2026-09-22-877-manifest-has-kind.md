---
status: draft
issue: 877
spec: spec/2026-09-22-877-manifest-has-kind.md
---

# Plan: keep-loaded plugins keep their shell API across settings changes

## Approved decisions (self-contained summary)

- **The cause (confirmed on razer):** omarchy 4.0.4's
  `manifestHasKind(manifest, kind)` (`shell/shell.qml:349`) uses
  `Array.isArray(manifest.kinds)`.
  - At creation, the manifest comes through a QML property, so `kinds` is a Qt
    sequence (length 2, `menu,bar-widget`, but `Array.isArray` false) and the
    recorded profile says `no-menu`.
  - At the first `shell.json` change, `prunePluginApis` recomputes the profile from
    the plain-JS `installedPlugins` manifest and gets `menu`.
  - The profiles mismatch, `revokePluginShellApi` destroys the API, and a
    keep-loaded plugin keeps a dead `shell` (`barConfig` is `null`).
- **Carry a patch, at the owner's explicit request (`AGENTS.md` §11), like #749.**
  - It is marked CARRIED and is deleted when upstream fixes the line.
  - Only `manifestHasKind` is patched. The other 17 `Array.isArray(...kinds)` sites
    go in the upstream report.
  - No re-inject safety net here.
- **The patch:** `substituteInPlace $out/share/omarchy/shell/shell.qml --replace-fail`,
  in `pkgs/omarchy/default.nix` next to the #749 `shell.qml` patch. The needle is
  upstream's whole function:
  ```qml
    function manifestHasKind(manifest, kind) {
      return !!manifest && Array.isArray(manifest.kinds)
        && manifest.kinds.indexOf(kind) !== -1
    }
  ```
  The replacement:
  ```qml
    function manifestHasKind(manifest, kind) {
      // nixarchy CARRIED patch (#877): kinds read through a QML property is a Qt
      // sequence, for which Array.isArray is false; accept anything list-shaped.
      var kinds = manifest ? manifest.kinds : null
      return !!kinds && typeof kinds.length === "number"
        && Array.prototype.indexOf.call(kinds, kind) !== -1
    }
  ```
  The Nix comment above it follows the #749 block: what breaks and the evidence,
  "CARRIED, and meant to be dropped", the upstream report, and when to delete it.
- **The check:** `tests/manifest-has-kind.nix`, a behavioural check run in a real QML
  engine (`qt6.qtdeclarative`'s `qml`, `QT_QPA_PLATFORM=offscreen`).
  - It extracts `manifestHasKind` from the built `shell.qml`: from the line
    containing `function manifestHasKind` to the next line that is exactly `  }`.
  - It embeds the function in a probe `Item` with
    `property list<string> kindsList: ["menu", "bar-widget"]`, a Qt sequence where
    `Array.isArray` is false (verified, qtdeclarative 6.11.2, exit-code probe).
  - It asserts four things, reporting through `Qt.exit(code)`, because the `qml`
    tool swallows console output here:
    - a sequence `menu`: true;
    - a plain array `menu`: true;
    - a sequence `bar`: false;
    - a `null` manifest: false.
  - Negative control: the same probe runs against the unpatched function (taken from
    the omarchy source before patching) and must fail. If it passes, the check fails.
  - It is wired into `flake.nix` `checks` next to `qml`.
- **Rejected** (don't reintroduce): patching all 18 sites; a re-inject patch; a
  grep-only check; normalising manifests at call sites; a workaround in the plugin.

**Constraints:**

- `pkgs/AGENTS.md`: every patch uses `--replace-fail` or an asserted anchor.
- `AGENTS.md` §1: prove the check fails first.
- `AGENTS.md` §4: a check must be able to go red, hence the negative control.
- §11: nothing is filed upstream by an agent.
- Commit subjects follow this repo's style, with `(#877)`.

**Live-test safety (razer):** announce on the bus; back up and restore `shell.json`;
make no Podman changes; any instrumentation is a temporary copy, never committed.

## Steps

One commit per step on `fix/877-manifest-has-kind`, citing `plan step N` and
`(#877)`.

1. **The check, failing first.**
   - Add `tests/manifest-has-kind.nix` and its `checks` entry in `flake.nix`.
     `nix build .#checks.x86_64-linux.manifest-has-kind` on today's code must
     **fail** on the patched-tree assertions. The negative control correctly fails
     too, as there is no patch yet.
   - Record the failing output for the commit and the PR.
   - Verify: the check is red, and it is red for the sequence `menu` assertion, not
     for a harness error. Inspect the log to be sure.
2. **The patch.**
   - Add the `substituteInPlace --replace-fail` block, with its CARRIED comment, to
     `pkgs/omarchy/default.nix`.
   - Verify:
     - `nix build .#omarchy`, and `grep` the built `shell.qml` for the new body;
     - the new check is **green**, including its negative control;
     - `nix build .#checks.x86_64-linux.patched-files` and `…qml` are green.
3. **The record.**
   - Find where the #749 carried patch is documented, under `docs/internals/` or
     `pkgs/AGENTS.md`, and add this one beside it. If it is recorded nowhere but the
     Nix comment, say so in the PR and add nothing.
   - Finalise the upstream report draft, listing the other 17 sites.
   - Verify: `nix flake check`.
4. **CI coverage.**
   - Push, open the PR, and confirm the check-coverage guard in `build.yml` passes
     and that the new check actually runs in CI (the job log shows
     `manifest-has-kind`). If the guard requires it, add the check to
     `.github/scripts/generated-checks.sh` in this step.
   - Verify: CI is green, and the check is visible in the job log.
5. **Merge, deploy, and check live on razer.**
   - After merge: a `nixarchy` input bump in nixos_config, through
     `just update-commit-deploy razer nixarchy`, or `all` if the owner prefers;
     announced on the bus.
   - Then on razer, with `shell.json` backed up:
     - open the Podman menu;
     - `omarchy bar set nixarchy.podman showStats false --json`;
     - open the menu again: the CPU and memory meters are gone, with **no** shell
       restart;
     - restore `shell.json` and post "done".
   - Verify: the observed behaviour. If it is still stale, stop and diagnose; don't
     patch further blind.
6. **Follow-up in nixarchy-podman.** A separate small PR drops the "restart the
   shell" sentence from `docs/usage.md` and closes the loop on #10's docs.

## Tests

```bash
nix build .#checks.x86_64-linux.manifest-has-kind   # red before step 2, green after
nix build .#checks.x86_64-linux.patched-files
nix build .#checks.x86_64-linux.qml
nix flake check
```

## Rollback

- Before merge: delete the branch and the `nixarchy-877` worktree.
- After merge: revert the merge commit; the next nixos_config bump restores
  upstream's function.
- razer: `shell.json` comes back from its backup. Nothing else changes by hand.
