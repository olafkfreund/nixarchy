---
status: approved
issue: 1301
intent: intent/2026-10-17-1301-menu-guards-pacman-disabled.md
---

# Spec: The menu's package guards ask Nix, and installed apps dim on stable as they do on edge

## Design

The approved intent states two problems. First, the menu's built-in
`omarchy-pkg-present` and `omarchy-pkg-missing` functions ask pacman, so on
NixOS they always say "absent". Second, the stable menu ignores `disabled`.
The two have to be fixed together: correcting the guards alone would hide
39 installed apps instead of dimming them, and would expose six remove rows
that run Arch scripts. The fix has three parts in code and one new check.

All evidence below was read from these places:

- the pinned stable source, `/nix/store/3pyxkhsa…-source` (Omarchy v4.0.4,
  rev `c668141e`);
- the edge pin, `/nix/store/73zrg55r…-source` (quattro `cce8b1c`);
- the deployed tree, `/nix/store/rla9km5s…-nixarchy-omarchy-tree`.

### Decisions

1. **The guards are right for every row, not only nixarchy's (intent Q1).**
   `pkgs/omarchy/default.nix` patches `guardHelpers()` in
   `shell/plugins/menu/MenuModel.js` with `substituteInPlace --replace-fail`.
   It replaces the two string lines that define `__omarchy_pkg_has`
   (stable :417-418, edge :494-495; the text is identical on both pins). The
   new version answers inside the shell with the rule nixarchy's own
   `omarchy-pkg-present` uses (`pkgs/omarchy/nix-bin/omarchy-pkg-present`):
   is the name a runnable command, either as written or with `-bin` and then
   `-stable` removed.

   It runs no extra process, so the guards stay one batch, which upstream's
   comment at :462-465 asks for. The functions keep their names, so every
   `when`, `checked` and `disabled` that calls them gets the Nix answer. That
   includes rows a user or a plugin adds in
   `~/.config/omarchy/extensions/omarchy-menu.jsonc`. The pacman snapshot
   lines above them are left as they are. They become dead, but harmless:
   the pacman shim refuses at once. Leaving them keeps the patch to the two
   lines whose text is identical on both pins. The snapshot itself differs:
   edge builds it in `guardPackageSnapshot()` (`fb09f26be1`), so one
   substitution covering it would not apply to both.

