---
status: approved
issue: 1644
spec: spec/2026-11-07-1644-proof-survives-unchanged-commit.md
coders:
  1: codex  # small tricky shell: worktree, probe commit, eval loop, floor and EXIT trap; the session runs it
  2: coder  # move one let-binding into a new file and drop three references
  3: codex  # small tricky shell: the version reader under set -u, and a self-check that has to be able to fail
  4: coder  # one /etc entry and one gated xdg.configFile entry
  5: codex  # small tricky Nix: a recursive let that must not capture itself, plus the commit-bound switch
  6: coder  # per-check remedies from step 1's list; mostly re-pointing configurations at checkInputs
  7: coder  # two assertions and one Mode A key in an existing runCommand
  8: agy    # mechanical prose moves: the flake.md section, its pointer, tests/AGENTS.md and the manual line
  9: coder  # one nightly job and one branch in the report ladder; a human merges it
reviewers:
  - codex  # read-only review of each commit against this plan; it reads the Nix and shell directly
  - agy    # read-only second reading of the plan and diff, answering from the text given
---

# Plan: A check's proof survives a commit that changes nothing it builds

## Approved decisions (carried from the spec and the owner)

1. **The rev leaves `omarchy`.** New `modules/revision.nix` (`self: { shortRev; date; }`) holds today's `flake.nix:530-548` logic verbatim: `self.shortRev or self.dirtyShortRev or "unknown"` (a dirty tree still says `-dirty`), and `lastModifiedDate` → `YYYY-MM-DD`, falling back to `"unknown"`, with its comment about the offline install. `flake.nix` loses `nixarchyRev`, `nixarchyDate` and their `inherit` at `:843`.
2. **`nixarchy-version` reads a file at run time:** the first that exists of `/etc/nixarchy/version` and `${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/version`. The file holds one line, `<shortRev> <date>\n`. With no file it prints `unknown  unknown`. The output format doesn't change, because `pkgs/verify.sh:55-62` and `tests/channel.nix:444-466` read it. The script still has no runtime dependency.
3. **The module writes the file.** `modules/nixos.nix` adds `"nixarchy/version".text` to the `/etc/nixarchy` block (`:1743-1747`), which already sits under `cfg.enable`, so Mode A stays inert. `modules/home.nix` adds `xdg.configFile."nixarchy/version"` only when `osConfig == null` (standalone Home Manager).
4. **The catalogue keeps the commit in its URLs and keeps its shape.** `modules/nixos.nix:284` and `pkgs/microvm.nix:65` don't change. Checks stop seeing the real rev because they get a placeholder `self`.
5. **Checks get a placeholder `self`.** `checkInputs` sits beside `stableInputs` (`flake.nix:505-516`) and sets `rev` to forty zeros, `shortRev = "0000000"`, `lastModifiedDate = "19700101000000"`, and `nixosModules.nixarchy`/`homeManagerModules.nixarchy` re-imported with `checkInputs`. `checks` shadows `inputs` with it, so a new check is proof-stable by default.
6. **Commit-bound checks are listed by name, each with its reason,** in `data/commit-bound-checks.nix` (`{ <check> = "<reason>"; }`). They get the real inputs. `flake.nix` and the guard both read that one file. Initial entries:
   - `vm-toplevel`, `reference-toplevel`, `reference-unencrypted-toplevel`: the machine a user gets.
   - `install`, `install-encrypted`, `free-space`, `installer-refusal`: they collect every input's outPath and seed what the installed machine evaluates.
   - `iso-source`, `iso-wifi`, `iso-budget`, `install-iso-net`: `installer/cd.nix` `inputSources`.
   - `installer-lock`: `installer/mkFlake.nix:22` pins `self.rev`.
   - `nixarchy-options`: the one place the real rev is asserted.
   
   A new entry needs one of these provenance reasons and has to name its carrier.
