---
status: draft
issue: 1325
intent: intent/2026-10-18-1325-edge-menu-actions.md
---

# Spec: checks.menu-actions passes on edge, and each of its findings there is a decision rather than noise

## What the 31 findings are

Each group was traced through the walker and quattro's scripts
(`omarchy-edge-20261017-5fcdaca`). No menu row runs pacman on x86_64, and
none is dangerous.

| group | what really runs | verdict |
|---|---|---|
| `setup.default.browser.*` (7) | `omarchy-default-browser` installs only a missing browser, through the nixarchy `omarchy-pkg-add` shims, which print guidance and `exit 1`. The "pacman" is `omarchy-lifecycle-dispatch` reading `/var/lib/pacman/local`, which x86_64 never reaches: `*) exit 0` comes first. | walker artefact |
| `update.password.drive` | Reaches dispatch only through `echo` text that names it. The real call is `"$OMARCHY_PATH/bin/…"`, and on x86_64 dispatch exits 0. | walker artefact |
| `setup.default.editor.*` (8) | Each editor branch ends in `theme-set-hermes`, which runs `omarchy-install-hermes-cli --check`. The user-unit `stop` is in the `--now` branch, which `--check` returns before. | walker artefact |
| `style.font.cjk.*` (6) | `omarchy-restart-shell`, which does `systemctl --user try-restart` on the user's own shell units | real and harmless |
| `setup.default.agent.{agy,kimi,ori}` | `omarchy-agent`. Only the `openclaw)` branch runs `launch-openclaw`. | walker artefact. These are new quattro rows; `agy` is the renamed antigravity. |
| `setup.security.ssh-agent` | `systemctl --user enable --now gcr-ssh-agent.socket` | real; it acts on the user's own socket |
| `remove.service.ssh-agent` | removes its own `environment.d` file, then runs `systemctl --user disable --now` | real and harmless. On NixOS the success message is wrong; see risk 3 |
| `setup.security.fingerprint` | The `omarchy-apply-lock` call comes after our guidance's `exit 1`, so it is dead code. The walker found the name in the error text. | walker artefact |
| stale: `style.theme` | The row now summons a shell widget and runs no script. | changed upstream |
| stale: `setup.default.agent.{gemini,antigravity}` | gemini is gone from quattro's menu, and antigravity became `agy` | removed upstream |

How the walker decides what a row reaches (`check-menu-actions.py:66-81`): it
follows every `omarchy-*` name anywhere in a script, whichever `case` branch it
sits in and even inside an `echo`. It sees nothing called as
`"$OMARCHY_PATH/bin/omarchy-x"`.

## Design

