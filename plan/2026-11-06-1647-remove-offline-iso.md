---
status: draft
issue: 1647
spec: spec/2026-11-06-1647-remove-offline-iso.md
coders:
  1: codex  # installer script branches, where a slip reaches a person's disk, with the checks that read them
  2: codex  # the reinstall command's promise changes, with preflights to keep
  3: codex  # two front doors and a release parser, with their fixtures
  4: codex  # the outputs, every reader, and the lists that fail silently if one is missed
  5: codex  # prose across the manual, written from the behaviour above
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

Each step is one commit and must evaluate and pass alone (found by review: a function or output removed before its readers change breaks the tree). The order is fixed. Line numbers are from `main` at `c7a2de9a` or close to it. Locate each edit by its text.

### 1. The installer and the checks that read it (codex)

Remove decision 3's code from `installer/install.sh`. `ask_network`'s branch on the marker, its three failure messages recommending the offline image (`:521`, `:568`, `:590`) and the store-space hint (`:2466`) say one thing. Remove the baked login message and flag in `installer/lib/`. Build the toplevel, then `nixos-install --system` stays.

In the same commit: `tests/installer-store-space.nix` stops extracting `rescue_build` (`:589-601`). `tests/installer-network.nix` retargets its offline Wi-Fi branch (`:102-110`), keeping the unattended cases. `tests/installer-offline-rescue.nix` and `tests/installer-baked-guard.nix` are deleted, with their flake entries and any `claimed` name. Anything else that extracts a removed function follows.

→ verify (Opus): `checks.installer-store-space`, `installer-network`, `installer-answers`, `installer-ui`, `installer-wizard`, `installer-refusal`, `grep-q-pipefail`, `nix flake show`.
Traps: §5 `set -e` inside `$(...)`, and `mapfile < <(cmd)` (§4). A refusal must still print before `format_disk`.

### 2. The reinstall command (codex)

Decision 4 in `pkgs/omarchy/nix-bin/nixarchy-reinstall-iso`: default attr becomes the network one (`:43-67`), the cache verdict (`:351`) always runs, the closure-size preflight (`:239-264`) and the offline advice (`:407`) go. `data/bin-ledger.nix`'s row says the new promise. `tests/reinstall-iso.nix` keeps its assertion that the verdict runs before `nix build` (`:156-171`), and drops its offline ones.

→ verify (Opus): `checks.reinstall-iso`, `bin-ledger`.

### 3. The two front doors (codex)

Decision 6. `installer/try.sh`: the default attr (`:339`), and the parser drops the `.iso.part-*` case (`:199-210`), so an old release gives its network image. `installer/try-nixarchy.sh`: `--full` (`:34`) says it has gone, and the four-part download (`:222`) goes. `tests/try-preflight.nix` (`:122-145`, `:153-198`) and `tests/try.nix` follow.

→ verify (Opus): `checks.try`, `try-preflight`.

### 4. The outputs, every reader, and the lists (codex)

All in one commit, as none of it evaluates apart.

- **Outputs:** `installer/cd.nix` loses decision 2's code and its `offline` argument, and the budget recorded at `:618` changes. `flake.nix` loses `packages.iso` (`:1328`) and `nixosConfigurations.iso` (`:1505`), and `iso-net` stops passing `offline`. `mkUserIso` (`:1767`) accepts `offline` and ignores it. `iso-budget` (`:2884`) measures only `iso-net`. `installer/template/flake.nix` (`:122`, `:141`) keeps only the network outputs. `isoSource` and `reference-hardware` go only if nothing below still reads them.
- **Checks:**

| Check | Do |
|---|---|
| `install-iso`, `reinstall-vm`, `offline-hardware-packages` | Delete the file and its flake entry |
| `tests/iso-wifi.nix:33` | Read `nixosConfigurations.iso-net` |
| `tests/options.nix:2681`, `:4614` | `isoSplash` reads `iso-net`; the two-image values become one |
| `tests/reference-initrd.nix:30` | Compare against `iso-net` |
| `tests/iso-source.nix` | Drop the three-machines assertion and the offline markers (`:57-73`). **Add two:** `system.extraDependencies` holds `inputSources`, and `/etc/nixarchy-iso` is absent |
| `tests/install-iso-net.nix:128`, `:142` | Keep `NOTBAKED`. Rewrite links to the deleted test |
| `tests/install-matrix.py:217`, `tests/install-teardown.py:13`, `:26` | Drop the three offline cells. Name the personal-image hole |
| `tests/generate-config-surface.nix`, `tests/config-warnings.nix` | Keep if `reference-hardware` stays for the reason they state. Say which, in the PR |
| `tests/options.nix`, new case | `mkUserIso` is called with `offline = true` and `false`, and both give a network image |

