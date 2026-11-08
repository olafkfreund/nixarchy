---
status: approved
issue: 1688
spec: spec/2026-11-08-1688-fcitx5-png-glyphs.md
coders:
  1: codex  # a --fuzz=0 patch to an upstream script; the rewrite must touch the copy, never the source
  2: codex  # a post-boot hook whose idempotence is the whole point
  3: codex  # two probes plus a break fixture that must fail only with the patch reverted
reviewers:
  - codex  # small, tricky shell where a wrong glob is a silent no-op
  - agy    # an independent read of the same diff
---

# Plan: the Fcitx candidate window has its arrows on NixOS 26.05 too

## Decisions carried from the approved spec

1. **The script, by a carried patch.** `pkgs/omarchy/1688-fcitx5-png-glyphs.patch`
   (`--fuzz=0`) replaces upstream's glyph loop in `bin/omarchy-theme-set-fcitx5`
   (lines 77-79, `for glyph in "$PACKAGED_THEME"/*.svg`). It links every
   `*.svg` and `*.png` in `$PACKAGED_THEME`. Then, for each `Image=<name>.svg`
   in the **copied** `theme.conf` whose SVG is absent from `$PACKAGED_THEME`
   but whose `<name>.png` exists, it rewrites that line to `Image=<name>.png`
   (`sed -i` on the copy, never on `$THEME_SOURCE`). A patch rather than
   `substituteInPlace`, because the edit replaces a multi-line loop. It
   carries a `pkgs/AGENTS.md` section, marked CARRIED and not meant
   upstream (Arch's fcitx5 always ships SVG).
2. **Existing machines (owner decision on the draft).** A post-boot hook,
   `omarchy/hooks/post-boot.d/fcitx5-glyphs`, reruns
   `omarchy-theme-set-fcitx5` (no `--activate`) once, and only when
   `~/.local/share/fcitx5/themes/omarchy/theme.conf` exists and an `Image=`
   names a file missing from that directory. Otherwise it does nothing. It
   sits under the same `enable` as the `user-migrations` hook, so Mode A is
   untouched.
3. **Timing limit:** the repair happens at the next login, not at the
   switch.
4. **Probes, split.**
   - `tests/input-methods.nix:342` checks the **packaged** theme directory:
     each of `prev`, `next`, `radio` and `arrow` exists as `.svg` or `.png`.
   - `tests/session.nix:3410-3414` checks the **generated** theme: every
     `Image=` in `theme.conf` resolves (`test -e`, which follows a link),
     and at least one exists.
   - The hook, in `checks.session` and the weekly `stable-session`: from a
     pre-fix state (a `theme.conf` from the template still naming `.svg`, no
     glyph links), the hook runs and every `Image=` resolves. A second run
     leaves the directory's mtime unchanged.
5. **§1 break, the same on both channels:** `OMARCHY_FCITX5_PACKAGED_THEME`
   (upstream line 12) is pointed at a fixture directory holding only the
   four `.png` files. The patched script resolves the theme, and with the
   patch line removed, `Image=prev.svg` fails.

## Steps

1. **The patch.** Copy upstream's script from the source input
   (`nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.omarchy.outPath'`,
   then `bin/omarchy-theme-set-fcitx5`), edit a copy, and
   `diff -u a/bin/... b/bin/...` rooted at `share/omarchy`, giving
   `pkgs/omarchy/1688-fcitx5-png-glyphs.patch`. In `pkgs/omarchy/default.nix`,
   right after the `substituteInPlace` at `:883-885`, add
   `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0 < ${./1688-fcitx5-png-glyphs.patch}`
   with a `# Why: pkgs/AGENTS.md#...` pointer. Append a short CARRIED
   section to `pkgs/AGENTS.md` after "Notification history" (`:1407`).
   Verify: `nix build .#omarchy` (package tier, gate first) applies it, and
   the built script has the new loop.
   Traps: the `''` string makes `\$` literal and only `${` interpolates, so
   check the built script, not the source. Keep `default.nix` additions to
   the patch line and its pointer, because `checks.install-phase-budget`
   measures `installPhase`. The rewrite's `sed` must not follow a
   dotfiles symlink onto `$THEME_SOURCE`.

2. **The hook.** `modules/home.nix`, beside `post-boot.d/user-migrations`
   (`:2458-2473`), in the same shape (`enable = osConfig.programs.nixarchy.enable or false;`,
   an explicit `PATH`). Its body is decision 2. The `Image=` scan is
   `sed -n 's/^Image=//p'`, followed by a `[ -e "$dir/$name" ]` per name.
   Verify: `nix eval` of the hook text; `bash -n` on it; step 3's hook
   probe.
   Traps: `grep -q` after a pipe under `pipefail` is a guarded pattern
   (`checks.grep-q-pipefail`). The hook must not start fcitx5; the script
   already avoids that (`busctl --auto-start=no`).

3. **Probes and the break** (decisions 4 and 5): the two probe edits at
   `tests/input-methods.nix:342` and `tests/session.nix:3410-3414`, then a
   new block after `:3414` for the hook probe and the PNG-only fixture.
   Verify: `checks.input-methods` (cheap) passes. `checks.session` (VM tier)
   passes. The break: remove the patch line from `default.nix`, rebuild
   `checks.session`, and it fails with "names a file that does not exist" on
   the PNG-only fixture. Capture that output, then restore.
   Traps: build by drvPath (`nix eval --raw ...drvPath`, then
   `nix build '<drv>^*'`), so a stale evaluation cannot answer (§5). Restore
   the break with `git checkout HEAD --`, never from the index (§5).

4. **Run, commit, PR** (session): cheap tier (`input-methods`,
   `grep-q-pipefail`, `patched-files`, fmt, statix, deadnix), package tier
   (`omarchy`), VM tier (`session`). Then dispatch the weekly
   `stable-session` on the branch
   (`gh workflow run weekly.yml -f job=stable-session --ref fix/1688-fcitx5-png-glyphs`)
   as the 26.05 proof. It failed at `tests/session.nix:3413` on main (run
   42466135557).

## Tests (by §6 tier)

| tier | check | expect |
|---|---|---|
| cheap | `input-methods`, `patched-files`, `grep-q-pipefail`, fmt, statix, deadnix | pass |
| package | `omarchy` | the patch applies with `--fuzz=0` |
| VM | `session` | probes and hook pass; fails with the patch removed |
| weekly (dispatched) | `stable-session` | green on 26.05 |

Not run locally: `stable-session`, which is a dispatched hosted run.

## Rollback

Revert the merge commit. The patch, the hook and the probe changes go
together. A theme directory the patch already repaired keeps its PNG links
and rewritten `theme.conf`, which is harmless: the next theme change
rewrites both.

## PR notes

`Closes #1688`. The body links the intent, the spec and this plan, says
which steps Codex did, and carries the §1 output. Comment "@codex review".
Merge with a merge commit (`--merge`), because the branch carries the
artifact history.