1. **Classify, on `edge-candidate` only.** `data/menu-actions.nix` is the same
   file on both channels, and its stale rule also fires for a row that does not
   exist (`:131-132`). So the edge-only rows cannot be added on main without
   turning stable red. They go in an `Edge:` carry commit, as `bin-ledger.nix`
   and `menu-exceptions.nix` already do. Reasons use the classes already in
   the file:

   | rows | reason |
   |---|---|
   | browser ×7, drive | `unreached: pacman is omarchy-lifecycle-dispatch reading /var/lib/pacman/local, which x86_64 never reaches (exit 0 first)` |
   | editor ×8 | `unreached: theme-set-hermes runs omarchy-install-hermes-cli --check only; its user-unit stop is the --now branch` |
   | cjk ×6 | `session: restarts the user's shell unit` (stable's wording for `install.style.font.*`) |
   | agy, kimi, ori | the existing OpenClaw reason, copied from their stable siblings |
   | fingerprint | `guidance: exits 1 before omarchy-apply-lock` |
   | setup ssh-agent | `session: enables the user's gcr-ssh-agent socket` |
   | remove ssh-agent | `session: disables the user's gcr-ssh-agent socket and removes its own environment.d file` |

   - **Removed on edge only:** `style.theme`, `setup.default.agent.gemini` and
     `setup.default.agent.antigravity`. Removing them on main would turn
     stable red.
   - **Reworded on edge:** `install.style.theme` and `remove.preinstalls` still
     pass, but say "removes only the wrapper it wrote". On quattro, what they
     reach is hermes-cli's user-unit stop.

2. **Leave the walker as it is.** Each fix considered either moves stable or
   changes nothing (see "Alternatives rejected"). Its two blind spots go into
   `tests/AGENTS.md` on main, in the menu-actions section, so the next reader
   of an artefact knows what produced it.

3. **Have edge's CI run the check.** Add `menu-actions` to the cheap-check list
   in `omarchy-edge.yml` (`menu-verbs bin-ledger …`). Without it, this goes red
   again and nobody is told. That is a CI-gate change (§11): a separate PR on
   main, for a maintainer to merge, and only **after** the edge carry has
   landed. Otherwise the edge run goes red the moment it merges.

4. **Where the work lives:**
   - **The main PR:** intent, spec and plan; the `tests/AGENTS.md` note; the
     workflow line. It is `Refs #1325`, because the workflow needs a human.
   - **The edge carry:** the data changes, pushed to `edge-candidate`, with an
     edge run dispatched.
   - **Closing #1325:** when the edge carry is green and the workflow PR has
     merged.

## Alternatives rejected

- **Teach the walker `case` branches or arguments.** That needs a shell parser
  for a check that greps on purpose. Every artefact here is explained by one
  sentence.
- **Have the walker follow `$OMARCHY_PATH/bin/omarchy-*` as well.** This was
  tried on a scratch copy: stable stays at 48 flagged, edge at 73, with no row
  differences. It changes nothing today, so it is not worth a diff.
- **Drop `/var/lib/pacman` from the pacman pattern.** That pattern is
  `ledger.PACMAN`, which the bin ledger shares, and it would hide a real
  pacman call written as a path read. An entry explains this one case.
- **Add the edge entries on main as well.** The stale rule turns stable red
  for rows stable does not have.
- **Patch `omarchy-remove-service-ssh-agent`** to give NixOS guidance. That is
  wrong for a user who enabled the socket from the Setup row rather than in
  their configuration, where the upstream script works. Telling those two
  cases apart needs a check of where the unit is enabled. That belongs in its
  own issue if the wording matters to someone (risk 3).

## Risks

1. **The next quattro bump moves rows again.** The edge workflow then reports
   it, once design 3 has landed. That is the point of design 3.
2. **The edge workflow rewrites `edge-candidate`.** Earlier carries survived
   its `Edge: Omarchy quattro … on main …` merges, and this one is a `data/`
   edit of the same kind.
3. **Remove › SSH Agent says "disabled"** even when the NixOS configuration
   (`services.gnome.gcr-ssh-agent.enable`) turns the socket back on at the next
   login. It is harmless, and it is left as is. Setup › SSH Agent should be
   hidden on the reference config by its own `when`. That was evaluated, not
   booted.
4. **An `unreached:` entry would hide a real hazard added later on the same
   row.** The reason names the exact script and branch, so a change to either
   reads as wrong in review. That is the same exposure stable's four
   `unreached:` entries already carry.

## Verification

- **`menu-actions` on the edge tree:** green, with 394 rows and 73 flagged.
- **`menu-actions` on main:** green, with its counts unchanged (335 rows, 48
  flagged).
- **§1 breaks on the edge tree,** each red with the named message, then green
  when restored:
  - B1: delete one browser entry → `setup.default.browser.firefox reaches omarchy-lifecycle-dispatch: pacman, with no entry`;
  - B2: delete the cjk `session:` entries → six rows named;
  - B3: restore `style.theme` → `entry for style.theme, which reaches no hazard: stale`.
- **`bin-ledger` and `menu-guards`** stay green on edge.
- **An edge run dispatched on the carry**, and its build step read for each
  check.
