---
status: approved
issue: 707
spec: spec/2026-09-15-707-mise-launchers.md
---

# Plan: first login stops installing mise launchers that shadow Nix agents

A mise launcher exists only when Nix does not already provide the command.

## Decisions, carried from the approved spec

- **D1.** `omarchy-mise-install` exits 0 without writing anything when
  `$command` resolves on PATH with `$HOME/.local/bin` removed. It is patched
  with `substituteInPlace --replace-fail` in `pkgs/omarchy/default.nix`. It
  covers both callers: first login through `install/user/mise.sh`, and
  `omarchy-refresh-applications`. `mise.sh` and `all.sh` are untouched. Tools
  with no Nix command keep upstream's launcher.
- **D2.** New `pkgs/omarchy/nix-bin/omarchy-mise-unshadow`, marked
  `# nixarchy:new` so the nix-bin loop links it onto PATH, with a
  `# omarchy:summary=` line. It deletes `~/.local/bin/<name>` only when both
  hold:
  1. the file has a line matching `^mise use -g --quiet ` and a line matching
     `^exec mise x `;
  2. `<name>` is executable in `/etc/profiles/per-user/$USER/bin` or
     `/run/current-system/sw/bin`.

  Each deletion prints one line. `modules/home.nix` runs it from
  `home.activation.nixarchyMiseUnshadow` (`entryAfter [ "writeBoundary" ]`) via
  `run`, so dry-run is respected. The profile directories are arguments, so the
  check can pass fakes.
- **D3.** `tests/mise-launchers.nix` is a stubbed `runCommand` in the style of
  `tests/theme-set-zed.nix`, registered as `checks.mise-launchers` in
  `flake.nix` with a `# Why:` pointer. It covers cases (a)–(e):
  - (a) a Nix codex means no wrapper;
  - (b) no Nix codex means upstream's wrapper;
  - (c) the unshadow script removes a shadowing wrapper;
  - (d) it keeps a wrapper that has no Nix twin;
  - (e) it keeps a user script of the same name.

  **Differs from the spec:** no `build.yml` edit. The coverage guard's
  generated step builds every check not claimed elsewhere, as `theme-set-zed`
  is today.

## Steps

1. **`pkgs/omarchy/nix-bin/omarchy-mise-unshadow`: D2**, written as
   `unshadow [profile-bin-dir...]`, defaulting to the two real directories.
   → verify: shellcheck is clean; `nix build .#omarchy`; the script is on
   `result/bin`.
2. **`pkgs/omarchy/default.nix`: D1**, patching `omarchy-mise-install` next to
   the `omarchy-refresh-applications` substitution, with a note at the line.
   The guard goes before `rm -f "$HOME/.local/bin/$command"`: look the command
   up with a PATH that has `$HOME/.local/bin` filtered out; if found, print
   "provided by Nix, no mise launcher" and `exit 0`.
   → verify: `nix build .#omarchy`; the patched file contains the guard.
3. **`tests/mise-launchers.nix` and `flake.nix`: D3.**
   → verify: `nix build .#checks.x86_64-linux.mise-launchers` passes.
4. **Seen red, twice (§1).**
   - With the D1 guard removed, (a) fails.
   - With the unshadow script's deletion replaced by `:`, (c) fails.

   Capture both outputs, prove each break landed with `git diff`, then restore.
   → verify: red, red, green.
5. **`modules/home.nix`: the D2 activation**, only inside the enabled Home
   Manager config.
   → verify: `checks.options`, `stable-eval`, `config-warnings`; statix and
   deadnix are clean; `nix fmt` runs last.
6. **PR:** link intent, spec and plan; paste the red outputs; add the release
   note "Nix-installed agents are no longer shadowed by mise launchers; a
   rebuild removes existing ones"; `Closes #707`.
   → verify: `checks.session` and `build` are green in CI.

## Tests

```sh
nix build .#checks.x86_64-linux.mise-launchers --print-build-logs   # green; red under both breaks
nix build .#checks.x86_64-linux.options
nix run nixpkgs#statix -- check . && nix run nixpkgs#deadnix -- --fail .
```

## Rollback

Revert the squash commit. Launchers the unshadow script already deleted are
not restored. Anyone who wants them back runs `omarchy-refresh-applications`,
which the revert makes write every launcher again.