2. **Installed apps dim on stable as they do on edge (intent Q2).**
   Stable carries upstream's own change, omacom/omarchy@4b93f8d84d ("Dim
   installed software in the Install menus instead of hiding it", #6955).
   Only its `shell/plugins/menu/Menu.qml` and `MenuModel.js` hunks are
   carried, as `pkgs/omarchy/1301-menu-disabled.patch`. It is applied with
   `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0`, after the
   existing patches.

   A `--fuzz=0` dry run applies cleanly to the pinned v4.0.4 source and to
   the deployed tree, which already has nixarchy's other patches; the only
   differences are line offsets of 1 to 6. The commit's `omarchy-menu.jsonc`
   and `test/` hunks are not carried, because nixarchy generates its own
   defaults. Edge already has this code, so an edge carry commit deletes the
   `patch` line, as `9958d4c1` did for 1153 and 1155.

   It is a CARRIED patch, to be dropped when stable reaches an Omarchy
   release that contains #6955. Stable and edge then look the same:
   installed apps are dimmed, marked ✓, cannot be selected, and drop out of
   search (upstream's `matchesQuery` change).

3. **A row nixarchy marks with `disabled` does not inherit upstream's
   package-guard `when`.** In the merge in `modules/apps.nix`
   (~:1027-1030), when the override has `disabled` and upstream's `when`
   calls `omarchy-pkg-*`, that `when` is not copied. Every other upstream
   `when` is still inherited. That matters for the 13
   `install.development.*` rows, whose `when` checks for a mise or rustup
   directory (`[[ ! -d $HOME/.local/share/mise/installs/go ]]`), not for a
   package. Whether those conditions are right is #1303's business, not
   this spec's. On stable this removes `! omarchy-pkg-present …` from the 39 rows
   that carry both. Without that, decision 1 would hide those apps when
   installed, so they could never dim. On edge it changes nothing: upstream
   moved those rows from `when` to `disabled` itself, in the same #6955.

   Rows nixarchy does not override keep upstream's `when`, which now gets
   the right answer. `install.ai.hermes` and `install.ai.perplexity` are the
   two install rows in this group.

4. **The six unmapped remove rows stay hidden until #1304 replaces their
   actions (settled by the lead).** In the same python, after the arch-map
   rewrite (~:983-1007), every upstream `remove.*` row that still carries
   upstream's `action` and whose `when` calls `omarchy-pkg-*` gets
   `when = "false"`. "Still carries upstream's action" means the row is not in
   nixarchy's overrides at all. Any row #1304 overrides is untouched by this
   rule, whatever its new action is, so the two issues can land in either
   order. A comment names #1304 as the issue that lifts it, row by
   row, as it ports each action. Today these are `remove.service.tailscale`,
   `remove.security.fingerprint`, `remove.security.fido2`,
   `remove.ai.hermes`, `remove.ai.perplexity` and
   `remove.browser.brave-origin`. That is the behaviour they have today, now
   on purpose instead of by accident.

   The rule is derived, not hand-listed, so a remove row that upstream adds
   with a package guard is hidden too, until somebody ports it. Decision 6
   proves that no such row becomes visible.

5. **The three "Not available on NixOS" rows are made unselectable by
   decision 2, and nothing else changes.** Their `disabled: "true"` now dims
   them and blocks a click. Their inherited Arch `action` belongs to #1304,
   which owns actions, and this spec leaves it alone.

6. **One new check, `checks.menu-guards` (`tests/menu-guards.nix`), owned
   by #1301 and generic enough for #1303 to reuse later (settled by the
   lead).** It is a `runCommand`, so it costs no VM. It is built the way
   `tests/menu-verbs.nix` is: it takes the reference configuration's
   `programs.nixarchy.tree`, which is the patched tree with the generated
   defaults. It also takes upstream's unmodified menu,
   `${cfg.package}/share/omarchy/default/omarchy/omarchy-menu.jsonc`, which
   is the generator's own input. That is how it finds the remove rows
   upstream guards by package, after decision 4 has rewritten their `when`.
   Then:

   - It loads that tree's own `shell/plugins/menu/MenuModel.js` under
     `nodejs` (the file exports itself for node at :481). It parses the
     defaults with `parseMenuJsonc`, then merges them with
     `mergeMenuSources(parsed, []).items`, as `Menu.qml` does.
     `parseMenuJsonc` returns an array, and `guardScript` takes its output
     ids from object keys, so skipping the merge reports `216:w:…` instead
     of `install.editor.helix:w:…`. It then builds the script with
     `guardScript(items)` and runs it with `bash -lc`, as `Menu.qml`'s
     guard process does. The guards are judged by the menu's own code,
     never by running a condition string on its own.
   - It runs that script with `bash`, twice, in two worlds that differ only
     in what is installed:
     - **absent:** `PATH` holds coreutils and grep, and an empty
       `~/.config/nixarchy/apps.nix`;
     - **present:** the same, plus an executable stub for every name the
       rows ask about, collected from the generated rows and from upstream's:
       `omarchy-pkg-present <name>`, the arch name with `-bin` and `-stable`
       removed, and `command -v <bin>`.
   - It parses the `<id>:<w|c|d>:<0|1>` output into result maps, the way
     `Menu.qml`'s guard process does. It then judges each row with the
     model's own `MenuModel.isVisible(items, itemOrder, whenResults, entry)`
     and `MenuModel.isDisabled(disabledResults, entry)`. It never reads raw
     lines as the verdict.
   - It asserts, over rows found by these rules and never from a list
     written in the check:
     - every Install row with `disabled` and no `when` is visible in both
       worlds;
     - every Install row with `disabled` is dim (`d:1`) in **present** and
       not dim (`d:0`) in **absent**, except `disabled: "true"` rows,
       which are dim in both;
     - no Install row with `disabled` has a `when` that calls
       `omarchy-pkg-*`;
     - every Install row whose `when` or `disabled` calls `omarchy-pkg-*`
       is offered in **absent**, and in **present** reads as installed:
       hidden if the guard is its `when`, dim if the guard is its
       `disabled`. The minimum count is on this whole group. On edge,
       upstream moved every such guard from `when` to `disabled`, so a group
       of "`when` only" rows would be empty there and fail;
     - every `remove.*` row whose `when` in upstream's menu calls
       `omarchy-pkg-*`, and whose generated row nixarchy does not override
       (its action is byte-identical to upstream's), is hidden in
       **present**. Rows like `remove.theme`
       and `remove.security.sshd`, which have no package guard, are not
       this check's concern;
     - the in-shell helper agrees with the tree's `bin/omarchy-pkg-present`,
       run by absolute path, for the same names (with and without `-bin` and
       `-stable`) in both worlds. This catches the two rules drifting apart.
   - It has a minimum count for every group, so an empty parse cannot pass
     (the §4 fail-open lesson). It has no #1303-specific cases.

   **What it cannot see:** `Menu.qml`. node runs `MenuModel.js`. The
   `Menu.qml` half of the carried patch is covered only by the patch
   applying at `--fuzz=0` and by the hand check in Verification. Dimming,
   cursor skipping and blocked clicks live in QML, and only a booted session
   could probe them. That hole is stated here, not closed (CLAUDE.md §3).

   CI runs it with no workflow edit, through the generated-checks step
   (CLAUDE.md §4).

7. **The documentation that is wrong today is corrected in the same
   change:**
   - `modules/AGENTS.md:1792-1794`: `disabled` is honoured on stable through
     the carried patch;
   - `data/bin-ledger.nix:392-395`: the menu answers with an in-shell copy
     of this rule;
   - `data/bin-ledger.nix:380-383` and `:397-400`: still true, now because
     decision 4 keeps those rows hidden;
   - `pkgs/AGENTS.md`: a section for the carried patch and the guard
     substitution, with the drop condition;
   - `data/apps.nix:756-758` and `docs/manual/development-tools.md:14`
     become true again and stay as they are.

8. **Follow-ups for the owner to file, not done here (settled by the
   lead).** nixarchy-menu loads its own copy of `MenuModel.js`, through its
   `omarchy-menu-model` store path from its own pin. It has both problems,
   and so may nixi. Neither is edited or filed by this work.
   nixarchy-menu's guard parser ignores tags it does not know (it reads only
   `w` and `c`), so nothing here breaks it.

