---
status: approved
issue: 1157
spec: spec/2026-10-02-1157-copilot-handoff-pipe.md
---

# Plan: the Copilot handoff survives a large failure log

## Approved decisions (self-contained)

- **`copilot-handoff.sh:45`:** `| head -100)` → `| sed -n '1,100p')`. It reads
  to EOF, so no stage upstream takes SIGPIPE under `pipefail`. No `|| true`.
- **`readme-counts.sh:106` and `:156`:** `| head -1` → `| sed -n 1p`, making
  them correct by construction.
- **`checks.copilot-handoff` (new, cheap):**
  - runs the real script in its own `DRY_RUN=1` mode, against a stub `gh`
    that serves a 500-line failure log;
  - asserts exit 0, the "would comment on #1154" line, and an excerpt that is
    non-empty and at most 100 lines;
  - carries a built-in negative control: a copy of the script with
    `head -100` restored must fail.
- **The workflow file is not touched** (§11).

## Repo traps

- **No heredoc inside a Nix indented string** (§5): write the stub `gh` and
  the log generator as their own files beside the check (`tests/copilot-handoff/`),
  or with `printf '%s\n'`.
- **Prove the negative control's edit landed** (§1): assert the copy contains
  `head -100` before running it.
- **Capture exit status with `if …; then`,** never through a pipe
  (`tests/AGENTS.md`).
- **A sandbox has no `/usr/bin/env`.** Run the script as
  `bash path/to/copilot-handoff.sh`, not by its shebang.
- **Cheap tier:** one build at a time under
  `flock /mnt/data/vmtest/codex-build.lock`.
- **Work only in `/mnt/data/vmtest/wt-1157`** (branch
  `fix/1157-copilot-handoff-pipe`).
- **After `.nix` edits:** `nix fmt`, then `git diff --stat`; then statix and
  deadnix, reading their exit status.

## Steps

1. **The fixes: `.github/scripts/copilot-handoff.sh:45`,
   `.github/scripts/readme-counts.sh:106,156`.**
   - Make the three replacements. Add one comment line at
     `copilot-handoff.sh:45`:
     `# sed, not head: head exits early and the stages before it die of SIGPIPE under pipefail (#1157, tests/AGENTS.md).`
   - **Verify:**
     - `bash -n` on both;
     - `OMARCHY_TREE=$(nix eval --raw .#omarchy.outPath) bash .github/scripts/readme-counts.sh --check`
       still exits 0. It needs a built `omarchy`; if that is not in the store,
       wait for the package tier, or let CI run it.
   - **Traps:** `grep -rn 'head -' .github/scripts/` afterwards, to confirm
     nothing else of this shape sits inside a `$(…)`. If something does,
     report it; do not widen the change.

2. **The check: `tests/copilot-handoff.nix` (new), `tests/copilot-handoff/gh`
   (new, the stub), and the `flake.nix` `checks` entry beside a similar
   script check (e.g. near `manifest-has-kind`).**
   - **The stub `gh`** dispatches on `"$*"`:
     - `run view * --json jobs*` → `system`;
     - `pr list *` → `1154`;
     - `run view * --json headSha*` → `deadbeef`;
     - `pr view * --json comments*` → `[]`;
     - `run view * --log-failed*` → generate 500 lines of
       `system\tDrive a session\t2026-10-02T00:00:00.0000000Z error: line N`;
     - anything else → print it to stderr and exit 3, so an unexpected call
       is loud.
   - **The check (`runCommand`, inputs: `bash jq gnused gawk gnugrep
     coreutils`):**
     - copies the stub onto a `PATH` directory;
     - sets `RUN_ID=1 REPO=o/r BRANCH=update/x DRY_RUN=1`;
     - runs `bash ${../.github/scripts/copilot-handoff.sh} > out.txt`, with
       status via `if`;
     - asserts `would comment on #1154` is in `out.txt`;
     - extracts the lines between the two `~~~~` fences and asserts the count
       is between 1 and 100 inclusive.
   - **The negative control, in the same check:**
     - `sed 's/sed -n .1,100p./head -100/'` produces a copy of the script;
     - `grep -q 'head -100' copy` passes, on a file, not a pipe;
     - running the copy against the same stub must exit non-zero, or the
       check fails with "the control passed".
     - Then measure: if 500 lines does not make the control fail, raise the
       count until it does, and say so in a comment. The pipe buffer decides
       this.
   - **Wiring:** `copilot-handoff = import ./tests/copilot-handoff.nix { pkgs = pkgsFor.${system}; };`
     (match the neighbouring entries' shape). `git add` everything.
   - **Verify (cheap tier):**
     `nix build .#checks.x86_64-linux.copilot-handoff --no-link -L`. It is
     green, and the log shows the control failing.
   - **§1:** in a scratch copy of the check, point the *positive* run at the
     reverted copy too. Show it red, and restore from the scratch copy. Keep
     the red output for the PR.

3. **PR.**
   - Run `nix fmt -- --ci`, statix and deadnix. Check
     `git merge-base origin/main HEAD` (§5).
   - **The body:**
     - links intent, spec and plan;
     - pastes the run 36981682776 error lines and the §1 red output;
     - uses `closes #1157`;
     - contains no skip-CI marker;
     - says which steps the coder did.
   - **Note in the PR:** #1154's handoff never ran. Once this is merged,
     re-running that workflow is the owner's call, since #1158 is fixing
     #1154's cause directly.

## Tests

| step | command | expected |
|---|---|---|
| 1 | `bash -n`; `readme-counts.sh --check` | clean; exit 0 |
| 2 | `checks.copilot-handoff` | green; the control fails inside it; the §1 inversion is red |
| 3 | CI on the PR | green |

## Rollback

Revert the squash commit.
