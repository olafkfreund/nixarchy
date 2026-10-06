---
status: approved
issue: 1199
spec: spec/2026-10-06-1199-release-cadence.md
---

# Plan: the release branch stays close to main without breaking users

## Approved decisions (from the spec)

- `main` stays the dev branch and `release` stays the stable channel. Installed
  machines follow `release` (`installer/mkFlake.nix:36`); only `release.yml`
  moves it, fast-forward only, when a human pushes a `v*` tag. No new branch.
- **Weekly proposal, human tag.** Every Monday 06:00 UTC a workflow updates
  one open issue labelled `release-candidate`: the candidate commit (head of
  the newest successful `nightly.yml` run on `main`), the proposed tag, the
  commit count, `git log --oneline release..<candidate>`, and the commands to
  cut it. Nothing pushes a tag. If `release` is not an ancestor of `main`, the
  issue says so first, in bold (a hotfix was not merged back).
- **Next tag** = `v<vendored Omarchy version>-<N>`: N is one more than the
  highest suffix among tags for that version, or 1 if there are none. The
  version comes from `nix eval --raw .#packages.x86_64-linux.omarchy.version`,
  exactly as `release.yml` "The tag names the Omarchy the flake vendors" does.
- **Guard change.** In `release.yml` "The tag is not behind main", a tag behind
  main is accepted when its commit is the head of the newest successful
  nightly on main. The missing commits are printed as a warning. Any other
  behind-main commit is refused as today. If the nightly lookup fails or
  returns nothing, behaviour is exactly today's. `RELEASE_ALLOW_BEHIND_MAIN`
  is left as it is.
- **Hotfix procedure, docs only:** fix merges to main first; branch
  `hotfix/<issue>` from `origin/release`; cherry-pick; tag `v<ver>-<N+1>` at
  its head and push the tag; then a PR into main containing
  `git merge -s ours <tag>`, merged with "Create a merge commit".
- **Stable boot test, weekly:** `checks.x86_64-linux.stable-session`, which is
  `tests/session.nix` with `nixpkgs-stable` and `home-manager-stable`. Sunday
  night, on `[self-hosted, nixos, kvm, big]`, its own concurrency group,
  `timeout-minutes: 300`. Not in PR CI, not in nightly.
- **Naming:** `nixarchy channel` unchanged. Docs say plainly that it picks
  nixpkgs, and that the nixarchy you get is the `release` branch.
- Cutting a release now is not part of this change.

## Steps

1. **`.github/scripts/release-guard.sh` (new) and `release.yml:114-180`.**
   Move the body of "The tag is not behind main" into a script:
   `release-guard.sh <tag> <tagged-sha> <main-sha>`, reading `NIGHTLY_SHA`
   from the environment (may be empty). Logic, in order: tagged == main → pass;
   tagged not an ancestor of main → notice, pass; tagged == `NIGHTLY_SHA` →
   print the missing commits as `::warning::`, say it is the newest green
   nightly, pass; `RELEASE_ALLOW_BEHIND_MAIN=1` → existing warning, pass;
   otherwise the existing error and exit 1. Keep the existing messages word
   for word where the case is unchanged.
   The step keeps its `git fetch -q origin main` (no `--depth`, the existing
   comment explains why and stays). Before calling the script it sets
   `NIGHTLY_SHA` from
   `gh run list -R "$GITHUB_REPOSITORY" -w nightly.yml -b main -s success -L 1 --json headSha -q '.[0].headSha' || true`
   with `GH_TOKEN: ${{ github.token }}` in the step `env`. Add `actions: read`
   to the top-level `permissions:` block (`release.yml:48-54`).
   → verify by step 2's check, and `actionlint` (as `build.yml:181` runs it).
   Traps: a `--depth` fetch re-shallows the clone and breaks release notes
   (comment at `release.yml:120-139`); `GITHUB_REF_NAME` is a branch on
   dispatch, so use `$TAG` only; the script must be `set -euo pipefail` and
   shellcheck-clean.

2. **`.github/scripts/release-candidate.sh` (new).** Usage:
   `release-candidate.sh <candidate-sha> <omarchy-version>`, run inside a full
   clone with `origin/main`, `origin/release` and tags fetched. Prints the
   issue body (markdown) on stdout, or nothing and exit 0 when
   `origin/release` already contains the candidate. Contents: a bold warning
   line first when `git merge-base --is-ancestor origin/release origin/main`
   is false; the candidate's short sha and subject; the proposed tag; the
   commit count; the `git log --oneline origin/release..<candidate>` list,
   capped at 100 lines with "and N more"; the two commands
   `git tag -a <tag> <sha> -m <tag>` and `git push origin <tag>` in a code
   block. Next-tag logic as in the decisions above, matching tags with
   `^v<version>-[0-9]+$` only.
   → verify by step 3's check.
   Traps: the version contains dots, so escape them in the regex; a line in
   the body starting with `#1234` becomes a heading in GitHub markdown; write
   "Issue #1234" or keep refs mid-line.

