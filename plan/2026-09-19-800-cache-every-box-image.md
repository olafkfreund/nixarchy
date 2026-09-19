---
status: approved
issue: 800
spec: spec/2026-09-19-788-cache-box-image.md (on branch fix/788-cache-box-image, approved d73ba89)
---

# Plan: cache every pinned box image, and write the availability exception into the allowlist

**#800 is #788's remainder.** #796 (merged as `aa39670`, closing #788) cached the
**Arch** image. The owner-approved #788 intent (`054ee76`, and the merged
`intent/2026-09-19-788-cache-box-test-image.md`) and spec (`d73ba89`, branch
`fix/788-cache-box-image`) decided more than that, and this plan finishes it.

## Decisions carried over (owner-approved, #788)

1. **Availability is a reason for the cache list:** an explicit exception to
   the #725 rule ("only what we would otherwise build"), written into
   `cache-allowlist.sh`'s **header**, naming #788.
2. **Every pinned box image is cached,** not only Arch: today `archlinux` and
   `debian` (`boxImagePins`, `flake.nix`), and each new template's image with
   no second edit.
3. The budget is measured with all of them (`cache-budget.sh`, 2 GB share).

**Departure, for the owner to approve with this plan:** the spec put the
images in a new `boxes` group, filled by the nightly `repush`. #796 has since
put the image in the **`system`** group, and added a producer step to
`build.yml` (`:1258`, `nix build .#hypr-rdp .#box-test-image`) so the `system`
job builds it before pushing. That step is a CI change that has already landed.
Moving to a `boxes` group would drop it, so pushes would wait for the nightly;
naming Debian separately would need a second workflow edit. So this plan keeps
**one entry, `.#box-test-image`**, and makes it cover every pin:
- no workflow edit;
- the `tests/cache-budget.nix` "exactly once" assertion is unchanged;
- a new template still needs no second edit.

## Steps

1. `flake.nix` (`packages.x86_64-linux.box-test-image`, `:911`): replace
   `boxImages.${system}.archlinux` with
   `pkgs.linkFarm "box-test-images" (lib.mapAttrs (_: i: i) boxImages.${system})`,
   plus `passthru.images = boxImages.${system}`. Its closure is every pinned
   tarball, so the existing `system` push caches them all. Keep the name, since
   `build.yml` and `tests/cache-budget.nix` name it. Rewrite the comment above
   it to say it is every pin.
   → verify: `nix eval --json .#box-test-image.passthru.images --apply builtins.attrNames`
   is `["archlinux","debian"]`.
2. `flake.nix` (`checks.box-boot`, `:2219`): `image = boxImages.${system}.archlinux;`
   (the default template's), no longer the package, which is now a join.
   → verify: box-boot's drvPath is **unchanged** against `main`, compared in the
   same tree (AGENTS.md §5).
3. **Same-path assertion**, in `checks.box-template` (it already receives
   `images`): for every pin, `images.<n>.outPath ==
   self.packages.${system}.box-test-image.passthru.images.<n>.outPath`, plus an
   assert that the join names every pin. **Break (§1):** drop `debian` from the
   join. It must fail naming `debian`. Restore with `git checkout HEAD --`.
4. `.github/scripts/cache-allowlist.sh`:
   - A header paragraph after the #725 rule: "One exception, for availability
     rather than build cost (#788, #800): the box checks' pinned base images.
     They are a download either way, but Docker Hub is not ours, and a 502
     from it turned `main` red on a cold runner. They are cached so the checks
     never depend on it."
   - The entry comment becomes "every pinned box image".
   → verify: `cache-allowlist.sh system | grep -cx '.#box-test-image'` is 1.
5. **Budget:** `cache-budget.sh` passes. Record the figure (both images) in the
   PR and in the header comment.
6. **The cache-only fetch proof (§1)**, recorded on the issue, not claimed in
   the PR:
   - **Red, before merge:** with the debian tarball absent locally,
     `nix build <debian image path> --max-jobs 0`. `--max-jobs 0` forbids even
     the fixed-output fetch, so it can only come from the cache, and today it
     isn't there. Capture the failure.
   - **Green, after merge:** after `main`'s `system` job pushes, the same
     command must substitute it.
7. Docs: one line in `docs/internals/workflows.md`, or wherever the cache
   allowlist is described (grep first), naming the availability exception.
8. `nix fmt -- --ci`, statix, deadnix. Heavy builds only through
   `/mnt/data/vmtest/heavy-build.sh`.
9. The PR links #788's intent and spec plus this plan, with `Closes #800`.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.box-template` with debian dropped from the join | exit 1, naming debian |
| the same, restored | exit 0 |
| box-boot drvPath, old vs new, same tree | identical |
| `cache-budget.sh` | pass, figure recorded |
| `--max-jobs 0` fetch of the debian image, before and after main's push | red, then green |

## Rollback

Revert the commit. `box-test-image` becomes Arch-only again, with the entry and
workflow unchanged, and Debian goes back to depending on Docker Hub.
