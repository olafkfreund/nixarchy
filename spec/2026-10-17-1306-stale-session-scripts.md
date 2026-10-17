---
status: draft
issue: 1306
intent: intent/2026-10-17-1306-stale-session-scripts.md
---

# Spec: After a switch, the menu and the scripts it runs come from one generation

## What the research found

The intent's premise is half right, and the half that is wrong changes the fix.

**The shell does not read `/etc/nixarchy/omarchy-menu.jsonc`.** `Menu.qml:13`
takes `omarchyPath` from `Quickshell.env("OMARCHY_PATH")` once, at startup, and
`Menu.qml:50` reads `omarchyPath + "/default/omarchy/omarchy-menu.jsonc"`. The
`/etc` copy is exported only for CI and the doctor (`modules/apps.nix:1402-1406`:
*"The tree below is what the shell reads"*). The `FileView` at `Menu.qml:922-938`
has `watchChanges: true`, but it watches a store file that never changes, and
`refresh()` (`:38-42`) re-reads the same pinned file. **So a running shell's rows
and its scripts already come from one tree: the shell's own.**

**That is a deliberate design, #1255.** `modules/home.nix:2299-2307` says *"A
switch must preserve the live generation until the user restarts it"*, and runs
`nixarchy-shell-session sync --if-running` on every activation. The helper
(`pkgs/omarchy/nix-bin/nixarchy-shell-session`) finds the running Quickshell, and
publishes **its** tree to Hyprland (`hl.env` plus `reload config-only`) and to
the user manager (`dbus-update-activation-environment`). An explicit
`omarchy-restart-shell` relaunches on the current system's tree (#982,
`pkgs/omarchy/default.nix:2014-2025`, reading `/run/current-system/etc/set-environment`),
and the new shell's `omarchy-launch-shell` syncs everything to that
(`default.nix:2002-2007`).

Measured on p620 today:

| process | started | `OMARCHY_PATH` |
|---|---|---|
| Hyprland | 2026-10-14 07:52 | (login) `zlhw6r3r…` |
| foot terminals | 2026-10-14 | `zlhw6r3r…` |
| Quickshell | 2026-10-15 09:51 | `p0frl0fn…` (restarted once since login) |
| `systemctl --user show-environment` | | `p0frl0fn…` (synced to the shell, as designed) |
| `/run/current-system/etc/set-environment` | | `rla9km5s…` |

The shell's tree `p0frl0fn…` has neither the `nixarchy-channel --current` rows
nor the script that answers them, so its menu and scripts agree. The issue's
evidence came from a **terminal** opened on 2026-10-14: its environment is fixed
at its own start, and no mechanism can change a running process's environment.

**The real defects are two, and neither is in the menu's rows.**

1. **Nothing says the desktop is running an older generation than the system.**
   After a switch, `omarchy-channel-current` (and everything else under the
   tree) keeps its old behaviour until the shell restarts, and the user has no
   way to know. The menu review behind #1301–#1305 audited the stale tree for
   exactly this reason.
2. **A new script can call an old sibling.** The session PATH puts the pinned
   tree's `bin` *ahead of* `/run/current-system/sw/bin`, twice: upstream's
   `default/hypr/envs.lua:30-36` and nixarchy's `omarchy-launch-shell` patch
   (`default.nix:2002-2004`). So a current-generation script reached by absolute
   path resolves its siblings in the old tree. Reproduced here:
   `/nix/store/rla9km5s…/bin/omarchy-channel-current` printed `nixarchy-channel`'s
   old usage text, because it calls `nixarchy-channel --current` by name and
   PATH found `zlhw6r3r…/bin` first. This is the mixed-generation case the intent
   describes, and it ends the moment the shell is restarted, because the restart
   republishes PATH with the new tree first.

Both end at a shell restart, not a re-login: #982 and #1255 already move the
shell, Hyprland's environment and the user manager to the current tree. Only
windows that were already open keep their own environment.

## Design

**Keep the pinned tree. When a switch leaves the running shell on a different
tree from the one being activated, show one notification that offers to restart
the shell.** The decision lives in `nixarchy-shell-session sync`, where the
cheap check can reach it.

