---
status: draft
issue: 1157
intent: intent/2026-10-02-1157-copilot-handoff-pipe.md
---

# Spec: the Copilot handoff survives a large failure log

## Design

### D1. Read to the end instead of closing the pipe early

- **The fix.** `.github/scripts/copilot-handoff.sh:45`: `| head -100)` becomes
  `| sed -n '1,100p')`.
  - `sed -n '1,100p'` prints the same first 100 lines, but keeps reading to
    EOF.
  - So no upstream stage is ever written into a closed pipe, and `pipefail`
    sees only real failures.
- **Why only this.** It is the smallest change that keeps the script's
  `set -euo pipefail` honest. `|| true` on the substitution would also hide a
  `gh` that really failed.
- **The comment.** One line at the site, pointing to `tests/AGENTS.md`'s
  existing SIGPIPE section. The reasoning already lives there, so it is not
  repeated here.

### D2. `readme-counts.sh`'s two `| head -1` sites

`.github/scripts/readme-counts.sh:106` (`sed -nE … "$readme" | head -1`) and
`:156` (`… | grep -oE '[0-9]+' | head -1`) have the same shape.
- **Today they are safe only by size:** the producer's whole output fits in
  the pipe buffer before `head` exits.
- **The change:** both become `sed -n 1p`, which reads to EOF. That makes them
  correct by construction rather than by size, at a cost of two lines.

### D3. `checks.copilot-handoff`: `tests/copilot-handoff.nix` (new)

A `runCommand` with `bash`, `jq`, `gnused`, `gawk`, `gnugrep` and `coreutils`.

- **The stub.** A stub `gh` on `PATH` answers by its arguments:
  - `run view … --json jobs` → a failed job name;
  - `pr list` → `1154`;
  - `run view … --json headSha` → a SHA;
  - `pr view … --json comments` → `[]`;
  - `run view … --log-failed` → **500** tab-separated log lines in the form
    the script's `awk` expects (`job\tstep\ttimestamp text`), each containing
    `error:`.
- **The run.** The script runs with `DRY_RUN=1` (its own existing mode, which
  prints the body instead of commenting) and `RUN_ID`/`REPO`/`BRANCH` set.
- **Assertions:**
  1. it exits 0;
  2. its output contains `would comment on #1154`;
  3. the excerpt inside the `~~~~` fence is at most 100 lines;
  4. the excerpt is not empty.
- **The negative control, inside the same check** (as
  `checks.shell-restart-race` does): a copy of the script with `sed -n
  '1,100p'` turned back into `head -100` must **fail** against the same stub.
  So every run proves the check can still see the bug.
- **Size of the stub log.** 500 lines is well past 100, and enough output to
  fill the pipe buffer ahead of `head`. The plan measures the smallest count
  that reproduces the break, and keeps 500 only if it does.
- **Wiring.** A `checks.copilot-handoff` entry; CI runs it with no workflow
  edit (§4).

## Alternatives rejected

- **`|| true` on `log=$(…)`.** It hides real `gh` failures too.
- **`set +o pipefail` around the block.** The same blindness, scoped wider.
- **`awk 'NR<=100'`.** Equivalent to `sed -n '1,100p'`, but `sed` is already
  a stage of this pipeline.
- **Testing via the workflow** with a forced failure. Slow, it needs GitHub,
  and the stub check is the cheap layer (§2).

## Risks

- **The stub can drift from `gh`'s real log format.** The fix itself does not
  depend on the format, but the check's "not empty" assertion does. Built
  from the `awk` program's own expectations, it fails loudly if the script's
  parsing changes, which is the useful direction.
- **The negative control's `sed` edit must actually land.** The check asserts
  that the copy contains `head -100` before running it (§1, "a break that
  never applied").

## Verification

1. `nix build .#checks.x86_64-linux.copilot-handoff -L`: green, and the log
   shows the control failing as required.
2. §1, shown in the PR:
   - the positive run pointed at an unpatched copy goes red;
   - restored, it goes green.
3. `checks.readme-counts`, or `readme-counts.sh --check`, still passes after
   D2.
4. `bash -n` on both scripts; statix, deadnix and `nix fmt -- --ci` are
   clean.
