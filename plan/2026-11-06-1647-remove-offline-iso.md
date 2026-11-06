---
status: draft
issue: 1647
spec: spec/2026-11-06-1647-remove-offline-iso.md
coders:
  1: codex  # installer script branches, where a slip reaches a person's disk
  2: codex  # one module's conditional becoming unconditional, and the flake around it
  3: codex  # the reinstall command's promise changes, with preflights to keep
  4: codex  # checks retargeted or deleted, each of which must still be able to fail
  5: codex  # workflows and lists that fail silently if one is missed
  6: codex  # prose across the manual, written from the behaviour above
reviewers:
  - codex  # the owner dropped agy for now: a fresh Codex read of the diff, independent of the coders
---

# Plan: The offline install machinery goes, and the network image stays

Worktree `/mnt/data/vmtest/wt-1647`, branch `chore/1647-remove-offline-iso`. The owner approved the intent and spec on 2026-11-06, choosing option B.

## Decisions carried from the approved spec

1. `packages.iso`, `nixosConfigurations.iso` and the `offline` argument go. `#iso-net`, its configuration and `/etc/nixarchy-iso-net` keep those names.
2. Out of `installer/cd.nix`: `storeContents`, the offline `extraDependencies`, the offline nix settings, `/etc/nixarchy-iso`, both `/etc/nixarchy-reference-*` markers. Stays: `inputSources`, cache settings, the network marker.
3. Out of `installer/install.sh`: `on_offline_image`, `rescue_build` and its report, the baked choice, `why_not_baked`, the retry, and the `--max-jobs 0` path. **`preflight_build` keeps its `on_net_image` guard exactly:** `checks.install` is markerless and relies on it, and #1646 owns changing it.
4. `nixarchy reinstall iso` is network-only. `--net` stays as an accepted word that changes nothing. Its cache verdict always runs, and the closure-size preflight and "use the offline image" advice go.
5. `mkUserIso` still accepts `offline` and ignores it, so a generated flake already on a machine evaluates. Both old output names give a network image.
6. `#try` and `installer/try-nixarchy.sh` boot the network image. `--full` says it has gone. `--net` stays accepted.
7. Named holes, not closed: nothing installs a personal image end to end once `reinstall-vm` goes, and offline install is gone. `tests/install-matrix.py` and `tests/AGENTS.md` name the first.
8. #1647 lands before #1619. `v4.5.0-1` is tagged after this.

## Steps

Line numbers are from `main` at `c7a2de9a` or close to it. Locate each edit by its text.

### 1. `installer/install.sh`, `installer/lib/` (codex)

Remove decision 3's code. `ask_network`'s branch on the marker, its three failure messages recommending the offline image (`:521`, `:568`, `:590`) and the store-space hint (`:2466`) say one thing. Remove the baked login message and flag in `installer/lib/`. `build the toplevel, then nixos-install --system` stays.

→ verify (Opus): `checks.installer-store-space`, `installer-answers`, `installer-ui`, `installer-wizard`, `installer-refusal`, `grep-q-pipefail`.
Traps: §5 `set -e` inside `$(...)`, and `mapfile < <(cmd)` (§4). A function another check extracts by `sed` must keep its name or that check must change in step 4. A warning on a refusal branch must still print before format_disk.

### 2. `installer/cd.nix`, `flake.nix`, `installer/template/flake.nix` (codex)

Remove decision 2's code, and the `offline` argument with its comment. Remove `packages.iso` (`flake.nix:1328`) and `nixosConfigurations.iso` (`:1505`). `iso-net` stops passing `offline`. `mkUserIso` (`:1767`) keeps accepting `offline` and ignores it. `installer/template/flake.nix` (`:122`, `:141`) keeps only the network outputs. `isoSource` and `reference-hardware` go only if step 4 finds nothing reading them. `iso-budget` (`:2884`) measures only `iso-net`, and its message and the budget recorded in `cd.nix` (`:618`) change.

→ verify (Opus): `nix eval` of `nixosConfigurations.iso-net.config.system.build.isoImage.drvPath`, `checks.iso-budget`, `checks.iso-source`, and `nix flake show`, which fails loudly on a dangling reference.
Traps: §5 a module argument cannot have a `?` default, and it is why `offline` was always passed. A flake sees only tracked files (§5).

### 3. `pkgs/omarchy/nix-bin/nixarchy-reinstall-iso`, `data/bin-ledger.nix` (codex)

Decision 4. Default attr becomes the network one (`:43-67`). The cache verdict (`:351`) always runs. Remove the closure-size preflight (`:239-264`) and the offline advice (`:407`). The ledger row says the new promise.

→ verify (Opus): `checks.reinstall-iso`, `checks.bin-ledger`.

### 4. Checks (codex)