7. **Checks still built from the real `self.nixosConfigurations.*`** (including `options-*` through `tests/options.nix:643`) **get the remedy only if the guard reports them.** The remedy builds the same configuration from `checkInputs`. If more than one check needs it, `flake.nix:1449`'s `nixosConfigurations` block is factored into a function of `inputs` and `checkInputs.self.nixosConfigurations` is set from it. The measured list decides which checks need the remedy. It doesn't choose the remedy.
8. **`microvm-template`** builds `nixarchyVm` with `callPackage ./pkgs/microvm.nix { inherit (checkInputs) self; }`.
9. **The real rev is still asserted in `nixarchy-options`,** against the real `self`:
   - Every declaration this repository owns (URL under `github.com/olafkfreund/nixarchy/blob/`) contains `/blob/${self.rev or "main"}/`, and at least one such declaration exists.
   - `etc."nixarchy/version".text` equals the line `revision.nix` gives.
   - `nixarchy/version` joins `hasOn`/`hasOff`.
10. **`build.yml`'s checkout is left alone.**
11. **The guard is `.github/scripts/commit-independent.sh`, run nightly. It isn't a `checks.*` entry.** It:
    - refuses a dirty tree;
    - works in a `git worktree add --detach` scratch tree under `${RUNNER_TEMP:-/mnt/data/vmtest}`, and refuses if that directory is missing;
    - takes the check names from its arguments, or uses all of `checks.x86_64-linux` minus the commit-bound ones. A commit-bound name that isn't a check is a failure;
    - evaluates outPaths one process at a time, and treats one that doesn't evaluate as a failure;
    - commits a `.commit-probe` file with `GIT_COMMITTER_DATE` two days after `HEAD`'s;
    - evaluates again, lists every check whose outPath moved and exits 1 if any did;
    - has a count floor;
    - cleans up with an EXIT trap on a global.
12. **Nightly job.** It's added to `report`'s `needs`, gets its own title branch, and doesn't use the `installer` label. **This is a CI workflow change, so a human merges it (§11).**
13. **Owner decision:** step 1 measures, locally, which checks move across two real commits before any broad edit. The session runs the guard prototype under the VM-tier gate.
14. **Out of scope:** catalogue URL rewriting, a `rev` field in `options.json`, a separate `nixarchy-version` package, a per-PR guard, and pushing proofs from local builds.

## Steps

