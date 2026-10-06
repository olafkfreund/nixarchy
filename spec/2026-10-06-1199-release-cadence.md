---
status: approved
issue: 1199
intent: intent/2026-10-06-1199-release-cadence.md
---

# Spec: the release branch stays close to main without breaking users

## Correction to the intent

The intent says a fix cannot ship on its own. It mostly can already.
`release.yml` "The tag is not behind main" only refuses a tag that is an
**ancestor** of main. A tag on a commit that is not on main (a hotfix) gets a
notice and continues. "Move the release branch to this tag" fast-forwards
`release` to any descendant. So the hotfix path needs a written procedure and
one safeguard, not new machinery.

A second finding: `RELEASE_ALLOW_BEHIND_MAIN` cannot be reached. The step
reads it from the shell environment, and nothing (no dispatch input, no
`env:`, no repository variable) ever sets it. Today the only commit that can
be released from main is main's tip.

## Design

Decisions for each open question in the intent. Each one is a recommendation
for this review to accept or change.

### 1. Cadence: weekly proposal, human tag

Every Monday a workflow proposes a release. A human decides and pushes the
tag. A week bounds how far `release` can fall behind, and keeps each release
to roughly 70 commits instead of 305. Nothing pushes a tag automatically
(intent constraint).

### 2. Proposal: one issue, updated in place

New workflow `.github/workflows/weekly.yml`, `schedule` (Monday 06:00 UTC,
after the 03:00 nightly) plus `workflow_dispatch`. Job `propose`, on
`ubuntu-latest`, `permissions: { contents: read, issues: write, actions: read }`:

1. Candidate = `headSha` of the newest **successful** `nightly.yml` run on
   `main` (`gh run list -w nightly.yml -b main -s success -L 1`).
2. If `release` already contains the candidate, do nothing.
3. Next tag = `v<vendored Omarchy version>-<N>`, where N is one more than the
   highest suffix among existing tags for that version, or 1 if there are none.
   The version is read the same way `release.yml` "The tag names the Omarchy
   the flake vendors" reads it, so the two cannot disagree.
4. Open or edit the single open issue labelled `release-candidate` with the
   candidate commit, the proposed tag, the commit count, the
   `git log --oneline release..<candidate>` list, and the two commands to
   cut it (`git tag -a <tag> <sha>`, `git push origin <tag>`).
5. **Safeguard:** if `release` is not an ancestor of `main`, the issue says
   so first, in bold. That state means a hotfix was never merged back, and the
   next normal release cannot fast-forward `release` (see 3).

### 3. Releasing a nightly-proven commit, not main's tip

Change the guard in `release.yml`: a tag that is behind main is **accepted**
when the tagged commit is the `headSha` of the newest successful nightly run
on main. The missing commits are still listed, as a warning instead of an
error. Any other behind-main commit is still refused, so the v4.0.2-7 case (an
arbitrary older commit tagged while a tested fix sat on main) still fails.
Commits after the newest green nightly have not been nightly-tested, so leaving
them out is the point of the rule.

The job gets `actions: read` for the query. `RELEASE_ALLOW_BEHIND_MAIN` stays
as it is, out of scope (see Risks).

### 4. Hotfix: branch off release, tag, merge back with `-s ours`

Documented in `README.md` "Releases", with no workflow change:

1. The fix merges to `main` first, as usual.
2. `git switch -c hotfix/<issue> origin/release`, then cherry-pick it.
3. Tag the branch head `v<version>-<N+1>` and push the tag. `release.yml`
   builds it; the guard passes (not on main); `release` fast-forwards (the
   commit descends from it).
4. Merge back: a PR into `main` containing
   `git merge -s ours <tag>`, merged with **"Create a merge commit"** (allowed
   on this repository). Main's tree is unchanged, since it already has the
   fix, and `release` becomes an ancestor of main again.

Skipping step 4 does not break users. It makes the next normal release fail
to move `release` (the existing step warns and leaves it alone). The weekly
issue flags it before that happens (2.5).

### 5. Stable nixpkgs boot test: weekly

