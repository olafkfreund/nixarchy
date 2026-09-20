---
status: approved
issue: 809
spec: spec/2026-09-20-809-panel-python-collision.md
---

# Plan: a default's runtime tools lose to the user's own

Branch `fix/809-panel-python-collision`, from `main` at `281eef2`, already
carrying the intent and the spec. One commit per step, each subject a full
sentence (AGENTS.md §8). A deviation updates this file in the same commit as
the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **`lib.lowPrio`**, applied **once**, where `modules/home.nix:826`
  concatenates the defaults' tools into `home.packages`:
  `++ map lib.lowPrio (lib.concatMap (p: p.packages) (lib.attrValues resolvedDefaults))`.
  So every default plugin's runtime tool — `gh`, `glab`, `python3`,
  `xdg-utils`, `jq`, `iproute2`, `herdr`, the devenv CLI — loses a collision
  with a package the user installed themselves, and a user with no copy of
  their own is unaffected.
- **Measured before the spec was written**, on this nixpkgs:
  `buildEnv [ python3, python3.withPackages(pytest) ]` refuses with
  `conflicting subpath … bin/idle3`; with `lowPrio` on the first it builds,
  its `bin/python3` resolves into the user's `-env`, and `import pytest`
  works.
- **The rule is written at the line** (a comment naming #809) and in
  `modules/AGENTS.md`: anything nixarchy puts in somebody's profile loses to
  what they installed themselves.
- **Two checks**: `defaultRuntimeToolsLowPriority` in `checks.options` for the
  rule, and a new `checks.home-profile` that *builds* a profile holding both
  interpreters for the symptom, asserting the user's env wins.
- **No workflow edit.** `build.yml`'s `omarchy` job builds every check no job
  claims, and a guard fails on an unclaimed, unbuilt one (§4).
- Wrapping `menu.py` with its own interpreter is **not** this change; it is
  the better long-term shape and becomes its own issue.

## Steps

1. **`modules/home.nix`: the fix and the rule at the line.** Wrap the
   `concatMap` at `:826` in `map lib.lowPrio`, with a comment saying what it
   prevents (a user's own `python3.withPackages` colliding with a panel's bare
   `python3`, which fails `home-manager-path` and so the whole closure), that
   the user's copy must win, and #809.
   → verify by step 3's `checks.options` case, red first.
2. **`modules/AGENTS.md`: the rule.** One entry beside the default-plugins
   section, in the house "Why:"/anchor style, so the next `packages = [ … ]`
   meets it.
   → verify by `nix fmt -- --ci` and by reading it beside the existing entries.
3. **`tests/options.nix`: `defaultRuntimeToolsLowPriority`.** For a home with
   the defaults resolved, every package contributed by `resolvedDefaults`
   carries `meta.priority` above nixpkgs' default; `off` is the same
   assertion on the unprioritised list, so dropping `lowPrio` breaks it.
   Reuse the existing `defaultHomeOn` fixture rather than evaluating another
   machine (#747).
   → verify red first: build `options` with the `map lib.lowPrio` removed, and
   quote the failure.
4. **`tests/home-profile.nix` and `flake.nix`: the symptom.** A NixOS
   evaluation with one normal user whose `home.packages` holds
   `python3.withPackages (ps: [ ps.pytest ])`, nixarchy on, defaults on. The
   check *builds* that user's `home.packages` profile (the same `buildEnv`
   Home Manager builds) and asserts:
   - it builds at all — today it refuses with `conflicting subpath … idle3`;
   - `bin/python3` resolves inside the user's `-env`, not the bare
     interpreter, so "it built" cannot pass with nixarchy's copy winning;
   - `import pytest` works through that `bin/python3`.
   Declared in `flake.nix` beside `options` (`:2010`), same shape.
   → verify red first: with the fix reverted the check reproduces the exact
   failure from #809, quoted in the PR.
5. **Whole-branch verification.** `nix fmt -- --ci`, statix, deadnix, then by
   name: `options`, `home-profile`, `plugin`, `reference-toplevel`.
   → verify all green, and that `home-profile` is picked up by the catch-all
   (its name appears in the generated-checks list the guard compares).
6. **On p620, the real proof.** In `~/.config/nixos`, override the nixarchy
   input to this branch and build p620's closure — the build that fails today.
   Then confirm the built profile's `python3 -c "import pytest"` works and the
   devenv panel from #802 is in it. Restore the override afterwards.
   → verify by the closure building and both assertions passing. **Applying is
   the owner's**, and only after this merges.
7. **PR.** Against `main`, closing #809, linking intent, spec and plan, with
   the red output for both checks, the measurement table, and a note that
   #802's rollout on p620 was blocked by this.

## Tests

| Command | Expected |
| --- | --- |
| `nix build .#checks.x86_64-linux.home-profile` | builds; the profile's `bin/python3` is the user's env and imports pytest |
| the same with `lowPrio` reverted | fails with `conflicting subpath … bin/idle3` |
| `nix build .#checks.x86_64-linux.options` | green, including `defaultRuntimeToolsLowPriority` |
| the same with `lowPrio` reverted | `these options do not take effect both ways: defaultRuntimeToolsLowPriority` |
| `nix fmt -- --ci`, statix, deadnix | clean |
| `nix build .#checks.x86_64-linux.{plugin,reference-toplevel}` | green |
| p620 closure with the input overridden to this branch | builds |

## Rollback

- **Before merge:** drop the branch; nothing outside it changed.
- **After merge:** revert the merge commit. `lib.lowPrio` only sets
  `meta.priority`, so nothing rebuilds and no closure moves either way.
- **For a user who wants nixarchy's copy to win instead:** install it
  themselves at default priority, or `lib.hiPrio` it in their own
  `home.packages` — their file, their order.
