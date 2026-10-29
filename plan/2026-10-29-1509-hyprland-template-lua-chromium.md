---
status: approved
issue: 1509
spec: spec/2026-10-29-1509-hyprland-template-lua-chromium.md
coders:
  1: agy
  2: agy
  3: agy
reviewers:
  - codex
---

# Plan: the hyprland template uses Lua config and start-hyprland, and its Chromium opens a window

Covers #1509 and #1510. Branch `fix/1509-1510-hyprland-template-lua-chromium`,
worktree `/mnt/data/vmtest/nixarchy-1509-1510`.

## Approved decisions, from the spec

- `modules/microvm/templates/hyprland.nix` replaces
  `environment.etc."hypr/hyprland.conf"` with
  `environment.etc."hypr/hyprland.lua"`, holding the same four settings:
  ```lua
  hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
  hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
    debug = { disable_logs = false, enable_stdout_logs = true },
  })
  ```
  Lua comments (`--`) carry the existing reasons for the monitor rule and the
  stdout logs.
- `ExecStart = "${pkgs.hyprland}/bin/start-hyprland -- --config /etc/hypr/hyprland.lua"`
  (the owner's decision). `Restart = "no"` stays. Its comment is rewritten:
  start-hyprland restarts a compositor that exits uncleanly, possibly in safe
  mode. Step 4 measures what actually happens.
- Chromium: `commandLineArgs = "--force-renderer-accessibility --ozone-platform=wayland"`.
  The wrapper is used, not `NIXOS_OZONE_WL`, because a session variable does
  not reach ai-mirror's lingering user service.
- The host is unchanged. `modules/nixos.nix:133` already uses start-hyprland,
  and `checks.coexist` guards it.
- `tests/microvm-ai-mirror.nix` gains two parts:
  - (d) `Hyprland --verify-config` on the evaluated Lua text, requiring
    `config ok` and exit 0 (see Deviations), plus the four settings in the
    text and no `hypr/hyprland.conf`;
  - (e) values: ExecStart and Chromium's `buildCommand` flags.

## Who does what

- **Steps 1–3: agy** (the owner asked for agy and Codex on the team), headless
  through the `handoff` skill, one step per handoff. agy cannot build. Each
  step's verify is run by this session, which also finishes any step agy
  hands back. On a fallback the step comes to this session, and the PR says so.
- **Review: Codex** read-only through `second-opinion`, given this plan and
  `git diff origin/main`, plus the usual fresh Opus reviewer given the same.
  Neither approves anything.
- Steps 4–6 belong to this session.

## Steps

1. **`modules/microvm/templates/hyprland.nix`** (agy). Change three things.
   - Replace the `etc."hypr/hyprland.conf".text` block (lines ~51–71) with
     `etc."hypr/hyprland.lua".text`, holding the Lua above. Keep the two
     reasons as `--` comments inside the Lua.
   - Change the Chromium line (~line 39) to the two-flag `commandLineArgs`.
     Add one clause to the comment above it: without
     `--ozone-platform=wayland` it tries X11, and this guest has no Xwayland
     (#1509).
   - Change `ExecStart` (~line 142) to the start-hyprland form, and rewrite the
     `Restart = "no"` comment as follows: the unit itself does not restart;
     start-hyprland restarts a crashed compositor (possibly in `--safe-mode`,
     which drops the monitor rule), so a crash shows as a restart in
     `journalctl --user -u hyprland` and as a wrong output size (#1510).

   → Verify (session): `nix eval --raw .#packages.x86_64-linux.microvm-hyprland-ai-mirror.drvPath`
   evaluates, and `grep -n 'hyprland.conf\|bin/Hyprland' modules/microvm/templates/hyprland.nix`
   is empty. Then run `nix fmt` and read `git diff --stat`.

   Traps:
   - In a Nix `''` string only `${` interpolates, so do not escape `$`
     (AGENTS.md §5). The Lua has no `${`.
   - The nixpkgs-fmt hook may reformat the file (§5). `nix fmt` restores it.

2. **`data/microvm-templates.nix`** (agy). In the `hyprland` note, change
   "plus Chromium forced to expose its accessibility tree" to "plus Chromium
   forced to expose its accessibility tree and to run on Wayland". Leave the
   rest alone.

   → Verify (session): `checks.x86_64-linux.microvm-template` builds.

3. **`tests/microvm-ai-mirror.nix`** (agy).
   - Update the header comment to name #1509 and #1510.
   - Add to the env attrs:
     - `luaText = cfg.environment.etc."hypr/hyprland.lua".text or "";`
     - `hasConf = lib.boolToString (cfg.environment.etc ? "hypr/hyprland.conf");`
     - `hyprExec = noCtx units.hyprland.serviceConfig.ExecStart;`
     - `chromiumCmd`: the `buildCommand` of the one package in
       `cfg.environment.systemPackages` whose `pname` is `chromium`, taken
       through `noCtx`. Use `lib.findFirst (p: (p.pname or "") == "chromium") null`
       and `throw` if it is null. Measured: `buildCommand` of
       `chromium.override { commandLineArgs = …; }` contains the flags.
   - Add (d) after (c):
     - `[ "$hasConf" = false ] || fail "the hyprland template still writes hyprland.conf"`;
     - `printf '%s' "$luaText" > "$d/hyprland.lua"` (create `d=$(mktemp -d)`
       earlier if needed; the file already makes `d` in (a), so put (d) after
       (a), or give it its own temp dir);
     - run `verify=$(env -i HOME=$dd XDG_RUNTIME_DIR=$dd ${pkgs.hyprland}/bin/Hyprland --verify-config --config "$dd/hyprland.lua" 2>&1) || true`;
     - `[[ $verify == *"config ok"* ]] || fail "Hyprland rejects the template's Lua: $verify"`;
     - for each of `Virtual-1`, `1920x1080`, `disable_splash_rendering` and
       `enable_stdout_logs`, `[[ $luaText == *"$k"* ]] || fail …`.
   - Add (e):
     - `[[ $hyprExec == */bin/start-hyprland\ --\ --config\ /etc/hypr/hyprland.lua* ]] || fail …`;
     - `--ozone-platform=wayland` and `--force-renderer-accessibility` must
       each be in `$chromiumCmd`.

   → Verify (session, cheap tier, under
   `flock /mnt/data/vmtest/codex-build.lock`):
   - Before building, `nix derivation show` on the check: its inputs must not
     include chromium, nixos-system or microvm derivations. `pkgs.hyprland`
     is expected and fine.
   - Build green.
   - **§1:** apply each break alone and prove it landed with `git diff`.
     Stage it, build it red, restore from a copy and re-stage:
     - (i) `disable_splash_rendering` → `disable_splash_renderingX` in
       hyprland.nix;
     - (ii) add an `etc."hypr/hyprland.conf".text = "";` back;
     - (iii) ExecStart back to `bin/Hyprland --config /etc/hypr/hyprland.lua`;
     - (iv) drop `--ozone-platform=wayland`.

     Capture each red line, then confirm the restored tree is green.
   - Also build `test-registration` and `grep-q-pipefail`, and run statix,
     deadnix and `nix fmt -- --ci`.

   Traps (tests/AGENTS.md):
   - Never name a variable `out`.
   - No `| grep -q`.
   - printf, not heredocs, inside `''`.
   - `--verify-config` exits 1 on a bad config (see Deviations); check both the status and the text.
   - If it needs more than `HOME` and `XDG_RUNTIME_DIR` in the sandbox,
     record that here as a deviation. Never drop the parse.

4. **Live on p620** (session; VM tier: `gh run list` shows 0 in flight).
   - Build the `hyprland-ai-mirror` runner from the branch into a scratch VM
     directory `t1509` under `~/.local/state/nixarchy/microvm/`, and start it
     as in #1508's step 5. Leave the owner's `ai-mirror` VM alone.
   - Drive it with the session's `mcp-drive.py`-style script over its CID:
     1. Take a screenshot and read it: no `.conf` toast and no start-hyprland
        toast.
     2. `hyprctl monitors` from a `launch`ed foot, or `windows`/`status`
        monitors: `Virtual-1` 1920x1080.
     3. `launch chromium` with no flags: a window appears in `windows`
        within 30 s, and `a11y_find` returns its controls.
     4. `kill -SEGV` Hyprland's pid, from a `launch`ed `sh -c`. Record what
        the journal and `status` show: whether it restarted, whether it ran in
        safe mode, and the monitor size afterwards.
   - If step 4 shows something the step 1 comment does not describe, fix the
     comment in the same commit as this plan's Deviations entry.
   - Stop only this VM's pid and remove its directory.

5. **PR:**
   - Link the three artifacts.
   - Include the red outputs, the live transcript and screenshot findings,
     and the crash result.
   - Say that agy did steps 1–3, or which it handed back, and that Codex and
     Opus reviewed.
   - `Closes #1509`, `closes #1510`, with the keyword repeated per issue (§8).

   Before opening it, read the bus, and post only if a §9 trigger fired.

6. **Merge:** `gh pr merge --auto --squash` (owner's standing preference).
   Watch it until merged. Check `mergeable` and the issues' state afterwards.

## Tests

| command | expect |
|---|---|
| `nix build .#checks.x86_64-linux.microvm-ai-mirror` | green; red under each of breaks (i)–(iv) |
| `nix build .#checks.x86_64-linux.{microvm-template,test-registration,grep-q-pipefail}` | green |
| statix, deadnix, `nix fmt -- --ci` | clean |
| step 4 | no toast, 1920x1080, Chromium window and a11y controls, crash behaviour recorded |

## Rollback

Revert the PR. Guests go back to the `.conf` config, the direct `Hyprland`
launch and X11 Chromium. Nothing on the host changes either way.

## Deviations found while implementing

- **`--verify-config`'s exit status is meaningful.** The spec said it "exits
  0 both ways". That came from `… | tail; echo $?`, which reads `tail`'s
  status, the pipeline trap in AGENTS.md §1. Measured directly with Hyprland
  0.56.2, it exits 0 with `config ok` on a good file and 1 with `unknown
  config key '…'` on a bad one. Inside the build sandbox, too, the bad case
  failed the derivation. So (d) checks both: `|| fail` on the exit status, and
  `config ok` in the text. Break (i) went red on the status
  (`unknown config key 'misc.disable_splash_renderingX'`).
- **The sandbox needs nothing beyond `HOME` and `XDG_RUNTIME_DIR`** for
  `--verify-config`, as the spec hoped.
