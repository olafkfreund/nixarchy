---
status: approved
issue: 897
intent: intent/2026-09-22-897-codex-duplicate-skills.md
---

# Spec: Codex lists every nixarchy skill twice

## Facts this design rests on

Measured 2026-09-22.

- **What Codex reads.** Codex's own documentation lists one user-scope skill
  directory, `$HOME/.agents/skills` (plus repo `.agents/skills`,
  `/etc/codex/skills` and bundled skills). It does not mention
  `~/.codex/skills`. The binary still reads it: Codex 0.155.1 and 0.151.0
  both contain `.agents/skills` and `.codex/skills` as skill paths. So
  `.codex` is a legacy location Codex still honours.
- **Codex does not deduplicate.** From the docs: "If two skills share the
  same `name`, Codex doesn't merge them; both can appear in skill selectors."
  So the duplicate is visible to the user, not just untidy on disk.
- **Which Codex nixarchy users have.**
  - nixarchy has one channel, `nixos-unstable`.
    `nixosConfigurations.reference.pkgs.codex.version` is `0.155.1`.
  - The oldest Codex found on any of our machines is a mise-installed
    0.151.0 on p510. It reads `.agents/skills`.
- **Two places create the `.codex` links:**
  - `modules/home.nix:992`, the per-activation relink loop, over
    `.agents .claude .codex .pi`.
  - Upstream's `omarchy-provision-user` (4.0.4): the `mkdir -p` on line 87,
    and `ln -sfn "$skill" ~/.codex/skills/"$name"` on line 93. It runs once,
    at first login. nixarchy already patches this script with
    `substituteInPlace --replace-fail` (`pkgs/omarchy/default.nix:1324`).
- **Tests and docs that name the four directories:**
  - `tests/session.nix:621` asserts all 12 checked skills are linked into
    `.codex/skills`.
  - `docs/manual/ai.md:37-40` and the comment at
    `pkgs/omarchy/default.nix:1075-1077` both list `.codex`.

## Design

Stop creating links in `~/.codex/skills`, keep removing old ones there, and
make both sources agree.

1. **`modules/home.nix`, relink block.** Split the single loop into a
   clean-up list and a link list:

   ```sh
   # Clean up everywhere a link was ever planted, including .codex:
   # removing it from the link list alone would strand the old links.
   for agentdir in .agents/skills .claude/skills .codex/skills .pi/agent/skills; do
     …remove symlinks into /nix/store/*/agents/skills/* (unchanged)…
   done
   # Link where each agent reads. Codex reads ~/.agents/skills, so
   # linking ~/.codex/skills as well listed every skill twice there.
   for agentdir in .agents/skills .claude/skills .pi/agent/skills; do
     run mkdir -p "$dest"; …ln -sfn as today…
   done
   ```

   The clean-up rule does not change: only symlinks whose target is a store
   `agents/skills` tree are removed. A hand-written skill in `.codex/skills`
   is a real directory or a link elsewhere, and is never touched. `.codex` is
   not `mkdir`'d any more.

2. **`pkgs/omarchy/default.nix`, next to the existing provision-user
   patch.** Two `--replace-fail` substitutions:
   - Remove ` ~/.codex/skills` from the `mkdir -p` line.
   - Delete the `ln -sfn "$skill" ~/.codex/skills/"$name"` line.

   `--replace-fail` makes a future upstream change to those lines fail the
   build rather than silently bring the duplicate back.

3. **Test (`tests/session.nix`).** Loop the positive assertions over
   `.agents`, `.claude` and `.pi`. Add a negative one: none of the 12 skills
   exists in `/home/omarchy/.codex/skills`. That proves both the loop and
   the patched provision-user.

4. **Docs.**
   - `docs/manual/ai.md` and the `pkgs/omarchy` comment: three directories,
     plus one sentence on why not `.codex`.
   - `modules/AGENTS.md`: the relink section gets a paragraph recording the
     deliberate divergence from upstream and its evidence (the docs quote
     and the binary check), the way other divergences there are written.

**Decisions on the intent's open questions:**

1. **Unconditional.** The only Codex nixarchy ships (0.155.1), and the oldest
   one found in use (0.151.0), both read `.agents/skills`, and it is Codex's
   only documented user location. A user running a Codex old enough to read
   only `.codex` would lose the nixarchy skills. That is accepted and
   recorded in `modules/AGENTS.md`, not guarded.
2. **Fix here. Upstream is a separate, optional follow-up.** Upstream
   carries the same duplicate. Reporting it on basecamp/omarchy is public
   and is the owner's call. It is not part of this change.
3. **No option.** One implementation, no knob, per the intent's "no new
   dependency" spirit and the unconditional decision above. Add one if a
   real user needs it.
4. **Hermes stays out of scope.** nixarchy does not link it today, and this
   change does not touch that.

## Alternatives rejected

- **Drop `.agents` instead of `.codex`.** Claude Code does not read
  `.agents`, but Antigravity does and Codex documents it as the location.
  Dropping it would break Antigravity and bet on Codex's legacy path.
- **Only change the relink loop, leave provision-user alone.** A fresh
  machine would get duplicates at first login and keep them until the first
  rebuild, and the test would need to allow that. Patching both costs two
  `--replace-fail` lines.
- **Remove `.codex` from both loops.** Leaves the 16 existing links on every
  current machine forever: nothing else deletes them, and they keep the
  duplicate alive.
- **An option (`programs.nixarchy.agentSkills.codexDir`).** Configuration
  for a case nobody has. Rejected per decision 3.

## Risks

- **An older Codex loses the skills.** A user on a Codex that predates
  `.agents/skills` support loses the nixarchy skills. Mitigation: the
  AGENTS.md note, and the fix is to update Codex. No such version was found.
- **Upstream edits the patched lines.** Then `--replace-fail` breaks the
  build. That is intended: it forces a look rather than a silent regression.
- **The patched script is not linted.** Same shape as #894's lesson. The
  VM test exercises provision-user's output (the negative assertion), which
  covers the result.
- **Users who planted their own `.codex` links into a nixarchy store tree**
  will see them removed. That was already true for the other three
  directories.

## Verification

1. `nix flake check`, including `checks.session`: the new negative
   assertion passes, and the three positive ones still do.
2. `nix build` of the `reference` configuration succeeds, meaning both
   `--replace-fail` substitutions matched upstream 4.0.4.
3. On a real machine after switching:
   - `comm -12 <(ls ~/.agents/skills) <(ls ~/.codex/skills)` prints nothing.
   - `~/.agents/skills/nixos/SKILL.md` resolves.
   - A hand-made test directory in `~/.codex/skills` survives the switch.
4. A fresh Codex session lists `nixos` once.
