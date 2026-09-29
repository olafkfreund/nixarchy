---
status: draft
issue: 953
intent: intent/2026-09-29-953-restart-shell-zero-shells.md
---

# Spec: Restarting the shell never leaves zero shells

Defaults taken for the intent's open questions, since approval came without
answers:

- **The bound** is 60 s for the old shell to exit.
- **The readiness poll** is lengthened to 60 s in the same patch.

Both can be overruled here.

## Design

### 1. Wait for the old shell to be gone, not for a client to give up

A carried patch in `pkgs/omarchy/default.nix`, beside #982's patch to the
same script, replaces upstream's line 66 with `substituteInPlace
--replace-fail`:

```sh
while timeout 5 quickshell kill -p "$CONFIG_DIR" --any-display >/dev/null 2>&1; do :; done
```

The replacement:

```sh
# nixarchy CARRIED patch (#953): wait until no instance of this config remains.
# `timeout 5` gave up on a slow teardown, the launch below lost the race with
# the dying shell ("already running"), and the desktop was left with none.
exit_wait=${OMARCHY_SHELL_EXIT_TIMEOUT:-60}
exit_deadline=$((SECONDS + exit_wait))
while [[ $(quickshell list -p "$CONFIG_DIR" --any-display 2>/dev/null) == *"Process ID:"* ]]; do
  if (( SECONDS >= exit_deadline )); then
    echo "Omarchy shell did not exit within ${exit_wait}s; not starting a second one." >&2
    exit 1
  fi
  timeout 5 quickshell kill -p "$CONFIG_DIR" --any-display >/dev/null 2>&1 || sleep 0.2
done
```

- **The loop asks the right question.** `quickshell list -p <config>` names
  the live instances of exactly this config (it hides dead ones by default).
  The loop runs until there are none, re-issuing the kill, which is harmless
  to repeat on an instance already exiting.
- **The fast path is unchanged.** One `list`, one kill that returns once the
  shell exits, one `list` that comes back empty.
- **No pipe into `grep -q`.** Capture, then pattern match: the #1058 trap.
  `list` prints several lines with `Process ID:` early, which is exactly the
  shape that fails under `pipefail`.
- **It is bounded.** A shell that will not exit within 60 s is reported, and
  **no second one is launched**, because a launch beside a live instance exits
  with "already running" by construction. The desktop keeps the shell it has.
  The message says what happened and the exit status is 1.
- **It fails open where upstream does.** If `quickshell list` itself errors,
  the capture is empty and the loop ends, which is today's behaviour, not a
  new hang.
- **`OMARCHY_SHELL_EXIT_TIMEOUT` follows the script's own convention.** It
  already takes `OMARCHY_SHELL_IPC_TIMEOUT`, and the check needs a short bound.
- **Never by process name.** Only `-p "$CONFIG_DIR"` instances are listed or
  killed, never `pkill` (§6).

### 2. Readiness waits as long as a plugin-heavy shell needs

Upstream's poll is `for (( attempt = 0; attempt < 20; attempt++ ))`, 20 ×
(0.5 s IPC + 0.1 s), about 12 s. A second `--replace-fail` makes it
deadline-based:

```sh
ready_deadline=$((SECONDS + ${OMARCHY_SHELL_READY_TIMEOUT:-60}))
while (( SECONDS < ready_deadline )); do
```

The loop body is unchanged, so the relock, the invitation re-run and
`exit 0` still happen only after a successful ping. A fresh plugin-heavy shell
(30–60 s to answer IPC) is then reported as the success it is.

### 3. The check: `checks.shell-restart-race`, a stubbed `runCommand`

`omarchy-restart-shell` is upstream's and unwrapped, so PATH stubs reach it,
the same basis as `tests/shell-restart-tree.nix` and
`tests/shell-ipc-resolve.nix`. The stubs model one quickshell config with a
state directory:

| Stub | Behaviour |
| --- | --- |
| `quickshell list` | prints an instance block with `Process ID:` while the old shell or the new one is alive |
| `quickshell kill` | marks the old shell "exiting", then blocks until its scripted death time (the slow teardown) |
| `hyprctl dispatch` (the launch) | if the old shell is still alive, the new one "exits: already running"; otherwise it becomes alive |
| `omarchy-shell shell ping` | succeeds only while the new shell is alive |
| others | `omarchy-hyprland-session-locked` returns 1 (not locked); `systemctl --user show-environment` prints `OMARCHY_PATH`; `jq` is real |

The cases:

1. **Slow teardown (7 s, longer than `timeout 5`).** The patched script exits
   0, the launch happened after the old shell died, and one shell is alive.
2. **The same case against upstream's unpatched script**, taken from the
   omarchy source as the negative control, the way `manifest-has-kind` does
   it. It must end with **zero shells** and exit 1. If upstream's script ever
   stops losing this race, the control fails and says the patch may be
   retirable.
3. **A wedged old shell** (never dies, `OMARCHY_SHELL_EXIT_TIMEOUT=6`). The
   script exits 1 with "did not exit within", and the launch stub was never
   called.
4. **Fast teardown (0.5 s).** Exit 0, one shell, and no slower than today.

About 25 s of wall time, no VM. It is a new `checks.*` entry, which
`build.yml`'s generated step runs on pull requests (§4, no workflow edit).

### 4. Documentation

- `pkgs/AGENTS.md` gains a section under "Patching upstream" covering the
  mechanism, the p620 evidence, and the retirement condition: drop the patch
  when upstream waits for exit itself, which the negative control reports by
  going red.
- `tests/AGENTS.md`: the check's reach and its limit. It cannot see a real
  quickshell's teardown time; p620 is the hand check.

Carried here; not reported upstream (owner's decision).

## Alternatives rejected

- **Drop `timeout 5` and rely on `quickshell kill` blocking.** If an
  instance's IPC is wedged, kill blocks forever, and a restart that hangs is
  worse than one that reports.
- **Detect "already running" after the launch and relaunch.** It reacts to
  the race instead of preventing it, needs journal scraping, and still leaves
  a zero-shell window.
- **`pgrep -f "$CONFIG_DIR"`.** It matches argv substrings of unrelated
  processes, such as an editor with the file open. `quickshell list -p` is
  the tool's own answer about its instances.
- **Fix only readiness.** It makes the report true but leaves the desktop
  empty.
- **A VM check that makes a real shell slow.** It would need a plugin that
  sleeps in teardown inside `checks.session`: a lot of cost for a property
  the stubs pin exactly. The real timing stays a hand check on p620.

## Risks

- **Restarting a wedged shell now fails loudly after 60 s** instead of racing.
  That is intended; the message names the cause.
- **`quickshell list` output format.** The patch keys on the `Process ID:`
  label. If quickshell renames it, the loop ends at once, which is today's
  behaviour, not a hang. The negative control does not catch that, so the
  check pins the label against the real `quickshell list --help`-era format
  by using a verbatim captured block in its stub.
- **Composition with #982.** Both are `--replace-fail` on different lines of
  one script. `shell-restart-tree` still greps the relaunch.

## Verification

- `checks.shell-restart-race`: green. Cases 1, 3 and 4 fail if the patch is
  removed, and case 2 is the in-check proof that upstream's script loses.
- Break proof: remove the patch. Case 1 must fail, reporting zero shells.
- `checks.shell-restart-tree`: still green.
- `nix build .#omarchy`: both `--replace-fail`s apply.
- `nix fmt -- --ci`, statix, deadnix.
- Hand check on p620 after merge: swap a plugin folder, run
  `omarchy restart shell` at once, and one shell must come back.
