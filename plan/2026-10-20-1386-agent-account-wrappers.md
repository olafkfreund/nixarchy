---
status: draft
issue: 1386
spec: spec/2026-10-20-1386-agent-account-wrappers.md
---

# Plan: on edge, `omarchy agent account use` changes the account that the next `claude`, `codex` or `grok` actually runs as

## Decisions (from the approved intent and spec)

- **Edge only.** The code lands as one carry commit on `edge-candidate`
  (base 14888ef8, quattro 0a7beb7). `main` has none of these commands. The
  intent, spec and plan go to `main` in a docs PR with `Refs #1386`.
- **Install upstream's wrappers file.** The `etc-overlay` row for
  `mise/conf.d/omarchy-agent-accounts.toml` goes `divergent` → `installed`.
  `modules/nixos.nix` (~:1703) then installs
  `${cfg.package}/share/omarchy/etc/mise/conf.d/omarchy-agent-accounts.toml`
  as `/etc/mise/conf.d/omarchy-agent-accounts.toml`. No code in `modules/`.
- **No mise install in place of Nix.** `bin/omarchy-agent-account-exec`
  refuses with exit 127 and a message naming `omarchy default agent <x>`.
- **The launchers are unchanged.** `omarchy-agent` already resolves the
  account (upstream lines 157-178), and a check case proves it.
- **A stubbed `runCommand` check, not a VM:** `checks.agent-account-routing`.

### A deviation from the spec, decided here

The spec replaced the whole fallback body (`export MISE_MINIMUM_RELEASE_AGE=0`
through `agent_binary=$(mise which "$provider")`). `pkgs/omarchy/default.nix`
requires every `--replace-fail` pattern and replacement to be one line,
because `nix fmt` re-indents multi-line strings (comment at ~:1225). So the
patch replaces one line, the first line of the fallback:

```
  export MISE_MINIMUM_RELEASE_AGE=0
```

with

```
  echo "$provider is not installed. nixarchy installs it through Nix: omarchy default agent $provider" >&2; exit 127
```

The `mise install` / `mise use -g` lines stay in the file but are
unreachable. Same behaviour, one-line patch. Check case 4 proves nothing past
the `exit` runs.

Also corrected from the spec: quattro ships **11** `omarchy-agent-account-*`
commands, not 12. That does not change the design.

## Steps

All edits are in a new worktree off `edge-candidate`:

```bash
git -C /mnt/code/Source-home/nixarchy fetch origin edge-candidate
git -C /mnt/code/Source-home/nixarchy worktree add -b carry/1386-agent-account-wrappers \
  /mnt/data/vmtest/wt-1386-edge origin/edge-candidate
```

1. **`data/etc-overlay.nix:104-107`**: set `class = "installed";` and
   replace `reason` with:
   > mise `[wrappers]` routing claude, codex and grok through
   > `omarchy-agent-account-exec`, so `omarchy agent account use` reaches a
   > CLI started in an activated shell. nixpkgs' mise reads `[wrappers]`
   > (2026.10.3, measured). The launchers resolve the account themselves.
   > The exec's mise install fallback is patched to refuse (#1386).

   → verify: `checks.etc-overlay` (cheap).
   Traps: none.

