---
status: draft
issue: 1359
intent: intent/2026-10-19-1359-owe-handoff-patch.md
---

# Spec: owe 0.2.11 with the handoff fix, instead of holding 0.2.10

## Design

`pkgs/apps/owe.nix` already carries one upstream change (#1153) in its
`postPatch`, as a `substituteInPlace … --replace-fail`. That is the repo's way
of patching (pkgs/AGENTS.md, "Patching upstream"), so this fix joins it there
rather than arriving as a `.patch` file.

1. **The version is 0.2.11** (hash `sha256-0o+YpXsgz2ibsmzQzOS2wInZcMaZrkUyovoBN6lrk38=`).
   If #1360 has merged first, this change also removes #1360's "Held at
   0.2.10" comment.
2. **The fix**, appended to `postPatch` under its own comment:

   ```nix
   # CARRIED (#1359, omacom/owe#18): switch_to_shell() schedules a park 2 s
   # out, and since 0.2.11 the engine stays "shell" through a handoff, so a
   # video set inside those 2 s had its loading renderer parked and never
   # showed. Clear the pending park when the handoff starts. Drop once owe has it.
   if grep -A1 'app->handoff_pending = true;' src/daemon/main.c | grep -q shell_stop_at_ms \
     || sed -n '/^static void process_shell_handoff/,/^}/p' src/daemon/main.c | grep -q handoff_pending; then
     echo "owe already clears the pending park during a handoff (omacom/owe#18): drop the #1359 substitution" >&2
     exit 1
   fi
   substituteInPlace src/daemon/main.c \
     --replace-fail 'app->handoff_pending = true;' \
                    'app->handoff_pending = true; app->shell_stop_at_ms = 0;'
   ```

   - `handoff_pending = true;` occurs exactly once in v0.2.11's `main.c` (in
     `owed_app_apply_policy`), so the substitution has a single, specific
     target. If a later release removes it, `--replace-fail` stops the build.
   - The guard makes the build fail if upstream fixes it either way: by
     clearing the park where the handoff starts (the proposed fix), or by
     skipping the park in `process_shell_handoff` during a handoff. Without
     it, `--replace-fail` would keep matching after an upstream fix and the
     patch would linger, carried and unnoticed.

Nothing else changes. The daily bump's `updateScript` rewrites version and
hash and leaves `postPatch` alone.

## Alternatives rejected

- **Keep holding 0.2.10** (#1360): gives up the first-frame handoff, which
  the owner asked to keep.
- **A `.patch` file:** this repo does not use them for upstream changes. A
  one-line substitution with `--replace-fail` reads in the diff and fails at a
  reworded bump.
- **Loosen `checks.session`** (a pause between the still and the video):
  that hides a bug users can hit.

## Risks

- **The fix is mine, not upstream's.** Upstream may fix it differently, for
  example in `process_shell_handoff`. The guard catches the two shapes I can
  foresee. A third shape would leave this substitution harmless: clearing an
  already-cleared deadline.
- **Clearing the park when a handoff starts** also means that, if the handoff
  is then cancelled, the renderer is not parked 2 s later. In
  `cancel_handoff`, owe stops the renderer itself (`owed_supervisor_stop`) when
  it is alive, so nothing is left running. Confirmed in v0.2.11's source.
- **p620 and razer** pick this up only through the owner's `/etc/nixos`
  nixarchy bump and switch. A p620 switch restarts the CI runners (§6), so it
  is announced on the bus and timed by the owner.

## Verification

- **§1 red:** owe 0.2.11 without the substitution failed `checks.session` on
  this exact sequence three times (`main` c335cad7 job 117978017543, edge
  verify run 39227743290, #1358's run 39236759325), each logging
  `renderer parked` after `renderer loading behind the shell's still`.
- **Green:** this PR's `checks.session` on 0.2.11 with the substitution. The
  owe log must show `engine: renderer` after the second `renderer loading
  behind`, and no `renderer parked` between them.
- **The guard, under bash:** a copy of v0.2.11's `main.c` with the proposed
  upstream line added must make the guard exit 1. Then a copy with
  `handoff_pending` checked inside `process_shell_handoff` must exit 1. The
  unmodified file must exit 0.
- `nix build .#owe` succeeds, and owe's own meson tests pass in it.
- `nix fmt -- --ci` clean.
