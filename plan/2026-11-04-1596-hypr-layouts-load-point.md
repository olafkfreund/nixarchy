---
status: draft
issue: 1596
spec: spec/2026-11-04-1596-hypr-layouts-load-point.md
coders:
  1: coder   # one substituteInPlace beside Hyprforge's, copying its exact shape
  2: codex   # small, order-sensitive test logic: two stages, restores, ownership
  3: coder   # two short prose edits
reviewers:
  - codex    # independent read of the probe's ability to fail
  - agy      # independent read of the docs against the code
---

# Plan: A supported load point for layout settings after looknfeel

## Decisions carried over from the approved spec

- **The hook.** In `pkgs/omarchy/default.nix`, beside Hyprforge's
  substitution (around line 2065), add:

      substituteInPlace $out/share/omarchy/config/hypr/hyprland.lua \
        --replace-fail 'require("hypr.looknfeel")' \
        $'require("hypr.looknfeel")\nrequire("default.hypr.require_optional").module("hypr.layouts") -- nixarchy: layout settings (#1596)'

  - Its comment has at most 2 lines and ends
    `# Why: pkgs/AGENTS.md#layouts-load-point`.
  - Hyprforge's line and its anchor stay byte-identical.
  - The anchor exists verbatim on stable `4.5.0-rc3` (`hyprland.lua:22`) and
    on edge `cc99764` (line 25).
- **Load order:** `looknfeel` < `layouts` < Hyprforge < toggles. Only the
  first `<` is measured. The rest follows from require order.
- **The probe** in `tests/session.nix` sits directly after the Hyprforge
  probe (which ends around line 745). It runs in two stages:
  1. `cp -p` `looknfeel.lua` aside. Append
     `hl.config({ general = { border_size = 5 } })` to it, `hyprctl reload`,
     and poll `getoption general:border_size -j` until it reads **5**. Fail
     with a message that names stage 1.
  2. Write `layouts.lua` containing
     `hl.config({ general = { border_size = 9 } })`, `chown omarchy:` it, and
     reload. Poll for **9**. Fail with "#1596: layouts.lua did not load after
     looknfeel", plus the reading.

  Then restore `looknfeel.lua` with `cp -p`, `rm` `layouts.lua`, and reload.
  Parse the output as JSON, as the Hyprforge probe does, with no
  `| grep -q`.
- **Docs.** `pkgs/AGENTS.md` gets a section with
  `<a id="layouts-load-point"></a>` beside the Hyprforge one. In
  `docs/manual/configuration.md`, the two brace lists stay as they are, and a
  separate sentence follows the first one: optional, never seeded, loaded
  automatically by the Omarchy session only, and the load order.
- **No `data/bin-ledger.nix` row.** `config/hypr/hyprland.lua` is not under
  `bin/`, and Hyprforge's edit to the same file has no row.
  `tests/patched-files.nix` is a fixture test and needs no change.
- **Out of scope:** asks 2 and 3 of #1596, and any `programs.nixarchy`
  option.

## Steps

1. **`pkgs/omarchy/default.nix`:** add the substitution and its comment
   directly after Hyprforge's block. Verify with:
   - `git add`, then `nix build .#omarchy --no-link --print-out-paths`;
   - `grep -n 'hypr.layouts' <out>/share/omarchy/config/hypr/hyprland.lua`
     shows exactly one line, directly after `require("hypr.looknfeel")`;
   - `nix build .#checks.x86_64-linux.install-phase-budget` (report the new
     margin).

   Traps:
   - **§5:** an editor hook may reformat with nixpkgs-fmt. Run `nix fmt`, and
     check that `git diff --stat` shows only this hunk.
   - The `$'…'` string has no `${`.
   - A multi-line `--replace-fail` argument re-flows the phase (pkgs/AGENTS.md).
     Keep the replacement on one line, as Hyprforge's is.
   - Omarchy is the package tier, so check the load and the VM gates first.

2. **`tests/session.nix`:** the probe as decided, after the Hyprforge probe.
   Verify that `nix eval --raw .#checks.x86_64-linux.session.drvPath`
   evaluates. I build the VM.

   Traps:
   - The probe runs as root through `machine.succeed`, so the restored file
     must stay owned by `omarchy` (`cp -p`).
   - Use the existing `on_desktop(...)` helper for `hyprctl`.
   - No `${` in the Python except deliberate Nix interpolation.
   - A §1 break must be able to fail it (step 4).

3. **`pkgs/AGENTS.md` and `docs/manual/configuration.md`:** the prose as
   decided. Keep it short, without renumbering, and don't touch Hyprforge's
   section. Verify with the cheap checks in step 4, which cover the docs and
   llms counts.

4. **Mine: the proofs, every local check, and the PR.**
   - Cheap tier: all `generated-checks.sh` targets plus `grep-q-pipefail`,
     under `flock`, then `nix fmt -- --ci`, `statix` and `deadnix`.
   - Package tier: the `omarchy` package and `install-phase-budget`, gated as
     §6 says.
   - VM tier, only while CI is idle: `checks.session` must be green.
   - **§1 breaks**, each on a temporary commit and each reverted with
     `git checkout HEAD~ -- <file>`. Each must go red, and the red output
     goes in the PR:
     - (a) the hook placed above `looknfeel` (stage 2 reads 5);
     - (b) the hook removed (stage 2 reads 5).
   - Squash to a real subject, open the PR linking all three artifacts, and
     post `@codex review`.
   - If nothing in it is a CI gate, arm `--auto --squash`. This change
     touches no workflow.
   - Also tell olafkfreund/nixos_config, in a comment on #2685, that it can
     drop the `autostart.lua` takeover once this ships. That repo is the
     owner's own, so commenting there isn't the upstream-filing case (§11).

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.session` | green; red under breaks (a) and (b) |
| `omarchy` package and `install-phase-budget` | green, margin reported |
| generated checks, `grep-q-pipefail`, fmt/statix/deadnix | green |

## Rollback

Revert the squash commit. Without the hook, a `layouts.lua` is simply never
loaded again, and nothing else depends on it.
