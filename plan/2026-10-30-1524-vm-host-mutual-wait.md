---
status: approved
issue: 1524
spec: spec/2026-10-30-1524-vm-host-mutual-wait.md
coders:
  1: agy   # a jq filter and a case variable: small, fully specified below
  3: agy   # fixture cases in the existing pattern; the session runs every check
reviewers:
  - codex  # reads the diff against this plan; independent of agy's edits
---

# Plan: an install and edge's verify stop waiting on each other

## Approved decisions (from the spec)

- **The standoff.** An install and edge's `verify` each ask `.github/scripts/vm-host-free.sh` whether the other's job is `in_progress`, and each waits inside its own job. When both wait together, neither proceeds until the install's 30-minute bound fails it. This happened on 10-29 (31 min) and 10-30 (30 min). Without the standoff, `verify` takes 19–21 min.
- **The fix is one-sided.** In `edge` mode only, an install job does not count as busy while its step named exactly `Wait for edge's VM checks to leave this host` is `in_progress`.
  - In every other state it stays busy: before the wait, after it, between steps (wait `completed`, next step `queued`), and with no `steps` at all.
  - `install` mode is unchanged: the install yields to the whole `verify` job.
  - It is never applied to both sides, because two jobs that both ignore a waiting peer can both boot (#1365).
- **Bounds.** The 30-minute bound and the install job's 90-minute timeout do not change. `omarchy-edge.yml` does not change. No host change and no deploy.
- **A rename guard.** `checks.vm-host-free` asserts that the step name is a `- name:` in `install-check.yml`. A rename silently brings the standoff back, and this turns it red.
- **CI-gate change (§11).** The owner approved it via the spec. A human merges it.

## Steps

1. **`.github/scripts/vm-host-free.sh`.**
   - Lines 6–9: the `case` gains `wait=`.
     - `install) wf=omarchy-edge.yml job=verify wait="" ;;`
     - `edge) wf=install-check.yml job=install wait="Wait for edge's VM checks to leave this host" ;;`
   - Line 4 comment: add one short line saying an install still in its wait step does not count for edge (#1524), so the two cannot wait on each other.
   - Line 21: pass `--arg w "$wait"` and change the filter to:

     ```jq
     .jobs[] | select(.name == $j and .status == "in_progress"
       and ([.steps[]? | select(.name == $w and .status == "in_progress")] | length) == 0) | .name
     ```

     With `wait=""` no step name is empty, so `install` mode behaves exactly as before.

   Verify: `bash -n`, shellcheck, then step 3's check.
   Traps: keep `set -euo pipefail`, the capture-first pattern and the `|| unknown` on every call (§4). Don't pipe the jq whose status matters.

2. **`.github/workflows/install-check.yml` lines 431–432.** Replace the two-line comment with two lines saying:
   - the install waits out the whole `verify` (≈20 min; the 51- and 84-minute runs were this standoff);
   - edge does not wait for an install still in this step (#1524), so `30 + ~25` still fits the 90-minute cap.

   **Do not rename the step.** Step 3's guard reads its name.

   Verify: actionlint on the file. `nix fmt -- --ci`.

3. **`tests/vm-host-free.nix`.**
   - Add fixtures in the existing `printf`/`fixture` style (no heredocs, §5):
     - `INSTALL_WAITING`: the install job is `in_progress`, with steps `[{"name":"Run actions/checkout@v5","status":"completed"},{"name":"Wait for edge's VM checks to leave this host","status":"in_progress"},{"name":"Install onto a blank disk, and into free space beside a neighbour","status":"queued"}]`.
     - `INSTALL_BOOTING`: the same, with wait `completed` and the next step `in_progress`.
     - `INSTALL_BEFORE_WAIT`: checkout `in_progress`, wait `queued`.
     - `INSTALL_BETWEEN`: wait `completed`, the next step `queued`.
     - `VERIFY_WAITING`: the verify job is `in_progress`, with a step named `Wait for edge's VM checks to leave this host` `in_progress`. This proves the exemption is edge-only.
   - New `run` lines:
     - `edge-vs-waiting-install` → 0 `free`
     - `edge-vs-booting-install` → 1 `busy: install-check.yml run 22 job install`
     - `edge-vs-install-before-wait` → 1 busy
     - `edge-vs-install-between-steps` → 1 busy
     - `install-vs-verify-with-wait-named-step` → 1 `busy: omarchy-edge.yml run 11 job verify`
     - `standoff`: put both runs (EDGE and INST) in `runs.json`. jobs-11 holds a waiting verify (`VERIFY_UP`); jobs-22 holds `INSTALL_WAITING`. The install asker gets 1 and the edge asker gets 0. `fixture` writes one jobs body to both files, so this case writes `fix/jobs-11.json` and `fix/jobs-22.json` itself.
   - **Step-name guard:**
     - add `workflow = ../.github/workflows/install-check.yml;` to the derivation's attributes;
     - extract the `wait="…"` string from `$script` with `sed -n`, and fail if it is empty;
     - `grep -qF -- "- name: $name" "$workflow"`, with a message naming the step.
   - **Break proofs, alongside breaks 1 and 2, each with a `cmp -s` landed-check:**
     - **Break 3:** sed the `wait="Wait …"` assignment to `wait=""`. Then `red no-exemption-is-caught any.sh edge 0 free` against `INSTALL_WAITING`.
     - **Break 4:** sed `and .status == "in_progress")]` to `and .status != "completed")]`. Then `red queued-wait-exempt-is-caught … edge 1 busy` against `INSTALL_BEFORE_WAIT`.
     - **Break 5:** run the guard against a sed copy of the workflow with the step renamed. It must fail. Implement it as a small function used for both the real and the broken file.

   Verify: `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.vm-host-free --print-build-logs`. Every `ok` line is printed, including three `…-is-caught` breaks and the guard break.
   Traps:
   - In a Nix `''` string, write `''${` for a literal `${` (§5), and never `\$`.
   - `git add` new content before building (§5).
   - `nix fmt` afterwards, and check `git diff --stat` for a hook reformat (§5).
   - `checks.grep-q-pipefail` if any `grep -q` sits in a pipeline.

4. **Session, no file edit: live API shape.** Read the steps of an install job while its wait step runs, if one happens before merge:

   ```
   gh api …/runs/<id>/jobs -q '.jobs[]|select(.name=="install")|.steps[]|"\(.status) \(.name)"'
   ```

   It must show `in_progress Wait for edge's VM checks to leave this host`. If no install waits before merge, record that it was not observed, and check it on the first overlap after merge.

## Tests

The cheap tier only (§6), one at a time under `flock /mnt/data/vmtest/codex-build.lock`:

```bash
nix fmt -- --ci
nix run nixpkgs#shellcheck -- .github/scripts/vm-host-free.sh
nix run nixpkgs#actionlint -- .github/workflows/install-check.yml
nix build .#checks.x86_64-linux.vm-host-free --print-build-logs
nix build .#checks.x86_64-linux.grep-q-pipefail
```

Expected: all exit 0. The `vm-host-free` log shows the new cases and breaks 3–5 caught. The PR carries that log as the §1 proof.

## Rollback

Revert the squash commit. The only behaviour change is the jq filter in `edge` mode, and reverting it restores today's job-level view, with the standoff but with #1365 intact.
