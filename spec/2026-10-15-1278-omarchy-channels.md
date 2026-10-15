---
status: approved
issue: 1278
intent: intent/2026-10-15-1278-omarchy-channels.md
---

# Spec: Omarchy edge and dev channels, separate from the nixpkgs channel

## Design

### The model: an Omarchy channel is the nixarchy branch the machine follows

Installed machines already follow a nixarchy branch. `installer/mkFlake.nix:42`
writes `nixarchy.url = "github:olafkfreund/nixarchy/release"` into the user's
`flake.nix` (`installer/template/flake.nix:60-66`), and
`.github/workflows/release.yml:518` ships stable by moving that branch. A
channel is therefore a branch, which is how nixpkgs' own channels work.

| Channel | Where it lives | What the user's `flake.nix` says |
|---|---|---|
| stable | `release`, unchanged | `nixarchy.url = "github:olafkfreund/nixarchy/release";` |
| edge | a new `edge` branch | `nixarchy.url = "github:olafkfreund/nixarchy/edge";` |
| dev | `edge`'s patch set over the user's checkout | the edge URL, plus a top-level `omarchy = { url = "git+file:///home/<u>/omarchy"; flake = false; };` and `inputs.omarchy.follows = "omarchy";` inside the `nixarchy` block |

**The two axes touch disjoint lines:**

- nixpkgs: the `nixpkgs.url` line and the `inputs.home-manager.url` line;
- Omarchy: the `nixarchy.url` line, plus the two dev lines when on dev.

So any pairing is one value per axis, and switching one never edits the
other's lines. The six pairings are:

- unstable or 26.05 nixpkgs,
- times stable, edge or dev Omarchy.

**Edge is ahead of main on purpose; the reverse is not allowed.** `edge` is
`main` plus:

- `omarchy.url` pinned to a `quattro` commit SHA;
- `omarchyVersion = "edge-<YYYYMMDD>-<sha7>"`;
- **carry commits** that adapt nixarchy to `quattro`.

What carry commits hold:

- patches dropped or rewritten;
- data tables updated (`data/bin-ledger.nix`, `data/skill-parity.nix`,
  `data/apps.nix`, `data/menu-exceptions.nix`);
- check adjustments, e.g. `tests/panel-loaders.nix`'s negative control, and
  `pkgs/review.sh:300` accepting a SHA pin;
- packages `quattro`'s session needs.

Two known first carries: `1153-owe-video-backgrounds.patch` and
`1155-panel-loaders-kept.patch` are fixes backported from `quattro`, so they
cannot apply to `quattro` itself.

**`main` gains no version conditionals.** When a stable tag catches up, the
carry is absorbed by the normal merge of `main` into `edge`.

**`edge` only fast-forwards.** Each run merges `origin/main` into the current
`edge`, never rebases. A history-rewriting push is ruled out for two reasons:

- CLAUDE.md §11 forbids it on a shared branch without a human;
- it would orphan the revisions users have already locked.

### Publishing edge: `.github/workflows/omarchy-edge.yml`

Daily, plus `workflow_dispatch`.

1. **`prepare`** (hosted `ubuntu-latest`, 45 min, the same budget as
   `omarchy.yml`):
   - Check out `edge`, or `main` on the first run.
   - Merge `origin/main`. A conflict fails the run and names the file.
   - Resolve the `quattro` tip SHA through the authenticated API, and refuse an
     empty answer (the lesson `omarchy.yml:54` already carries).
   - Rewrite the URL and the version literal; prove the two agree the way
     `omarchy.yml:84-98` does.
   - Run `nix flake update omarchy`, then `nix build .#omarchy`.
   - Run the cheap checks: `menu-verbs`, `bin-ledger`, `skill-parity`,
     `review-pins`, `panel-loaders`, `stable-eval` and `options`.
     - `stable-eval` is the 26.05+edge pairing at evaluation time.
     - `options` is allowed on a hosted runner: §6 limits it on p620 only.
   - Write the briefings from `omarchy.yml`'s scripts (`omarchy-package-delta.sh`,
     `omarchy-config-delta.sh`, `omarchy-patched-files.sh`), comparing against
     `release`'s pin.
   - Push the result to `refs/heads/edge-candidate`.
   - **Skip the run** when neither the `quattro` SHA nor `origin/main` moved
     since `edge`'s head.
