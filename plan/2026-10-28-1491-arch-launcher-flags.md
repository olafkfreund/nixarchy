---
status: approved
issue: 1491
spec: spec/2026-10-28-1491-arch-launcher-flags.md
coders:
  1: codex   # self-contained shell + one Nix expression; codex is strong on both
  2: agy     # an independent author for the launcher's test, so it is not written by the launcher's author
  3: coder
  4: coder
  5: coder
  6: coder
reviewers:
  - codex
  - agy
---

# Plan: the browser flags Omarchy seeds reach the browser

## Approved decisions (from intent and spec)

- **A launcher** reads `${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf`
  at every start, as Arch's `/usr/bin/chromium` does:
  - one flag per line, skipping blank lines and `#` comments;
  - every `/usr/share/omarchy/` becomes `${OMARCHY_PATH:-/run/current-system/sw/share/omarchy}/`;
  - all `--enable-features=` values fold into one, plus
    `WaylandWindowDecorations` when `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY`
    are both set (nixpkgs' wrapper adds its own first, and Chromium keeps
    only the last);
  - it `exec`s `${chromium}/bin/chromium` with the file's flags, then `"$@"`.
- The seeded `config/chromium-flags.conf` stays verbatim. Existing homes are
  fixed by the launcher's rewrite.
- **Native hosts:** the two install scripts are patched to
  `HOST_PATH=/run/current-system/sw/bin/omarchy-chromium-{copy-url,ytdlp}-host`,
  with ledger rows, and run at every Home Manager activation. A failure warns.
- **Policy:** `environment.etc."chromium/policies/managed/omarchy.json"`,
  not `programs.chromium`.
- **Obsidian** is left alone, and #1493 is closed.
- **Brave** is out of scope.

## Steps

1. **The launcher.** coder: codex.
   - New `pkgs/omarchy/chromium-flags.sh` (bash, `set -euo pipefail`). It
     builds an array from the file as above and `exec`s
     `"$CHROMIUM_REAL" "${flags[@]}" "$@"`. `CHROMIUM_REAL` is substituted
     at build time; the stub test sets it at run time instead, so read it
     as `${CHROMIUM_REAL:-@chromium@}`. A missing file means no flags.
   - In `pkgs/omarchy/default.nix`, a `let` binding `chromium-flags` is a
     `symlinkJoin { name = "chromium-flags-${chromium.version}"; paths = [ chromium ]; postBuild = ...; }`.
     The `postBuild` removes `$out/bin/chromium` and
     `$out/bin/chromium-browser` and installs the script at both, with
     `substitute ... --replace-fail @chromium@ ${chromium}/bin/chromium`.
     Put `chromium-flags` in place of `chromium` in the runtime list
     (`:260`), with a one-line `# Why:` pointer to the new `pkgs/AGENTS.md`
     section.
   - Verify: `flock /mnt/data/vmtest/codex-build.lock nix eval --raw .#omarchy.drvPath`
     evaluates. Then build `.#omarchy` under the package-tier gate (§6;
     `vm-host-free.sh` must print `free` for both install and edge, and
     **exit** otherwise), and `ls -l result/...` shows that the
     runtime-profile's `bin/chromium` is the script.
   - Traps:
     - codex can't build, so the session runs every build.
     - nixpkgs-fmt hook: run `nix fmt` and read `git diff --stat` (§5).
     - `writeShellApplication` isn't used here, because the script must keep
       the caller's PATH.
     - Run `checks.grep-q-pipefail` after the shell edit (memory: it failed
       CI twice).
     - The script must not contain a literal `/usr` other than inside the
       rewrite pattern. The session `/usr` scan reads `bin/` of the
       omarchy tree, not this package. Check that it stays green anyway, in
       step 6.

