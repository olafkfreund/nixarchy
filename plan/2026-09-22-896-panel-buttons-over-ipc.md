---
status: draft
issue: 896
spec: spec/2026-09-22-896-panel-buttons-over-ipc.md
---

# Plan: the rebuild panel's buttons are driven by a check

## Decisions this plan carries over from the approved spec

- **Three IPC functions, a verb each**, on the existing `IpcHandler` in
  `pkgs/rebuild-panel/Panel.qml`: `rebuild()`, `copyLog()`, `openLog()`. Each
  calls the `RebuildState` method the button already calls
  (`start()`, `copyLog()`, `openInTerminal()`), so IPC and the button are **one
  code path by construction** -- there is no second implementation to drift.
- **Not one generic `invoke(action)`.** `omarchy-shell` wraps `qs ipc call` and
  repairs its "IPC-level failures exit 0" behaviour by matching the output --
  `"Function not found."`, `"Too few arguments provided"` -- and failing. That
  repair is **per function name**, so a typo'd or deleted verb fails loudly. A
  bad string argument to a generic `invoke` is only as loud as the QML chooses
  to be, and a `switch` with no `default` returns quietly with `qs` exiting 0.
- **Every assertion is a system fact, never a pixel.** #765 PR 1 established
  this theme is unreadable to the test's OCR, which is why the existing probe
  waits on a `polkit-agent-helper@*` unit rather than on text.
- **Opening the panel must start nothing.** This is the assertion that protects
  #895's "it asks before it switches"; every other assertion here still passes
  if a regression made the panel rebuild on open.
- **`copyLog` is in, with a stated fallback.** If the `wl-copy`/`wl-paste`
  round trip proves flaky in CI, drop *that row* and name it in
  `tests/AGENTS.md` as a hole. Never retry until green (§10). It must not be
  allowed to make the other two read as flaky.
- **No new `checks.<name>`**, so no workflow edit and no CI-gate change (§4,
  §11). The assertions extend `checks.session`, which a PR-triggered workflow
  already builds.
- **Out of scope:** "one polkit dialog per Apply" (needs a real networked
  switch; already a named hole from PR 1), and the panel's rendering.

## What the code already looks like

- `pkgs/rebuild-panel/Panel.qml` has an `IpcHandler` with `open`, `close`,
  `show`, `hide`, `toggle`, `status`. `status` returns
  `{"state":…,"exit":…}` as JSON.
- `pkgs/rebuild-panel/RebuildState.qml` has `start()`, `copyLog()`,
  `openInTerminal()`. `start()` returns early if `root.active`.
