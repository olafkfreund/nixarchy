---
status: approved
issue: 1342
intent: intent/2026-10-18-1342-launch-browser-self-call.md
---

# Spec: upgrading to Omarchy 4.0.5 must not turn a link into an endless process chain

The intent's two questions, answered: **hold the seed** of
`hyprland-mimeapps.list` until the next login, and **carry a self-call guard**
in `omarchy-launch-browser`. Plus a release note.

## Design

### 1. The mimeapps list is seeded at login, not at a switch

The file is only safe once the session runs a launcher that knows to skip
`omarchy-browser.desktop`, and a session gets its launcher at login. So the
file is seeded at login.

- **A new script, `pkgs/seed-hyprland-mimeapps.sh`**, packaged with
  `writeShellApplication` (`coreutils` in `runtimeInputs`). It takes the
  source file and the destination. If the destination exists, as a file or as
  a symlink (`-e || -L`), it does nothing. Otherwise it copies the file with
  `--no-preserve=mode,ownership`, like `seed_file`.
- **`modules/home.nix`, the `nixarchySeed` activation** (`:1132`):
  `seed_dir` copies the whole of `config/`. Right after it, if the
  destination list did not exist **before** `seed_dir` ran, remove what
  `seed_dir` just wrote and print one line: *"nixarchy: hyprland-mimeapps.list
  is seeded at your next login (#1342)"*. A file the user already had is never
  touched, because the check is "absent before this run".
- **A session-start hook, `~/.config/omarchy/hooks/post-boot.d/seed-mimeapps`**
  (`xdg.configFile`, executable, like `default-plugins` at `home.nix:2161`),
  that runs the script with `${omarchyPath}/config/hyprland-mimeapps.list` and
  `${config.xdg.configHome}/hyprland-mimeapps.list`. Hyprland runs
  `post-boot.d` once, when the session starts, and a switch never does. Login
  is when the session picks up the current generation's tree, so the launcher
  and the file arrive together.

  **Not a systemd user unit** (revision, after the plan review). Home
  Manager's `systemd.user.startServices` defaults to `true`, and it starts a
  *new* unit wanted by an active target at the switch. In a logged-in 4.0.4
  session `graphical-session.target` is active, so a `WantedBy` unit would
  seed the file seconds after the activation held it back: #1342 again.

On a fresh install there is no session at the first switch, and the first
login seeds the file, before any link can be opened from that session. On a
machine that already has the file (p620, and any machine on edge), nothing
changes.

**Not:** seeding at activation when no graphical session is active. Whether
"a session is active" is true from inside home-manager's activation depends on
how the switch was started (a system switch runs it from a system unit). One
rule, "at login", has no such case.

### 2. The launcher refuses to launch itself

A CARRIED patch, `--replace-fail`, in `pkgs/omarchy/default.nix`, on
`omarchy-launch-browser`. Insert directly after the `browser_exec=$(…)` line:

```sh
if [[ ${browser_exec##*/} == omarchy-launch-browser ]]; then
  omarchy-notification-send -u critical "No browser to open this in" "The default browser entry runs omarchy-launch-browser itself (#1342). Choose a browser with: omarchy default browser"
  exit 1
fi
```

It protects launchers built from now on. It cannot reach a 4.0.4 launcher
already running, which is what §1 is for. In 4.0.5 the branch is unreachable
by design (`omarchy-cmd-default-browser` skips the entry), so it costs nothing
on the normal path and stops the next mismatch of this shape at one process.

`data/bin-ledger.nix`: `omarchy-launch-browser` is already a `patch` row (the
applications-path fix at `default.nix:616`); its text gains the guard. The
replacement text lives in `pkgs/omarchy/1342-launch-browser-self-call.sh`,
for the `installPhase`-string reason in `pkgs/AGENTS.md`. A `pkgs/AGENTS.md`
anchor section records it and when to drop it: when no supported upgrade path
crosses from a launcher without `omarchy-cmd-default-browser`.

### 3. The release note

The release that first ships 4.0.5 says: "Log out and back in after this
upgrade. Until you do, links open through the session you logged in with."
Where it lives: the release notes source the release workflow reads
(found in the plan), and the Discussions post (§14's rule for changed
defaults).

## Coexistence (§14)

- **A user who manages `~/.config/hyprland-mimeapps.list` with Home Manager**
  has a symlink there. The script treats a symlink as present (`-L`), so it
  never replaces it. That is the `-L` before content rule from §1. Fixture:
  the script's check has a symlink case.
- **A user's own `mimeapps.list`** (Home Manager's `xdg.mimeApps`, as on
  p620) is a different file and untouched.
- **Mode A:** without `programs.nixarchy`, the seed and the hook are not
  there, as today.

## Alternatives rejected

- **Release note only.** It reaches only those who read it, and the failure
  takes a host down.
- **Seed only when no session runs** (detect a session from activation).
  Unreliable from a system-started switch, see §1.
- **Patch the old launcher.** It is already running, from a store path, and
  cannot be changed.
- **Make `omarchy-browser.desktop` safe instead** (an `Exec=` that is not the
  launcher). It is upstream's design; 4.0.5 relies on routing links through
  the launcher for focus handoff. Ours to keep, not to change.
- **A process limit (`ulimit -u`) on the launcher.** It would still fork up to
  the limit on every link, and it is a value nobody can choose correctly.

## Risks

- **A link opened before the first login of a fresh install** cannot happen
  from that session; from a TTY, `xdg-open` reads `mimeapps.list` as before.
- **Between a switch and the next login**, links use upstream 4.0.4 behaviour,
  the `xdg-settings` default, which is the browser from `mimeapps.list`. That
  is the behaviour the session already had.
- **The hook runs at every login.** It is one `test -e` when the file exists.
- **The guard's notification** names a command, `omarchy default browser`;
  the plan checks it exists in 4.0.5.

## Verification

- **`checks.seed-hyprland-mimeapps`** (runCommand) drives the script:
  absent → seeded; a file present → untouched; a dangling symlink present →
  untouched **and the script exits 0**. Control: the script with the `-L` test
  removed must exit non-zero on the dangling link. (GNU `cp` refuses to write
  through a dangling symlink, so `-L` buys "the seed does not fail at every
  login", not "the link is not replaced"; the first version of this spec said
  the latter.)
- **The activation hold**, as its own check: the hold block is extracted from
  `home.activation.nixarchySeed.data` and run in a sandbox with `run()`
  defined, as `tests/home-activation-writes.nix` does. Absent before → removed;
  a file or a symlink already present → kept; a dry run → nothing written.
  Control: the block without its `rm` must leave the file.
- **`checks.launch-browser-self-call`** (runCommand) runs the built
  `omarchy-launch-browser` against a fixture whose default browser entry runs
  the launcher, with every launch counted through a wrapper on `PATH`. The
  patched launcher exits 1 after one invocation. Control: upstream's
  unpatched 4.0.4 launcher, which must reach the wrapper's cap (20) and be
  stopped by it, or the check cannot see the recursion.
- **`checks.session`**: the file is absent once Home Manager has run and
  before login, and present after login (the hook ran). The pair is what
  makes it fail on a full revert, where the boot-time activation would seed
  it.
- Each new check fails with its fix reverted (§1), and the output goes in the
  PR.