### Coexistence (CLAUDE.md §14)

This sets no NixOS or Home Manager option and merges into no environment,
so no option-collision fixture can fail. The one shared surface is the
user's menu extension. It is still merged over the defaults row by row, and
nixarchy still never writes it. The one visible change is that a user's own
row using `omarchy-pkg-present` now gets the Nix answer instead of "always
absent". That goes in the release notes.

## Alternatives rejected

- **Delete the shadowing functions so the PATH scripts answer.** That
  starts one process per guard, 47 on stable, and the batch exists to avoid
  exactly that. Decision 6's agreement test keeps the in-shell copy honest
  instead.
- **Rewrite all 47 guards in the generator, and leave `MenuModel.js`
  alone.** Rows a user or a plugin writes would still be answered by
  pacman. It would also mean hand-maintaining 47 overrides that upstream
  keeps changing.
- **Fold `disabled` into `when` on stable.** Installed apps would vanish
  from stable but dim on edge, the three "Not available" rows would vanish,
  and the manual would be wrong on stable.
- **Show the six remove rows when present.** They would run upstream's Arch
  remove scripts, which is #1304's to fix. The lead ruled it out.
- **Report the pacman lookup upstream.** It is correct on Arch, so it is
  not Omarchy's bug (CLAUDE.md §11).
