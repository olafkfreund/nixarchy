---
status: approved
issue: 1031
spec: spec/2026-09-28-1031-hyprland-056-lua-fallback.md
---

# Plan: hypr-rdp's Lua fallback never fires on Hyprland 0.56

## Approved decisions, carried from the spec

- **The bug.** Hyprland 0.56 answers `unknown request` to the legacy `keyword`
  IPC request. hypr-rdp's `is_non_legacy_parser_error()` (`src/hyprland.rs:250-254`
  of the pinned source) matches only `non-legacy parsers`, so its correct
  fallback -- `eval hl.monitor({...})` -- never fires and the daemon exits with
  `failed to set headless output resolution`.
- **The fix** is a patch carried here,
  `pkgs/hypr-rdp/lua-fallback-on-unknown-request.patch`: the matcher also
  accepts `unknown request`, plus one unit test asserting it. Nothing else in
  the fallback changes.
- **Applied** by `overrideAttrs` on the overlay attribute in `flake.nix`,
  adding the patch and turning tests back on for the patched module only:
  `doCheck = true; checkFlags = [ "hyprland::tests" ];`. Upstream sets
  `doCheck = false`; without this the unit test never runs. The vendor hash
  does not move: only `.rs` changes, and `cargoDeps` comes from `src`.
- **Documented** in the existing flake.md section, with the retirement
  condition: drop the patch when a hypr-rdp tag carries the wider matcher. The
  build says when -- the patch stops applying.
- **Probe:** `checks.session` enables the daemon and asserts it brought up its
  headless output at the configured resolution, after first asserting the VM's
  Hyprland refuses `keyword` -- so the probe cannot pass without exercising the
  fallback.
- **Not filed upstream.** Nothing goes to `MuNeNiCK/hypr-rdp` without the
  owner's explicit word (§11).

## One deviation from the spec, for approval with this plan

The spec says the test-only age key is **committed** under
`tests/fixtures/hypr-rdp/`. This plan **generates it at build time** instead:
a `runCommand` inside `tests/session.nix` runs `age-keygen` and `sops -e`,
exactly as `tests/secret-enroll.nix:41-44` already does. Same fixture, no
private key in the repository -- nothing for a future secret scanner to
misread, and no one has to wonder whether it protects anything. The test never
needs the password itself; it does not connect.

## Steps

**0. Before any local build:**
`gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
must print 0 (§6). Repeated before steps 2, 3, 6 and 7.

1. **Patch file.** Move the untracked `pkgs/patches/hypr-rdp-lua-fallback-on-unknown-request.patch`
   to `pkgs/hypr-rdp/lua-fallback-on-unknown-request.patch`; remove the empty
   `pkgs/patches/`. Add a hunk after upstream's test at `:604`:
   `non_legacy_parser_error_detection_matches_unknown_request`, asserting
   `anyhow!("Hyprland IPC error: unknown request")` is detected.
   → verify: `patch -p1 --dry-run` applies cleanly against a scratch copy of
   `nix flake archive --json . | jq -r '.inputs["hypr-rdp"].path'`.

2. **Overlay.** `flake.nix`, the `hypr-rdp =` attribute: the `overrideAttrs`
   exactly as in the spec, `# Why:` pointer kept. `nix fmt`, then read
   `git diff --stat` (the nixpkgs-fmt hook, §5).
   → verify: `nix build .#hypr-rdp --print-build-logs` green, and the log shows
   `hyprland::tests` running with 3 passed. Record the build time with tests
   on, for the PR.

3. **Unit test red (§1).** Commit steps 1–2 as a baseline first (the memory:
   `git checkout HEAD` eats uncommitted work). Break: delete the matcher hunk
   from the patch, keep the test hunk; `git diff` to prove the break landed.
   → verify: `nix build .#hypr-rdp` fails in `cargo test`, naming
   `..._matches_unknown_request`. Capture it. Restore with
   `git checkout HEAD -- pkgs/hypr-rdp/`; green again.

4. **Docs.** `docs/internals/flake.md`, section "The RDP daemon, re-exported
   from its own flake…": a paragraph -- what the patch fixes, that it is the
   wrong way round, the retirement condition, and why checks are scoped to one
   module.
   → verify: `grep -n "unknown request" docs/internals/flake.md`.

