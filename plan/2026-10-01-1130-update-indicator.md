---
status: approved
issue: 1130
spec: spec/2026-10-01-1130-update-indicator.md
---

# Plan: Detect an available Nixarchy release for the bar

The Omarchy shell's `SystemUpdate.qml` runs `omarchy-update-available` at
startup, every six hours, and on IPC refresh. It shows its icon only for exit
0; every other exit hides it. This task answers only whether the machine's
moving Nixarchy `release` input has a proven newer published release. It does
not detect nixpkgs updates. `omarchy update` remains the icon's action.

The installer's `installer/mkFlake.nix:35-39,122-148` writes a moving
`original.ref = release` and an exact `locked.rev`; old or user-owned flakes
can instead pin a tag, exact rev, other branch, or local path. Read the user's
`flake.lock` without Nix evaluation; `programs.nixarchy.flake` defaults to
`/etc/nixos` (`modules/apps.nix:1114-1117`) and reaches session commands as
`NIXARCHY_FLAKE` (`modules/nixos.nix:1185-1189`). Exit 1 for uncertainty,
offline state, bad or unreadable locks, unsupported pins, and equal or older
releases. The check's network budget is one timeout-bound Git invocation.

## Steps

1. **`tests/update-available.nix` and `flake.nix:1751-1760`:** create a
   network-free `runCommand` check and register it in `uniformChecks` (its
   function arguments are `{ inputs, pkgs }`). Run the actual replacement
   script with fixture `flake.lock` files and a fake `git` on PATH; use the
   real `jq` and `timeout` from build inputs. The fake emits branch and tag
   refs and records each invocation. Begin with a newer-tagged-release case
   that expects exit 0; add explicit ShellCheck of the script. Stage the new
   test file and `flake.nix` with `git add`, because an unstaged new file is
   invisible to flake evaluation (`AGENTS.md` §5). Under the shared build
   lock, build only this check **before changing the script**.
   Save the failing output: the newer-case assertion must report the current
   `exit 1`, rather than an evaluation error or missing fixture. This is the
   red proof required by `AGENTS.md` §1 and `tests/AGENTS.md:10-16`.
   → verify: `nix build .#checks.x86_64-linux.update-available
   --print-build-logs` fails for that assertion; `git diff --cached` shows
   registration and the new test. No live network access is allowed in the
   check. Traps: use `printf`, not an indented Nix-string heredoc (§5); a
   sourced-function test alone would miss package installation and ShellCheck.

2. **`pkgs/omarchy/nix-bin/omarchy-update-available:6-18`:** replace `exit 1`
   and its obsolete comment, keeping the first-line Omarchy metadata and
   exit-only interface. Read `${NIXARCHY_FLAKE:-/etc/nixos}/flake.lock` with
   `jq`. Resolve `.nodes.root.inputs.nixarchy` to its actual node name, then
   require `original.type = github`, `owner = olafkfreund`, `repo = nixarchy`,
   `ref = release`, and a full 40-hex-character `locked.rev`. Missing,
   unreadable, malformed, different-source, tag, rev, path, and other-branch
   locks return 1 before the network call. Do not parse arbitrary
   `flake.nix` syntax or evaluate the flake.
   → verify: the check's non-release fixture cases return 1 and record zero
   fake-Git invocations. Trap: an error under the bar must mean hidden icon,
   not a spinner or shell error code.

3. **The same script:** for an eligible lock, invoke
   `git -c credential.helper= ls-remote --heads --tags` against the fixed
   Nixarchy HTTPS repository exactly once under `timeout 10`. Set
   `GIT_TERMINAL_PROMPT=0`, `GIT_CONFIG_GLOBAL=/dev/null`,
   `GIT_CONFIG_NOSYSTEM=1`, `GIT_ASKPASS=false`, and `SSH_ASKPASS=` so neither
   terminal nor desktop credentials can interrupt the bar. Parse the
   `release` branch tip and only `v<major>.<minor>.<patch>-<revision>` tags.
   Use peeled `^{}` commits for annotated tags and direct commits for
   lightweight tags. Require both the branch tip and installed `locked.rev`
   to match release-tag commits, and compare all four numeric version
   components; exit 0 only if the tip's tag is higher than every tag matching
   the installed commit. Empty or malformed refs, Git failure, timeout,
   untagged commits, and equal or older tips exit 1. This prevents a different
   SHA from being mistaken for a newer release. The release workflow advances
   `release` only after publishing and checking its assets
   (`docs/internals/workflows.md:297-301`).
   → verify: newer returns 0; same, older, untagged, timeout, and offline
   return 1; eligible cases record one fake-Git invocation. Trap: Git output
   can include both annotated tag objects and peeled commits; compare commits,
   and compare numeric components so `-10` sorts after `-9`.

