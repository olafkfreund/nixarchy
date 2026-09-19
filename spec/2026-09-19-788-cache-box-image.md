---
status: draft
issue: 788
intent: intent/2026-09-19-788-cache-box-image.md
---

# Spec: a Docker Hub outage does not turn main red

## Design

**One declaration of the pins, used three ways.** `boxImagePins` (archlinux and
debian, `flake.nix:1535`) moves out of the checks' `let` into
`data/box-image-pins.nix`, the same pattern as `data/microvm-templates.nix`.
`checks.box-template` and `checks.box-boot` read it exactly as they read the
local binding today, so their image derivations do not change. A third
consumer is new: one package output per pin,
`packages.x86_64-linux.box-image-<name>`, built with the same
`dockerTools.pullImage` arguments (image name, digest, tag and `sha256`). Same
arguments and same `pkgs` give the **same store path** the checks use, so
whatever the cache holds is exactly what the checks need.

**A new cache group, `boxes`,** in `.github/scripts/cache-allowlist.sh`. It is
read from the data file the way the `runners` group reads
`data/microvm-templates.nix`, so a new template brings its image with no second
edit. It joins the default group list (`omarchy system runners apps boxes`).

**The exception is written down, not slipped in.** The allowlist's header says
an entry belongs only if it would otherwise be *built* (#725). This group is
the first entry whose reason is *availability*: an upstream registry outage
otherwise fails CI. The header gains one paragraph saying so and naming #788,
and the group carries its reason beside it: "the box checks pull these on every
cold runner, and a Docker Hub 502 turned main red (#788)".

**How it reaches the cache: no workflow edit.** Each `build.yml` job pushes its
own group by name (`:313` omarchy, `:1153` apps, `:1267` system). A `boxes`
push from the `box` job would be a workflow edit, and so a human change (§11).
It is not needed: the nightly `repush` job (`nightly.yml:290`) builds and
pushes **every** allowlist entry that `cache-entries.sh` finds missing. So the
images land in the cache by the next nightly, and stay there under the same
eviction protection as the runners. Adding the push to the `box` job is
offered in the PR as an optional follow-up for the owner.

## Alternatives rejected

- **Retrying the pull** (skopeo `--retry-times`, or nix download attempts).
  It reduces red runs but does not remove them: a longer outage still fails.
  It also needs a patch to `dockerTools.pullImage`'s fetcher.
- **Only the default image (archlinux).** Rejected by the owner:
  `box-template` pulls every pin, so debian would still fail during an outage.
- **A registry mirror** (ghcr.io, or our own). That's another external service
  to keep alive, and nothing in this repo manages one.
- **Referencing the images from the checks through `self.packages`.** It isn't
  needed, since identical arguments already give the same store path, and it
  would couple the checks to the package set. Case (b) below proves the paths
  are identical instead.

## Risks

- **Budget.** Two base images (archlinux about 150–200 MiB, debian about
  50 MiB, compressed) count against the 2 GB `cache-budget.sh` share. It is
  measured, and fails loudly if it is over. Every new box template adds its
  image.
- **Digest bumps.** A new pin is a new store path, so there's one cold nightly
  window where it is not cached yet. The window is the same one the runners
  have, and a push from the `box` job would close it (the optional follow-up).
- **Eviction.** The free tier evicts by last download. CI downloads these on
  every box run, which keeps them warm, and the nightly repush restores them
  if they are evicted anyway.
- **Public cache:** these are public Docker Hub base images, redistributed
  under their own terms, the same as Docker Hub serves them. Nothing unfree.

## Verification

- **(a) Cache-only fetch, the §1 proof.**
  `nix build .#box-image-archlinux --max-jobs 0` with nixarchy.cachix.org as a
  substituter and the path absent locally. `--max-jobs 0` forbids even the
  fixed-output fetch, so the image can only come from the cache. **Red today**
  ("…required to build… but max-jobs is 0"), captured for the PR. **Green**
  after the first nightly repush following merge. It's recorded on the issue,
  not claimed in the PR.
- **(b) Same path.** An eval asserting that `packages.x86_64-linux.box-image-<name>`'s
  outPath equals the path each check pulls, for every pin. Break it: change the
  tag in the package output only, and it must fail. It lives in an existing
  cheap check (`checks.box-template` already evaluates the pins), so there is
  no new `checks.<name>`.
- **(c) The group is not empty.** `cache-allowlist.sh boxes` prints one entry
  per pin. Break it: point the group at a missing data file, and the script's
  own "group evaluated empty" guard must exit 2.
- **(d) Budget.** `cache-budget.sh` passes with the new group, and the figure
  goes in the PR.
- `nix fmt -- --ci`, statix, deadnix. `checks.box-template` stays green, and
  its image derivations are unchanged: the same drvPaths as on `main`,
  compared in the same tree (AGENTS.md §5, "you cannot compare closures across
  commits").
