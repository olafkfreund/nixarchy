---
status: draft
issue: 710
spec: spec/2026-09-15-710-plugin-reloads.md
---

# Plan: an activation that changes no plugin leaves running plugins alone

The declared-plugins activation in `modules/home.nix` (the `.nixarchy-managed`
block) moves from remove-all-then-relink to a reconcile.

## Decisions, carried from the approved spec

- **D1.** For each declared plugin, compute `id` and `target=$(readlink -f
  drv/plugin)`.
  - A real directory is kept, with today's message.
  - If `readlink dir/$id` already equals `target`, the plugin is left alone.
  - Otherwise, `run ln -sfn`.

  Every declared id that is not a user's own directory is appended to
  `.nixarchy-managed.new`.
- **D2.** Old manifest ids absent from `.new`, and still symlinks, get
  `run rm -f`. That is today's guard, applied only to retired ids.
- **D3.** Then:
  - if `.new` is empty, remove both files;
  - if it equals the old manifest (`cmp -s`), remove `.new`;
  - otherwise, `run mv .new` over the manifest.

  Hidden names are ignored by the shell's watcher. `.new` is written directly,
  as today's manifest append is, and the final `mv` goes through `run`.
- **D4.** `tests/plugin.nix` checks two things:
  - the inode of the `remco.bar-toggle` link is unchanged after the test
    re-runs the user's Home Manager activation by restarting the
    `home-manager-omarchy` unit;
  - after `omarchy plugin remove`, a second re-run brings the link back to the
    same target.

  There is no new check and no workflow edit.

## Steps

1. **`tests/plugin.nix`: D4 first, against today's block**, so the red is the
   real one.
   → verify: `nix build .#checks.x86_64-linux.plugin` fails on the inode
   assertion. Capture the output. Check the §6 queue first: this is a VM.
2. **`modules/home.nix`: D1–D3**, replacing the block. The one-line notes at
   the lines stay; the `# Why:` pointer stays.
   → verify: `checks.plugin` is green; the restore assertion passes.
3. **`modules/AGENTS.md`:** update the `declared-plugins-linked-in-by-the-id…`
   anchor section to say activation reconciles rather than relinks, and why
   (#710: every relink reloads every plugin).
   → verify: `grep -n "#710" modules/AGENTS.md`.
4. **Local checks:** `checks.options`, `stable-eval`, `config-warnings`;
   statix and deadnix; `nix fmt` last.
   → verify: all pass.
5. **PR:** link intent, spec and plan; paste the step 1 red; state that the
   changed-source and retired-plugin branches are not VM-tested (spec
   Alternatives); `Closes #710`. Open issues for the nixi and voice plugin
   writers (intent answer 1), with a milestone and area label at filing.
   → verify: CI `plugin` and `session` are green; both issues exist with a
   milestone.

## Tests

```sh
nix build .#checks.x86_64-linux.plugin --print-build-logs   # red before step 2, green after
nix build .#checks.x86_64-linux.options
```

## Rollback

Revert the squash commit. Activation goes back to relinking everything.
Nothing on disk needs cleaning: the manifest format is unchanged, one id per
line.
