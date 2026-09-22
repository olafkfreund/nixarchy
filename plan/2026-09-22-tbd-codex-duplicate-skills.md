---
status: draft
issue: TBD
spec: spec/2026-09-22-tbd-codex-duplicate-skills.md
---

# Plan: Codex lists every nixarchy skill twice

## Approved decisions (from the spec)

- **Stop linking nixarchy skills into `~/.codex/skills`.** Codex's documented
  user location is `~/.agents/skills`, which Codex 0.155.1 (shipped) and
  0.151.0 (oldest found) both read. Codex does not merge same-named skills,
  so linking both listed every skill twice.
- **Keep cleaning up `~/.codex/skills`.** Otherwise the 16 links already on
  every machine stay forever. The clean-up rule is unchanged: remove only
  symlinks whose target is a store `agents/skills` tree. Hand-written
  skills are never touched.
- **Patch upstream `omarchy-provision-user`** with `--replace-fail`, so a
  fresh machine never gets the `.codex` links at first login, and an
  upstream change to those lines fails the build.
- **Unconditional, no option.** Upstream reporting is a separate step and the
  owner's call. Hermes is out of scope.
- **Record the divergence from upstream in `modules/AGENTS.md`**, with its
  evidence.

## Steps

All paths are relative to the nixarchy repo root.

1. **`modules/home.nix`, relink block (currently line 992).** Replace the
   single `for agentdir in .agents/skills .claude/skills .codex/skills
   .pi/agent/skills` loop with two loops:
   - **Clean-up** over all four directories. Its body is the current
     `for link in "$dest"/*` symlink-removal loop, verbatim, guarded by
     `[ -d "$dest" ] || continue` instead of `mkdir`.
   - **Link** over `.agents/skills .claude/skills .pi/agent/skills`, with the
     current `run mkdir -p "$dest"` and the `find … | while read -r skill;
     do run ln -sfn …` body, verbatim.

   Add a one-line comment above each loop giving the reason (as in the
   spec's sketch).
   → verify: `nix eval .#nixosConfigurations.reference.config.home-manager.users.omarchy.home.activation`
   evaluates, and `nix fmt -- --ci` is clean.
2. **`pkgs/omarchy/default.nix`, directly after the existing
   `substituteInPlace $out/share/omarchy/bin/omarchy-provision-user`
   (line 1324).** Add to the same `substituteInPlace` (or a second one, next
   to it):
   ```
   --replace-fail '~/.claude/skills ~/.codex/skills ~/.pi/agent/skills' \
                  '~/.claude/skills ~/.pi/agent/skills' \
   --replace-fail 'ln -sfn "$skill" ~/.codex/skills/"$name"' \
                  ': # nixarchy: not ~/.codex/skills; Codex reads ~/.agents/skills'
   ```
   The second one keeps a no-op line rather than deleting it, so the loop
   body's shape and line count stay stable. Both strings were checked
   against upstream 4.0.4 source lines 87 and 93.
   → verify: `nix build .#nixosConfigurations.reference.pkgs.omarchy`
   succeeds, and `grep -c codex/skills` on the built
   `share/omarchy/bin/omarchy-provision-user` returns 0.
3. **Update the comment at `pkgs/omarchy/default.nix:1075-1077`:** three
   directories, and why not `.codex`.
4. **`tests/session.nix:621`.**
   - Change the positive loop's list to `[".agents/skills",
     ".claude/skills", ".pi/agent/skills"]` and its closing `print` to
     "three agent homes".
   - After it, add a negative loop over the same 12 skill names:
     `machine.fail(f"test -e /home/omarchy/.codex/skills/{skill}")`, with a
     comment saying it covers both the activation loop and the patched
     provision-user.
   → verify: Tests §2.
5. **`docs/manual/ai.md:37-40`:** list three directories and add one
   sentence: Codex reads `~/.agents/skills`, and linking `~/.codex/skills`
   as well made Codex list every skill twice.
6. **`modules/AGENTS.md`, "Agent skills, relinked on every activation":**
   append a paragraph. It says nixarchy links three of upstream's
   directories. It explains why not `.codex`, citing the Codex docs quote on
   same-named skills and the binary check on 0.151 and 0.155. It records
   that `.codex` is still cleaned so old links do not linger, and that
   provision-user is patched to match. It names the accepted risk, a Codex
   old enough to read only `.codex`, and notes that Hermes is not linked
   (unchanged).
7. **Commit** steps 1–6 as one commit:
   `fix(skills): stop linking nixarchy skills into ~/.codex/skills (#TBD)`.
8. **Deploy to p620 only for real-machine verification**, from a nixos_config
   worktree with the nixarchy input overridden to this branch. Announce on
   the agent bus first, and diff units and closure against the running
   generation. Then Tests §3.

## Tests

1. **Lint and eval:**
   ```bash
   nix fmt -- --ci
   nix build .#nixosConfigurations.reference.config.system.build.toplevel --no-link
   ```
   Both succeed. The build proves both `--replace-fail` strings matched.
2. **VM session check (~5 min):**
   ```bash
   nix build .#checks.x86_64-linux.session --print-build-logs
   ```
   It passes. The log shows the "three agent homes" line, and the new
   negative assertion raises nothing.
3. **On p620 after step 8:**
   ```bash
   comm -12 <(ls ~/.agents/skills) <(ls ~/.codex/skills)   # prints nothing
   test -e ~/.agents/skills/nixos/SKILL.md                    # resolves
   ls ~/.codex/skills                                          # only non-nixarchy entries (agent-bus)
   ```
   Before switching, `mkdir ~/.codex/skills/handmade-test && echo x >
   ~/.codex/skills/handmade-test/SKILL.md`. After switching, it still
   exists. Then remove it.
4. A fresh `codex` session lists `nixos` once. The owner checks this;
   Codex has no non-interactive skill listing.

## Rollback

- **Code:** `git revert` the commit. The next activation relinks into
  `.codex` again, because the clean-up and link loops merge back into one.
- **p620 after step 8:** `nixos-rebuild switch --rollback`, or switch from
  nixos_config main. Either restores the old nixarchy, which relinks
  `.codex`. Nothing is deleted except store links that the next activation
  recreates.
