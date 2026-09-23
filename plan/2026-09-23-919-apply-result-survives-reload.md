---
status: approved
issue: 919
spec: spec/2026-09-23-919-apply-result-survives-reload.md
---

# Plan: an apply started from a panel tells you how it ended

This plan is self-contained: it carries every approved spec decision.

## Decisions

- **The bar widget in `pkgs/rebuild-panel/` holds the settled result** (owner,
  2026-09-23). Not a notification, not a panel that reopens itself.
- **`Panel.qml:58` is the whole defect for the success case.** Today:
  `visible: RebuildState.active || root.opened || RebuildState.state === "failed"`.
  Running shows, **failed already shows**, succeeded hides. The user is not
  told the thing they are waiting for.
- **The result already persists and nothing durable is invented.**
  `modules/apps.nix:3620-3629` maps the `nixarchy-rebuild` unit's `SubState` /
  `Result` / `ExecMainStatus`, and `exited` + `Result=success` + `code=0` is
  `succeeded`. #765 omits `--collect` on purpose, so the unit stays loaded and
  the state outlives the panel, the reload and the session.
- **Opening the panel is the acknowledgement.** A settled result the user has
  looked at stops drawing in the bar. No new verb, no new UI.
- **The view carries the run's end time**, because a unit loaded from the last
  boot would otherwise claim a fresh success at every login.
- **The other panels are not touched.** They hand off to `nixarchy-apply` and
  exit; that is why "must not require every panel to be changed" is satisfied
  by construction.
- **The reload is investigated and deliberately NOT changed.** The finding: the
  shell is not a systemd user unit, so a switch does not restart it that way.
  `modules/home.nix:1020` and `:1026` say the shell reloads every plugin on any
  event in `~/.config/omarchy/plugins/`, and activation writes a link only when
  its target differs (#710). So a rebuild that changes any plugin's store path
  closes every panel, and one that changes none does not. Suppressing that
  would be #710 run backwards, and a genuinely changed plugin *should* reload.
- **Failure is not made louder than success.** It is already the visible one;
  the gap is symmetry.

## Steps

**1. `pkgs/rebuild-panel/RebuildState.qml`: carry the end time.**
Read `ExecMainExitTimestamp` alongside the fields already parsed, exposed as a
property. Absent or unparseable is empty rather than an error — a unit that has
never run has no such timestamp.

→ verify by `checks.qml` staying green, and by the property appearing in the
file; there is no QML driver in this suite, which is why step 2 keeps the
logic out of QML.

**2. `modules/apps.nix`: `nixarchy-rebuild-state` emits the end time.**
The mapping already lives in a command rather than in QML precisely so it can
be tested (#765 PR 5). Extend its output with the timestamp, in the same shape
as the state.

→ verify by `checks.apply-staging`, which drives it against a stubbed
`systemctl`; add the exited/success/0 case if it is not already covered.
→ **break:** stub a unit with `Result=success`, `ExecMainStatus=0`,
`SubState=exited` and assert the output carries both `succeeded` and a
timestamp. Remove the timestamp from the command and watch it fail.

**3. `pkgs/rebuild-panel/Panel.qml`: the widget stays up on a settled result.**
The rule becomes visible while running, while open, while failed, **and while a
settled result has not been acknowledged**. Acknowledgement is `root.opened`
having been true for this result.

→ verify by reading the built file, and by step 4's assertion.

**4. `pkgs/omarchy/default.nix`: assert the rule survives a source bump.**
A grep-shaped assertion beside the existing `--replace-fail` anchors: the built
`Panel.qml` mentions `succeeded` in its visibility expression.

→ verify by `nix build .#omarchy`.
→ **break:** revert the visibility rule to today's and watch the build fail
naming #919.

**5. `pkgs/rebuild-panel/RebuildView.qml`: show when it finished.**
"Applied" and "Failed" carry the end time from step 1.

→ verify by `checks.qml`.

**6. `modules/AGENTS.md`: record what closes the panels.**
Beside the #710 note it extends, because that note explains the reconcile and
this explains its consequence. Include the falsifiable prediction, so the next
reader can check it rather than believe it.

→ verify by the anchor resolving from any `# Why:` pointer that references it.

**7. The prediction, on real hardware.** Apply a change that touches
**packages but no plugin**, and confirm the panel stays open. This is the only
step that can falsify the reasoning the whole spec rests on.

→ verify by the observation, recorded in the PR. **If the panel closes anyway,
the plugin-watcher explanation is wrong** — steps 1-5 still stand, because they
fix the missing success report regardless, but step 6's paragraph is deleted
rather than shipped.

**8. The on-screen behaviour**, once, by the owner: apply from a panel and
watch the bar after the reload.

→ verify by the observation. Not reachable by any check here: no VM in this
repository has a session that reloads its shell mid-apply, which is why CI
never saw the bug.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.apply-staging` | green; red with the timestamp removed from the command |
| `nix build .#omarchy` | green; red with the visibility rule reverted |
| `nix build .#checks.x86_64-linux.qml` | green |
| `nix build .#checks.x86_64-linux.options` | green — no option changes, so this is a regression check only |
| step 7, on razer or p620 | the panel stays open for a plugin-free apply |
| step 8, on razer or p620 | the bar reports the result after the reload |

## Rollback

Every change is additive and confined to `pkgs/rebuild-panel/`, one command in
`modules/apps.nix`, one assertion in `pkgs/omarchy/default.nix`, and one
paragraph in `modules/AGENTS.md`. Reverting the commit restores today's
behaviour exactly: the widget hides on success again, and nothing else on the
machine changes. No option, no user-visible default, nothing in anyone's
configuration.
