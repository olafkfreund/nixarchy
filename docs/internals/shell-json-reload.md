# Writing shell.json under a running shell breaks IPC (#847)

This is the evidence for an **upstream** report, written down here rather than
sent. Nothing in nixarchy fixes it and nothing here should pretend to: the
defect is in Quickshell's IPC handler registry, reached through Omarchy's
shell. Per the root `AGENTS.md` §11, an agent does not file in anybody else's
repository — a human sends this, and
`pkgs/omarchy/skills/nixarchy/contributing.md` has the routing.

Keeping it in the tree means the next person to hit this does not repeat the
measurement, and that the report is versioned with the tree it was made
against.

## What happens

Saving `~/.config/omarchy/shell.json` while the shell runs — **even writing it
back byte for byte identical** — leaves the bar's IPC targets dead. Measured on
one machine, 2026-09-24:

    $ sha256sum backup live      # identical: b0adf5cc6221a0f0…
    $ cat backup > ~/.config/omarchy/shell.json
    $ sleep 4
    $ omarchy-shell omarchy.clock status
    Target not found.
    $ omarchy-shell omarchy.network status
    Target not found.

with, in the shell's log:

    WARN: QQmlVMEMetaObject: Internal error - attempted to evaluate a function
          in an invalid context
    WARN scene: @plugins/bar/Bar.qml[2008:-1]: TypeError: Property
          'pluginBarApiFor' of object Bar_QMLTYPE_21 is not a function
          (exception occurred during delayed function evaluation)

61 `invalid context` errors in the following minute. `omarchy-restart-shell`
recovers it; nothing else does.

**The content is irrelevant.** Identical bytes are enough, which rules out any
explanation involving what the file says.

**It is not conditional on a stale environment.** The original report wondered
whether it mattered that the machine's login environment held a newer
`OMARCHY_PATH` than the running shell. It does not: the run above was made with
both verified on the same tree beforehand, as a control, and it reproduced
anyway.

## Why: `registerHandler` does not replace an incumbent

`src/io/ipchandler.cpp:356` at `v0.3.1`:

```cpp
void IpcHandlerRegistry::registerHandler(IpcHandler* handler) {
	auto& targetVec = this->knownHandlers[handler->targetState.target];
	targetVec.append(handler);

	if (this->handlers.contains(handler->targetState.target)) {
		qmlWarning(handler) << "Handler was registered but will not be used because another handler "
		                       "is registered for target "
		                    << handler->targetState.target;
	} else {
		this->handlers.insert(handler->targetState.target, handler);
	}
	...
```

The **first** handler to claim a target keeps it. A later one for the same
target is appended to the vector, warned about, and left inert. So if the
handler holding a target belongs to a generation that is being torn down, every
handler that replaces it is registered-but-unused, and IPC to that target
answers `Target not found` while the QML behind it throws in an invalid
context. That is the observed failure, and it is a consequence of **ordering**
rather than of anything the writer did — which is why identical bytes suffice.

`deregisterHandler` does promote `targetVec.first()` when the active handler
leaves, but that is whichever happens to be first in the vector, not
necessarily a live one.

## Why the existing fix does not cover it

`28771c7c74b4` — *"ipc: ensure handler deregistration upon destruction"*,
2026-08-02 — deregisters in `~IpcHandler()`.

**That commit is already in `v0.3.1`**: the tag (2026-08-21) is 11 commits
ahead of it and 0 behind. `v0.3.1` is also the latest tag, and it is what
reproduces. So this is not "fixed already, please upgrade" — there is nothing
to upgrade to, and the obvious fix is present.

The reason it does not cover this: destruction is **garbage-collector timed**,
not tied to generation teardown. On reload, the new generation's handlers can
register while the old generation's objects are still alive and still holding
their targets. Deregistering on destruction is correct and too late.

Two shapes of fix would address it, and this report should ask which is
preferred rather than assert one:

- deregister a generation's handlers at **generation teardown**, before the
  next generation registers; or
- have `registerHandler` **demote the incumbent** and take the target, rather
  than going inert — which also removes a silent failure mode where a handler
  is registered and simply never used.

## The crash, which is a second and less reproducible thing

The original report also saw a segfault, with this stack:

    #1  __dynamic_cast (libstdc++)
    #2  qs::io::ipc::IpcHandler::updateRegistration()
    #3  qs::io::ipc::IpcHandler::onPostReload()
    #4  QQmlObjectCreator::finalize(QQmlInstantiationInterrupt&)

`updateRegistration` (`ipchandler.cpp:304`) calls
`EngineGeneration::findObjectGeneration(this)` on the path taken when the
handler is not yet registered — i.e. during `onPostReload`, while the old
generation is being torn down. A dynamic_cast over an object whose generation
is going away is a plausible use-after-free, and it is consistent with the
frame.

**It did not reproduce in the controlled run.** The shell's pid was unchanged
throughout and no signal appears in the journal. Only the IPC breakage is
reliable. The report should say exactly that rather than imply a repro exists,
because a crash report that cannot be reproduced on demand and claims it can be
is worse than one that is honest about it.

## A duplicate that exists before any reload

On a **freshly restarted** shell, one monitor, nothing reloaded, there is
already exactly one such warning — for `omarchy.bar`. So that target is
double-registered from a clean start.

`Bar.qml` declares its `IpcHandler` at `:1185`, *outside* the
`Variants { model: Quickshell.screens }` blocks that begin at `:1196`, so
per-screen instantiation does not explain it. Something loads that component
twice.

This looks like Omarchy's rather than Quickshell's, and it is probably a
separate report. It is included because it is the seed: the target that is
already duplicated on a healthy shell is the one most exposed when a reload
adds a third.

It is **not** caused by nixarchy's packaging. nixarchy does patch `Bar.qml`
(`pkgs/omarchy/901-bar-keyed-layout.patch`) and that patch touches neither
`IpcHandler` nor `Variants` — checked, because a defect introduced by our own
patch would be ours to fix and would not belong in an upstream report.

## Versions

| | |
|---|---|
| Quickshell | 0.3.1, `tag-v0.3.1`, from nixpkgs |
| Qt | 6.11.2 (from the original report) |
| Omarchy | the tree nixarchy vendors, with `901-bar-keyed-layout.patch` |

## What nixarchy did instead

Nothing that fixes it, deliberately. A patch to Quickshell or to the shell
would be re-applied at every source bump, and this is a lifetime bug in a
dependency's IPC layer.

- `modules/AGENTS.md` no longer suggests writing the file live, and states the
  supported path: change it through the running shell's own writer or its IPC.
- `build.yml` fails if anything under `modules/`, `pkgs/`, `installer/` or
  `tests/` acquires a writer for it.
- `tests/session.nix` asserts the **recovery** — that
  `omarchy-restart-shell` brings the targets back and leaves the file
  unchanged — and says in the file that it deliberately does not assert the
  defect, so it cannot invert when this is fixed.
