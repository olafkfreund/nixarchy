---
status: draft
issue: 1398
intent: intent/2026-10-21-1398-edge-generated-checks.md
---

# Spec: edge publishes again: green on its full check list, and on the newest quattro

Approved in the intent:
- one task, one carry commit per cause;
- the digest fix is part of this task, on `main`;
- an upstream bug is carried here, with an upstream report drafted for your approval.

Research was read-only and done by three agents. I re-measured the one
claim that touched #1386. Logs from the five red checks on plain edge are
in `/mnt/data/vmtest/edge-only-*.log`.

## Scope change from the intent: 087f73d is a follow-up, not this task

The intent's outcome was "green on the newest quattro". Fixing 087f73d's
two broken patches is not enough for that. Quattro 087f73d also moves the
whole `style.*` menu tree to `appearance.*`, 85 ids, and nixarchy still
names several of them:

- `data/menu-actions.nix:111-120`;
- `modules/apps.nix:882`;
- the demo scenes.

That is a menu migration, not a patch re-anchor.

So this task makes edge **green at quattro 0a7beb7, its current pin**.
After that, a scheduled run whose newest quattro is red still promotes
main through #1394's fallback. Edge then gets main's fixes every day
again.

Adopting 087f73d becomes a new issue, filed after this spec is approved,
with everything the scan found:

- the two re-anchors below;
- the `menu-guidance` `head -n1` change;
- the `appearance.*` ids.

## Design

### Causes and verdicts

All five reds fail identically on `origin/edge` with main **not** merged
in, so none comes from main. The "same at 087f73d" column was read from
the upstream source, not built.

| # | Check | Cause | Verdict | Same at 087f73d |
|---|---|---|---|---|
| 1 | `menu-conditions` (editor, browser) | quattro's setters gained `if omarchy-cmd-missing "$x"; then exec … --install` (`bin/omarchy-default-editor:42-44`, `bin/omarchy-default-browser:42-44`). They probe `helix` (nixpkgs ships `hx`) and `zen-browser` (nixarchy's binary is `zen-beta`). The `setsid: not found` line comes only from the check's PATH, and `util-linux` is in `runtimeDeps`. | **Real bug:** on edge, picking Helix or Zen opens a terminal that tries an Arch install, and nothing is set | yes |
| 2 | `menu-conditions` (hibernate) | Upstream changed the row's `when` to `omarchy-hibernation-available && ! omarchy-sleep-disabled`, and `tests/menu-conditions.sh:75` compares it for equality | **Stale check** (§1 read backwards) | yes |
| 3 | `launch-browser-self-call` | The #1342 guard is placed in front of `if $browser_exec --help … MOZ_LOG; then`. Quattro moved that line inside the `--private` branch, so the guard runs only for private launches | **Real bug:** #1342's unbounded relaunch is back on edge for normal link opens | yes |
| 4 | `menu-guidance` (remove fingerprint) | Edge's #1278 patch makes the script call `/run/current-system/sw/bin/id`, which the sandbox lacks. The script exits 1 there, before the #1304 guidance it splices in prints | **Check-only:** users are fine. The guidance is placed after a lookup it does not need | yes |
| 5 | `provision-launchers` | Quattro's `install/user/mise.sh` no longer writes `~/.local/bin` launchers. It is now `mise reshim --system; mise reshim` (tools are lazy mise shims, and `omarchy-tools.toml` is divergent here on purpose, #707) | **Stale check.** Real mise exits 0 on both calls with no config (measured), so first login is safe | yes |
| 6 | `stale-scripts` | The spotify installer now calls `omarchy-hw-x86` and `omarchy-webapp-install`. Both ship, but the check's PATH holds only its stubs, so the `if` takes the ARM branch and exits 127 | **Stale check.** It tests nothing about our `/usr/bin/spotify` patch any more | yes |
| 7 | the failure digest (main) | `.github/scripts/failure-excerpt.sh:13` greps case-sensitively for `error\|Error\|FAIL…`. A `substituteStream() … ERROR: pattern` line and a check's own last line (`menu-guidance: … did not name …`) match neither. `failure-digest.sh:54-55` then says "no error lines" | **Real bug** (#1393's own) | n/a |

### Fixes: carry commits on `edge-candidate`, one per cause

1. **Setters** (`pkgs/omarchy/default.nix`, beside the #1303 block at
   ~:1379):
   - `omarchy-default-editor`: replace
     `'if omarchy-cmd-missing "$editor"; then'` with
     `'if omarchy-cmd-missing "$([[ $editor == helix ]] && echo hx || echo "$editor")"; then'`.
     The file still records `helix`, so the menu's `checked` test and the
     launcher's existing `helix → hx` patch still hold.
   - `omarchy-default-browser`: replace `'command="zen-browser"'` with
     `'command="zen-beta"'`.

   `data/bin-ledger.nix` gains a `patch` row for `omarchy-default-editor`,
   and the browser row's reason grows a clause.
2. **Hibernate check:** `tests/menu-conditions.sh:75` accepts a `when`
   that is `omarchy-hibernation-available`, or begins with
   `omarchy-hibernation-available && `. The property is "it still asks
   whether hibernation is available", not the exact string. That passes
   on main and edge.
