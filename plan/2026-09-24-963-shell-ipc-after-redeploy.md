---
status: approved
issue: 963
spec: spec/2026-09-24-963-shell-ipc-after-redeploy.md
---

# Plan: find the shell by instance when the path we hold is stale

## The approved decisions, carried over

Self-contained; nothing here needs the intent or spec open.

1. **Match by instance, not by a stable path.** The intent leaned to a symlink
   in front of `OMARCHY_PATH`; it was **measured not to work**. Quickshell
   matches the config path as given, not canonicalised:

       $ qs ipc -n -p "$OMARCHY_PATH/shell" call nosuchtarget nosuchfn
       Target not found.                                   <- instance FOUND
       $ qs ipc -n -p "<symlink>/shell" call nosuchtarget nosuchfn
       No running instances for ".../stable-omarchy/shell/shell.qml"

2. **Path-first, instance-second.** A machine that has not rebuilt since login
   never reaches the new code, so the ordinary case cannot regress.

3. **One match calls it; none says the shell is not running; two refuses and
   names them.** Two omarchy shells is not a state to guess in.

4. **Nothing goes upstream.** On Arch `OMARCHY_PATH` is `/usr/share/omarchy` and
   stable, so the code is correct there; a patch would fix a bug they do not
   have. This is a consequence of our port making the path unstable.

5. **`omarchy-restart-shell` is NOT changed here.** Retiring its
   `show-environment` workaround would widen a first patch into a second, on a
   script #953 is separately about. A follow-up, not scope creep.

## Confirmed while writing this, and it shrinks the main risk

**The house style is `--replace-fail`, not a `.patch` file.** `pkgs/AGENTS.md`:
*"Everything is patched with `--replace-fail`, so an Omarchy bump that rewords a
line a patch depends on **fails the build** rather than quietly restoring Arch
instructions."* The one `.patch` in the tree
(`901-bar-keyed-layout.patch`) is a QML exception, not the pattern for a shell
line.

The spec worried that a first patch to this script becomes the silent kind at
the next source bump, and asked for `pkgs/AGENTS.md`'s bump procedure to name
it. **`--replace-fail` provides that mechanically**: a bump that rewords the
line fails the build. The procedure note is still worth having, but it is no
longer the only thing standing between us and a silently dropped fix.

**The line to replace**, verified in the built tree
(`share/omarchy/bin/omarchy-shell`):

```sh
output=$(timeout --kill-after=1s "$ipc_timeout" qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@" 2>/dev/null)
```

## Steps

1. **`pkgs/omarchy/default.nix`** -- `substituteInPlace
   $out/share/omarchy/bin/omarchy-shell --replace-fail` on that one line,
   swapping the fixed `-p "$OMARCHY_PATH/shell"` for a resolved selector:

   ```sh
   output=$(timeout --kill-after=1s "$ipc_timeout" qs ipc -n "''${qs_sel[@]}" call -- "$@" 2>/dev/null)
   ```

   with `qs_sel` built just above it -- `-p "$OMARCHY_PATH/shell"` when that
   path has a running instance, else `-i <instance>` from the fallback.
   → verify by step 4.

2. **The resolver**, in the same replacement. `qs list --all` is parsed for
   `Instance <id>:` and `Config path:`; candidates are those whose config path
   ends `/shell/shell.qml`. **It refuses on an implausible parse** rather than
   reporting no instance -- returning "none" from a broken parse would restore
   the exact silent failure this issue is about, inside the fix for it.
   → verify by step 4's unparseable case.

3. **`pkgs/AGENTS.md`** -- a line under "Patching upstream" naming this as the
   first patch to `omarchy-shell`, why it is not sent upstream, and that
   `--replace-fail` is what makes a bump that reworks the line loud.
   → verify by reading it back.

4. **`tests/shell-ipc-resolve.nix`** -- a `runCommand` driving the patched
   script against a **stub `qs`** on PATH. A PATH stub works here and did not in
   #967: that script is a `writeShellApplication` with a strict PATH, this one is
   upstream's and unwrapped.

   | case | assert |
   |---|---|
   | caller path has an instance | called with `-p`, unchanged |
   | caller path stale, one instance | called with `-i <that id>` |
   | no instance | fails saying the shell is not running |
   | two instances | refuses, names both |
   | `qs list` unparseable | refuses; does **not** report "no instance" |

   **Section 1:** each seen failing with step 2's fallback removed, and that
   output in the PR. The trap: asserting the script printed something. Assert
   **which selector it called with** -- the stub records its own argv.

5. **`tests/AGENTS.md`** -- what no check reaches: a real redeploy under a live
   session, which is the whole bug. `checks.session` boots a desktop but does
   not rebuild under one. Checked by hand on p620, which has a live shell and
   rebuilds often.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.shell-ipc-resolve` | passes; five cases |
| `nix build .#omarchy --print-build-logs` | builds; the `--replace-fail` lands |
| `nix build .#checks.x86_64-linux.menu-verbs` | still passes |
| `nix fmt -- --ci`, statix, deadnix | clean |

No workflow edit: `generated-checks.sh generated` enumerates every flake check
and emits all but its `claimed`/`exempt` lists.

Queue check before the heavy build, per section 6.

## Rollback

`git revert`. The `--replace-fail` disappears and the shipped script is
upstream's again, so the behaviour returns to today's exactly. No state, no
activation, no user file, and nothing persists between the two.