5. **Session probe.** `tests/session.nix`:
   - `let`: a `rdpFixture` `runCommand` (`age`, `sops` in
     `nativeBuildInputs`) writing `$out/age.key` and `$out/rdp.yaml` holding
     `hypr-rdp-password: <random>`, encrypted to that key with an explicit
     `--age` recipient.
   - `nodes.machine`: `sops.age.keyFile = "${rdpFixture}/age.key";`,
     `sops.secrets.hypr-rdp-password.sopsFile = "${rdpFixture}/rdp.yaml";`, and
     `programs.nixarchy.services.hypr-rdp = { enable = true; passwordSecret = "hypr-rdp-password"; };`
     (user left at the module's default).
   - `testScript`, once the session is up (after the existing pkexec block,
     which already exports `HYPRLAND_INSTANCE_SIGNATURE`), through the existing
     `as_user` helper:
     a. **The variable guard:** `hyprctl keyword monitor ...` prints
        `unknown request`. If not, fail saying this Hyprland still accepts
        `keyword`, so the probe no longer exercises the fallback.
     b. **The property:** `wait_until_succeeds` that `hyprctl monitors -j`
        lists an output other than the VM's own with `width` 1920 and `height`
        1080. By resolution, not name: upstream calls its output `hypr-rdp-1`
        (`src/hyprland.rs:593`), not `HEADLESS-N`.
     c. `journalctl --user -u hypr-rdp` does not contain `unknown request`.
     d. `systemctl --user is-active hypr-rdp` -- **if the VM can support it**;
        see the decision point.
   - The timeout on (b) is the first run's measured time ×3, with the
     measurement in a one-line comment -- not a guess.
   → verify: build the check (step 6's procedure), green.

   **Decision point.** The daemon may fail in the VM *after* setting the mode
   for a reason unrelated to this bug (no GPU for capture, pipewire). If so,
   (d) is dropped, (b) and (c) carry the probe, and this plan is updated **in
   the same commit** saying so, with the VM's journal line as the reason. (b)
   remains exactly what this bug breaks: the daemon dies before the mode is set.

6. **Session red (§1).** Take the patch out of the overlay (the `patches` line
   only), commit it as a temporary commit, prove with `nix derivation show`
   that the closure's hypr-rdp has no patch. Evaluate
   `nix eval --raw .#checks.x86_64-linux.session.drvPath`, build `'<drv>^*'`
   (no stale evaluation, §5), only at step 0's 0.
   → verify: fails on (b), with `unknown request` in the printed journal.
   Capture it. Drop the temporary commit; rebuild green the same way.

7. **Lint.** `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
   `nix run nixpkgs#deadnix -- --fail .`. Update the lines in
   `tests/AGENTS.md` and `tests/install-matrix.py` describing RDP coverage
   (`grep -n -i "rdp\|remote desktop"`; the `tests/remote-tunnel.nix` header
   names them): `session` now starts the daemon; a real client connection
   remains a two-machine hole.
   → verify: all exit 0; `git diff --stat` lists only files named in this plan.

8. **PR.** Squash to one commit, full-sentence subject (§8), e.g. "hypr-rdp
   brings its desktop up on Hyprland 0.56, and the session check now starts
   it". Template filled including both failing outputs (steps 3 and 6); links
   to all three artifacts; `Closes #1031` and nothing beside the keyword.
   Before opening: `read_new` on the bus; post only if a trap qualifies
   (upstream's `doCheck = false` making a carried test inert is a candidate).

9. **The real machine** (after merge, owner's deploy). Check the CI queue is
   empty before deploying to p620 (§6: a deploy kills installs in flight). Then
   `systemctl --user status hypr-rdp` active, `hyprctl monitors` lists the
   output, and `nixarchy remote connect` from razer reaches p620's desktop.

## Tests

| command | expected |
|---|---|
| `nix build .#hypr-rdp` | green; `hyprland::tests` 3 passed |
| same, matcher hunk removed | red in `cargo test`, naming the new test |
| `nix build '<session drv>^*'` | green; probe (a)–(c) pass |
| same, patch out of the overlay | red on (b); journal shows `unknown request` |
| `nix fmt -- --ci`, statix, deadnix | exit 0 |
| `checks.hypr-rdp-builds` (from #1034) | still green -- it forces the now-patched package |

## Rollback

Revert the single commit. The overlay returns to upstream's unpatched package,
`checks.session` loses the RDP block, and no host state changes. On p620/p510,
roll back to the previous system generation. No data or secret migration to
undo.