4. **`tests/update-available.nix`:** complete the fixture matrix: newer,
   same, older, untagged installed and tip, annotated and lightweight tags,
   multiple tags for one commit, Git failure, timeout, unreadable and malformed
   lock, missing input, and tag/rev/path/other-branch pins. Assert exact exit
   codes and fake-Git call counts, including no call before a valid release
   lock. Ensure the green newer case actually reached the fixture and fake.
   Assert the fake Git sees the prompt-blocking environment and cleared
   credential helper. Feed valid newer refs before the Git-failure and timeout
   cases, so removing `|| exit 1` or `timeout 10` makes each check red. For
   the timeout negative control, copy the script aside, remove `timeout 10`
   temporarily, run and capture red, then restore with `cp` and rerun green.
   Keep the explicit `shellcheck` invocation: Omarchy's replacements are
   copied as **unwrapped** scripts by `pkgs/omarchy/default.nix:1013-1034`,
   so its package build does not run `writeShellApplication`'s ShellCheck.
   → verify: the focused check passes. Then copy the working script to a
   scratch file under `/mnt/data/vmtest/`, write the original `exit 1` version
   into the script from the pre-change commit, stage it, and rerun the check
   to capture a second newer-case red. Restore with `cp` from the scratch
   file, stage it, and rerun green. Inspect `git diff` after each swap to
   prove the intended break and restoration landed. **Do not use `git
   checkout` to restore files**; it can discard someone else's work.

5. **`pkgs/omarchy/default.nix:184-195,282` and `flake.nix:1320-1329`:**
   verify the existing shared `runtimeDeps` already carry `coreutils`
   (`timeout`), `jq`, and `git` into the installed system; add no duplicate
   declarations. Build the Omarchy package to verify the replacement is
   installed, and build `omarchy-runtime` to verify the three commands resolve.
   If implementation unexpectedly adds a `writeShellApplication`, its own
   package build must also run because that builder runs ShellCheck.
   → verify: focused package builds pass and the resolved runtime paths
   contain `jq`, `git`, and `timeout`. Trap: the unwrapped Omarchy package's
   closure alone does not prove runtime tools reach PATH; they enter via the
   module's `systemPackages` and `passthru.runtimeDeps`.

6. **`docs/manual/updates.md:43-44` and `data/bin-ledger.nix:608-611`:** say
   the icon tracks newer Nixarchy releases only for the moving `release` pin
   and stays hidden offline or for custom/fixed pins. Update the ledger's
   replacement reason to describe the bounded release check. Keep the
   existing manual page; no new navigation entry is
   needed (`docs/AGENTS.md`). Run `nix fmt -- --ci`, the repository's statix
   and deadnix commands, and `git diff --check`. Read `git diff --stat` after
   any formatting; `nix fmt` can rewrite unrelated lines if a Nix string is
   misindented (§5). The generated-checks workflow discovers the registered
   check automatically (`AGENTS.md` §4), so leave `.github/` unchanged.
   → verify: static gates pass and the diff contains only the script, focused
   check, `flake.nix` registration, ledger reason, and manual sentence.

## Tests

An orchestrator-directed local build gate change, pending owner confirmation:
run cheap `runCommand`, static, and evaluation checks under the shared
`/mnt/data/vmtest/codex-build.lock` even while CI runs. Run non-cheap package
builds under that lock only when
`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` returns 0 and
load1 is below 12 immediately before the build. VM and `checks.options`
stay CI-only unless separately authorized.
This directed gate replaces the earlier CI-zero requirement for this task;
it is recorded as an implementation deviation, not owner approval. Do not run broad
VM or installer checks for this shell command. Stage newly added files before Nix
evaluation. `installer/mkFlake.nix` needs a committed `self.rev`; this plan's
focused check and package builds must not pull in installer derivations while
the implementation tree is dirty.

The minimum gates after implementation are:

```sh
nix build .#checks.x86_64-linux.update-available --print-build-logs
nix build .#packages.x86_64-linux.omarchy --print-build-logs
nix build .#packages.x86_64-linux.omarchy-runtime --print-build-logs
nix fmt -- --ci
nix run --inputs-from . nixpkgs#statix -- check .
nix run --inputs-from . nixpkgs#deadnix -- --fail .
git diff --check
```

Expected: the first check is red against the saved original script and green
against the fix; only the newer release fixture exits 0; no fixture reaches
the network; the package and runtime build; ShellCheck and static gates pass.
Capture the red output for review. No deployment, CI workflow edit, or host
build is needed.

## Rollback

Revert the implementation commit that changes the command, check,
registration, and manual, restoring the old always-hidden behavior. Keep the
approved intent and spec as the decision record. Do not roll back an installed
machine or edit its `flake.lock` for this change.
