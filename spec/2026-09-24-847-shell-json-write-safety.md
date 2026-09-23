---
status: draft
issue: 847
intent: intent/2026-09-24-847-shell-json-write-safety.md
---

# Spec: writing shell.json while the shell runs must not break the shell

## Design

Scope (a), as approved: document the hazard, make our own tree safe, report
upstream. Four changes, and only the first two are code we own.

### 1. `modules/AGENTS.md:1382` stops recommending the failing path

Today it reads:

> The shell watches the file and reloads it, so an atomic replace is picked up
> live, with no IPC.

That is written as reassurance and it is an instruction to do the thing in the
repro. It gets replaced by what actually happens, with the measurement from the
intent attached: a write — **even of identical bytes, and with no
`OMARCHY_PATH` mismatch** — triggers a reload that leaves `omarchy.clock` and
`omarchy.network` answering `Target not found`, floods the log with
`invalid context`, and needs `omarchy-restart-shell`.

It also states the supported path, which the tree already uses in two places
and documents in none: **change it through the running shell's own writer or
its IPC, never by editing the file.** `modules/home.nix:1749` gives the reason
independently — the shell rewrites that whole file from memory, so a second
writer loses updates — and `tests/demo/screencast/` restores a borrowed desktop
that way. The paragraph makes one rule out of what is currently two local
habits and one contradicting sentence.

### 2. A static check: nothing we ship writes `shell.json`

`modules/home.nix` asserts this in prose three times (`:315`, `:673`, `:1749`)
and nothing enforces it. A grep-shaped check over `modules/`, `pkgs/`,
`installer/` and `tests/` fails if anything acquires a writer.

It starts green, because nothing writes it today — verified. Per §1 a check
that has never been seen failing has not been seen working, so the plan carries
the deliberate break: add a writer, watch it name the file and the line, remove
it.

**It extends an existing check rather than adding a `checks.*` entry.** Adding
one means a workflow edit, which is a CI-gate change needing a human (§4, §11).
This assertion is seconds of grep and belongs in `build.yml`'s existing static
block beside the other repo-shape assertions, or in a check a PR-triggered
workflow already builds — the plan picks one and says which.

### 3. A VM check: a write under a running shell must not disarm the bar

The static check guards our tree. It says nothing about the defect, and §2 asks
for a probe at the highest layer that can see it. That layer exists and is
cheaper to reach than the intent first assumed: `checks.session` boots a real
desktop and asserts on `pgrep -a quickshell`, and `checks.plugin` already waits
for a `shell.json` written *by a live shell* (`tests/plugin.nix:656`).

So the assertion is added to **`checks.session`, which a PR-triggered workflow
already builds** — no new `checks.*` entry, no workflow edit, no gate change.
It writes the file back byte for byte under the running shell and then requires
that an IPC target still answers. On today's Quickshell that is expected to
**fail**, which is the point: it is a regression detector for a defect we have
not fixed, and the plan must decide whether it lands as a check that fails
(unacceptable — a red `main` teaches people to ignore red) or as a check that
asserts the *current* broken behaviour and inverts when upstream fixes it.

That decision is the one open thing in this spec and is called out under Risks.

### 4. The upstream report, filed by a human

The crash is not ours. `IpcHandler::updateRegistration()` at `v0.3.1`
(`src/io/ipchandler.cpp:304`) calls
`EngineGeneration::findObjectGeneration(this)` on the path taken when the
handler is not yet registered — and the reported stack is `__dynamic_cast`
inside exactly that frame, reached from `onPostReload()`, i.e. while the old
generation is being torn down. That is a plausible use-after-free and it is
what the report should say.

The report must also say the thing that took the most work to find, because it
is the part that makes the report useful rather than noise: **`v0.3.1` already
contains `28771c7c74b4` "ipc: ensure handler deregistration upon destruction"
(2026-08-02) — the tag is 11 commits ahead of it and 0 behind — and still does
this.** Without that sentence the obvious response is "fixed already, upgrade",
and it would be wrong.

Two separate things may need reporting and the plan distinguishes them:

- the **segfault**, which is Quickshell's;
- the **duplicate registration** — one `Handler was registered but will not be
  used because another handler is registered for target X` per IPC target on
  every reload — which may be Quickshell's or may be the shell registering
  handlers it should not. That is determined before filing, not guessed.

Per §11 nothing is filed in anyone else's repository by an agent. This work
produces the text and the evidence; a human sends it.
`pkgs/omarchy/skills/nixarchy/contributing.md` governs the routing.

## Alternatives rejected

**Patch the vendored shell, or Quickshell, in this tree.** A patch carried here
is re-applied at every source bump, forever, and this is a use-after-free in a
dependency's IPC layer — the least suitable kind of thing to carry locally. The
intent's constraint says not without a human deciding the exposure justifies it,
and the exposure is a broken bar recoverable by one documented command.

**Ship a `nixarchy shell-config` writer that stops, writes and relaunches.**
Rejected on the owner's scope decision, and independently on evidence: nothing
we ship writes `shell.json`, so the command would have no caller in this tree.
Building a supported path for a caller that does not exist is how an option
surface grows without anyone asking for it. If something later needs to write
that file, this is the right shape and the reasoning is here to be picked up.

**Suppress the reload.** Rejected in #919 for the same reason it would be
rejected here: the watcher fires only when plugin links genuinely changed
(measured — three activations with no plugin change produced no reload), and a
rebuild that changes plugin code should re-read it. Suppressing means not
reconciling during activation, which is the bug #710 fixed from the other side.

**Wait for an upstream release.** There is nothing to wait for. `v0.3.1` is the
latest tag and it is what reproduces.

## Risks

**A check that asserts a bug is a check that must be inverted later, by
someone who knows why.** The VM assertion in §3 encodes today's broken
behaviour. If upstream fixes it, that check goes red *because the bug was
fixed* — the exact shape `CLAUDE.md` §1 warns about, where a deliberate change
turns a check red and the first instinct is to satisfy it. Whatever the plan
chooses, the check's own comment has to say what it is asserting and what a
failure means, in the file, not in this document.

**The segfault is not reliably reproducible.** It did not fire in the
controlled run — the shell pid was unchanged and no signal appears in the
journal. Only variant 1 (the bar disarming) is reliable. So the VM check can
assert variant 1 and cannot assert variant 2, and the upstream report says the
crash was seen once with a stack, not that it reproduces on demand. Claiming
otherwise would be the "worse than no harness" failure.

**Nothing in CI builds `tests/demo/`,** where the working workaround lives. It
is `packages`, not `checks` (AGENTS.md §4). This work does not change that, and
the documentation change is what makes that workaround discoverable to somebody
who is not reading that directory.

**`checks.session` is a ~10-20 minute booted VM.** Adding an assertion to it
costs nothing extra in CI — it is already built on pull requests — but it does
mean a failure there now has one more possible cause, and the assertion must
name itself clearly enough that a reader does not go looking in the wrong
subsystem.

## Verification

| | |
|---|---|
| the static check, with a writer added to `modules/` | **red**, naming the file and line |
| the static check, writer removed | green |
| `checks.session` with the new assertion | behaves as the plan decides, and its comment says which |
| `modules/AGENTS.md` | no longer contains "picked up live, with no IPC" as advice |
| the controlled repro on razer | already done, in the intent: `Target not found` for two IPC targets, 61 `invalid context` errors, recovered by `omarchy-restart-shell`, `shell.json` byte-identical throughout |
| the upstream text | states that `v0.3.1` contains `28771c7c74b4` and still reproduces |

The last row is the one that decides whether this work was worth doing. The
code changes here are small and defensive; the finding is the deliverable.
