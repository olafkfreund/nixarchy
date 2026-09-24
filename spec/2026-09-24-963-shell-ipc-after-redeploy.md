---
status: draft
issue: 963
intent: intent/2026-09-24-963-shell-ipc-after-redeploy.md
---

# Spec: find the shell by instance, not by the path we happen to hold

## The intent's lean was wrong, and it was measured rather than argued

The intent leaned to **a stable path in front of `OMARCHY_PATH`** -- a symlink
the module repoints, so upstream's match-on-path assumption becomes true here
and nothing needs patching. It was the largest of the three shapes and it does
not work.

Tested against the live shell on p620, mutating nothing (the target named does
not exist, so the only signal is whether the instance was *found*):

```
$ qs ipc -n -p "$OMARCHY_PATH/shell" call nosuchtarget nosuchfn
Target not found.                              <- instance FOUND

$ qs ipc -n -p "$PWD/stable-omarchy/shell" call nosuchtarget nosuchfn
No running instances for ".../stable-omarchy/shell/shell.qml"   <- NOT found
```

Quickshell matches the config path **as given**, not canonicalised. A symlink in
front of the store path is a different string, so the running shell -- which
registered under the store path -- is missed exactly as before.

**The same test handed over the answer.** `qs ipc` takes `-i/--id` and `--pid`,
and `qs list --all` prints both:

```
Instance wgslpguvlt:
  Process ID: 1016672
  Config path: /nix/store/rp5i87d4pwxhiwi1pgwll2qjxlb815y8-nixarchy-omarchy-tree/shell/shell.qml
```

and `qs ipc -i wgslpguvlt call nosuchtarget nosuchfn` answers `Target not
found.` -- the instance reached.

## Design

**Resolve the instance, then call it.** `omarchy-shell` stops passing
`-p "$OMARCHY_PATH/shell"` and instead:

1. Ask `qs list --all` for running instances.
2. Keep those whose **Config path** ends in `/shell/shell.qml` **and** whose
   directory looks like a nixarchy omarchy tree. The caller's own
   `$OMARCHY_PATH` is the first candidate, so the ordinary case -- caller and
   shell agree -- is matched first and nothing changes for it.
3. Exactly one match: call it with `-i <instance>`.
4. None: fail with a message that says the shell is not running, rather than
   timing out silently.
5. More than one: name them and refuse. Two omarchy shells is not a state to
   guess in.

**Path-first, not id-first**, deliberately: on a machine that has not rebuilt
since login the existing behaviour is exactly right, and a change that reroutes
the common case to a new mechanism is a change that can break it. The instance
lookup is the fallback, taken only when the path match finds nothing.

### Where it lives

`omarchy-shell` is upstream's and nixarchy does not patch it today. This adds
the **first** patch to it, which section 11 says is re-applied at every source
bump -- so the patch must be small, and `pkgs/AGENTS.md`'s bump procedure has to
name it.

That cost is accepted rather than avoided because the alternative -- teaching
each caller to work around the false assumption -- is what produced the state
this issue describes: `omarchy-restart-shell:8` already reads the session's
`OMARCHY_PATH` for the same mismatch, in one script, and nobody meeting the
second one found the first.

**Not sent upstream**, because there is nothing to send: on Arch
`OMARCHY_PATH` is `/usr/share/omarchy` and stable, so the code is correct there
and a patch would be a fix for a bug they do not have.

## Alternatives rejected

| | why not |
|---|---|
| Stable symlink in front of `OMARCHY_PATH` | **Measured not to work**, above. Quickshell matches the path as given. |
| Read the session's `OMARCHY_PATH`, as `omarchy-restart-shell` does | Fixes the redeploy case and not the general one: a script run from a systemd unit or before login has no session to ask, the same boundary #950 dealt with. It also leaves the match-on-path assumption in place for the next caller. |
| `--any-display` | Addresses a different filter (display), not the config-path mismatch. |
| Rebuild-time restart of the shell | Kills a running desktop to fix a keybind. Upstream's own `omarchy-restart-shell` exists precisely so the user chooses when. |

## Risks

- **The first patch to an upstream script.** Every source bump re-applies it, and
  a bump that changes those lines is a conflict somebody has to read. The bump
  procedure must name it, or it becomes the silent kind.
- **`qs list --all` output is a format, not an API.** Parsing `Instance <id>:`
  and `Config path:` is scraping, and a Quickshell bump can reword it. The parse
  must **refuse** on an implausible result rather than fall through to "no
  instance", which would be the silent failure this issue is about, restored by
  the fix for it.
- **Two omarchy shells** is rare and real -- a second display, a stale process.
  Refusing is right; silently picking one is how a keybind starts doing
  something on the wrong screen.
- **The ordinary path is untouched**, which is the main mitigation: a machine
  that has not rebuilt never reaches the new code.

## Verification

- A **`runCommand`** driving the patched `omarchy-shell` against a **stub `qs`**
  on PATH -- the script is upstream's and unwrapped, so unlike
  `writeShellApplication` a PATH stub does work here, which #967 established the
  hard way. Cases: caller path matches (calls through, unchanged); caller path
  stale and one instance (falls back and calls it); no instance (fails, says
  so); two instances (refuses, names them); `qs list` output unparseable
  (refuses rather than reporting no instance).
- **Section 1:** each seen failing with the fallback removed, and that output in
  the PR. The trap: asserting the script *printed* something. Assert which
  instance it called, which the stub records.
- **What no check reaches:** a real redeploy under a live session. That is the
  whole bug, it needs a logged-in desktop, and `checks.session` boots one but
  does not rebuild under it. Goes in `tests/AGENTS.md`, and is checked by hand
  on p620 -- which has a live shell and rebuilds often.

## Open question

Should the patch also make `omarchy-restart-shell` use the same resolution,
retiring its `show-environment` workaround? It would leave one mechanism instead
of two, which is the argument. It also widens a first patch into a second, on a
script #953 is separately about. I have specified **no**, and would rather it be
a follow-up than scope creep here.