2. **`checks.chromium-flags`.** coder: agy.
   - New `tests/chromium-flags-test.sh`. `$1` is the launcher, and a stub
     `CHROMIUM_REAL` prints one argv entry per line. Cases:
     - (a) a fixture file with a comment, a blank line, two
       `--enable-features=` lines and `--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url,/usr/share/omarchy/x`.
       Assert no `/usr/share/omarchy` survives, both paths start with
       `$OMARCHY_PATH`, there is exactly one `--enable-features=`, and its
       value holds both lines' features;
     - (b) the same with `NIXOS_OZONE_WL=1 WAYLAND_DISPLAY=w`, where the
       merged value also holds `WaylandWindowDecorations`;
     - (c) a caller argument `--foo` is the last line;
     - (d) with no file, the output is exactly `--foo`;
     - (e) with `OMARCHY_PATH` unset, the path uses
       `/run/current-system/sw/share/omarchy`.
   - In `flake.nix` beside `screencast-placement` (~`:2500`), a
     `runCommand "nixarchy-chromium-flags"` that runs it with
     `${./pkgs/omarchy/chromium-flags.sh}`. It is picked up by the
     generated-checks step, so no workflow edit (§4).
   - Verify: green, then red. Remove the rewrite line in a scratch copy,
     confirm the break landed with `grep`, and watch case (a) fail. Capture
     the output for the PR (§1).
   - Traps:
     - The cheap tier runs under `flock`.
     - `git add` before building (§5).
     - Use `printf`, not a heredoc, inside the Nix string (§5).

3. **Host scripts patched, with ledger rows.**
   - In `pkgs/omarchy/default.nix`, beside the other browser patches
     (~`:899-941`): `substituteInPlace` on
     `$out/share/omarchy/bin/omarchy-install-chromium-copy-url` and `-ytdlp`,
     replacing
     `--replace-fail 'HOST_PATH="$OMARCHY_PATH/bin/omarchy-chromium-copy-url-host"'`
     (and the ytdlp twin) with the `/run/current-system/sw/bin/...` path.
   - In `data/bin-ledger.nix`, `class = "patch"` rows for both, with the
     reason: the store path is garbage-collected after an update.
   - Verify: `checks.patched-files` and the bin-ledger check (find its
     name: `grep -n bin-ledger flake.nix`) are green. After the step 1
     build, `grep HOST_PATH result/share/omarchy/bin/omarchy-install-chromium-*`.
   - Traps: a patch needs its ledger row in the same change
     (`pkgs/AGENTS.md#a-patch-needs-its-ledger-row-in-the-same-change`).

4. **Registration at activation.**
   - In `modules/home.nix`, a new
     `home.activation.nixarchyChromiumHosts = lib.hm.dag.entryAfter [ "nixarchySeed" ]`.
     When `/run/current-system/sw/bin/omarchy-chromium-copy-url-host` is
     executable, run both `${omarchyPath}/bin/omarchy-install-chromium-*`
     with `OMARCHY_PATH=${omarchyPath}`, each wrapped
     `|| warnEcho "..."`.
   - Standalone Home Manager without NixOS has no such path, so it skips.
     Note that as the known gap in `pkgs/AGENTS.md`.
   - Verify: `nix eval` of a home config's activation script contains the
     block (find the HM test config used by `options-home`). The behaviour
     is proven in step 6.
   - Traps:
     - The scripts use `sed`, `mkdir` and `cat`, so check that HM's
       activation PATH has `gnused`. If not, run with an explicit
       `PATH=${lib.makeBinPath [ coreutils gnused ]}:$PATH`.
     - `$DRY_RUN_CMD`/`run` for writes, as `nixarchySeed` does.
     - Mode A: this sits under the same enable guard as `nixarchySeed`.