2. **`verify`** (self-hosted):
   - Wait until `gh run list` shows nothing else in flight (the §6 tier rule
     for VM checks).
   - Build `session`, `coexist` and `plugin` on `edge-candidate`.
   - Only if all three are green, run `.github/scripts/edge-promote.sh`, which
     **fast-forwards** `edge` to the candidate. It refuses anything that is not
     a descendant of the current remote `edge`, and refuses if `edge` moved
     since `prepare` read it.
3. **Failure reporting:**
   - Either job failing updates one rolling issue labelled `omarchy-edge`.
     It names the step, the first failing check, the patch anchor or reject
     from the build log, and the package delta.
   - The issue is commented on only when the failure signature changes, and is
     closed by the run that next promotes.
   - The `omarchy-edge` label is a repository-setting change (§11). The PR asks
     you to create it; the workflow does not create it.
4. **Weekly boot of 26.05+edge:** `weekly.yml`'s existing "Boot a session on
   nixos-26.05" step (`:107`) gains a second invocation on `ref: edge`, using
   the same `--override-input` pair.
5. **Cache:** nothing is pushed. No `cachix-push.sh`, neither `--proof` nor
   closures. Edge shares every derivation with `main` except `.#omarchy` and
   what depends on it, so users substitute the rest from the existing caches
   and build the Omarchy tree locally (minutes).

### Switching: `nixarchy-channel omarchy`

`pkgs/omarchy/nix-bin/nixarchy-channel` gains a subcommand. It goes in the
existing script rather than a new one, so both axes share one implementation
of the file-safety rules.

```
nixarchy-channel omarchy                       # report
nixarchy-channel omarchy stable|edge
nixarchy-channel omarchy dev [PATH]            # PATH defaults to ~/omarchy
nixarchy-channel omarchy --current             # prints stable|edge|dev|custom
nixarchy-channel --current                     # nixpkgs: stable|unstable|custom
```

The existing nixpkgs forms keep their syntax and behaviour. `--current` is new
on both axes, for the menu's check marks and the delegating scripts.

**Rules, carried over from the nixpkgs half:**

- **Read the intent, not the lock.** Classify from `flake.nix`:
  - a top-level `omarchy` input with `git+file:` and the `follows` line → `dev`;
  - `…/nixarchy/edge` → `edge`;
  - `…/nixarchy/release` or a bare `github:olafkfreund/nixarchy` → `stable`;
  - anything else → `custom`.

  A user who pinned their own fork is told so and refused, never rewritten.
- **Only lines nixarchy wrote are rewritten.** The match is anchored to the
  `nixarchy` block, the way the home-manager insertion already is (`:202-213`).
  A reshaped block refuses and prints the edit.
- **Backup, checksum, restore:** `flake.nix.pre-channel`; a `cksum` before and
  after, so a sed that matched nothing is caught; a failed re-lock restores
  the backup and says so.
- **Re-lock only what moved:** `nixarchy` for stable/edge, plus `omarchy` for
  dev.
