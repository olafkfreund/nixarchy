---
status: approved
issue: 1398
spec: spec/2026-10-21-1398-edge-generated-checks.md
---

# Plan: edge publishes again: green on its full check list at quattro 0a7beb7

## Decisions (from the approved intent and spec)

- **Target: edge green at its current pin, quattro 0a7beb7.** Adopting
  087f73d is a follow-up issue (step 9). Exempting checks from edge's list
  is ruled out.
- **One carry commit per cause** on `edge-candidate`, so a later quattro
  bump can revert one alone.
- **The digest fix goes on `main`**, in this branch's PR
  (`fix/1398-edge-generated-checks`) with intent, spec and plan.
- **Verdicts:**
  - real bugs, fixed by a patch: the setters (1), the browser guard (3)
    and the digest (7);
  - check-only, fixed by a patch: fingerprint guidance (4);
  - stale checks, retargeted: hibernate (2), provision-launchers (5) and
    stale-scripts (6).
- **Promotion** is one `omarchy-edge` dispatch with `from_candidate=true`,
  carrying these fixes and #1386 (4cd1fa90). It runs only with your
  go-ahead, and before the 06:00 UTC scheduled run, which force-pushes
  `edge-candidate` from `origin/edge`.

## Repo traps that apply to every step

- `--replace-fail` patterns and replacements in `pkgs/omarchy/default.nix`
  are one line each (comment at ~:1225).
- After editing any `.nix` file, run `nix fmt` and read `git diff --stat`.
  A hook may reformat it with `nixpkgs-fmt` (§5).
- In Nix indented strings, write files with `printf '%s\n'`, not heredocs
  (§5).
- `git add` new files before evaluating anything (§5).
- Cheap builds run one at a time, under
  `flock /mnt/data/vmtest/codex-build.lock`, by drvPath:
  `nix build "$(nix eval --raw .#checks.x86_64-linux.<n>.drvPath)^*"`.
- `.#omarchy` builds only when the 1-minute load in `/proc/loadavg` is
  below 12.
- Never run `checks.options` or any VM check locally. Never `pkill` by
  name.

## Steps

### Part A: carries on `edge-candidate`

Worktree: `git worktree add -b carry/1398-edge-checks /mnt/data/vmtest/wt-1398-edge origin/edge-candidate`
(14888ef8, the same as `origin/edge`).

Commit each step on its own, with a full-sentence subject ending
`(#1398)`.

**A1. Helix and Zen setters (cause 1).**
- `pkgs/omarchy/default.nix`, after the #1303 `zen.desktop` loop
  (~:1380-1383), add:
  ```nix
  # #1398: quattro's setters install a missing app; nixpkgs' helix is `hx`, nixarchy's Zen is `zen-beta`.
  substituteInPlace $out/share/omarchy/bin/omarchy-default-editor \
    --replace-fail 'if omarchy-cmd-missing "$editor"; then' 'if omarchy-cmd-missing "$([[ $editor == helix ]] && echo hx || echo "$editor")"; then'
  substituteInPlace $out/share/omarchy/bin/omarchy-default-browser \
    --replace-fail 'command="zen-browser"' 'command="zen-beta"'
  ```