1. **`nixarchy-shell-session sync` gains `--current TREE`.** After it has
   resolved the live shell and published its environment (unchanged), if
   `--current` was given and differs from `selected_tree`, it sends:

   ```
   omarchy-notification-send -u normal -r <id> -p \
     "Restart the shell to finish this update" \
     "The menu and its commands are from the generation you logged in with. Windows already open keep the old commands until reopened." \
     --exec "$current/bin/omarchy-restart-shell"
   ```

   - `-r`/`-p`: the id is kept in `${XDG_RUNTIME_DIR}/nixarchy/restart-notice-id`,
     so a second switch before a restart **replaces** the notice instead of
     stacking one per switch (the edge-channel constraint). `$XDG_RUNTIME_DIR` is
     per-login, so a re-login starts clean.
   - `--exec` uses the absolute path in the **new** tree. The shell runs the
     click in its own, old, environment, and `omarchy-restart-shell` from the
     new tree is what reads `set-environment` and relaunches on it (#982).
   - Equal trees, no shell (`--if-running`), or a failed notification: no notice
     and no failure. The notice is advice; the sync stays the contract.
   - Called by name, like `qs`, `hyprctl` and `dbus-update-activation-environment`
     already are, so the test stubs it the same way.
2. **`modules/home.nix:2304-2305`**: the activation passes
   `--current ${omarchyPath}` and adds `${cfg.package}/bin` to the PATH it
   already builds, which is where `omarchy-notification-send` lives.
   `omarchy-launch-shell`'s own `sync --pid` call passes nothing, so a fresh
   launch never notifies.
3. **`docs/manual/plugins.md:278-280`**: "log out and back in once" becomes
   "restart the shell when the notice offers it", and says why once.

### The intent's open questions, answered

1. **Fix, or tell? Recommend (b), tell, with the restart one click away.**
   (a) would reverse #1255's model rather than finish it. See the rejected
   alternatives below.
2. **The running shell's QML.** It needs a restart to pick up new plugin code,
   and the menu does **not** re-read its rows from a new generation (above).
   `omarchy-restart-shell` is the existing, tested way to do both (#953, #982,
   #1255), so the notice offers it rather than a re-login.
3. **Does anything rely on `OMARCHY_PATH` staying the same? Yes, three things,**
   all of which (a) would break:
   - `nixarchy-shell-session` **identifies** the shell by its tree:
     `config_path` minus `/shell/shell.qml`, checked for
     `bin/omarchy-system-sleep-lock`. A stable path makes every generation look
     like the same shell.
   - `omarchy-restart-shell` **kills** by the session's path and launches by the
     current one (#982: *"killing by the new one finds nothing and leaves two
     shells"*). The sleep monitor and lock helper are pinned the same way
     (`sleep-lock-generation`, #1255).
   - Store **liveness**. The old tree survives garbage collection because the
     running processes reference it, and Nix's collector treats paths found in
     `/proc/<pid>/environ` as runtime roots. On a stable path, a shell that has
     not yet lazily loaded a panel would load it from a newer generation than the
     QML it already holds.

   `modules/home.nix:514-516` is not affected: it is a build-time
   `omarchy-plugin-validate` run inside a derivation. The `systemd.user.services`
   at `home.nix:1322-1365` pin `OMARCHY_PATH` per generation, and Home Manager
   restarts them when they change, so they are consistent already.

## Alternatives rejected

- **(a) A stable `OMARCHY_PATH`** (`/run/current-system/sw/share/omarchy`, or
  an `/etc/nixarchy/tree` link). The first is the wrong tree: `pathsToLink`
  (`nixos.nix:1381`) exposes `cfg.package`, not `cfg.tree`, so it lacks the
  generated menu file (#210). The second is the right tree, but it is the three
  breakages above. It would also change the running shell's QML under it with
  no user choice, which the intent's constraint forbids. Upstream's
  `/usr/share/omarchy` is stable because pacman replaces files in place. Nixarchy
  cannot do that, and #982 and #1255 were written to fit a path that moves.
- **(c) Both.** Inherits all of (a).
- **Drop the tree's `bin` from the session PATH**, so `/run/current-system/sw/bin`
  wins. That would fix defect 2 alone. But it splits the menu (old rows) from
  its scripts (new), which is the bug the intent describes. It would also mean
  patching upstream's `envs.lua` and reverting #1255's PATH normalisation.
- **A notice from Home Manager activation itself**, with the comparison written
  inline in `home.nix`. Same behaviour, but only an eval-level grep or a VM can
  see it. Inside the helper, the existing `runCommand` harness can vary it.
- **A persistent bar indicator** (extending `switch-indicator.qml`). It does
  not stack, but it is new QML. Only a shell that is *already* current would
  have the indicator, so the first restart after this lands would still be
  silent. It can follow if the notification proves too easy to dismiss.
- **Restart the shell automatically after a switch.** Pulls the session out
  from under the user (intent constraint), and would drop open panels and a
  lock in progress.

## Risks

- **The notification may not reach the shell from activation.** The
  Home Manager unit (`home-manager-<user>.service`) sets no
  `DBUS_SESSION_BUS_ADDRESS`. `omarchy-notification-send` uses
  `busctl --user`, and sd-bus falls back to `$XDG_RUNTIME_DIR/bus`. The existing
  `sync` already runs `dbus-update-activation-environment` from the same
  activation, and p620's journal for today's 14:42 activation has no
  *"could not synchronize"* line. That is indirect evidence. **Not verified for
  the notification itself**: the plan's manual step measures it. If it fails,
  the switch still succeeds and the notice is simply absent, which is today's
  behaviour.
- **`checks.bin-ledger`** records changes to `nix-bin` commands. The new flag
  may need a ledger row.
- **A rollback to the live generation** gives equal trees, so no new notice is
  sent. A notice left from an earlier switch stays until it is dismissed, and
  clicking it then restarts onto the same tree, which is harmless.
- **Hosts:** every Omarchy-session machine. No change to boot, the
  greeter, or anything that runs without a graphical session (`--if-running`
  and the activation's `is-active graphical-session.target` gate are kept).

## Coexistence (§14)

No NixOS or Home Manager option gains or changes a value, and nothing enters
`environment.systemPackages`, `hardware.graphics` or any other merged
environment. The change is the helper's behaviour plus one activation line
inside `config = lib.mkIf cfg.enable` (`home.nix:829`), so Mode A is untouched.
A user with their own notification daemon receives a standard
`org.freedesktop.Notifications` call; only the click action is Omarchy-specific
(`omarchy-exec-argv` hint), and without it the text alone is still correct.
No fixture is added to `tests/coexistence/fixtures.nix`: no option collides, and
§14 forbids a fixture that cannot fail.

## Verification

**The variable (§3) is the generation of the running shell versus the
generation being activated.** Every existing check logs in after the switch, so
those two are always equal and the notice can never fire. The cheapest layer
that can make them differ is **`checks.shell-session`**, a `runCommand`
(`tests/shell-session.nix`, `tests/shell-session.sh`). It already runs a real
process under one tree and resolves it, with `qs`, `hyprctl` and
`dbus-update-activation-environment` stubbed on PATH. It costs seconds.

New cases in `tests/shell-session.sh`, with a stub
`omarchy-notification-send` that logs its argv to its own file (so the
existing `length == 3` assertion on `$TEST_CALLS` is unaffected) and prints an
id for `-p`:

1. Live shell on `$new`, `sync --current "$old"`: exactly one notice, with
   `--exec "$old/bin/omarchy-restart-shell"`.
2. Live shell on `$new`, `sync --current "$new"`: no notice.
3. `sync` with no `--current` (the launcher's call): no notice.
4. Two differing syncs in a row: the second passes `-r` with the id the first
   printed.
5. The notifier stub exits 1: `sync` still exits 0, and Hyprland and the user
   manager were still published.

**Proving it fails (§1).** In a scratch worktree (`git worktree add --detach`,
§5), apply each break, confirm it landed with `git diff`, then build
`checks.x86_64-linux.shell-session` and capture the output:

- delete the comparison, so the helper never notifies: case 1 fails;
- invert it to `==`: cases 1 and 2 fail;
- drop the `-r` id: case 4 fails;
- let the notifier's failure propagate: case 5 fails.

The four failing outputs go in the PR.

**The activation wiring.** One assertion in `tests/options.nix`, in the
enabled state: `home.activation.nixarchySyncSession.data` contains
`--current ${tree}`. Proven by deleting the flag and watching `options` fail.
`options` is the expensive evaluation check (about 8 minutes, 11.5 GB), so it
is left to CI under §6's tiers, unless a local run is clear to go.

**What no automatic layer reaches, said plainly (§3).** That the notification
crosses from Home Manager activation to the running shell over the session bus,
and that clicking it brings the menu, a new terminal and
`systemctl --user show-environment` onto the new tree. `checks.session` could
reach this with a switch inside a booted VM, but it costs a VM run. That is out
of proportion for one notice. So this stays a manual step on p620, recorded in
the PR:

1. switch to a generation whose tree differs;
2. see the notice;
3. switch again, and see it replaced rather than doubled;
4. click it, then compare the new Quickshell's `/proc/<pid>/environ`
   `OMARCHY_PATH` with `/run/current-system/etc/set-environment`.

A row in `tests/AGENTS.md` names the hole.