- **A VM probe in `checks.session`.** A VM costs 10–20 minutes, and the
  thing that is wrong is pure JS plus bash, which a `runCommand` can reach.
  §2 asks for the highest layer that can see the bug, and the cheapest layer
  sees it here. The existing session block at `tests/session.nix:1520-1560`
  stays. It still proves that the condition strings answer correctly on a
  real machine.

## Risks

- **The carried patch has to come off at the next stable bump.** If upstream
  rewrites the menu, `--fuzz=0` and `--replace-fail` fail the `omarchy`
  build loudly, on stable, which is the intended signal.
- **Edge.** If the patch line is still there on edge, the build fails
  (`--forward` finds the patch already applied). The edge carry commit that
  deletes it has to land in the same edge integration as this change. The
  guard `substituteInPlace` applies on edge unchanged, because its text is
  the same at `cce8b1c`.
- **User rows change answer.** A user row written as `! omarchy-pkg-present
  foo` used to show always. Now it hides when `foo` is on PATH. That is the
  bug being fixed, but it is visible.
- **The "installed" rule is a heuristic.** It is the same one
  `omarchy-pkg-present` has always used: a runnable command, with `-bin` and
  `-stable` removed. An Arch package whose command is named differently and
  is not overridden still answers "absent". That is the same as today, and
  no worse.
- **Speed.** The guard batch now forks no `pacman -Q` for versioned names.
  The dead snapshot still starts the pacman shim twice per batch, as it
  does today.
- **Hosts.** Every nixarchy desktop on stock `omarchy.menu`. Mode A (the
  module imported but not enabled) is unaffected: the tree and defaults are
  produced only under `programs.nixarchy.enable`.

## Verification

- **The §1 proof for `checks.menu-guards`.** Commit a known-good baseline
  first. For each break, show it landed with `git diff`, run the check under
  bash, and capture the red output. Then restore with `git checkout HEAD --
  <path>`, never `git checkout -- <path>`, because that restores the index
  (CLAUDE.md §5). All four breaks go in the PR.

  | break | expected red |
  |---|---|
  | delete the guard `substituteInPlace` (decision 1) | `install.ai.hermes` visible with `hermes-desktop` present, and the helper disagrees with `bin/omarchy-pkg-present` for every name |
  | delete the `1301-menu-disabled.patch` line (decision 2) | `normalizeItem` drops `disabled`, so `guardScript` emits no `d:` answers and `MenuModel.isDisabled` is not a function: the check stops with that `TypeError`, naming the first dim row it reached |
  | delete the generator's `when` skip (decision 3) | `install.editor.helix` still carries `! omarchy-pkg-present helix` and is hidden in **present**: hidden instead of dimmed |
  | delete the generator's remove-row hide (decision 4) | `remove.service.tailscale` visible in **present** with upstream's action |

  After each restore, the check is green.

- **Builds, cheap tier first, one at a time under
  `flock /mnt/data/vmtest/codex-build.lock`:**
  - `checks.menu-guards`;
  - `checks.patched-files`;
  - `checks.menu-verbs`;
  - the `omarchy` package, which is the non-cheap tier: no p620 system build
    running, and load below 12.

  `checks.options` and `checks.session` are left to CI (the §6 tiers).
  `nix fmt -- --ci`, `statix` and `deadnix` must pass.
- **Edge:** the edge carry commit builds edge's `omarchy` package with the
  patch line removed, and `checks.menu-guards` passes against edge's tree.
- **By hand on the deployed machine,** after the switch:
  - Install > Editor shows Helix dimmed with ✓ when `hx` is installed;
  - Sublime Text is dim and does nothing when clicked;
  - Remove > Service shows no Tailscale row.