A second job in `weekly.yml`, `stable-session`, on
`[self-hosted, nixos, kvm, big]`, Sunday night (its own `schedule` entry, so
Monday's proposal sees a fresh result). It runs a new check
`checks.x86_64-linux.stable-session`: `tests/session.nix` instantiated with
`nixpkgs-stable` and `home-manager-stable` instead of the unstable pair.
Weekly, not nightly: stable closures are not in nixarchy.cachix, so the first
run builds a lot locally. Its own concurrency group, so it never waits behind
or blocks `nightly`. `stable-session` is not added to PR CI.

`docs/manual/channels.md`: "tested by nixarchy: evaluation only" becomes
"evaluation on every change; a session boot weekly". The paragraph that says
nothing starts a VM on stable is updated to match.

### 6. Naming: docs only

`nixarchy channel stable|unstable` stays. It mirrors Omarchy's own
**Update ▸ Channel**, and renaming it breaks muscle memory and the menu. Two
doc edits:

- `docs/manual/channels.md`, at the top: this chooses your **nixpkgs**.
  Which nixarchy you get is the `release` branch, and every installed machine
  already follows it.
- `README.md` "Releases": one paragraph naming both, with a link each way.

### 7. Cutting a release now

Not part of this change. On 2026-10-06 the newest green nightly (`d1afbdda`)
is one commit behind main (`496e24b7`), so today's guard refuses it. Either
tag main's tip after the next green nightly, or wait for 3 to land.

## Alternatives rejected

- **A separate `dev` branch.** `main` already is one, and `release` is the
  stable channel installed machines follow. A third branch adds merges and no
  protection.
- **Auto-tagging on a green nightly.** Ships to every user with no human in
  the loop. The intent rules it out.
- **Wiring `RELEASE_ALLOW_BEHIND_MAIN` as a dispatch input.** A general
  override is the opposite of 3, which accepts exactly one commit for a
  stated reason. It also does not cover a tag push.
- **Hotfix by PR into `release`.** Merging a PR moves `release` without a tag
  and without `release.yml`, so users would get a commit with no ISO, no
  notes, and no checks.
- **Hotfix without merge-back, force-moving `release` next time.** The
  existing rule that `release` never moves backwards exists so a machine is
  never downgraded. Relaxing it is a bigger risk than one merge commit.
- **Renaming `nixarchy channel`.** It breaks users and the menu to fix a word
  that the docs can fix.
- **Stable session test on every PR or nightly.** The intent's cost
  constraint; it can move to nightly once weekly runs show its real time.

## Risks

- **The nightly lookup is wrong or empty** (API error, no green run in days).
  The guard then falls back to today's rule and refuses behind-main tags, so
  the failure is "cannot release an older commit", never "released the wrong
  commit". The weekly job says "no green nightly" instead of proposing one.
- **`tests/session.nix` asserts unstable-only behaviour**, for example the
  screen-share picker that `modules/nixos.nix` drops on 26.05. The stable
  instance needs a `stable` argument to skip those assertions. The plan names
  each one.
- **First stable build is long** on p620/p510, uncached. It shares the pool
  with nightly and installs. Sunday night, separate concurrency group, and a
  timeout of 300 minutes, which the plan revisits after the first run.
- **Republishing an old tag** through `workflow_dispatch` is already refused by
  the guard today, because the hatch cannot be reached. Unchanged by this
  spec; noted so nobody thinks 3 caused it.
- **The weekly issue is ignored.** That is the state today; the issue makes it
  visible, it cannot make it happen.

## Verification

- `actionlint` on `release.yml` and `weekly.yml`.
- Guard logic as a script under `.github/scripts/` with a small test run on
  three fixtures: tip of main (pass), the green-nightly commit behind main
  (pass, warning), another behind-main commit (fail).
- `weekly.yml` `propose` run by `workflow_dispatch` on the branch: it opens
  the `release-candidate` issue with `d1afbdda` (or the then-newest green
  nightly) and proposes the right next tag.
- `nix build .#checks.x86_64-linux.stable-session` passes on p620 once,
  by hand, before the schedule is trusted.
- Hotfix procedure walked through once in a scratch clone: branch from
  `release`, cherry-pick, `merge -s ours` back, then
  `git merge-base --is-ancestor origin/release <main>` is true. No tag is
  pushed in that walk-through.
- Doc edits pass the repository's markdown checks.
