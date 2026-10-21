---
status: approved
issue: 1416
intent: intent/2026-10-21-1416-verify-errexit.md
---

# Spec: nixarchy-verify runs every check on every machine, and leftover guests and prompting Bluetooth agents stop reading as failures

Pre-approved by the owner, 2026-10-21 ("I preapprove the spec and the plan
as well. Just finish this").

Covers #1416, #1417 and #1418, folded in by the intent's decision 1:
**one script, one harness.** The research was done by two read-only agents,
and their claims are cited by line.

## Design

### 1. Guard every assignment that can abort the run (#1416)

The script is packaged with `writeShellApplication`
(`flake.nix:780`, `errexit nounset pipefail`). The union of the static sweep
and a live probe of the packaged binary in an empty environment gives these
lines:

| line | probe | trigger |
|---|---|---|
| 237-240 | `screencast=$(timeout 5 busctl … ScreenCast …)` | no portal or bus (measured: exit 1) |
| 299, 350, 366 | `omarchy-shell lock/idle/listPlugins` | `omarchy-shell` absent, or a timeout |
| 383-386 | `notifier=$(… Notifications GetServerInformation)` | no notification daemon |
| 472 | `aim_owner=$(grep … \| grep … \| tr …)` | `state.json` without `owner` (#1416's report) |
| 509 | `adapters=$(timeout 5 bluetoothctl list \| wc -l)` | `bluetoothctl` times out |
| 547 | `radios=$(rfkill list …)` | no `/dev/rfkill` (not reproduced here) |
| 689 | `exec 8>"$dir/.lock"` | an unwritable `.lock`; use `{ exec 8<"$dir/.lock"; } 2>/dev/null \|\| continue` (a read-only fd is enough for flock, measured) |
| 746-749 | `scheme=$(… busctl … color-scheme)` | no portal |
| 757 | `cursor=$(gsettings … \| tr …)` | schema missing (measured: exit 1) |
| 999 | `menu_rows=$(python3 - … <<'PY')` | an extension file that is a JSON array |

Each gets the script's own `|| true` (or `|| rc=$?` where the status is
used), matching lines 671, 1307 and 1318. Every empty-value branch already
reports the problem, so `|| true` turns a silent abort into a reported `·`
or ✗. Every other assignment was checked and is already guarded, inside a
condition, or measured safe. No `nounset` hazard exists.

### 2. A leftover guest is `·`, not ✗ (#1417)

In the "MicroVM guests" loop (`verify.sh:654`), before the dangling-link ✗,
the script decides whether `/var/lib/microvms/<name>` is still a guest:

- **Declared** if `systemctl cat "install-microvm-$name.service"` succeeds
  (microvm.nix creates that unit per declared VM, `host/default.nix:111`),
  **or** `/nix/var/nix/gcroots/microvm/<name>` exists. The second covers
  imperative `microvm -c` guests (`pkgs/microvm-command.nix:126-130`).
- **Not `microvm@<name>`.** The host module's template unit
  (`host/default.nix:274`) makes every name resolve, so a leftover would
  read as declared.
- Not declared and dangling gives `hmm "<name>: no longer declared" "its
  state can be removed: /var/lib/microvms/<name>"`. A declared guest that is
  dangling stays ✗. Guests in the user's own state dir
  (`~/.local/state/nixarchy/microvm`) are unchanged.

### 3. A prompting agent explains a pairable adapter (#1418)

In the Bluetooth section (`verify.sh:497-521`), before "adapter is pairable
with no temporary agent" gives ✗: if
`pgrep -x blueman-applet || pgrep -x bluedevil || pgrep -x gnome-shell`
finds a known prompting agent, report `hmm "adapter is pairable: <name>
holds a prompting agent" "pairing asks first"`. BlueZ does not expose the
registered agents on D-Bus, so a process probe is the only read-only
signal (#1418's evidence: blueman's `KeyboardDisplay` agent prompts,
`BluezAgent.py:200-223`).

`modules/AGENTS.md:599-600` changes from "still needs confirmation on
hardware" to "confirmed in BlueZ's source (`agent.c:156-171`); on hardware it
is masked whenever the user runs their own agent".

### 4. Checks

- **`checks.verify-runs` (#1416).** It runs the **packaged** `verify`
  (`self.packages.${system}.verify`) in a `runCommand` with:
  - `HOME` and `XDG_RUNTIME_DIR` under `$TMPDIR`, and `WAYLAND_DISPLAY` set
    (without it `:72` stops on purpose);
  - `ai-mirror/state.json` set to `{"generation":3}`, with no `owner`;
  - stubs on PATH for the undeclared commands (`ai-mirror`,
    `omarchy-shell`, `hyprctl`, `nixarchy-version`);
  - `systemctl` as an exported bash function (functions beat the wrapper's
    PATH), which says Voice is active.

  It asserts that the output matches
  `[0-9]+ passed, [0-9]+ failed, [0-9]+ worth a look`, **not** the exit
  code: an abort and a run with ✗ rows both exit 1. The packaged binary is
  essential, because the bug exists only inside the wrapper.
- **`checks.verify-sections` (#1417 and #1418).** It follows the
  `tests/verify-boxes.nix` pattern: `sed` extracts the "microvm guests" and
  "bluetooth" sections, rewrites `/var/lib/microvms` and
  `/sys/class/bluetooth` to fixture dirs, and sources them with
  `timeout(){ shift; "$@"; }` and function stubs. It asserts the
  `ok`/`bad`/`hmm` counters for **both shapes** of each:
  - a declared dangling guest gives ✗; a leftover gives `·`;
  - a pairable adapter held by `blueman-applet` gives `·`; one with no agent
    gives ✗.

  One shape alone could not fail on the other (§1).

## Alternatives rejected

- **Turning `errexit` off in the script:** it would hide real bugs
  everywhere. The sweep guards only the probes that are meant to fail.
- **A production variable for the microvm root:** extraction needs no
  change to the shipped script (the house pattern, `verify-boxes.nix`).
- **`microvm@<name>` as the declared test:** the template resolves any name.
- **Reopening #1085:** its fix holds in the source (#1418).

## Risks

- The extraction depends on the `# ---- <name>` markers. A renamed section
  breaks the check loudly (zero lines extracted), never silently: the check
  refuses an empty extraction.
- The process list is a heuristic. A prompting agent it does not know
  still reads ✗, which is today's behaviour, with the same hint.

## Verification (§1)

| change | red | green |
|---|---|---|
| guards | `verify-runs` with only line 472 reverted: no summary line | the summary line is printed |
| #1417 | `verify-sections` with the declared test removed: the leftover gives ✗ | the leftover gives `·`; the declared guest stays ✗ |
| #1418 | `verify-sections` with the agent probe removed: the blueman case gives ✗ | the blueman case gives `·`; no agent stays ✗ |
| hardware | — | `nixarchy-verify` on p620 runs to its summary, with p1 shown `·` and Bluetooth `·` |
