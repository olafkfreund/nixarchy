---
status: draft
issue: 1131
spec: spec/2026-10-01-1131-automatic-store-optimise.md
---

# Plan: Deduplicate the store on installed machines

## Approved decisions

Installer-managed hosts lack periodic store deduplication. Their existing
`programs.nh.clean` prunes generations and the 3/8 GiB `min-free`/`max-free`
settings collect unreferenced paths; neither hard-links identical files still
in the store. Set the NixOS option `nix.optimise.automatic = true` only in
`installer/host.nix`. The generated host imports that file; Mode A imports the
Nixarchy module without it and keeps its own disk policy whether Nixarchy is
enabled or disabled. Do not add an option to `modules/nixos.nix`, daemon-side
`auto-optimise-store`, `nix.gc.automatic`, or a custom unit.

Use the pinned NixOS defaults: daily 03:45, persistent timer, up to 30 minutes
of randomized delay, `Nice = 19`, idle CPU and I/O scheduling, and an AC-power
condition. Do not set CPUWeight or IOWeight without measured contention.
Store optimisation may cause noticeable disk work on the first pass, and
an always-on-battery laptop may defer it indefinitely. Savings on nixarchy
remain unmeasured; the reported nixbook result is not an acceptance target.

## Steps

1. **`tests/options.nix:1455-1492`: add the check before the setting.** Beside
   `installedHostDiskPolicy`, assert that the installer-backed `vm` config has
   `nix.optimise.automatic == true` and an enabled `nix-optimise` timer. Assert
   that both `adopter` (Mode A with Nixarchy on) and `modeAOff` (Mode A with
   Nixarchy off) have `automatic == false` and no active timer. Use those
   existing fixtures and the existing `checks.options` entry at
   `flake.nix:2373`; do not add a check or workflow. Make failures name the
   installed or Mode A case. → Verify the edit landed with `git diff`, run
   `nix fmt`, inspect `git diff --stat`, then `nix fmt -- --ci`. In an idle
   build window under the shared lock, run `checks.options` and capture its
   **expected red** output naming the missing installed-host setting. The
   Mode A assertions should already be true. Trap: a grep for source text
   is not a resolved-option check; `checks.options` uses about 11.5 GiB RSS.

2. **`installer/host.nix:145-200`: enable the native timer.** Add the single
   `nix.optimise.automatic = true;` setting adjacent to the installer-owned
   Nix disk policy. Keep `nix.settings.min-free/max-free`, `nix.package`, and
   `programs.nh.clean` unchanged. Do not set dates, weights, or systemd unit
   fields. → Verify the diff contains only that setting and a brief reason;
   run `nix fmt`, inspect `git diff --stat`, and run `nix fmt -- --ci`. In an
   idle build window under the lock, rerun `checks.options` and capture its
   **green** result. Evaluate the installed `vm` option and generated timer
   and service settings to confirm the native defaults and the existing disk
   policy. Trap: Mode A never imports `installer/host.nix`; moving the setting
   into `modules/nixos.nix` changes the approved scope.

3. **`modules/nixos.nix:235-260` and `tests/options.nix`: prove the Mode A checks
   can fail, without keeping a module edit.** Copy `modules/nixos.nix` to a
   save file outside the worktree. Temporarily add an inline module
   `{ nix.optimise.automatic = true; }` to its `imports` list; run `git diff`
   to confirm the break landed. Under the same idle/load gate and lock, run
   `checks.options` expecting both the enabled `adopter` and disabled
   `modeAOff` cases to fail.
   Restore the saved file with `cp` (never `git checkout`), confirm its diff
   disappeared, and rerun the check green. Keep the red line for the eventual
   review. This deliberate break verifies both Mode A guards independently of
   the installed-host red from Step 1. Trap: do not commit the temporary edit
   or leave its save file in the worktree.

4. **`installer/host.nix` and `tests/options.nix`: finish static review.** Run
   `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
   `nix run nixpkgs#deadnix -- --fail .`, and `git diff --check`; inspect
   `git diff --stat` for unrelated formatting. Check the resolved installed
   host still has 3/8 GiB thresholds and `programs.nh.clean` enabled. → Verify
   all static gates pass and only the approved production/test files changed.
   Trap: `nix fmt` may expose a formatting hook's unrelated rewrite; review
   the diff before committing.

## Tests

- Before **every** local `nix build`, check
  `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
  plus `pgrep -af 'nixosConfigurations.p620|nh os build'` and the one-minute
  load from `/proc/loadavg`. Defer `checks.options` if CI work is active, a
  p620 system build is running, or the one-minute load is 12 or higher.
  `checks.options` is an ~8-minute, 11.5 GiB evaluation, not a cheap
  exception to root `AGENTS.md` §6. Do not touch other agents' processes.
- Serialize each permitted run with
  `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.options --print-build-logs --no-link`.
  Capture the command's exit status directly; do not pipe it through `tail`.
  Keep red logs outside the worktree and cite the relevant failure lines in
  the eventual PR. The sequence is: missing-setting red; setting green;
  temporary leak red for both Mode A states; restored green. If repeated
  runs are unsafe under current load, wait for an idle window rather than
  weakening the proof.
- Use `nix eval --json` on `.#nixosConfigurations.vm.config` subattributes
  to inspect `nix.optimise.automatic`, `systemd.timers.nix-optimise`, and
  `systemd.services.nix-optimise` after the green run. Confirm the service's
  AC/idle settings come from pinned nixpkgs, and that `programs.nh.clean` and
  3/8 GiB thresholds did not move. No VM, install, ISO, store optimisation,
  deploy, or runtime timer activation is needed for this option change.
- No builds or implementation edits occur while this plan is draft. After
  approval, name the plan step being executed; if implementation must deviate,
  update this plan in the same commit as the code.

## Rollback

Revert the implementation commit that adds the installer option and its
assertion. The NixOS timer returns to its default disabled state on installed
machines after their next rebuild; `nh clean` and `min-free`/`max-free` remain
as before. Store files already hard-linked by a completed optimisation need
no reversal: Nix continues to address them by immutable store paths.