- `tests/session.nix` already has, in one block (`:518`-`:540`): a running
  `nixarchy-rebuild` unit (a `sleep 300` left over from #805's refusal case),
  an `as_user` helper carrying `XDG_RUNTIME_DIR` and
  `DBUS_SESSION_BUS_ADDRESS`, an assertion that `nixarchy-rebuild-state` reads
  it as running, and `nixarchy-plugin nixarchy.rebuild` opening the panel. It
  ends by stopping the unit.

## The trap this plan exists to avoid

**The panel runs `journalctl --user -u nixarchy-rebuild` itself.**
`RebuildState`'s `followProcess` follows the unit's journal whenever the panel
is showing a rebuild. So an `openLog` assertion written as "a process matching
`journalctl.*nixarchy-rebuild` exists" is satisfied **by the panel's own log
follower**, with `openInTerminal()` emptied. That is a green light, and it is
the obvious way to write it.

`openLog` must therefore match the **terminal launch**, not the journalctl
call: `omarchy-launch-floating-terminal-with-presentation` is what
`openInTerminal()` execs, and nothing else in the panel runs it. Step 4 proves
this by emptying the function and watching the assertion go red -- if it stays
green, the assertion is matching the follower and must be retargeted before
anything else here is believed.

## Steps

0. **Before anything local:** read the bus, and check nothing is in flight:
   `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
   (§6). `checks.session` is a booted VM. Work in
   `/mnt/data/vmtest/nixarchy-896`.

1. **The three IPC functions.** `pkgs/rebuild-panel/Panel.qml`, in the existing
   `IpcHandler`, beside `status`:

   ```qml
   function rebuild(): void { RebuildState.start() }
   function copyLog(): void { RebuildState.copyLog() }
   function openLog(): void { RebuildState.openInTerminal() }
   ```

   With a 1-3 line note at the block saying what they are for: a check presses
   what a person presses, through the same methods, so there is no second path
   (§7).
   → Verify: `nix build .#checks.x86_64-linux.qml` still parses the file.

2. **The mechanism, once.** Before trusting any assertion below, prove the
   wrapper turns an unknown verb into a failure. In `tests/session.nix`:
   `machine.fail(as_user("omarchy-shell nixarchy.rebuild.bar noSuchVerb"))`.
   → This is not decoration. Without it every assertion below rests on an
   untested assumption, and `qs ipc` on its own exits 0 for exactly this case.
   **Red first:** none needed -- it *is* the negative case. But confirm it goes
   green only after step 1, and that it names `Function not found.`

3. **Reattach, where a unit is already running** -- so it goes *before* the
   existing stop at `:540`, inside the block that still has the `sleep 300`
   unit:
   - `omarchy-shell nixarchy.rebuild.bar close`
   - `omarchy-shell nixarchy.rebuild.bar open`
   - `status` still reports `running`.
   → **Red first:** make `RebuildState` reset `state` to `idle` in its
   `onOpenedChanged`, so a reopened panel forgets the unit. `status` then
   reports `idle` over a running unit.

4. **`openLog`**, still with the unit running:
   - `omarchy-shell nixarchy.rebuild.bar openLog`
   - assert a process whose argv contains
     `omarchy-launch-floating-terminal-with-presentation` -- **not** a bare
     `journalctl` match (see the trap above).
   → **Red first:** empty `openInTerminal()`'s body. The assertion must go red.
   **If it stays green, stop:** the assertion is matching the panel's own log
   follower and the whole row is worthless until retargeted.

5. **`copyLog`**, still with the unit running and a journal to copy:
   - `omarchy-shell nixarchy.rebuild.bar copyLog`
   - `wl-paste` in the same session returns text the unit's journal contains.
   → **Red first:** empty `copyLog()`'s body -- `wl-paste` returns the previous
   selection or fails.
   → **If flaky:** drop this row, record it in `tests/AGENTS.md`, do not retry
   (§10). Note in the PR that it was dropped and why.

6. **Now stop the unit** (the existing line at `:540`), and clear it, so the
   machine is genuinely idle: reset its failed state as well as stopping it,
   because #805's decisions record that a failed unit stays loaded without
   `--collect`.
   → Verify: `nixarchy-rebuild-state` reads `idle`.

7. **Opening starts nothing** -- the assertion that matters most:
   - with no unit, `omarchy-shell nixarchy.rebuild.bar open`
   - assert the unit **still does not exist** (its `LoadState` is `not-found`,
     or `nixarchy-rebuild-state` reads `idle`).
   → **Red first:** call `RebuildState.start()` from the panel's
   `onOpenedChanged`. The unit appears and this goes red while every other
   assertion here stays green -- which is the point of having it.

8. **`rebuild` starts the unit.**
   - `omarchy-shell nixarchy.rebuild.bar rebuild`
   - wait until the `nixarchy-rebuild` unit exists.
   The VM is offline and cannot evaluate its own flake, so the unit will fail
   quickly with `Result=exit-code` -- as #805's probe already relies on. That
   is the honest measurement here: **the unit was started**, never that a
   rebuild succeeded.
   → **Red first:** empty the `rebuild()` IPC function's body. No unit appears.

9. **Docs.** `tests/AGENTS.md`: the "The panel one" section shrinks. It must
   now say what is covered (the three actions, reattach, and that opening
   starts nothing) and what is still not (the rendering, and the dialog count),
   rather than reading as though nothing is covered.

10. **Format and lint:** `nix fmt -- --ci`, statix, deadnix. §5: no heredoc
    inside an indented Nix string; write files with `printf '%s\n'`.

11. **Commit and PR.** `git add` every file (§5). One commit, subject a full
    sentence (§8). Paste the red output from steps 3, 4, 5, 7 and 8. `Closes
    #896`. Check `gh pr view --json mergeable` against a freshly rebased `main`
    (§9), and confirm the PR's `headRefOid` matches what was pushed before
    reading any check result (§6).

## Tests

| check | expected green | §1 break, and the expected red |
|---|---|---|
| `checks.qml` | the panel's QML still parses | a syntax error in `Panel.qml` |
| `checks.session`, step 2 | an unknown verb fails | it is the negative case itself |
| `checks.session`, step 3 | reattach reports the running unit | state reset on `onOpenedChanged` -> `idle` |
| `checks.session`, step 4 | `openLog` launches the terminal | `openInTerminal()` emptied -> red (**if green, the assertion matches the panel's own follower**) |
| `checks.session`, step 5 | `copyLog` puts the journal on the clipboard | `copyLog()` emptied |
| `checks.session`, step 7 | opening starts nothing | `start()` called from `onOpenedChanged` -> unit appears |
| `checks.session`, step 8 | `rebuild` starts the unit | the IPC function emptied -> no unit |

**`checks.session` does not run locally** (`tests/AGENTS.md`), so each of these
costs a CI round trip. Write every assertion before the first push rather than
discovering them one run at a time, and expect the red proofs to be a second
push rather than a local loop. Never pipe a build whose exit status is the
result (§1).

## Rollback

Revert the PR. The three IPC functions go away and the panel is exactly as
#895 shipped it -- the buttons never depended on them, because they call
`RebuildState` directly. `tests/session.nix` returns to asserting only that the
panel opens. Nothing a user runs changes in either direction: no menu row, no
key bind and no script calls these verbs, and nothing is written outside the
system closure.
