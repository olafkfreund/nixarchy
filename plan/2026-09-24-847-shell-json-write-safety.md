---
status: draft
issue: 847
spec: spec/2026-09-24-847-shell-json-write-safety.md
---

# Plan: writing shell.json while the shell runs must not break the shell

Self-contained. The approved decisions, carried over so this can be implemented
without opening the intent or the spec:

- **Scope (a)**: document the hazard, make our own tree safe, report upstream.
  No writer command, no patch to the vendored shell or to Quickshell.
- The bug is **general**. Reproduced on razer with the running shell and the
  login environment verified on the same tree first, writing byte-identical
  content: `omarchy.clock` and `omarchy.network` went to `Target not found`,
  `Bar.qml[2008]` threw `Property 'pluginBarApiFor' … is not a function`, 61
  `invalid context` errors followed in a minute, and `omarchy-restart-shell`
  recovered it with `shell.json` byte-identical throughout.
- The **`OMARCHY_PATH` mismatch is a red herring** — not a precondition.
- The **segfault did not reproduce**; only the bar disarming is reliable.
- **`v0.3.1` is the latest upstream tag**, it is what reproduces, and it
  *already contains* `28771c7c74b4` "ipc: ensure handler deregistration upon
  destruction" — 11 commits ahead, 0 behind.
- Nothing nixarchy ships writes `shell.json`. Verified by grep.
- `checks.session` already boots a real desktop and is already built by a
  PR-triggered workflow, so assertions can be added to it **without** a
  `checks.*` entry and without a workflow edit (§4, §11).

## The decision the spec delegated

The spec left one thing open: a VM assertion that encodes today's broken
behaviour goes red *when upstream fixes it*, which is §1's exact trap — a
deliberate change turns a check red and the reader's first instinct is to
satisfy it rather than to ask what it was asserting.

**Resolved: the VM check asserts the recovery contract, not the bug.**

`checks.session` gains: write `shell.json` back byte for byte under the running
shell, then run `omarchy-restart-shell`, then require that an IPC target
answers again. That invariant is true today **and** remains true after any
upstream fix, so it never inverts. It guards precisely what the documentation
tells a user to do when this happens, which is the part we own and the part
that would be embarrassing to have silently break.

**The defect itself is documented as a hole, not asserted.** §3 is explicit
that a row naming what no layer can reach is worth more than a check that
closes it on paper — a documented hole gets tested by a human, an undocumented
one gets tested by a user. Asserting the broken behaviour would buy detection of
an upstream fix at the cost of a check that means the opposite of what it says.

**A canary that detects the upstream fix is proposed, not wired.** The right
home is the nightly, and adding a job there is a workflow edit and therefore a
CI-gate change needing a human (§11). Raised in the PR with the reasoning; not
built here.

## Steps

1. **`modules/AGENTS.md:1382`**: delete "The shell watches the file and reloads
   it, so an atomic replace is picked up live, with no IPC." Replace with what
   happens (the measurement above, in two or three lines) and the supported
   path — through the running shell's own writer or its IPC, never by editing
   the file — citing `modules/home.nix:1749` for the independent reason a second
   writer loses updates.
   → verify by `grep -n "picked up live, with no IPC" modules/AGENTS.md`
   returning nothing, and the new text naming `Target not found`.

2. **The static check**: in `build.yml`'s existing static block, beside the
   other repo-shape assertions, fail if anything under `modules/`, `pkgs/`,
   `installer/` or `tests/` writes `shell.json`. Match writes (redirection,
   `tee`, `mv`/`cp` into it, a Nix `writeText` targeting it), not mentions —
   the tree is full of legitimate mentions, including this plan's own siblings,
   so `intent/`, `spec/` and `plan/` are out of scope along with `*AGENTS.md*`.
   → verify per §1: add a writer to a file under `modules/`, run the step,
   watch it fail **naming that file and line**, remove it, watch it pass.
   Capture both outputs for the PR.

3. **`checks.session`**: add the recovery assertion decided above. Its comment
   says, in the file, what it asserts and what a failure means — that
   `omarchy-restart-shell` no longer recovers a shell whose config was written
   under it, **not** that the underlying defect is fixed or unfixed.
   → verify per §1 by asserting the IPC target *before* the restart instead of
   after; that must fail, because that is the broken state. Then restore the
   order and watch it pass.

4. **`tests/AGENTS.md`**: a row naming the hole. No layer here asserts that
   writing `shell.json` under a running shell is *survivable*, because it is
   not, and encoding that would be a check that inverts on an upstream fix. The
   row carries the repro so a human can run it: back the file up, `cat` it back
   over itself, wait four seconds, `omarchy-shell omarchy.clock status`.

5. **The upstream report text**, written into the repository rather than sent —
   a file under `docs/internals/`, so the evidence is versioned and a human can
   send it verbatim. It must contain:
   - the stack: `__dynamic_cast` inside `IpcHandler::updateRegistration()`,
     reached from `onPostReload()`; and that at `v0.3.1`
     (`src/io/ipchandler.cpp:304`) that function calls
     `EngineGeneration::findObjectGeneration(this)` on the not-yet-registered
     path, while the old generation is being torn down;
   - the repro, and that identical bytes are enough;
   - **that `v0.3.1` already contains `28771c7c74b4` and still does this**,
     with the ahead/behind counts, so the report is not answered with
     "upgrade";
   - that the segfault was seen once and does not reproduce on demand, while
     the bar disarming is reliable. Do not overstate it.
   → verify by `grep -c 28771c7c` on the file being 1 or more.

6. **Decide whether the duplicate registration is Quickshell's or ours** before
   the report claims either. One warning per IPC target on every reload —
   `Handler was registered but will not be used because another handler is
   registered for target omarchy.bar` — could be Quickshell failing to
   deregister, or the shell registering handlers it should not. Read
   `IpcHandlerRegistry::registerHandler` at `v0.3.1` and the shell's own
   handler declarations, and say which in the report. If it cannot be
   determined from reading, say *that*, rather than picking one.
   → verify by the report naming a side with a file and line, or explicitly
   declining to.

7. **Raise the nightly canary in the PR**, with the reasoning, for a human to
   accept or decline. Do not edit any workflow to add it.

## Tests

| Command | Expected |
|---|---|
| `grep -n "picked up live, with no IPC" modules/AGENTS.md` | nothing |
| the new static step, with a writer added under `modules/` | **red**, naming the file and line |
| the new static step, writer removed | green |
| `nix build .#checks.x86_64-linux.session` | green |
| `checks.session` with the assertion moved before the restart | **red** |
| `grep -c 28771c7c docs/internals/<report>.md` | ≥ 1 |
| `nix fmt -- --ci`, statix, deadnix | clean |

`checks.session` is a ~10–20 minute booted VM and must not be built locally
while an install job is in flight on p620 (§6). Check
`gh run list --limit 8 --json status` first.

## Rollback

Every change is additive: one paragraph replaced in `modules/AGENTS.md`, one
step added to an existing `build.yml` block, one assertion added to an existing
check, one row in `tests/AGENTS.md`, one new document under `docs/internals/`.
No option, no default, nothing in a system closure, nothing a user can observe.
Reverting the commit restores today's behaviour exactly — including, honestly,
today's misleading sentence at `modules/AGENTS.md:1382`.

Nothing here fixes the defect, and the PR must not imply it does. The
deliverable is that the hazard is written down where people look, our tree
cannot acquire a writer without CI saying so, the documented recovery is
guarded, and the upstream report is good enough to be acted on.