3. **`tests/release-scripts.nix` (new) and a `release-scripts` entry in
   `flake.nix` checks, next to `cache-budget` (`flake.nix:2361`).** Same shape
   as `tests/cache-budget.nix`: `pkgs.runCommand` with `bash coreutils git
   gnugrep gnused`, `scripts = ../.github/scripts`. Build a fixture git repo
   (a bare "origin" plus a clone): commits A–B–C–D on main, `release` at A,
   tags `v4.0.4-1` at A and `v4.0.3-2` at an older root commit.
   Guard cases: tag at D (tip) → pass; tag at C with `NIGHTLY_SHA=C` → pass
   and output contains `::warning::`; tag at B with `NIGHTLY_SHA=C` → exit 1;
   tag at B with `NIGHTLY_SHA` empty → exit 1; tag at a commit off main →
   pass. Candidate cases: candidate C → body proposes `v4.0.4-2` and counts 2
   commits; `release` moved to C → empty output; `release` at a commit not on
   main → body starts with the bold warning; version `4.0.5` → proposes
   `v4.0.5-1`.
   → verify by `nix build .#checks.x86_64-linux.release-scripts -L`.
   Traps: `git` in the sandbox needs `HOME` and `user.name`/`user.email`
   set; use `git -c init.defaultBranch=main`.

4. **`.github/workflows/weekly.yml` (new).**
   `on.schedule`: `"0 6 * * 1"` (propose) and `"0 22 * * 0"` (stable session);
   `workflow_dispatch` with a `choice` input `job: [propose, stable-session]`.
   Top-level `permissions: { contents: read }`.
   Job `propose`, `runs-on: ubuntu-latest`, `timeout-minutes: 20`,
   `if: github.event.schedule == '0 6 * * 1' || inputs.job == 'propose'`,
   job `permissions: { contents: read, issues: write, actions: read }`.
   Steps: `actions/checkout@v5` with `fetch-depth: 0`; `git fetch -q origin
   release`; `./.github/actions/setup-nix` (as `build.yml:107` uses it); read
   the version with the `nix eval` above; read the candidate with the
   `gh run list` above; if empty, write "no green nightly on main" to the job
   summary and stop green; run `release-candidate.sh`; if the body is empty,
   close any open `release-candidate` issue with a comment saying `release` is
   current; otherwise `gh label create release-candidate --force`, then edit
   the open issue with that label or create one titled
   "Release candidate: <tag>", using `--body-file`.
   Job `stable-session`, `runs-on: [self-hosted, nixos, kvm, big]`,
   `timeout-minutes: 300`,
   `if: github.event.schedule == '0 22 * * 0' || inputs.job == 'stable-session'`,
   `concurrency: { group: stable-session, cancel-in-progress: false }`.
   Steps: `actions/checkout@v5`;
   `nix build .#checks.x86_64-linux.stable-session --print-build-logs`.
   No cachix push (stable closures are not on the allowlist).
   → verify by `actionlint`, then after merge a `workflow_dispatch` with
   `job: propose` (step in Tests).
   Traps: `github.event.schedule` is the exact cron string, so the `if:` must
   match it character for character; never pass prose through `-b`/`--body`
   on a command line, use files.

5. **`tests/session.nix` and `flake.nix` checks.** Add a `stable ? false`
   argument. Replace `inputs.home-manager.nixosModules.home-manager`
   (`tests/session.nix:135`) with
   `(if stable then inputs.home-manager-stable else inputs.home-manager).nixosModules.home-manager`.
   In the "every binary the seeded config names exists" block
   (`tests/session.nix:1546-1612`), make `expected_absent` contain
   `"hyprland-preview-share-picker"` when stable; on 26.05
   `modules/nixos.nix` leaves the picker out on purpose (see
   `tests/stable-eval.nix`). Render the flag into the test script as
   `stable = ${if stable then "True" else "False"}`.
   In `flake.nix` checks, next to `session` (`flake.nix:2002`), add
   `stable-session = import ./tests/session.nix { inherit inputs; stable = true;
   pkgs = import inputs.nixpkgs-stable { localSystem = system; overlays = [
   self.overlays.default ]; }; inherit (self.packages.${system}) doctor; };`.
   Then run it once on p620. For each further assertion that fails only
   because stable lacks something, gate it on `not stable` with a one-line
   reason, and list it in this plan under "Stable-only skips" in the same
   commit.
   → verify by `nix build .#checks.x86_64-linux.session --dry-run` (unstable
   derivation unchanged apart from the rendered `stable = False` line) and
   `nix build .#checks.x86_64-linux.stable-session -L` passing on p620.
   Traps: `doctor` is built from unstable `pkgs`; if the stable test needs it
   from the stable set, say so here and deviate in this file. Check that
   `stable-session` is not picked up by `generated-checks.sh` or
   `pr-touches-build.sh` into PR CI; if it is, exclude it there. Before
   building on p620, announce on the agent bus (shared host, long build).