5. **The policy and its coexistence fixture.**
   - In `modules/nixos.nix`, next to the browser-policy tmpfiles block
     (`:1895-1912`):
     `environment.etc."chromium/policies/managed/omarchy.json".source = "${cfg.package}/share/omarchy/default/chromium/policies/omarchy.json";`
   - In `tests/coexistence/fixtures.nix`, the fixture
     `chromium-own-policy = { programs.chromium = { enable = true; extraOpts.BookmarkBarEnabled = true; }; };`.
     Then check how `checks.coexistence` asserts per fixture and add an
     assertion that both `default.json` and `omarchy.json` are in the
     toplevel's `etc`.
   - Verify: `checks.coexistence` is green. For red, temporarily point ours
     at `default.json`, and the fixture fails with the etc conflict.
   - Traps:
     - The tmpfiles `d` rule makes the directory user-owned for the theme
       script, and an `environment.etc` file inside it is a symlink that
       setup-etc creates. Confirm in step 6 that `color.json` is still
       written, since the existing accent probe at `tests/session.nix:1426`
       covers it.
     - `options-*` shards are VM-tier locally (§6), so leave them to CI.

6. **Session probe.**
   - In `tests/session.nix`, after the browser-accent block (`:1426-1445`):
     - `test -s /etc/chromium/policies/managed/omarchy.json`;
     - for both manifests under
       `/home/omarchy/.config/chromium/NativeMessagingHosts/`, the `path`
       field (read with `jq -r .path`) starts with `/run/current-system/sw/bin/`
       and `test -x` passes;
     - as the user on the desktop,
       `chromium --headless=new --remote-debugging-port=9223 --user-data-dir=$(mktemp -d) about:blank &`,
       then `wait_until_succeeds` `curl -s localhost:9223/json/list`
       listing `chrome-extension://bgpiichlckmfanooecilcjemknkcpngb/` and
       `chrome-extension://dedjgknigfeelejglamclffonmophnfl/` (timeout 60).
       Kill it by its pid, not by name.
   - Verify: CI builds `checks.session`. That is VM tier, so it runs
     locally only with nothing in flight. Red proof: on a throwaway branch
     with step 1's runtime-list change reverted, the service-worker
     assertion fails. Capture it for the PR.
   - Traps:
     - The check must be able to fail (§1).
     - `curl` and `jq` must be in the VM. Check
       `environment.systemPackages` in the session config first.
     - Bracket any `pgrep -f` pattern (`tests/AGENTS.md`).
     - `--load-extension` is still honoured by unbranded Chromium. If the
       probe shows it is not, stop and report rather than weaken it.

7. **Docs.** Self.
   - A `pkgs/AGENTS.md` section, "Chromium reads its flags through our
     launcher (#1491)": why it exists, the `--enable-features` fold, the
     host paths, and the standalone Home Manager gap.
   - In the PR body, a release-notes line that flags in
     `~/.config/chromium-flags.conf` now take effect.

## Deviations recorded during implementation

- Step 5: the policy entry sits inside `modules/nixos.nix`'s existing
  `environment.etc` attrset (next to `omarchy/xcompose`), not beside the
  tmpfiles rules, because a second `environment.etc =` in the module would
  clash. nixpkgs' `programs.chromium` writes `extra.json` for `extraOpts`, and
  `default.json` only for `defaultProfile`, so the fixture asserts `extra.json`
  and `omarchy.json`. Red: pointing ours at `extra.json` prints
  `chromium-own-policy: FAIL extra.json and omarchy.json are not both in etc`.
- Step 4: the activation prefixes `PATH` with coreutils and gnused
  unconditionally rather than probing Home Manager's activation PATH.

## Tests

- Cheap tier (`flock`):
  - `checks.chromium-flags`, `patched-files`, the bin-ledger check,
    `coexistence`, `grep-q-pipefail` and `runtime-profile`;
  - `nix fmt -- --ci`;
  - statix and deadnix.
- Package tier, gated: `.#omarchy`.
- CI: `checks.session` and the `options-*` shards.

## Rollback

Revert the squash commit. The seeded flags file was never touched. Host
manifests already written point at `/run/current-system/sw/bin`, which
still exists after a revert; the old behaviour wrote store paths.