- **Lists:** `generated-checks.sh`'s `claimed` (`:43`) and `nightly_only` (`:82`). `nightly.yml`: job `install-iso` (`:130`) stops building `#iso` and running `checks.install-iso`, keeps `iso-budget` and `install-iso-net`, and is renamed `install-iso-net`, with `report.needs` (`:613`) and **all four** `needs.install-iso.result` conditions (`:655`) changed together, so a failure is still reported. The `reinstall-vm` job and its `needs` go. `release.yml`: one build (`:214`, `:221`), no split (`:262`), `SHA256SUMS`, outputs (`:295-305`), `:476`, and the notes' "two images" text (`:374`). `.github/scripts/cache-allowlist.sh` if it names anything removed. `.github/ISSUE_TEMPLATE/install.yml:40`.

→ verify (Opus): `nix eval` of `nixosConfigurations.iso-net.config.system.build.isoImage.drvPath`, `nix flake show`, `checks.iso-budget`, `iso-source`, `iso-wifi`, `reference-initrd`, `options-*`, `options-shards`, `actionlint`, and `git grep` for each removed name.
Traps: §5 a module argument cannot have a `?` default, which is why `offline` was always passed. A flake sees only tracked files (§5). §4 a hand-maintained list fails open: `report.needs` is the example. §11 this edits workflows, and the owner has said to merge such PRs.

### 5. Docs (codex)

`README.md:369`, `docs/manual/getting-started.md:29`, `the-iso.md:18`, `:67`, `:108`, `:243`, `try-it-in-a-vm.md:19`, `reinstall-image.md:64`, `:113`, `:140`, `how-this-is-tested.md:151`, `docs/internals/workflows.md:204`, `:356`, `docs/internals/design.md`, `docs/llms.txt:66`, `docs/index.md`, `installer/AGENTS.md`, `tests/AGENTS.md`, and `AGENTS.md` §6's table. `reinstall-image.md` says the new promise plainly: a reinstall needs a network and caches holding the machine's packages, and a package no cache holds is compiled or fails.

→ verify (Opus): `readme-counts.sh`, docs checks in `generated-checks.sh`, and `git grep -il 'offline image\|offline iso\|part-aa'` empty outside `plan/`, `spec/`, `intent/`.

### 6. Prove, review and open the PR (Opus)

All generated checks, then `options-*`, `session`, `installer-refusal`, `iso-wifi`, `reference-initrd`. `install-iso-net` and `iso-budget` when no runner is busy, since this changes them most. `install` in CI, named as not run locally. A fresh `codex review`, read-only.

**Breaks,** on a commit where a check reads `self.rev`, each with a captured reason:

| Break | Must go red |
|---|---|
| `mkUserIso` drops its `offline` tolerance | the new options case |
| Remove `inputSources` from `cd.nix` | `iso-source`'s new assertion |
| Add `/etc/nixarchy-iso` back to `cd.nix` | `iso-source`'s new assertion |
| `iso-budget`'s budget set below the image | `iso-budget` |
| `reinstall` skips its cache verdict | `reinstall-iso` |
| Leave a check in `claimed` with no workflow naming it | `build.yml`'s coverage guard (`:406-425`), run locally |

PR: "The offline ISO goes: releases publish one network image, and reinstall fetches". `Closes #1647`. It links all three artifacts, says Codex did steps 1 to 5, says agy's review was skipped by the owner's choice, names the holes, and carries the release note from the spec. "@codex review". `--auto --squash --delete-branch`.

Then: rebase #1619 and drop its step 6 and the offline sentences of step 7, update #1646, and tag `v4.5.0-1`.

## Tests

| Command | Expected |
|---|---|
| `nix eval .#nixosConfigurations.iso` | fails: gone |
| `nix build .#checks.x86_64-linux.install-iso-net` | passes |
| `nix build .#checks.x86_64-linux.iso-budget` | passes with one image |
| `git grep -n 'nixosConfigurations.iso\b'` | nothing outside `plan/`, `spec/`, `intent/` |

## Rollback

Revert the squash commit. Published releases are untouched. A release cut in between has no offline image and stays that way.