- **Dev refuses** a path with no `.git`, or one that lacks `bin/` and
  `default/` and `shell/` (upstream's own test, `omarchy-channel-set:24-33`).
  It warns that uncommitted edits are not built, because `git+file:` locks a
  commit.
- **Leaving dev** removes both dev lines.
- **Ends by printing the rebuild command.** It does not rebuild, matching the
  nixpkgs half.

**The upstream channel scripts delegate** (`pkgs/omarchy/default.nix`):

- `omarchy-channel-current` → `exec nixarchy-channel omarchy --current`
- `omarchy-channel-set` → `exec nixarchy-channel omarchy "$@"`

`rc` is refused with a one-line explanation. Both entries in
`data/bin-ledger.nix` move from `vendor` to `patch`, and `omarchy-channel-set`
loses its `pacman` note.

**`omarchy-update`** (`pkgs/omarchy/nix-bin/omarchy-update:194-217`): when the
machine is on dev, updating nixarchy also re-locks `omarchy`. Otherwise new
commits in the checkout would never be built.

### Menu: two groups

In `modules/apps.nix:635-680`:

- **`update.channel`** becomes the Omarchy channel:
  - rows `stable`, `edge` and `dev`, each running
    `nixarchy-channel omarchy <x>` in the floating terminal;
  - `rc` keeps `when = "false"`;
  - check marks come from upstream's own
    `[[ $(omarchy-channel-current) == x ]]`, which the generator already
    inherits (`modules/apps.nix:961`) and which becomes true once the script
    delegates.
- **`update.nixpkgs`** is a new parent with `stable` and `unstable` rows. These
  carry today's `nixarchy-channel stable|unstable` actions and descriptions,
  with explicit
  `checked = "[[ $(nixarchy-channel --current) == stable|unstable ]]"`.

### Reporting

- **Doctor** (`pkgs/doctor.sh:661-708`) adds an `omarchy-channel` line beside
  the nixpkgs one. It uses the same classifier: it calls
  `nixarchy-channel omarchy --current`, with no second parser. Dev also names
  the checkout path.
- **`nixarchy-version`** appends the channel when it is not stable. The
  version string already carries edge's date (`edge-YYYYMMDD-<sha>`), so a
  stalled edge shows its age without a new mechanism.

### Docs

- `docs/manual/channels.md` gets a section on the two axes, with the six
  pairings, the dev loop (commit in `~/omarchy`, then
  `omarchy-update --nixarchy`) and rollback (`nixarchy-channel omarchy stable`,
  or the previous generation).
- `docs/manual/updates.md` links to it.

### Coexistence

No change here sets a NixOS option a user might also set, and the module
gains no option. Everything is:

- a script editing the user's own `flake.nix` under the existing rewrite rule;
- menu rows inside `mkIf cfg.enable`.

Mode A is untouched and `checks.options` covers it. So **no fixture in
`tests/coexistence/fixtures.nix`**: §14 asks for a fixture where an option can
collide, and none can.

The one flake-level collision is a user flake that already has a top-level
input named `omarchy`. Dev refuses it as `custom` rather than editing it.

### Answers to the intent's open questions

1. **Where edge lives:** a branch (above).
2. **Dev's shape:** a rebuild from a `git+file:` input, not a live link. A link
   bypasses the 144 `--replace-fail` edits that make Omarchy run on NixOS.
3. **Edge-only packages:** only what `quattro`'s session and the gating checks
   need, found by the package delta and the boot checks. `gliff`, `owe` and
   `owe-lockfeed` are already packaged (`flake.nix:897-904`). The fcitx5
   addons, `ffmpeg` and `vi` are in nixpkgs.
4. **A stalled edge:** visible in `nixarchy-version` through the date in the
   version string, and to maintainers through the rolling issue. No timer, no
   warning.

## Alternatives rejected

- **A second flake input (`omarchy-edge`) on `main`, picked by an option.**
  - One derivation cannot carry both patch sets: there are 144 exact
    replacements and 5 zero-fuzz patches, all fitting one revision.
  - Every user's lock would grow by an input they don't use.
  - `nixi` and `nixarchy-menu` follow exactly one `omarchy`.
- **Rebase `edge` daily and force-push it with `--force-with-lease`** (agy's
  proposal). It keeps carry commits tidy, but a force-push to a shared branch
  needs a human each time (§11), and it orphans the revisions users have
  locked.
- **Dev as a nested override, `nixarchy.inputs.omarchy.url = "git+file:…"`.**
  Whether `flake = false` survives a nested override was not established, and
  a reviewer flagged it. The top-level input plus `follows` is the documented
  shape; the verification below proves it before it is relied on.
- **Dev as a live `OMARCHY_PATH` link, as upstream does.** It runs unpatched
  Arch scripts on NixOS.
- **A state file, `/etc/nixarchy/omarchy-channel`, written from
  `passthru.channel`.** It describes the running build, not the choice. It
  cannot tell dev from edge, because the version string is the branch's in
  both. And it disagrees with the flake between a switch and a rebuild.
- **Reading the fontconfig file through `cfg.package`** instead of
  `inputs.omarchy` (`modules/nixos.nix:2161`). That would be
  import-from-derivation, which `modules/AGENTS.md` rejects. `inputs.omarchy`
  already follows the dev override.
- **Reusing `nixarchy channel stable|unstable` for Omarchy.** Those words mean
  nixpkgs today (#529), and the owner wants the axes kept separate.
- **rc.** Out of scope by decision.

## Risks

- **Edge cannot publish until `quattro` boots.** The last recorded `quattro`
  build gave `coexist` and `plugin` a black desktop, cause unknown. Seeding
  `edge` includes that investigation, and the gate holds `edge` back until it
  passes. Users see nothing in the meantime, because the switcher ships after
  the first publish.
- **Upstream churn will turn edge's gates red often.** By design: `edge` stops
  rather than shipping breakage. The rolling issue keeps the noise out of PRs
  and the bus.
- **p620 load.** Three VM checks a day:
  - start only when nothing else is in flight;
  - `concurrency` cancels a superseded edge run;
  - the skip rule avoids reruns when nothing moved.

  Mitigation if they still collide: drop to every other day.
- **26.05+edge may need newer packages than 26.05 has.** `stable-eval` daily
  and the weekly boot catch it; the fix is a carry commit in the overlay.
- **Merging `main` into `edge` can conflict** in files the carry commits
  touch, `pkgs/omarchy/default.nix` most of all. The run fails and names the
  file; a human resolves it on `edge`.
- **A dev user's uncommitted edits are not built.** The switcher and the docs
  say so. This is the cost of not using a live link.
- **Branch protection on `edge` is unverified.** `GITHUB_TOKEN` may need push
  rights on that ref. Checked before the workflow is merged.

## Verification

Each new or changed check is shown failing on the broken tree, with the
failure captured for the PR (§1).

| Check | Proves | Fails when |
|---|---|---|
| `tests/channel.nix`, extended | all six pairings switch without touching the other axis; `--current` on both axes; refusal of `custom` and of a bad dev path; backup restored after a failed re-lock; delegation by `omarchy-channel-set`/`-current` | the subcommand is removed, or a rewrite touches the other axis's line |
| `tests/menu-verbs.nix`, extended | the menu's `nixarchy-channel omarchy <x>` verbs exist; the generated `update.channel.*` and `update.nixpkgs.*` rows carry the intended `action` and a non-empty `checked` | a row keeps the old nixpkgs action, or loses its `checked` |
| `bin-ledger` | the two upstream scripts are classed `patch` | the patch is reverted |
| `tests/edge-promote.nix` (new, `runCommand`, local bare remote) | a red gate leaves `edge`; a non-fast-forward candidate is refused; a stale remote head is refused; a green candidate advances `edge` | the ancestry or lease test is removed |
| dev override (new, scratch flake from the real installer template, evaluation only) | with dev on, `nixarchy`'s Omarchy source, `nixi`'s and `nixarchy-menu`'s are all the checkout | the `follows` line is dropped |
| `omarchy-edge.yml` gates | `edge` moves only after `.#omarchy`, the cheap checks, `session`, `coexist` and `plugin` pass | exercised by the first seeded run |
| end to end | `nixarchy-channel omarchy edge` on a scratch copy of an installed flake, then the toplevel builds | — |

The two workflow changes (`omarchy-edge.yml`, `weekly.yml`) are CI-gate
changes. A human merges them (§11), and the PR says so.
