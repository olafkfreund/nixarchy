---
status: approved
issue: 953
author: olafkfreund
---

# Intent: Restarting the shell never leaves zero shells

## Problem

`omarchy restart shell` (`bin/omarchy-restart-shell`) can leave the desktop
with **no shell and no bar** until somebody notices and restarts again. On
p620 on 2026-09-29 that lasted about 17 minutes. It happened four times on
2026-09-24.

The script stops the running shell with:

```sh
while timeout 5 quickshell kill -p "$CONFIG_DIR" --any-display >/dev/null 2>&1; do :; done
```

Its comment promises that each kill "only returns once it has fully exited, so
the no-duplicate launch below can't race a dying shell". `timeout 5` breaks
that promise whenever teardown takes longer than 5 s.

- A plugin-heavy shell measured about 14 s to tear down.
- One that is mid-way through a plugin hot-reload stops answering for 8–30 s.
  Swapping a plugin folder triggers that reload, and a Home Manager switch
  that installs or updates a plugin does exactly that.

The chain is then deterministic:

1. `timeout` kills the kill client, and the loop ends with the old shell still
   alive.
2. The relaunch fires. The new instance sees the old one, prints "An instance
   of this configuration is already running.", and exits.
3. The old one finishes exiting. Zero shells remain.
4. The readiness poll gives up after about 12 s with "did not become ready"
   and exits 1. Nothing retries, and a caller in a loop never notices.

**Why it is ours now.** #953 was closed on 2026-09-24 as upstream's: the
script is Omarchy's, and an Arch machine with 20 plugins races the same way.
Two things have changed since:

- **The owner's decision of 2026-09-28:** nothing is posted upstream, and
  upstream bugs are carried here as patches, each with a condition for
  dropping it.
- **nixarchy makes the window common.** Plugins arrive by Home Manager switch,
  which swaps plugin folders and so starts a hot-reload. "Then restart the
  shell" is the natural next step. nixarchy's own docs and plugins say to
  restart after a switch, and #982 already patches this very script so a
  restart picks up the new tree.

Carried here; not reported upstream (owner's decision).

## Proposed outcome

After `omarchy restart shell`, exactly one shell is running. It may take a
plugin-heavy machine a while, but it never ends with zero.

- If the old shell takes longer than the script is willing to wait, the
  script says so and still does not launch into a race it will lose.
- The script exits 0 only when a shell answers. It never exits 0, and never
  exits at all without saying so, while zero shells are running.
- A fast restart on a light machine stays as fast as it is today.

## Affected users and systems

- Every nixarchy user who restarts the shell: from the menu, from
  `omarchy restart shell`, from nixarchy's own post-switch guidance, and from
  a plugin developer's loop.
- `pkgs/omarchy/default.nix`, which already patches this script (#982, the
  relaunch tree).
- `tests/shell-restart-tree.nix` (asserts on the patched script), and whatever
  check can make teardown slow on purpose.
- `pkgs/AGENTS.md` (the carried patch and when to drop it).

## Constraints

- **A carried patch** with `--replace-fail`, so an upstream change to line 66
  breaks the build instead of silently un-fixing. It records its retirement
  condition: upstream stops using `timeout 5`, or waits for exit itself.
- **It must compose with #982's relaunch patch** in the same script.
- **The locked-session path must keep working.** The script refuses while a
  locker is active, and it re-locks after a restart from a stranded lock.
- **Never `pkill` by name.** Other quickshell instances (other configs) are
  not ours to touch (§6's rule, applied to the script itself).
- It is bounded. A wedged old shell must not hang the script forever; after
  the bound, the script says what it found and exits non-zero.

## Open questions

1. **The bound.** Measured teardown is up to about 14 s, and a hot-reload
   stall up to about 30 s. Default proposal: 60 s, which is generous, and
   reports clearly when it is exceeded.
2. **Readiness.** The post-launch poll is about 12 s, while a fresh
   plugin-heavy shell can take 30–60 s to answer IPC. Lengthen it in the same
   patch, or leave it for a separate issue? Default proposal: lengthen it
   here. A restart that succeeds but reports failure is this issue's second
   symptom.