1. **Guard and exempt table first, then measure.**

   **`data/commit-bound-checks.nix`** (new) holds decision 6's entries.

   **`.github/scripts/commit-independent.sh`** (new, `#!/usr/bin/env bash`, `set -euo pipefail`) implements decision 11:
   - `git diff --quiet HEAD && git diff --cached --quiet` must hold, and there must be no untracked files other than ignored ones. Otherwise it refuses with exit 2.
   - `scratch_root=${RUNNER_TEMP:-/mnt/data/vmtest}`, then `[ -d "$scratch_root" ] || exit 2`.
   - Set `scratch=$(mktemp -d "$scratch_root/commit-independent.XXXXXX")` as a **global**, and register `trap 'git worktree remove --force "$scratch/tree" 2>/dev/null; rm -rf "$scratch"; git worktree prune' EXIT` (the worktree is `$scratch/tree`, not `$scratch`: removing the parent fails and leaves a registered worktree) before `git worktree add --detach "$scratch/tree" HEAD`.
   - `bound=$(nix eval --json --file data/commit-bound-checks.nix --apply builtins.attrNames) || exit 1`.
   - `all=$(nix eval --json "git+file://$scratch/tree#checks.x86_64-linux" --apply builtins.attrNames) || exit 1`. Use `jq` to find any bound name missing from `all` and fail naming it. The names to compare are `$@` if given, else `all - bound`.
   - `evalall <tag>` loops one name at a time with `out=$(nix eval --raw "git+file://$scratch/tree#checks.x86_64-linux.$c.outPath") || { echo "$c: does not evaluate" >&2; exit 1; }`, writing `name<TAB>out` to `$scratch/<tag>.tsv`. It also logs per-check seconds on stderr.
   - The probe commit:

     ```
     printf '%s\n' "probe" > "$scratch/tree/.commit-probe" && git -C "$scratch/tree" add .commit-probe &&
       GIT_COMMITTER_DATE="@$(( $(git log -1 --format=%ct) + 172800 ))" \
       git -C "$scratch/tree" -c user.name=commit-probe -c user.email=probe@invalid commit -q -m probe
     ```

     It runs in `$scratch/tree`. Git takes `@<epoch>`; a bare number is not read as a date.
   - Then `evalall after`. `join`/`awk` the two files and print each name whose out differs, as `name  before  after`.
   - The floor: the line counts of both files must equal the requested count, or it exits 1 ("compared N of M").
   - Exit 1 if anything moved, else print `commit-independent: N checks, none moved`.

   **Session, before any other step (decision 13):**
   - Commit both files (`git add` first, §5). Then wait for the VM tier (§6): `gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'` prints `0`, and `pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` prints `0`. Ask again if the slot gets taken, and read an API failure as busy.
   - Run it under `systemd-run --user --scope -p MemoryAccounting=yes`, timed. Sample `anon` from the scope's `memory.stat`, because `/usr/bin/time` and `free` mislead (§6, #1460).
   - **Expected: red.** It should list at least `omarchy`-dependants: `session`, `coexist`, `integration`, `plugin`, `microvm-template`. That output is the guard's §1 failing proof. Keep it for the PR.
   - Also prove the guard's own failure modes in a throwaway `git worktree add --detach` tree (§5: not a `cp -a`):
     - a bound name that isn't a check → exit 1;
     - a `throw` in one check → exit 1, not "none moved".
     
     Show `git show --stat` before each run, so the break is known to have landed (§1).

   **Record in this plan, in the same commit:**
   - the full moved list, each name with its **carrier**, read from `nix derivation show` on the before/after drvs (`nix-diff` if present);
   - wall time;
   - peak anon memory.

   **Stop-gate:** the spec's remedies cover rev and date carriers only. `checkInputs.self` keeps the real `outPath`. Known `self.outPath` carriers:
   - `vm/configuration.nix:173` (`inputs.nixarchy.url = "path:${inputs.self}"` in an activation script);
   - `installer/host.nix:289` (`extraDependencies = inputs.self.lib.inputSources inputs`);
   - `tests/options.nix:648` (asserts `self.outPath` is rooted).
   
   **If any non-exempt check moves only through a `self.outPath` carrier, stop and take that list to the owner as a spec amendment.** Don't invent a remedy. The step 1 guard is also final. Later steps change only `data/commit-bound-checks.nix`, and only with the provenance reasons in decision 6.
   → `bash -n`, `checks.grep-q-pipefail`, `shellcheck .github/scripts/commit-independent.sh`, the measured run.
   Traps:
   - `set -e` doesn't reach inside `$(...)` (§5), so every capture is `x=$(cmd) || exit`.
   - The trap is on a global (§5).
   - No heredoc. `/tmp` is not a fallback (§5).
   - No pipe hides `nix eval`'s status (§1).
   - Run as a script under bash, not pasted into zsh (§1).
   - Two processes must not share the scratch tree (§5).

   **Step 1 measurement (2026-11-07, guard at `56559805`, probe `24397c26`).**
   - Red, as expected: **79 of 193** non-exempt checks moved. Exit 1.
   - Wall time **~66 min** for the guard itself (15:19 to 16:25, 3916 s of per-check `nix eval`; the 6120 s total includes 34 min waiting at the VM-tier gate). Peak anon in the scope: **13.28 GB** (`memory.stat`, sampled every 5 s).
   - Carriers, read from each moved check's drv closure (grep for the source path, the short rev and the `omarchy` drv) and `nix-diff` against the probe commit where that found nothing:
     - **`omarchy` splice (rev and date), 70:** account-copy agent-account-routing agent-local-memlock android app-selection appimage-extract bin-ledger bluetooth-pairing box-boot branch-guard channel coexist coexistence crash-report-repo doctor-channel etc-overlay factory-reset hibernate-resume home-activation-writes home-profile input-methods install-font-terminal integration keybindings-lua-timeout keyboard-boot language-edge launch-browser-self-call location manifest-has-kind menu-actions menu-close menu-conditions menu-guards menu-guidance menu-keys menu-model-merge menu-verbs microvm-boot microvm-template mise-free mise-launchers omarchy omarchy-app-template omarchy-package-ledger panel-loaders passwordless-sudo-hidden plugin provision-launchers qml qml-color-qualified reference-initrd release-notes remove-fingerprint remove-fingerprint-vm remove-preinstalls restart-terminal-wrapped retroarch-paths runtime-profile session shell-ipc-resolve shell-restart-race shell-restart-tree shell-session shell-session-launch sleep-lock-generation sshd-enable stale-scripts text-size-managed theme-set-zed update-available.
     - **`installer/mkFlake.nix` rev (`nixarchy-flake-template.drv`), 4:** initrd-pin-guard, installer-input-validation, installer-wizard, reinstall-image.
     - **rev in a script (`nixarchy-try.drv`), 1:** try-preflight.
     - **rev through a drvPath embedded as a string (no closure edge), 2:** install-seed-shape (the install configurations' `system-path` drvPaths), stable-eval (a `nixos-system` drvPath).
     - **rev and `self.outPath`, 1: options-files.** `omarchy`, `options.json`, `nixarchy-vm` carry the rev; `activate.drv` carries `inputs.nixarchy.url = "path:/nix/store/…-source"` (`vm/configuration.nix:173`), and `nixos-system-nixarchy` has the source in its inputs.
     - **Whole-tree content, 1: cache-keys.** `tests/cache-keys.nix:11-16` takes `lib.fileset.difference ../. (intent spec plan)` as its `source`. The probe's new `.commit-probe` file is in that set. No rev, date or `self.outPath` carrier.
   - Guard failure modes: a bound name that is not a check → exit 1 naming it; a `throw` in one check → exit 1, "does not evaluate"; restored → "1 checks, none moved", exit 0. No scratch tree or worktree left behind.

   **Stop-gate hit.** The spec's remedies (placeholder rev and date) leave two non-exempt checks moving: `options-files` through the `self.outPath` carrier at `vm/configuration.nix:173`, and `cache-keys` through whole-tree content, a carrier the spec does not name. Both go to the owner as a spec amendment. Steps 2 onward wait.

2. **`modules/revision.nix` (new) and `flake.nix:529-548`, `:843`.**
   - Move the body of `nixarchyRev`/`nixarchyDate` verbatim into `self: { shortRev = …; date = …; }`. Use `builtins.substring`, because there's no `lib` argument.
   - Move the offline-install comment with it, and move the `# Why:` pointer at `:530` to the new file.
   - Delete both bindings and the `inherit nixarchyRev nixarchyDate;` at `:843`. `grep -n nixarchyRev flake.nix` must print nothing.
   
   This step is only correct once step 3 is in. Steps 2 and 3 land together in one commit.
   → `nix eval .#packages.x86_64-linux.omarchy.outPath` evaluates.
   Traps: `nix fmt` after the edit, then `git diff --stat`, because the hook reformats with `nixpkgs-fmt` (§5). `git add` the new file before evaluating (§5).

3. **`pkgs/omarchy/default.nix:6-10`, `:1053-1080`, `pkgs/omarchy/nix-bin/nixarchy-version`.**
   - Drop the `nixarchyRev`, `nixarchyDate` arguments and the comment above them.
   - `substituteInPlace` keeps only `--replace-fail '@omarchyversion@' '${version}'`.
   - **Script.** Replace the last `printf` with a read of the first readable file of `/etc/nixarchy/version` and `${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/nixarchy/version`:

     ```
     rev=unknown date=unknown
     for f in …; do
       if [ -r "$f" ]; then read -r rev date <"$f" || true; break; fi
     done
     printf 'nixarchy  %s  %s\n' "${rev:-unknown}" "${date:-unknown}"
     ```

     `${HOME:-…}` is needed because `set -u` would otherwise abort where `HOME` is unset.
   - Update the header comment: the values now come from the module, not a splice.
   - **Self-check.** Two runs replace the single `case`. Write the files with `printf`, never a heredoc, inside the Nix `''` string (§5):
     - `XDG_CONFIG_HOME=$TMPDIR/xdg-set` holding `abc1234 2026-01-02` must print `${version}`, `abc1234` and `2026-01-02`;
     - `XDG_CONFIG_HOME=$TMPDIR/xdg-none` (empty) must print `unknown  unknown`.
   
   → `nix build .#packages.x86_64-linux.omarchy` (package tier: no p620 system build, load under 12, and `vm-host-free.sh install` and `edge` both `free`).

   **§1 break:**
   - Drop the file read, so the script always prints unknown → build red on the first fixture.
   - Restore it → green.
   - Keep the red output.
   
   Then `checks.channel` and `checks.verify-runs` stay green.
   Traps:
   - `\$` in a `''` string is a literal backslash (§5, #1504).
   - `nix fmt` after the edit.
   - `checks.grep-q-pipefail`.
   - The self-check assumes the build sandbox has no `/etc/nixarchy` (an unsandboxed build on a nixarchy machine would read the real file). Say so in a one-line comment.

4. **`modules/nixos.nix:1743-1747`, `modules/home.nix:1488`.**
   - In `nixos.nix`: `"nixarchy/version".text = let r = import ./revision.nix inputs.self; in "${r.shortRev} ${r.date}\n";` in the `/etc/nixarchy` attrset beside `options.json`.
   - In `home.nix`: add the same text as `"nixarchy/version" = lib.mkIf (osConfig == null) { text = …; };` inside the `xdg.configFile = {` at `:1488`. That block is inside `config = lib.mkIf cfg.enable` (`:855`), so both gates hold.
   
   → `nix eval .#nixosConfigurations.reference.config.environment.etc.\"nixarchy/version\".text` prints `<shortRev> <date>\n`; `checks.options-files` (VM tier, the options shard row).
   Traps:
   - §7: plain assignment, not mkDefault, on the attrset entry.
   - Mode A (§7): it has to stay inside the `cfg.enable` block. Step 7 proves that.
   - §14: there's no merged env, so no coexistence fixture (the spec's Coexistence section).
   - `nix fmt`.

5. **`flake.nix` top-level `let` (after `stableInputs`, ~`:516`), `checks` (`:1735`), `:2743-2751`, `:2822-2827`.**
   - **Top-level `let`:** add `checkInputs` as the spec writes it (decision 5), plus `commitBound = import ./data/commit-bound-checks.nix;`. Here `inputs` is still the function argument, so `checkInputs` reads the real one.
   - **Checks `let`:** shadow `inputs` only. **Don't** write `let realInputs = inputs; inputs = checkInputs;` in the same `let`. A Nix `let` is recursive, so `realInputs` would capture the shadowed value. Bind `realInputs = inputs;` in the **top-level** `let` instead, and only `inputs = checkInputs;` in the checks `let`.
   - **`genAttrs uniformChecks` (`:2822`):** pass `inputs = if commitBound ? ${n} then realInputs else inputs;`.
   - **Explicit entries named in `commitBound`** (`iso-source` `:2222`, `installer-lock` `:2280`, `iso-wifi`/`iso-budget` if explicit, and the toplevels, which read `self` directly and are untouched) use `realInputs` where they take `inputs`.
   - **`microvm-template`:** `nixarchyVm = pkgsFor.${system}.callPackage ./pkgs/microvm.nix { inherit (inputs) self; };` (now `checkInputs.self`).
   - **Drift check.** `nix eval --json .#checks.x86_64-linux --apply builtins.attrNames` with `jq` against `commitBound`: every bound name is a check. The guard asserts the same at run time.
   
   → Re-run step 1's guard (VM tier). The moved list must shrink to the configurations step 6 handles. Commit-bound checks still get the real inputs. A drvPath compared across commits proves nothing here, because `installer/host.nix:289` roots every input's source path (§5). Assert a property instead: `nix derivation show -r .#checks.x86_64-linux.install` contains the real `shortRev` in the `nixarchy/version` text and not `0000000 1970-01-01`. **Break:** delete `install` from `data/commit-bound-checks.nix` (throwaway commit, `git show --stat` first) → the placeholder appears.
   Traps:
   - §5: a background build's evaluation isn't pinned. Evaluate the drv visibly before anything long starts.
   - `nix fmt`; `statix`, `deadnix`.
   - `checks.test-registration` (it reads `uniformChecks`).

6. **Remedies for what step 1/5 still lists.** Only for a check moving through rev or date via a real `self.nixosConfigurations.*`:
   - Build that configuration from `checkInputs`, **modules included**: `vmModulesWith` (`flake.nix:485`) and `mkReference` (`flake.nix:1605`) name `self.nixosModules.nixarchy` directly. Passing `checkInputs` as `specialArgs` alone would leave the real-rev module in place, so the factored function takes the module from `inputs.self.nixosModules.nixarchy`. If two or more need it, factor `flake.nix:1449`'s `nixosConfigurations` into `mkConfigurations = inputs: …`. `nixosConfigurations = mkConfigurations inputs;` and `checkInputs.self.nixosConfigurations = mkConfigurations checkInputs;`. Use a lazy reference, which is fine in the recursive top-level `let`.
   - A check that moves for a provenance reason in decision 6 instead gets a `data/commit-bound-checks.nix` entry naming its carrier.
   - Anything else returns to the owner (step 1's stop-gate).
   
   Record the final list in this plan, in the same commit.
   → Guard green (VM tier). **First break (spec):** in a throwaway detached worktree commit, restore the `nixarchyRev`/`nixarchyDate` arguments and `--replace-fail '@nixarchyrev@' '${nixarchyRev}'` in `pkgs/omarchy/default.nix` → guard red naming `omarchy` and its dependants. **Second break:** remove `nixosModules` from `checkInputs.self` in a throwaway detached worktree commit (`git show --stat` first) → guard red naming `session`. The captured red must be the moved list, not the dirty-tree refusal (§1).
   Traps:
   - `options-*` peak memory (§6 tier table).
   - `microvm-template`'s `templates.kvm`/`.tcg` still come from real `self.packages.*.microvm-*` (`flake.nix:2746-2748`). If the guard lists `microvm-template` after step 5, build those runners from `checkInputs` the same way. They're configurations, so this is the same remedy, not a new decision.

7. **`tests/nixarchy-options.nix`, `flake.nix:2692-2696`.**
   - Add `self` and `revision` arguments: `self = self;` (real) and `revision = import ./modules/revision.nix self;`.
   - In Nix, compute `ownUrls`: every declaration **object's `.url`** under `https://github.com/olafkfreund/nixarchy/blob/` (`modules/nixos.nix:304-307` emits `{ url; name; }`, not strings, so a string-only filter finds zero) from `builtins.fromJSON (builtins.readFile opts…)`. Better done in `jq` in the script, with `rev` passed as an env string `${self.rev or "main"}`. Fail if the count is 0, or if any lacks `/blob/$rev/`. Flatsnap's and nixpkgs' declarations are excluded by the URL prefix.
   - Pass `versionOk = etc."nixarchy/version".text == "${revision.shortRev} ${revision.date}\n"` as `"1"`/`"0"`.
   - Add `(etc ? "nixarchy/version")` to `hasOn` and `|| (off ? "nixarchy/version")` to `hasOff`.
   
   → `nix build .#checks.x86_64-linux.nixarchy-options` (cheap tier, under `flock`).

   **§1 breaks, each red, then restored:**
   - `rev = "main"` at `modules/nixos.nix:284`;
   - a wrong date in the version line;
   - the version entry moved outside `cfg.enable`.
   
   Traps:
   - `git checkout HEAD -- <path>` to restore, not `git checkout --` (§5).
   - Commit a baseline before the break loop.
   - `jq` reading an empty match must not pass (the zero-count floor).

8. **Docs.**
   - Move the `docs/internals/flake.md:907-930` section (anchor `which-nixarchy-built-this-machine-208-for-nixarchy`) so its code block and text describe `modules/revision.nix` and the `/etc/nixarchy/version` reader. Keep the anchor id, so the `# Why:` pointer in `revision.nix` still resolves.
   - `tests/AGENTS.md`: one paragraph. Checks get a placeholder `self` (`checkInputs`), and a check that must carry the real commit goes in `data/commit-bound-checks.nix` with its reason. Name the guard and that it's nightly. Name the `self.outPath` carriers step 1 found.
   - `docs/manual/omarchy-channels.md:98-100`: `nixarchy version` reads `/etc/nixarchy/version`.
   - The PR body gets the release-note line from the spec's Risks: every machine's `omarchy` changes once.
   
   → `checks.manual-*`/docs checks that `generated-checks.sh` lists, and `.github/scripts/readme-counts.sh`.
   Traps: a list naming things elsewhere wants a comparison (§4). That's already true of the exempt table, through the guard.

9. **`.github/workflows/nightly.yml`.** Copy the `cache` job's hosted-runner setup to add a `commit-independent` job:
   - `runs-on: ubuntu-26.04`, `actions/checkout`, the nix install, `cachix-action` with `skipPush: true`. It doesn't touch p620.
   - The run step is `.github/scripts/commit-independent.sh`, with `RUNNER_TEMP` provided.
   - `timeout-minutes` is step 1's measured wall time × 1.5. If that exceeds 300, or the measured peak anon memory exceeds 14 GB, stop and raise it: a hosted runner has 16 GB.
   
   Then the `report` job:
   - add it to `report`'s `needs` (`:588`);
   - add an `elif` branch before the final `else` (`:630-667`) when it alone failed and the installs succeeded: `title="nightly: a commit leaks into a check's proof"`;
   - make the label a variable, with `installer` only on the install title, and `gh issue create` uses it (`:694`).
   
   → `actionlint`, `yq` parse, `checks.grep-q-pipefail`. Run the job's script locally (that's step 1's run).
   Traps:
   - **This is a CI-gate change (§10/§11): the PR proposes it for a human to merge.** Say so in the PR body.
   - A job missing from `needs` files nothing (§4, `reinstall-vm`).
   - Don't quote a skip-CI marker in the commit or PR text (§8).

## Tests (by §6 tier)

- **Cheap** (any time, one at a time under `flock /mnt/data/vmtest/codex-build.lock`):
  - `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`, `shellcheck`, `actionlint`;
  - `checks.grep-q-pipefail`, `nixarchy-options` with its three breaks, `installer-lock`, `channel`, `verify-runs`, `test-registration`, `cache-budget`, `options-shards`;
  - `.github/scripts/readme-counts.sh`.
- **Package** (gate: no p620 system build, load under 12, `vm-host-free.sh install|edge` both `free`): `packages.omarchy` with the self-check break.
- **VM tier** (runners not busy, at most two):
  - the guard run before (red, step 1) and after (green);
  - the guard's two breaks, plus its exempt-name and throw failure modes;
  - `options-system`, `options-home`, `options-microvm`, `options-files`;
  - `session`, `coexist`, `integration`, `plugin`, `microvm-template`;
  - every target `generated-checks.sh` prints, plus each claimed check whose files changed.
- **Not run locally:**
  - the `install` job (self-hosted install slot). It's named in the PR, and its drvPath is shown unchanged by step 5;
  - the nightly job on a hosted runner. Its first run is after the human merge;
  - the proof-hit effect itself (a second CI run on a docs-only commit reading `already-proven`). It's checked on the first docs-only `main` push after merge.

## Rollback

Revert the merge.
- Machines rebuild once: `omarchy` regains the splice, and `/etc/nixarchy/version` and the standalone `~/.config/nixarchy/version` disappear. `nixarchy-version` prints the spliced values again.
- Nothing persists outside the store.
- The nightly job goes with the revert. Its open issue, if any, is closed by hand.
