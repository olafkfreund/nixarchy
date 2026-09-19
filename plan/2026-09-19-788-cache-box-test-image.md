---
status: approved
issue: 788
spec: spec/2026-09-19-788-cache-box-test-image.md
---

# Plan: Cache the shared Arch box test image

Keep both existing digest/hash pins unchanged. Move their table to flake.nix's
outer let, create one image map per system, expose Arch as box-test-image,
and inject the common image/map into the existing box tests. Add Arch alone
to the system cache allowlist. Build it in the existing early hypr-rdp step
before that group's main-only publication. Preserve all budget, licensing,
workflow trigger and test semantics.

## Steps

1. Add a system-allowlist assertion to tests/cache-budget.nix and run its
   shell command locally before the fix; capture failure.
2. Update flake.nix and tests/box-{boot,template}.nix to use shared images.
   Compare original and new Arch outPaths; they must be identical.
3. Update cache-allowlist.sh and build.yml's existing producer command.
   Run the assertion successfully; remove the entry temporarily and prove
   it fails, then restore it. Inspect actual producer-before-push ordering.
4. Run formatting, Nix parsing and bash syntax checks. Commit before tests
   that require self.rev. No changes outside the owned worktree.
5. Coordinate the shared heavy-build slot with the team. Build existing
   cache-budget, box-template and box-boot checks. Measure the complete
   allowlist via cache-budget.sh and the Arch NAR size without increasing
   its 2048 MiB cap. Capture failures; do not retry until green.
6. Use disposable local stores under /mnt/data/vmtest to prove cold image
   realization fails without a cache when upstream is unavailable, then
   imports the same fixed-output image from a binary cache without a Hub
   request. Never delete or invalidate shared host store paths. Local binary
   cache proof is not evidence of public Cachix publication; report that
   separately until the main-only publisher runs.
7. After root schedules one push, open a ready PR with evidence, artifact
   links and Closes #788. No merge by this agent. Preserve GPL/licence files
   inside the unmodified official base image; no proprietary images added.

## Tests

- `bash .github/scripts/cache-allowlist.sh system` must contain exactly one
  `.#box-test-image`; the assertion fails when that entry is removed.
- `nixfmt --check flake.nix tests/box-boot.nix tests/box-template.nix tests/cache-budget.nix`;
  `bash -n .github/scripts/cache-allowlist.sh`; `git diff --check`.
- Through `/mnt/data/vmtest/heavy-build.sh <log>` when granted the slot:
  `.#checks.x86_64-linux.cache-budget`, `.#checks.x86_64-linux.box-template`,
  `.#checks.x86_64-linux.box-boot` with `--print-build-logs`.
- `.github/scripts/cache-budget.sh`: union of complete allowlist below
  2048 MiB; log actual incremental image NAR bytes.
- Isolated `nix copy`/realization using the image's exact store path, with
  no access to a shared-store fallback; retain failure and success output.

## Rollback

Revert the implementation commit. The prior duplicated constructors and
registry dependency return; reopen #788. Do not delete any cached or local
store paths. Remove only task-owned disposable test stores after evidence is
saved. No host switch is involved.

Approval source: the user's explicit approval of all #788 stages and work;
record this plan's approval in its own commit before implementation.

## Execution adjustment

The coordinating agent directed that a duplicate local box-boot VM is not
needed after proving the old and new Arch output paths identical and passing
box-template. Existing CI still runs box-boot. Public cache publication stays
main-only; the pre-merge cold-store proof uses a local binary cache and must
not be described as proof that nixarchy.cachix.org already serves the image.
