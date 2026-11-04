---
status: approved
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
  1. `cp -p` `looknfeel.lua` to `/tmp/looknfeel.lua.bak`, **outside**
     `~/.config/hypr` (agy). Append the line with a leading newline,
     `printf '\nhl.config({ general = { border_size = 5 } })\n' >>`, so it
     can't join a last line that has no newline (agy). `hyprctl reload`,
     then poll `getoption general:border_size -j` until it reads **5**. Fail
     with a message that names stage 1.
  2. Write `layouts.lua` containing
     `hl.config({ general = { border_size = 9 } })`, `chown omarchy:` it, and
     reload. Poll for **9**. Fail with "#1596: layouts.lua did not load after
     looknfeel", plus the reading.

  Then restore with `cp -p /tmp/looknfeel.lua.bak` over `looknfeel.lua`,
  `rm -f` the backup and `layouts.lua`, and reload.

  **The seeded copy.** Also assert that `/home/omarchy/.config/hypr/hyprland.lua`,
  the fresh home's seeded copy, contains `hypr.layouts`. That's the spec's
  seeded-copy decision, which only this layer can see (codex).
  Parse the output as JSON, as the Hyprforge probe does, with no
  `| grep -q`.
- **Docs, the full content (codex, agy):**
  - **`pkgs/AGENTS.md`:** a section anchored `<a id="layouts-load-point"></a>`,
    placed after the Hyprforge section (around line 143). It says:
    - what the hook is, and that it's optional (`require_optional`);
    - why it's in the store file and not in `autostart.lua`: the session runs
      the store `hyprland.lua` through `--config`, so downstream had to take
      over `autostart.lua`, a file the user is meant to edit
      (nixos_config#2686);
    - the load order `looknfeel` < `layouts` < Hyprforge < toggles, and that
      only the first `<` is measured;
    - **coexistence:** a user's own `~/.config/hypr/layouts.lua`, written for
      their own Hyprland session, is now also loaded by the Omarchy session.
      Their own session is unaffected;
    - that a fresh home's seeded `hyprland.lua` carries the line too.
  - **`docs/manual/configuration.md`:** the brace lists at `:637` and `:667`
    stay as they are. After the first one, add a short paragraph:
    `~/.config/hypr/layouts.lua` is optional and never seeded. The Omarchy
    session loads it automatically after `looknfeel`. Your own session loads
    it only if your own `hyprland.lua` requires it. Then the load order, in
    one line.
- **No `data/bin-ledger.nix` row.** `config/hypr/hyprland.lua` is not under
  `bin/`, and Hyprforge's edit to the same file has no row.
  `tests/patched-files.nix` is a fixture test and needs no change.
- **Out of scope:** asks 2 and 3 of #1596, and any `programs.nixarchy`
  option.

## Steps

1. **`pkgs/omarchy/default.nix`:** add the substitution and its comment
   directly after Hyprforge's block. Verify with:
   - `git add`, then `nix build .#omarchy --no-link --print-out-paths`;
   - `grep -n -B1 'hypr.layouts' <out>/share/omarchy/config/hypr/hyprland.lua`
     shows exactly one match, with `require("hypr.looknfeel")` on the line
     before it (agy);
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
   decided, with every bullet above present. Keep it short, without
   renumbering, and don't touch Hyprforge's section. Verify with
   `grep -n 'layouts' pkgs/AGENTS.md docs/manual/configuration.md`, read
   against the bullets, plus the cheap checks in step 4.

4. **Mine: the proofs, every local check, and the PR.**
   - Cheap tier: all `generated-checks.sh` targets (they include
     `patched-files`, which the spec names; confirm it's in the list) plus
     `grep-q-pipefail`, under `flock`, then `nix fmt -- --ci`, `statix` and
     `deadnix`.
   - Package tier: the `omarchy` package and `install-phase-budget`, gated as
     §6 says.
   - VM tier, only while CI is idle: `checks.session` must be green.
   - **§1 breaks.** First commit the good tree as the baseline. Each break is
     an **uncommitted** edit, `git add`ed so the flake sees it, and proven to
     have landed with `git diff`. Evaluate its `drvPath` once and build that.
     Restore with `git checkout HEAD -- pkgs/omarchy/default.nix`, which
     restores HEAD, the good commit, and not the index. Then check that
     `git diff HEAD` is empty before the next break (codex). Each break must
     go red, and its output goes in the PR:
     - (a) **the generated require above `looknfeel`**: the replacement
       string becomes
       `$'require("default.hypr.require_optional").module("hypr.layouts")\nrequire("hypr.looknfeel")'`.
       Moving the Nix block alone would change nothing (codex). Stage 2
       reads 5.
     - (b) the substitution removed. Stage 2 reads 5, and the seeded-copy
       assertion fails too.
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