| Check | Do |
|---|---|
| `install-iso`, `installer-offline-rescue`, `installer-baked-guard`, `reinstall-vm`, `offline-hardware-packages` | Delete the file and its flake entry |
| `tests/iso-wifi.nix:33` | Read `nixosConfigurations.iso-net` |
| `tests/options.nix:2681`, `:4604` | `isoSplash` reads `iso-net`; the two-image assertions become one |
| `tests/reference-initrd.nix:30` | Compare against `iso-net` |
| `tests/iso-source.nix` | Drop the three-machines assertion. **Add one:** `system.extraDependencies` holds `inputSources` |
| `tests/install-iso-net.nix:128`, `:142` | Keep `NOTBAKED`. Rewrite links to the deleted test |
| `tests/installer-network.nix` | Retarget its offline Wi-Fi assertions, keeping the unattended ones |
| `tests/reinstall-iso.nix` | Drop offline assertions, keep the network preflight's |
| `tests/installer-store-space.nix` and anything else that extracts a removed function | Follow what step 1 removed |
| `tests/install-matrix.py:217`, `tests/install-teardown.py:13`, `:26` | Drop the three offline cells. Name the personal-image hole |
| `tests/generate-config-surface.nix`, `tests/config-warnings.nix` | Keep if `reference-hardware` stays for the reason they state. Say which, in the PR |
| `tests/options.nix`, new case | `mkUserIso` accepts `offline = true` and `false`, and both give a network image |
| `installer/try.sh`, `installer/try-nixarchy.sh`, `tests/try.nix` | Decision 6 |

→ verify (Opus): each named check, `options-*`, `options-shards`, `reference-initrd`, `iso-wifi`.
Traps: §1 a check whose fixture changed may no longer be able to fail, so each new assertion gets a break. §4 a new `checks.<name>` is run by the generated step, and a deleted one must leave every list.

### 5. Workflows and lists (codex)

`nightly.yml`: job `install-iso` (`:130`) stops building `#iso` and running `checks.install-iso`, and keeps `iso-budget` and `install-iso-net`. Rename it `install-iso-net`, and change `report.needs` (`:613`) and **all four** `needs.install-iso.result` conditions (`:655`) together, so a failure is still reported. Remove the `reinstall-vm` job and its `needs`. `release.yml`: one build (`:214`, `:221`), no split (`:262`), `SHA256SUMS`, outputs (`:295-305`), `:476`, and the notes' "two images" text (`:374`). `generated-checks.sh`: `claimed` (`:43`), `nightly_only` (`:82`). `.github/scripts/cache-allowlist.sh` if it names anything removed. `.github/ISSUE_TEMPLATE/install.yml:40`.

→ verify (Opus): `actionlint`, `checks.check-coverage` or the equivalent guard, and `git grep` for each removed name.
Traps: §4 a hand-maintained list fails open, and #1405's `report` job is the example. §11 this edits workflows, and the owner has said to merge such PRs.

### 6. Docs (codex)

`README.md:369`, `docs/manual/getting-started.md:29`, `the-iso.md:18`, `:67`, `:108`, `:243`, `try-it-in-a-vm.md:19`, `reinstall-image.md:64`, `:113`, `:140`, `docs/llms.txt:66`, `docs/index.md`, `installer/AGENTS.md`, `tests/AGENTS.md`, `AGENTS.md` §6's table, `docs/internals/design.md`. `reinstall-image.md` says the new promise plainly: a reinstall needs a network and caches holding the machine's packages, and a package no cache holds is compiled or fails.

→ verify (Opus): `readme-counts.sh`, docs checks in `generated-checks.sh`, and `git grep -il 'offline image\|offline iso\|part-aa'` empty outside `plan/`, `spec/`, `intent/`.

### 7. Prove, review and open the PR (Opus)

All generated checks, then `options-*`, `session`, `installer-refusal`, `iso-wifi`, `reference-initrd`. `install-iso-net` and `iso-budget` when no runner is busy, since they are the ones this changes most. `install` in CI, named as not run locally. A fresh `codex review`, read-only.

**Breaks,** on a commit where a check reads `self.rev`, each with a captured reason:

| Break | Must go red |
|---|---|
| `mkUserIso` drops its `offline` tolerance | the new options case |
| Remove `inputSources` from `cd.nix` | `iso-source`'s new assertion |
| `iso-budget`'s budget set below the image | `iso-budget` |
| `reinstall` skips its cache verdict | `reinstall-iso` |
| A check entry left in `flake.nix` with no workflow claiming it | `build.yml`'s coverage guard, locally through `generated-checks.sh` |
| Add `/etc/nixarchy-iso` back to `cd.nix` | `iso-source` or a new assertion that it is absent; add one if none |

PR: "The offline ISO goes: releases publish one network image, and reinstall fetches". `Closes #1647`. It links all three artifacts, says Codex did steps 1 to 6, says agy's review was skipped by the owner's choice, names the holes, and carries the release note from the spec. "@codex review". `--auto --squash --delete-branch`.

Then: rebase #1619 and drop its step 6 and offline sentences of step 7, close #1646's overlap, and tag `v4.5.0-1`.

## Tests

| Command | Expected |
|---|---|
| `nix eval .#nixosConfigurations.iso` | fails: gone |
| `nix build .#checks.x86_64-linux.install-iso-net` | passes |
| `nix build .#checks.x86_64-linux.iso-budget` | passes with one image |
| `git grep -n 'nixosConfigurations.iso\b'` | nothing outside `plan/`, `spec/`, `intent/` |

## Rollback

Revert the squash commit. Published releases are untouched. A release cut in between has no offline image and stays that way.