6. **`README.md` "Releases" (around line 653) and
   `docs/manual/channels.md`.**
   README: a paragraph "Two kinds of stable": `nixarchy channel` picks
   nixpkgs; the `release` branch picks nixarchy, and every installed machine
   follows it. Then a "Releasing" subsection: the weekly
   `release-candidate` issue, the rule that a release is the newest green
   nightly or main's tip, and the four-step hotfix procedure from the
   decisions above, including why the `-s ours` merge-back matters.
   channels.md: a short note right under the title that this picks nixpkgs,
   linking README "Releases". In the "uncomfortable part" section and the
   table row "tested by nixarchy", replace "evaluation only" with
   "evaluated on every change; a session boot weekly", and rewrite the
   sentence "Nothing starts a VM on stable" to match.
   → verify by the repo's markdown checks (`build.yml` docs job; run locally
   with the same command).
   Traps: `docs/` is a published site (`_config.yml`), so keep relative links
   working; a line starting with `#1199` turns into a heading.

   *Deviation (step 5, recorded with the code):* no `stable-session` check,
   no `stable` argument, no input rewiring in `tests/session.nix`. The first
   design swapped only the `nixpkgs` attribute, so inputs that follow nixpkgs
   (`nixi`, `ai-mirror`, `flake.nix:253,289`) stayed on unstable. The user
   profile then held Python 3.13 and 3.14 and buildEnv refused it, a
   collision no installed machine has. `weekly.yml` now builds the ordinary
   `checks.session` with `--override-input nixpkgs` and
   `--override-input home-manager` set to this flake's locked 26.05 pair, which
   re-resolves every `follows` the way the installer template does. The only
   stable difference left in the test is the share picker, read from the
   package set itself. With no new check, `generated-checks.sh` is unchanged.
   The first build on this path also found #1205, fixed and released as
   v4.0.4-2.
   The override run then booted the VM on 26.05 and found #1211: the SDDM
   greeter's weston (glibc 2.42) cannot load the system Mesa that `main` takes
   from Hyprland's unstable pin (glibc 2.43), so no greeter ever starts. Step
   5's "passes on p620" therefore cannot hold until #1211 is fixed, and the
   weekly job is expected to be red until then. That is the job doing what it
   is for.

   *Review fixes (recorded with the code):* `gh issue close` has no
   `--comment-file`, so the close is now `gh issue comment --body-file` then
   `gh issue close`. release.yml runs the guard script from `$GITHUB_SHA` (the
   workflow's own commit), so a dispatch that re-publishes an older tag still
   finds it. The candidate body says it is valid only until the next nightly
   goes green. Lock nodes are resolved through `root.inputs`. The next-tag
   test covers `-9`/`-10`/`-rc1`. channels.md says the weekly stable job is
   red until #1211. Not fixed: a hotfix on top of a release that already
   contains the newest nightly closes the issue without the merge-back
   warning, until the next nightly goes green.

## Stable-only skips

`hyprland-preview-share-picker`, decided by `pkgs ? hyprland-preview-share-picker`
rather than a flag. Others are added here if the stable run finds them.

## Tests

- `nix build .#checks.x86_64-linux.release-scripts -L` → passes (all cases).
- `nix shell --inputs-from . nixpkgs#actionlint -c actionlint -ignore 'SC[0-9]+:(info|style):'`
  → clean.
- `nix build .#checks.x86_64-linux.stable-session -L` on p620 → passes.
- `nix flake check --no-build` → evaluates.
- After merge: dispatch `weekly.yml` with `job: propose` → one
  `release-candidate` issue proposing the newest green nightly with the next
  tag. Dispatch with `job: stable-session` → green.
- Hotfix walk-through in a scratch clone (no tag pushed): branch from
  `release`, cherry-pick, `git merge -s ours` into main, then
  `git merge-base --is-ancestor origin/release main` is true.

## Rollback

Every change is additive or a single workflow step. Revert the PR. The guard
returns to "tip of main only"; `weekly.yml` disappears; the open
`release-candidate` issue can be closed by hand. No installed machine is
affected: nothing here moves `release`.
