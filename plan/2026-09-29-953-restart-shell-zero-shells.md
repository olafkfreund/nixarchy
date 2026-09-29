---
status: approved
issue: 953
spec: spec/2026-09-29-953-restart-shell-zero-shells.md
---

# Plan: Restarting the shell never leaves zero shells

## Approved decisions

- **Part 1: exit wait.** A carried `--replace-fail` patch on upstream's line
  66 of `bin/omarchy-restart-shell`
  (`while timeout 5 quickshell kill … do :; done`). The replacement:
  - loops while `quickshell list -p "$CONFIG_DIR" --any-display` shows
    `Process ID:`;
  - re-issues `timeout 5 quickshell kill` inside the loop;
  - is bounded by `OMARCHY_SHELL_EXIT_TIMEOUT` (default 60). Past the bound
    it prints "did not exit within", exits 1, and does **not** launch.
  - The output is captured and pattern-matched, never piped into `grep -q`
    (#1058).
- **Part 2: readiness.** A second `--replace-fail` turns
  `for (( attempt = 0; attempt < 20; attempt++ ))` into
  `ready_deadline=$((SECONDS + ${OMARCHY_SHELL_READY_TIMEOUT:-60}))` and
  `while (( SECONDS < ready_deadline ))`. The body is unchanged.
- **The check.** `checks.shell-restart-race`, a stubbed `runCommand`. The
  script is unwrapped, so PATH stubs reach it. Four cases: slow teardown
  (patched), slow teardown (upstream, the negative control), wedged, fast.
- **Docs.** A `pkgs/AGENTS.md` section with the retirement condition, and a
  `tests/AGENTS.md` note on the check's reach.
- **Scope.** Carried here; not reported upstream (owner's decision).

## Steps

1. **`pkgs/omarchy/default.nix`**: the two `substituteInPlace --replace-fail`s
   on `$restartBin`, placed after #982's. The new text is built with `printf`
   lines, as #982's is, with no heredoc (§5), plus a `# Why:` pointer to the
   new `pkgs/AGENTS.md` anchor.
   - Verify: `nix build .#omarchy`, then read the patched script's two
     regions.
   - Verify: `bash -n` on the patched script.
2. **`tests/shell-restart-race.nix`**: a `runCommand` with `bash`,
   `coreutils`, `gnugrep`, `gnused` and `jq`.
   - A stub directory is prepended to PATH:
     - `quickshell` (`list`, `kill`);
     - `hyprctl` (`dispatch` starts the new shell, unless the old one is
       still alive, in which case the new one "exits already running");
     - `omarchy-shell` (`shell ping` succeeds while the new shell lives;
       `lock` not used);
     - `omarchy-hyprland-session-locked` (exit 1);
     - `systemctl` (`show-environment` prints `OMARCHY_PATH`; `try-restart`
       succeeds);
     - `sleep` is **not** stubbed.
   - State lives in files: death times as epoch seconds, `alive-old` and
     `alive-new` flags, a launch log.
   - The `list` stub prints a block copied verbatim from a real
     `quickshell list` (Process ID, Shell ID, Config path, …), so the patch is
     tested against the real label.
   - Runs the patched script from `${omarchy}/share/omarchy/bin` and the
     unpatched one from `${omarchySrc}/bin` (the negative control).
   - Stubs are written with `printf`, not heredocs (§5, nixfmt).
   - Each case prints its outcome, and the check refuses if any case did not
     run.
3. **`flake.nix`**: `checks.shell-restart-race = import ./tests/shell-restart-race.nix { pkgs; omarchy; omarchySrc = omarchy input; }`,
   beside `shell-restart-tree`.
4. **Docs.**
   - `pkgs/AGENTS.md`: a section "omarchy-restart-shell waits for the old
     shell to be gone (#953)", covering the mechanism, the p620 evidence (17
     minutes with no shell), both patches, and the retirement condition.
   - `tests/AGENTS.md`: a section on `shell-restart-race`, covering what the
     stubs pin and what only p620 can show (real teardown time).
5. **Baseline commit, then §1.** Local builds only with `gh run list` empty.
   - Green: `checks.shell-restart-race`, `checks.shell-restart-tree`,
     `.#omarchy`.
   - Break: remove the part-1 patch. Case 1 must fail with zero shells.
     Restore with `git checkout HEAD --`.
   - Break: remove the part-2 patch, with a case whose new shell takes 15 s
     to answer (case 1's new shell answers after 15 s, so the unpatched
     ~12 s poll fails). This proves part 2 is exercised too.
   - `nix fmt -- --ci`, statix, deadnix.
6. **PR.** Use the template and "Closes #953", link the three files, and
   include the break outputs. Merge when green and `mergeable`. After the
   merge, the p620 hand check (swap a plugin folder, restart at once) is left
   to the owner and noted in the PR.

## Tests

| Command | Expected |
| --- | --- |
| `nix build .#checks.x86_64-linux.shell-restart-race` | green, four cases reported |
| the same with the part-1 patch removed | red: case 1 ends with zero shells |
| the same with the part-2 patch removed | red: case 1 reports "did not become ready" |
| `checks.shell-restart-tree` | green |
| `nix build .#omarchy` | both `--replace-fail`s apply |

## Rollback

Revert the squash commit. The script returns to upstream's 5-second kill
loop, with the zero-shell race back.