- `data/bin-ledger.nix`:
  - add a `"omarchy-default-editor"` row with `class = "patch"` and the
    reason "quattro's setter installs an editor it thinks is missing, and
    probes `helix`, which nixpkgs installs as `hx`. So choosing an
    installed Helix tried an Arch install and set nothing (#1398).";
  - extend the `"omarchy-default-browser"` reason (~:199) with "Quattro
    also probes `zen-browser` before setting, and nixarchy's binary is
    `zen-beta` (#1398)."

→ verify:
- `checks.bin-ledger`. It builds `.#omarchy`, so check the load first.
- `checks.menu-conditions`: the editor and browser lines go green. The
  hibernate line is still red until A2.

**A2. Hibernate check (cause 2).**
- `tests/menu-conditions.sh:75`: replace the equality test with
  ```bash
  case "$(field "$menu" system.hibernate when)" in
    omarchy-hibernation-available | "omarchy-hibernation-available && "*) ;;
    *) bad "system.hibernate no longer asks omarchy-hibernation-available" ;;
  esac
  ```
- One comment line above it: upstream may add conditions after the
  availability probe (#1398).

→ verify: `checks.menu-conditions` is fully green.

**A3. Browser guard (cause 3).**
- `pkgs/omarchy/default.nix:626-627`: change the anchor to quattro's
  top-level `private_flag="--private"`:
  ```nix
  # Why: pkgs/AGENTS.md#launch-browser-refuses-to-launch-itself-1342
  # quattro moved the MOZ_LOG probe into the --private branch; anchor above it (#1398).
  substituteInPlace $out/share/omarchy/bin/omarchy-launch-browser \
    --replace-fail 'private_flag="--private"' "$(sed '$d' ${./1342-launch-browser-self-call.sh})"$'\n''private_flag="--private"'
  ```
  `sed '$d'` drops the snippet's last line, which is main's anchor. Do not
  edit the snippet file: `main` shares it.

→ verify:
- grep the built `omarchy-launch-browser`: the guard's `if` must be at
  column 0, before `private_flag=`;
- `checks.launch-browser-self-call` is green.

**A4. Fingerprint guidance (cause 4).**
- `pkgs/omarchy/default.nix:1505-1507`: change the anchor from the
  `echo -e "\e[32mRemoving fingerprint scanner…` line to
  `'# Resolve the invoking account before changing authentication or packages.'`.
- Replace it with
  `"$(cat ${./1304-guidance-remove-fingerprint.sh})"$'\n''# Resolve the invoking account before changing authentication or packages.'`.
- Add one comment line: the guidance runs before the `id` lookup, which
  the sandbox and a broken PATH cannot reach (#1398).

→ verify: `checks.menu-guidance` is green.
Traps: the `/run/current-system/sw/bin/id` patch (#1278, ~:937) stays.

**A5. provision-launchers (cause 5).**
- `tests/provision-launchers.nix`:
  - remove the `cmds=…` line (:122) and its comment (:121), and the
    `for c in $cmds` line (:133);
  - replace :142 with
    `grep -qx 'mise reshim --system' "$TMPDIR/calls" || fail "mise.sh did not reshim"`;
  - leave every changed, deleted and unexpected-file assertion (#1319) as
    it is.
- `tests/AGENTS.md` (~:1809): change `all.sh:14` to `all.sh:18`, and add
  one sentence saying quattro's mise.sh reshims instead of writing
  launchers (#1398).

→ verify: `checks.provision-launchers` is green.

**A6. stale-scripts (cause 6).**
- `tests/stale-scripts.nix:15`: before `chmod +x stub/*`, add
  `printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > stub/omarchy-hw-x86`.

→ verify: `checks.stale-scripts` is green.

**A7. Add #1386 to the stack.**
- `git cherry-pick 4cd1fa90` onto A6.
- It touches `pkgs/omarchy/default.nix` near A3's lines. Resolve any
  conflict by keeping both changes.

→ verify: `checks.agent-account-routing` is green.

### Part B: digest fix on `main`

Branch `fix/1398-edge-generated-checks`, worktree `/mnt/data/vmtest/wt-1398`.

**B1.** Make three changes:
- `.github/scripts/failure-excerpt.sh:13`: add `|ERROR` to the `grep -E`
  alternation. Do not use `-i`.
- `.github/scripts/failure-digest.sh:54-55`: when `$excerpt` is empty,
  print `nix log "$drv" 2>/dev/null | tail -n 10 || true`, indented, under
  the line "(no error lines; last lines of the log)".
- `tests/failure-digest/` and `tests/failure-digest.nix`:
  - add `e-substitute.log`, trimmed from run 39553533096 (the
    `Cannot build '…omarchy-edge-20261021-087f73d.drv'` block,
    `gh run view 39553533096 --log`);
  - add its nixlog file under `nixlog/`, named like the existing ones and
    holding the builder lines, which end in `substituteStream() … ERROR: pattern … doesn't match anything in file …`;
  - add a second root whose nixlog ends in
    `menu-guidance: remove fingerprint did not name Nothing on this machine was changed`;
  - assert `has e-substitute "doesn't match anything in file"` and
    `has e-substitute 'did not name Nothing on this machine was changed'`.
  - Follow how the existing fixtures supply `nix log`.

→ verify: `checks.failure-digest` is green. It is cheap.
Traps: §8 says a skip-CI marker anywhere in a commit message skips CI.
The trimmed log must not contain one.

### Part C: proofs, by the lead

**C1.** Each red is run in a `git worktree add --detach` scratch tree,
with the break proven to have landed (`git diff` or a grep of the built
file) before its result is read:

| Cause | Break | Expected red |
|---|---|---|
| 1, 3, 4 | the real reds are plain `origin/edge` today | already captured in `/mnt/data/vmtest/edge-only-*.log` |
| 2 | the row's `when` set to `omarchy-sleep-disabled` (via the check's menu input) | "no longer asks" |
| 5a | line 3 of mise.sh deleted (a `substituteInPlace` in the scratch tree) | "did not reshim" |
| 5b | mise.sh writes over `~/.local/bin/claude` | the existing changed-file assertion |
| 6 | the `/usr/bin/spotify` substitution reverted | "launched '-- /usr/bin/spotify'" |
| 7 | the new fixtures, run on `origin/main`'s scripts | `has` fails |

Each break gets its green on the real tree. Logs go to
`/mnt/data/vmtest/proof-1398-*.log`.

**C2.** On the carry tree, build every check `generated-checks.sh`
emits, one at a time under the lock, the way the edge run does. That
list is the gate; a check missing from it is not proven.

### Part D: land

**D1. Edge.**
- `nix fmt -- --ci`, `statix` and `deadnix` on the carry tree.
- `git merge-base` must equal `origin/edge-candidate`.
- `git push origin HEAD:edge-candidate`: a fast-forward only.

**D2. Main.**
- Push the branch and open the PR with intent, spec, plan and B1.
- The body includes `Refs #1398`, the red output and the carry SHAs, and
  says which steps the coder did.
- Workflow-adjacent scripts are merged by you.

**D3. Promotion.** With your go-ahead, before 06:00 UTC:
- dispatch `omarchy-edge` with `from_candidate=true`;
- watch `prepare` and `verify`.
- If it is red, read the digest. Do not re-run blindly.

**D4.** Once `origin/edge`'s `flake.lock` no longer names them, delete
the five `nixarchy/qt612-on-pin` branches (#1391), and comment on #1398
and #1386.
- Close #1398 when edge publishes.
- Close #1386 after the p620 check in its plan.

### Part E: follow-up

**E1.** File "Adopt quattro 087f73d on edge" with milestone *Keeping the
lights on*, labels `omarchy-edge` and `ci`. Its body lists:
- the `omarchy-version-channel` re-anchor (the `grep -Eq …(arm-)?…`
  line);
- the `Menu.qml` `cardWidth` re-anchor, plus `style.font` →
  `appearance.font` in `1339-menu-fit-width.qml`;
- `tests/menu-guidance.nix:111`: use `grep -qx` instead of `head -n1`;
- the `style.*` → `appearance.*` ids, at `data/menu-actions.nix:111-120`,
  `modules/apps.nix:882` and the demo scenes;
- the other setter binary names to check: `microsoft-edge-stable`,
  `google-chrome-stable`, `zeditor`, `subl`, `cursor`;
- `omarchy-toggle-suspend`'s `/etc` write.

## Tests

| check | where | tier | expected |
|---|---|---|---|
| `menu-conditions`, `launch-browser-self-call`, `menu-guidance`, `provision-launchers`, `stale-scripts`, `bin-ledger`, `agent-account-routing` | carry tree | cheap; `bin-ledger` builds `.#omarchy` | green, with their reds from C1 |
| the full generated list | carry tree | cheap, one at a time | green |
| `failure-digest` | main branch | cheap | green, red on main's scripts |
| `checks.options`, the VM checks | CI only | | green in the `from_candidate` run and on the PR |

## Rollback

- **Edge:** `git revert` the carry concerned on `edge-candidate`, then
  run a `from_candidate` dispatch. Each cause is its own commit.
- **Main:** revert the PR. The digest goes back to "no error lines",
  which changes no CI status.

## Deviations during implementation

- **A3: the check's control could not see the bug on quattro.** Quattro
  runs the MOZ_LOG probe only for `--private`. A normal launch therefore
  recurses through `systemd-run … uwsm-app -- "$browser_exec"`, and the
  check stubbed both of those as loggers, so its control stopped at one
  call. The stubs now run what they are handed. The fixture still opens a
  plain URL: a `--private` fixture would pass the old placement too.
  C1's red for cause 3 is therefore re-run: the old anchor (guard inside
  the `--private` branch) must fail the updated check.
- **A3: `$'\n''…'` cannot be written inside a Nix `''` string**, because
  the `''` ends it. The second half is double-quoted instead, with the
  same result.
- **A6: a second stale line in `stale-scripts`.** With `omarchy-hw-x86` stubbed,
  the check reaches its Antigravity block, which expects the stored menu id
  `antigravity`. Edge stores `agy` on purpose (135c9394, #1278: "quattro names
  it agy, its command"). The edge check now expects `agy`; `main`'s stays
  `antigravity`, which is right for stable.
- **C2 found four more reds** on the stack with main merged; three were
  already red on plain `origin/edge`, invisible because they fail at
  evaluation or were never in a hand-kept list. Each gets its own carry:
  - D8 `shell-restart-race`: edge's `flake.nix` passes `omarchySrc`, which
    the test file (rewritten in #1335) no longer takes. Drop the argument.
  - D9 `iso-source`: edge's version `edge-YYYYMMDD-<rev>` makes the ISO label
    `NIXARCHY_edge-20261020-0a7beb7_NET` (34 chars, lowercase, `-`). Edge
    labels from the quattro rev: `NIXARCHY_EDGE_<REV>` + variant (25 chars).
  - D10 `install-phase-budget`: plain edge is 125723 bytes against the
    123000 budget; the stack adds ~1.2 KB. Long comments in the edge install
    phase move to `pkgs/AGENTS.md` behind `# Why:` pointers (the check's own
    instruction), at least 6000 bytes so a bump has headroom.
  - D11 `grep-q-pipefail`: A3 removed the old anchor line from
    `default.nix`, so its allowlist entry is stale. Delete it; the snippet's
    own entry stays.
