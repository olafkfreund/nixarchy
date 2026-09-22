---
status: draft
issue: 896
intent: intent/2026-09-22-896-panel-buttons-over-ipc.md
---

# Spec: the rebuild panel's buttons are driven by a check, not only by hand

## Design

The panel's three actions already live in the `RebuildState` singleton, and the
buttons are thin: `RebuildView.qml`'s buttons call `RebuildState.start()`,
`RebuildState.copyLog()` and `RebuildState.openInTerminal()` and do nothing
else. So the IPC surface is three functions that call those same three methods,
and the intent's hardest constraint -- *whatever the button does and whatever
IPC does must be one code path* -- holds **by construction** rather than by
discipline. There is no second implementation to drift.

`pkgs/rebuild-panel/Panel.qml`'s existing `IpcHandler` gains:

```qml
function rebuild(): void { RebuildState.start() }
function copyLog(): void { RebuildState.copyLog() }
function openLog(): void { RebuildState.openInTerminal() }
```

### Open question 2, settled: a verb per button, not a generic `invoke`

The intent left this to the spec. **A verb per button**, because of how a wrong
call fails.

`omarchy-shell` is a wrapper over `qs ipc call`, and its own comment records the
trap: *"qs reports connection failures with a nonzero exit, but IPC-level
failures (unknown target/function, bad arguments) go to stdout with exit 0."*
The wrapper repairs that with an explicit case over the output --
`"Function not found."`, `"Too few arguments provided"` and friends become a
`fail` and a nonzero exit.

That repair is **per function name**. With a verb per button, a typo'd or
removed verb is caught by the wrapper itself: `Function not found.`, exit
nonzero, loudly. With one `invoke("rebuild")`, the function always exists and a
bad action string is only as loud as the QML chooses to be -- and a QML `switch`
with no `default` returns quietly, with `qs` exiting 0. That is §1's green light
with an extra layer of indirection: the check would pass against a panel whose
action dispatch had been deleted.

The surface does not grow without bound. The panel has three actions because it
has three buttons, and a fourth would be a design decision worth noticing, not a
line to hide behind a string argument.

### What each assertion asserts, and on what

Every assertion is a **system fact**, never a pixel. #765 PR 1 established this
theme is unreadable to the test's OCR, which is why the existing probe waits on
a `polkit-agent-helper@*` unit rather than on text.

| action | asserted by |
| --- | --- |
| `rebuild` | the `nixarchy-rebuild` user unit exists and is active afterwards, having not existed before |
| `copyLog` | `wl-paste` in the same session returns the unit's journal text |
| `openLog` | a terminal process is running with `journalctl` and the unit name in its argv |
| reattach | with a unit running, `close` then `open` then `status` still reports `running` |
| **opening starts nothing** | after `open` on an idle machine, the unit still does not exist |

The last row is the one that matters most and is the easiest to leave out. The
panel exists so that a switch is not one stray click (#895, "it asks before it
switches"). A regression that started the rebuild on open would be invisible to
every other assertion here -- each of the others would still pass.

### Where it goes

`tests/session.nix`, immediately after #895's existing panel probe, which
already logs in through the greeter, already drives the `nixarchy-rebuild` unit,
and already has the `as_user` helper carrying `XDG_RUNTIME_DIR` and
`DBUS_SESSION_BUS_ADDRESS`. No new node, no new `checks.<name>`, so no workflow
edit and no CI-gate change (§4, §11).

## Alternatives rejected

- **Drive a real click.** Nothing in the suite clicks in the shell's QML, and
  building that means synthesising input to a compositor and then reading the
  result back -- by OCR, which does not work against this theme. It would test
  the harness more than the panel.
- **One generic `invoke(action)`.** Rejected above: a bad action string fails
  quietly where a bad function name fails loudly.
- **Assert `start()` by stubbing `nixarchy-apply`.** Tempting, because the VM is
  offline and the rebuild cannot succeed. Rejected: a stub proves the panel
  called *a* command, not that it started the unit the rest of the design reads.
  Pointing the detached apply at a missing flake -- what #805's probe already
  does -- gives a real unit with `Result=exit-code`, which is the honest
  measurement available here.
- **Move the actions out of QML into the state command.** `nixarchy-rebuild-state`
  is read-only by design; making it start and stop things would put a second
  writer beside `nixarchy-apply --detach` for no gain.

## Risks

- **`wl-copy` may not survive for `wl-paste` to read** (open question 1). It
  forks a daemon that holds the selection, and in a VM under the test driver
  that daemon's lifetime is not something this spec controls. **Decision:**
  include it, because the plugin already puts `wl-clipboard` on the session
  PATH and `wl-paste` is a system fact rather than a pixel -- but if it proves
  flaky in CI, drop *that one row* and record it in `tests/AGENTS.md` as a
  named hole rather than retrying until green (§10). It is the weakest of the
  three and must not be allowed to make the other two flaky by association.
- **`checks.session` does not run locally.** Every red/green pair costs a CI
  round trip. This is the main cost of the work and the reason to write all the
  assertions before the first push rather than discovering them one run at a
  time.
- **The session VM is offline**, so a *successful* rebuild still cannot be
  staged (#805's recorded hole). `rebuild` is proven to start the unit, never
  to finish it.
- **Adding IPC functions does not change the bar or Mode A.** The panel remains
  a `defaultPluginSet` entry resolving to nothing without
  `programs.nixarchy.enable`, so there is no Mode A surface to re-check beyond
  what `checks.options` already asserts.

## Verification

Each assertion gets its §1 red/green pair, and each break must be shown to have
removed *the thing the assertion is about* -- not merely to have landed. That
distinction cost a wrong proof on #895: renaming a `defaultPluginSet` attribute
went red on a different assertion while the plugin stayed installed.

| assertion | break that must turn it red |
| --- | --- |
| `rebuild` starts the unit | the IPC function body emptied -- the unit never appears |
| opening starts nothing | `RebuildState.start()` called from the panel's `onOpenedChanged` -- the unit appears when it must not |
| `copyLog` | the function emptied -- `wl-paste` returns the previous selection or nothing |
| `openLog` | the function emptied -- no terminal process matches |
| reattach | `RebuildState` made to reset its state on close -- `status` reports `idle` over a running unit |

Plus, once, the mechanism itself: call a verb that does not exist and confirm
`omarchy-shell` fails with `Function not found.` and a nonzero exit. Without
that, every assertion above rests on an untested assumption about the wrapper,
and `qs ipc` on its own would have exited 0.

## Out of scope

**"One polkit dialog per Apply"** (open question 3, confirmed out). It needs a
real switch with a network; no VM here drives one. It is already a named hole
from #765 PR 1 and stays a by-hand check on real hardware. Folding it in would
make #896 unclosable.

**The panel's rendering.** Nothing here proves what it looks like. The hole in
`tests/AGENTS.md` shrinks to that, and to the dialog count, rather than
disappearing.