3. **Browser guard** (edge, ~:627): anchor on upstream's top-level line
   12, `private_flag="--private"`. Insert the guard before it with
   `"$(sed '$d' ${./1342-launch-browser-self-call.sh})"$'\n''private_flag="--private"'`.
   `sed '$d'` drops the snippet's own last line, which is main's anchor.
   The snippet file is shared with main and stays untouched. No ledger
   change: the row is already `patch`, and its reason still holds.
4. **Fingerprint guidance** (edge, ~:1505): splice the guidance in front
   of `# Resolve the invoking account before changing authentication or packages.`
   (one line, one match), so it prints and exits before the lookup. The
   `id` path patch (#1278) stays, because `stale-scripts` depends on it.
   Patch only, the check is unchanged.
5. **`provision-launchers`** (edge): retarget to what mise.sh does now.
   - Drop the 14-launcher `want` list.
   - Assert `grep -qx 'mise reshim --system' "$TMPDIR/calls"`, using the
     check's mise stub, which already logs its calls.
   - Keep every assertion that nothing writes over or deletes a Home
     Manager link (#1319). That is still the property that matters.
   - Update `tests/AGENTS.md:1809`, where the `all.sh` line number moved
     from 14 to 18.
6. **`stale-scripts`** (edge): stub `omarchy-hw-x86` to exit 0
   (`tests/stale-scripts.nix:15`). The x86 branch then runs on any
   builder, and the existing `-- spotify` assertion guards our
   `/usr/bin/spotify` patch again.

### Fix on `main`: the digest (cause 7)

- `failure-excerpt.sh:13`: add `ERROR` to the alternation. Not `-i`,
  which would pull in `-Werror` and `errors=0`.
- `failure-digest.sh:55`: when the excerpt is empty, print the last 10
  lines of `nix log` instead of "no error lines". A check's own final
  verdict line is then always shown.
- `tests/failure-digest/`: add `e-substitute.log` plus its nixlog,
  trimmed from run 39553533096 lines 912-927. Add a second root whose log
  ends in the `menu-guidance: … did not name …` line. `has` asserts both
  lines.

### Promotion order

Scheduled edge runs start from `origin/edge` and force-push
`edge-candidate` daily at 06:00 UTC (`omarchy-edge.yml:348`). So:

1. Push carries 1–6, then #1386's 4cd1fa90, to `edge-candidate` as
   fast-forwards.
2. **With your go-ahead**, run one `omarchy-edge` dispatch with
   `from_candidate=true`. It keeps the candidate's quattro, merges main,
   and builds the full list. Do this before the next 06:00.
3. Once edge has main, delete the five `qt612-on-pin` branches (#1391).

## Alternatives rejected

- **Exempting the five checks from edge's generated list:** hides what
  #1392 exposed (§4, intent constraint).
- **Bumping to 087f73d in this task:** an 85-id menu migration hiding in
  a "fix CI" task. It gets its own issue (above).
- **Stubbing `id` for `menu-guidance`:** an absolute path cannot be
  stubbed, and dropping the `id` patch breaks #1278.
- **Cutting the #1342 snippet to its four guard lines** so each branch
  adds its own anchor: cleaner, but it edits `main` for an edge-only
  problem.
- **Putting `${omarchy}/bin` on `stale-scripts`' PATH:** real commands
  would then start resolving in the later cursor and snapshot sections,
  so it is no longer hermetic.

## Risks

- **Cause 1's fix covers only Helix and Zen.** Quattro's new install
  branch may misfire for any app whose nixpkgs binary name differs:
  `microsoft-edge-stable`, `google-chrome-stable`, `zeditor`, `subl`,
  `cursor`. These were not checked, and go in the follow-up issue.
- **`omarchy-toggle-suspend` writes `/etc/systemd/sleep.conf.d/…`**,
  which the new hibernate `when` reads, and which is probably not
  writable on NixOS. This is unverified, and goes in the follow-up.
- **The fallback publishes main on 0a7beb7 only while 0a7beb7 stays
  green.** A future main change that breaks edge's list still stops
  edge. That is the intended behaviour, and it now files an issue
  (#1398 was filed that way).
- **#1386 rides the same promotion.** Its proof was re-checked against
  the provision agent's concern: `mise reshim` writes the wrappers to
  `command-wrappers/bin` only, and `shims/` stays empty (measured). So
  the agent launcher's shims-first PATH cannot pick a wrapper up.

## Verification (§1)

| Cause | Red | Green |
|---|---|---|
| 1, 3, 4 | the existing check, red on plain edge today (logs above) | the same check after the carry |
| 2 | `menu-conditions` with the row's `when` set to something not starting with `omarchy-hibernation-available` | the retargeted check |
| 5 | (a) line 3 of the shipped mise.sh deleted: "did not reshim"; (b) mise.sh writing over `~/.local/bin/claude`: the existing changed-file assertion | the retargeted check |
| 6 | our `/usr/bin/spotify` substitution reverted: "launched '-- /usr/bin/spotify'" | the stubbed check |
| 7 | the new fixtures on `main`'s current scripts | the fixtures after the fix |
| all | the full generated list on the candidate, through the `from_candidate` run | the same run |

For every red, prove the break landed (`git diff`, or grep the built
file) before reading the result.
