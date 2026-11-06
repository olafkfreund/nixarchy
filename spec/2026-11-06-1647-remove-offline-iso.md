---
status: draft
issue: 1647
intent: intent/2026-11-06-1647-remove-offline-iso.md
---

# Spec: The offline install machinery goes, and the network image stays

The owner approved the intent on 2026-11-06, choosing option B: not only the published image, but the machinery behind it.

## Design

**One image.** `packages.iso` and `nixosConfigurations.iso` go. `#iso-net`, its configuration and `/etc/nixarchy-iso-net` stay under those names (intent, decision 2).

**`installer/cd.nix`:** the `offline` argument goes, and the module always builds what `offline = false` builds today. Out: `isoImage.storeContents`, the offline `extraDependencies`, the offline nix settings, `/etc/nixarchy-iso`, and both `/etc/nixarchy-reference-*` markers. Stays: `inputSources`, which evaluates the generated flake on the network image too, the cache settings, and the network marker. About 250 to 330 lines, by Codex's reading.

**`installer/install.sh`:** out go `on_offline_image`, `rescue_build` and its incomplete-image report, the baked choice, `why_not_baked`, the retry, and the `--max-jobs 0` copied-system path, about 220 to 280 lines. `ask_network`'s branch on the marker, the three failure messages recommending the offline image, and the store-space hint are rewritten to say one thing. `preflight_build` stays exactly as it is, including its `on_net_image` guard: `checks.install` is markerless and relies on it, and #1646 owns changing it.

**`nixarchy reinstall iso` becomes network-only.** It keeps `--net` as an accepted word that changes nothing, because docs and habits name it, and its default becomes what `--net` builds today. Its cache verdict now always runs. The closure-size preflight and the "use the offline image" advice go. `mkUserIso` loses its `offline` default, and `installer/template/flake.nix` keeps only the network outputs. **The promise changes, and the manual says so plainly:** a reinstall needs a network and caches holding the machine's packages, and a package no cache holds is compiled during the install, or fails.

**Checks:**

| Check | Outcome |
|---|---|
| `install-iso`, `installer-offline-rescue`, `installer-baked-guard`, `reinstall-vm` | Deleted, with their flake entries. `reinstall-vm` proves "fetch nothing, build nothing", which is no longer the contract |
| `iso-budget` | Measures only `iso-net`; its message and the budgets recorded in `cd.nix` change |
| `iso-wifi` | Reads `nixosConfigurations.iso-net` |
| `iso-source` | Its assertion that the image carries three reference machines goes. It keeps asserting what the network image needs to evaluate the flake |
| `install-iso-net` | Stays, and now also covers a personal network image's route. Its links to the deleted test are rewritten |
| `installer-network`, `reinstall-iso`, `install-matrix.py`, `install-teardown.py`, `try` | Retargeted. The matrix loses its three offline cells |
| `install`, `free-space`, `install-encrypted`, `install-seed-shape` | Unchanged: their seeded closures are the test's own, not the image's |

**Lists that change together (§4):** `flake.nix`'s check lists, `generated-checks.sh`'s `claimed` and `nightly_only`, `nightly.yml`'s job and `report.needs` and all four `needs.install-iso.result` conditions, `release.yml`'s two builds and its split, checksum, outputs and notes, the README, `docs/manual/getting-started.md`, `the-iso.md`, `try-it-in-a-vm.md`, `reinstall-image.md`, `docs/llms.txt`, and the issue template. `isoSource` and `reference-hardware` go only if nothing else reads them.

**`#try`:** boots the network image by default. `--net` stays accepted. Its release parser drops the `.iso.part-*` case, so a person pointing it at an old release gets the network image of that release.

## Order

#1647 lands before #1619. Otherwise #1619 adds a gate this removes. #1619 then drops its plan's step 6 entirely and the offline sentences of step 7, and keeps steps 1 to 5. #1621 is independent, whichever lands later rebases. `v4.5.0-1` is tagged after this.

## Coexistence

Nothing here is a NixOS option a user sets, so no fixture applies (§14). A generated flake already on a machine still names `reinstall-iso` and per-host offline outputs, and those are the person's own files. They keep evaluating until they update their nixarchy input, at which point `mkUserIso` must still accept the old `offline` argument and ignore it, or a rebuild would fail on a stale flake. A case in `tests/options.nix` holds that.

## Alternatives rejected

- **Only the published image (option A).** The owner chose B: it removes the machinery, not only the download.
- **Renaming `#iso-net` to `#iso` now.** Touches the marker and every doc, for no saving. #1646 may change it.
- **Removing `--net` from the reinstall command and `#try`.** Breaks scripts and docs for nothing.

## Risks

- **A machine with no working network can't install or reinstall.** Accepted by the owner, and announced. A personal package no cache holds is compiled or fails, and the command's existing preflight warns before building.
- **`checks.install` has its own seeded closure.** Removing the image's must not touch it. `install-seed-shape` holds that.
- **A stale generated flake:** the coexistence case above.

## Verification

- `checks.install`, `free-space`, `installer-refusal` and `install-iso-net` pass. `install-iso-net` and `iso-budget` are nightly, run by §6's tier. The nightly's job still reports failure.
- §1: put back `offline` handling in `mkUserIso` without the stale-flake tolerance, and the options case fails. Make `iso-budget` measure a missing image, and it fails. Restore a `nixarchy-iso` marker and `checks.install-iso-net`'s `NOTBAKED` assertion fails. Add `iso` back to a workflow, and the check-coverage guard names it.
- `git grep` for each removed name returns nothing outside `plan/`, `spec/` and `intent/`.
- Release dry run: `release.yml` builds one image, with no `split`, under the size limit.

## Release note, for the Discussions post

The offline ISO is gone. Releases now publish one network image of about 2 GB, and installing needs a network. `nixarchy reinstall iso` also fetches the system when it reinstalls, so a machine you would rebuild from it needs a network and caches holding its packages, and anything no cache holds is compiled during the install. Images you have already downloaded keep working.