2. **`pkgs/omarchy/default.nix`, right after the `omarchy-agent`
   `substituteInPlace` (~:1215-1217)**:
   - add a `substituteInPlace $out/share/omarchy/bin/omarchy-agent-account-exec`
     with the single `--replace-fail` pair above;
   - put one comment line above it: no mise download of an agent nixarchy
     chose not to install, see `nix-bin/omarchy-default-agent` (#1386).

   → verify: `.#omarchy` builds. That is the "not cheap" tier: no p620
   system build running (`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'`
   prints 0) and the 1-minute load below 12.
   Traps:
   - The pattern and the replacement are each one line (§ above).
   - The pattern keeps its two leading spaces, so it matches only that
     line.
   - Run `nix fmt`, then `git diff --stat`, because a hook may have
     reformatted the file with `nixpkgs-fmt` (CLAUDE.md §5).

3. **`data/bin-ledger.nix`, after the `"omarchy-agent-crash"` row
   (~:131)**: add
   ```nix
   "omarchy-agent-account-exec" = {
     class = "patch";
     reason = "Its mise install fallback refuses with exit 127 instead: nixarchy installs claude, codex and grok through Nix, and one it did not install (unfree off) stays not installed (#1386).";
   };
   ```
   → verify: `checks.bin-ledger` (cheap; it builds `.#omarchy`, so it runs
   after step 2's build).
   Traps: the ledger fails in both directions, so the row and step 2 land
   together.

4. **`tests/options.nix:1098`**: next to
   `etcMise = etcInstalled "mise/conf.d/omarchy.toml";`, add
   `etcMiseAccounts = etcInstalled "mise/conf.d/omarchy-agent-accounts.toml";`.
   Follow every use of `etcMise` in the file and assert the new name the
   same way, in both states.
   → verify: CI only. `checks.options` is the VM tier (11.5 GB), so do not
   run it locally.
   Traps: `modules/nixos.nix` says `tests/options.nix` names every installed
   row in both states. Without this step the row is installed and
   unasserted.

5. **`modules/AGENTS.md`, section "Three files from upstream's /etc overlay,
   installed as themselves" (~:393)**: add one sentence naming
   `mise/conf.d/omarchy-agent-accounts.toml` as installed on edge, and why
   (#1386).
   Traps: **do not rename the heading.** `modules/nixos.nix:1702` links its
   anchor.

6. **New `tests/agent-account-routing.nix`, plus a `flake.nix` entry after
   `language-edge` (~:2276)**, in the same shape:
   ```nix
   # Edge carry (#1386): mise's [wrappers] route claude through the selected
   # account, and the exec refuses a mise install.
   agent-account-routing = import ./tests/agent-account-routing.nix {
     pkgs = pkgsFor.${system};
     omarchy = self.packages.${system}.omarchy;
   };
   ```
   Model the check on `tests/language-edge.nix`: a `runCommand` with
   `fails`/`bad()`, stubs in `$PWD/stub`, and `test "$fails" -eq 0`.

   **Setup:**
   - Isolate all state under `$PWD` (CLAUDE.md §4: moving `HOME` alone is
     not isolation): `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
     `XDG_STATE_HOME`, `XDG_CACHE_HOME`, `MISE_DATA_DIR`, `MISE_CONFIG_DIR`,
     `MISE_STATE_DIR` and `MISE_CACHE_DIR`.
   - `MISE_SYSTEM_CONFIG_DIR` is a dir whose `conf.d/` holds a copy of
     `${omarchy}/share/omarchy/etc/mise/conf.d/omarchy-agent-accounts.toml`.
     That is the same file `modules/nixos.nix` installs. Confirm mise reads
     `conf.d` under that variable, with `mise config ls`.
   - PATH: `${omarchy}/share/omarchy/bin`, `pkgs.mise`, `jq`, `python3`
     (`omarchy-agent-account-state` is Python), coreutils, gnugrep and bash.
   - A stub `claude` prints
     `CFG=${CLAUDE_CONFIG_DIR-unset} PIN=${OMARCHY_AGENT_CLAUDE_HOME-unset}`.
     PIN is set (possibly to empty) only by the exec, so it proves which
     route was taken.
   - Stub `omarchy-notification-send`, `omarchy-agent-usage-update` and
     `omarchy-i18n` to no-ops.
   - A helper `run_in_shell` runs `bash -c` with
     `eval "$(mise hook-env -s bash)"` and then the command. That is what an
     activated interactive shell does.

   **Cases:**
   1. **Selected account reaches a typed `claude`.** Create account
      `work` through the shipped commands: `omarchy-agent-account-add` if it
      completes without a real login, otherwise the
      `omarchy-agent-account-state` subcommands it calls (`begin` /
      `register`). Then `omarchy-agent-account-use claude work`.
      `run_in_shell claude` must print
      `CFG=<omarchy-agent-account-home claude>`, and that value must be
      non-empty.
   2. **No accounts (implicit Main).** In a fresh state dir,
      `run_in_shell claude` prints `CFG=unset PIN=` (empty, but set) and
      exits 0.
   3. **A user's own wrapper wins.** `$XDG_CONFIG_HOME/mise/config.toml`
      sets `[wrappers.claude]` with `command = "echo"` and
      `args = ["USER"]`. The output is `USER`.
   4. **No claude: refuse, install nothing.** The PATH has no stub
      `claude`. Calling `omarchy-agent-account-exec claude` directly exits
      127, stderr contains `omarchy default agent claude`, and
      `$MISE_DATA_DIR/installs` does not exist.
   5. **The launcher follows the account.** With account `work` selected,
      stub `omarchy-default-agent` to print `claude`. Then
      `omarchy-agent --inline` prints `CFG=` work's home. This runs outside
      `run_in_shell`, because no wrapper is involved.

   → verify: green under
   `flock /mnt/data/vmtest/codex-build.lock nix build "$(nix eval --raw .#checks.x86_64-linux.agent-account-routing.drvPath)^*" -L`.
   Traps:
   - `git add` the new file before evaluating (§5).
   - Write files with `printf '%s\n'`, not heredocs (§5, nixfmt reindent).
   - If `hook-env` alone does not create `command-wrappers/bin/claude`,
     **stop and report.** Do not add `mise reshim` silently: that is the
     spec's open risk, and the answer changes what p620 must check.

7. **§1 proof, by the lead.** In a `git worktree add --detach` scratch
   tree, run two reds and then the green:
   - **red 1:** step 1's row set back to `divergent`, with the check
     pointed at a `MISE_SYSTEM_CONFIG_DIR` without the file. Equivalently,
     the check copies the toml only if the row is `installed`. Case 1
     must fail, with `CFG=unset`.
   - **red 2:** step 2's `substituteInPlace` removed. Case 4 must fail:
     the exit is not 127, or the message is missing.
   - **green:** on the real tree.

   Prove each break landed (`git diff`) before reading its result. Save the
   logs under `/mnt/data/vmtest/proof-1386-*.log`.

   For red 1, the check must derive whether to copy the toml **from
   `data/etc-overlay.nix`'s class**, not copy it unconditionally. Otherwise
   it cannot fail when the row reverts, and that would be a check of the
   arrangement, not the property (§1). Read the class with
   `(import ../data/etc-overlay.nix)."mise/conf.d/omarchy-agent-accounts.toml".class == "installed"`.

8. **Land it.**
   - `nix fmt -- --ci`, `statix`, `deadnix`.
   - One commit, subject *"On edge, `omarchy agent account use` reaches the
     next claude, codex or grok typed in a shell, and the exec never mise-installs
     an agent (#1386)"*.
   - `git merge-base` must equal `origin/edge-candidate`, and
     `git show --stat` must list only the files above.
   - `git push origin HEAD:edge-candidate`: a fast-forward, never a force.
   - Then open the docs PR to `main` with intent, spec and plan,
     `Refs #1386`, linking the carry commit. It says the coder did steps
     1-6.

9. **Promotion and p620**, only after your go-ahead:
   - an `omarchy-edge` dispatch with `from_candidate`;
   - then, on p620 on edge, in a fresh terminal,
     `omarchy agent account use claude <second account>`, after which
     `claude` shows that account's login, and the agent keybinding does
     too;
   - close #1386 after that.

## Tests

| check | tier | expected |
|---|---|---|
| `checks.agent-account-routing` | cheap, flock | green; red 1 fails case 1, red 2 fails case 4 |
| `checks.etc-overlay`, `checks.bin-ledger` | cheap, flock | green |
| `.#omarchy` | package tier | builds |
| `checks.options` | CI only | green, with the new `etcInstalled` |

Edge verify builds the generated check list (#1392), so the new check runs
there without a workflow edit (§4).

## Rollback

`git revert` the carry commit on `edge-candidate`. The row goes back to
`divergent`, the exec to upstream's, and the check goes. An edge machine
that has already switched loses `/etc/mise/conf.d/omarchy-agent-accounts.toml`
at its next switch. Account registries under `~/.local/state/omarchy/agents`
are upstream's and are not touched either way.
