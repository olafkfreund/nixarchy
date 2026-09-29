---
status: draft
issue: 1052
spec: spec/2026-09-29-1052-menu-on-by-default.md
---

# Plan: Turn nixarchy-menu on by default

## Approved decisions

These are carried over from the spec, so the plan can be followed without
opening it.

- **Delete `enableByDefault` outright.** A default resolves with
  `cfg.defaultPlugins.${name} or true`.
- **Do not add `menu` to the `defaultPlugins` default attrset.** Absent means
  on, so the menu survives a host that sets other keys.
- **The menu entry is otherwise unchanged.** It keeps `placement = ""`, the
  pre-disable of competing clones, the marker, and the restore path. The pin
  stays `2cce175` (v1.0.0).
- **No ISO special case.** The live ISO has no Home Manager. Installed systems
  and the offline reference closure gain about 85 MiB.
- **Menu overrides need no change.** nixarchy-menu reads
  `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`.
- **The opt-out is `menu = false`.** Every "every default off" list gains it.
- **readme-counts loses its opt-in category.** The docs sentence becomes
  "…eleven are always on, and three turn on with their feature. Voice is
  opt-in." (the exact wording follows the regex the script keeps).
- **Demos and screenshots are not re-recorded.** The PR says so.
- **The PR closes #1052 and is merged once green and mergeable** (the user
  asked for this).

## Steps

1. **Baseline for the break loop.** Before touching `tests/`, prove
   `noDefaultsHome` needs `menu = false`. That comes naturally out of step 3:
   run `checks.options` once with the module flipped but `noDefaultsHome`
   unchanged, and expect `defaultPluginsNoHookWhenEmpty` to fail. Commit a
   baseline first (§5: `git checkout HEAD` eats uncommitted work).
2. **`modules/home.nix`**
   - At :424, change `or p.enableByDefault` to `or true`.
   - Delete the `enableByDefault` option (:726-733).
   - Delete `enableByDefault = false;` in the `menu` entry.
   - Rewrite the entry comment and the `defaultPlugins` description so they
     say the menu is on by default and that `menu = false` restores the stock
     menu.
   - Verify with `nix fmt` and `git diff --stat`. The hook reformats `.nix`
     files (§5).
3. **`tests/options.nix`**
   - Fixture `clone`: drop `enableByDefault = false`, and change the comment
     from "opt-in clone" to "clone".
   - Delete `defaultPluginsEnableByDefault` and
     `defaultPluginsEnableByDefaultSurvivesOtherKeys`.
   - Delete `menuOnHome`. Its uses (`menuValidated`, `defaultHookScript`)
     become `defaultHomeOn`.
   - Replace `menuIsOptIn` with `menuIsOnByDefault`:
     - on: `defaultHomeOn` installs `nixarchy.menu` and the hook lists it;
     - off: `homeOn { } { programs.nixarchy.defaultPlugins.menu = false; }`
       does neither.
   - `noDefaultsHome` gains `menu = false`.
4. **`tests/plugin.nix`**: the machine's `defaultPlugins` gains `menu = false`,
   with a one-line comment in the file's register (ungated since #1052).
5. **`.github/scripts/readme-counts.sh`**
   - Remove `p_off`, its comment, `p_off_word` and the `default-plugins-optin`
     quantity.
   - `p_on_word` uses `p_total - p_gated`.
   - Verify with `bash .github/scripts/readme-counts.sh` run as a script.
6. **Docs**
   - `docs/index.md:90`: the sentence above.
   - `docs/llms.txt:115`: Menu no longer listed as opt-in.
   - `docs/manual/plugins.md` (:40, :373, :386-395): on by default, and
     `menu = false` or Setup > Plugins to go back.
   - `docs/manual/configuration.md`: the opt-out example gains `menu = false`.
   - `docs/internals/flake.md` #946 section: the heading becomes
     "nixarchy-menu, on by default (#946, #1052)". Replace the "Off unless" and
     "reaches a machine only when switched on" paragraphs.
   - `flake.nix:298`: point the `# Why:` at the new anchor.
   - `grep -rn 'opt-in' docs README.md modules | grep -i menu` should return
     nothing stale.
7. **Local checks.** `nix fmt -- --ci`, statix, deadnix, readme-counts.
   `checks.options` only when `gh run list` shows nothing in flight.
8. **Commit, push, open the PR.** Use the template, "closes #1052", links to
   intent, spec and plan, and the failing output from the break proof. Merge
   once every required check is green and `gh pr view --json mergeable` says
   `MERGEABLE`. Confirm #1052 closed.

## Tests

- `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`: all clean.
- `bash .github/scripts/readme-counts.sh`: exit 0.
- `nix build .#checks.x86_64-linux.options`: passes.
- Break proof (§1): put `enableByDefault` back as a hard `false` on the menu
  in the resolver (`or (name != "menu")`). `menuIsOnByDefault` fails; restore
  and it passes. Prove the break applied with `git diff`.
- CI: `plugin`, `session`, `install`, `omarchy` green on the PR head.
- After merge: the next nightly `iso-budget` is green.

## Rollback

Revert the squash commit. Machines that already enabled the menu keep it,
because the marker exists; to go back, set `programs.nixarchy.defaultPlugins.menu
= false`, and #946's restore path re-enables the stock menu at next login.
