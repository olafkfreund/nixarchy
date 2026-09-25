---
status: approved
issue: 982
intent: intent/2026-09-25-982-shell-tree-after-rebuild.md
---

# Spec: relaunch on the generation's tree, read from /run/current-system

## The intent's open question 2, answered -- and it kills the intent's lean

The intent asked whether activation updates the user manager's `OMARCHY_PATH`
on a switch, or only at login, and said to establish it before the spec.

**Only at login.** Measured on p620:

| source | value |
|---|---|
| `/run/current-system/etc/set-environment` | `s3jlsx59...-nixarchy-omarchy-tree` |
| `systemctl --user show-environment` | `rp5i87d4...-nixarchy-omarchy-tree` |

`environment.sessionVariables` lands in `/etc/set-environment`, which PAM sources
**at login**. Nothing in `modules/` calls `systemctl --user set-environment` or
`import-environment`, so a switch never refreshes a running user manager.

So `omarchy-restart-shell`'s line 8 -- the read the file already does, with a
comment explaining it -- returns the **login-time** value. It is the same stale
path Hyprland holds, arrived at by a different route.

**That kills the intent's preferred fix.** "Pass the session manager's value
explicitly into `exec_cmd`" would have passed the stale path through to the
launch and changed nothing observable. The stated lean was wrong, and it was
wrong for a reason no amount of reading the script would have shown -- only
comparing the two values on a machine that had rebuilt since login.

## Design

**Read the tree from `/run/current-system`, and pass it explicitly.**

```sh
# The generation's tree, not the session's. sessionVariables reach a login
# shell through /etc/set-environment and never reach a RUNNING user manager,
# so `systemctl --user show-environment` answers with the login-time value --
# the same stale path Hyprland holds. Measured: the two differ on any machine
# that has rebuilt since login, which is the whole bug.
current_tree=$(sed -n 's/^export OMARCHY_PATH="\(.*\)"$/\1/p' \
  /run/current-system/etc/set-environment | tail -n 1)
```

used for **both** halves:

- `CONFIG_DIR="$current_tree/shell"` for the kill, when it resolves;
- `exec_cmd("env OMARCHY_PATH=<current_tree> omarchy-launch-shell")` for the
  relaunch, so Hyprland's own environment is overridden for that child only.

**The kill must keep working against the OLD tree.** The running shell
registered under the login-time path, so killing by the *new* path finds
nothing and leaves two shells. So the kill keeps using the session value
(line 8, unchanged) and only the **launch** takes the current one. That is the
one asymmetry in this change and it is the point of it.

**Fall back to today's behaviour** when `/run/current-system/etc/set-environment`
has no `OMARCHY_PATH` -- a machine where the module is off, or a future where
the variable moves. A restart that works as it does now beats one that fails.

## Alternatives rejected

| | why not |
|---|---|
| Pass the session manager's value (the intent's lean) | **Measured stale.** It is the login-time value; passing it changes nothing. |
| `systemctl --user set-environment` then restart | The issue already tried it: it updates the user manager, not a running Hyprland, so `exec_cmd` children are unaffected. |
| Resolve it inside `omarchy-launch-shell` | Fixes every caller including keybinds, and is a bigger change to another file that may also be upstream's. Worth doing if a second caller appears; not for this. |
| Restart the shell from activation | Kills the desktop under someone mid-task. Upstream's restart command exists so the user chooses when. |
| Tell the user to re-login | The outcome the intent allows as a fallback, and strictly worse than fixing it when the value is one `sed` away. |

## Risks

- **First patch to this script**, so `--replace-fail` per `pkgs/AGENTS.md`: a
  bump that rewords the `exec_cmd` line fails the build rather than silently
  restoring the old behaviour. Same mechanism as #963's.
- **Parsing `/etc/set-environment`** is reading a generated file's format. It is
  stable (NixOS generates `export NAME="value"` lines) but it is a format, not
  an API -- so the fallback above is load-bearing, not politeness.
- **`env` in the exec string** must be the coreutils one; Hyprland's `exec_cmd`
  runs through a shell with the session PATH, which has it.
- **Two shells** if the kill and the launch disagree about which tree. Mitigated
  by leaving the kill on the session value.

## Verification

- **A `runCommand`** driving the patched script against a fake
  `/run/current-system/etc/set-environment` and a stub `hyprctl` that records
  its argv. A PATH stub works here: `omarchy-restart-shell` is upstream's and
  unwrapped, unlike `nixarchy-apply` -- the distinction `tests/AGENTS.md`
  already records after four failures.
  Cases: the exec string carries the **current** tree, not the session's; with
  no `OMARCHY_PATH` in the generated file, the exec string is unchanged from
  today's.
- **Section 1:** both seen failing with the `env` prefix removed.
- **What no check reaches:** that the relaunched shell actually reads the new
  tree. That needs a real session that has rebuilt since login. p620 is one
  today, so it is a hand check and goes in `tests/AGENTS.md` as a documented
  hole.

## Open question

Should the kill also move to the current tree once the launch is fixed? After
one restart the running shell *is* on the current tree, so the session value
becomes wrong for the next kill -- but only until the next login, and only on a
machine that rebuilt twice without logging out. I have specified leaving the
kill alone; say if that residue is worth closing now rather than noting.
