---
status: approved
issue: 1320
intent: intent/2026-10-17-1320-dimmed-arch-only-rows.md
---

# Spec: Arch-only menu rows say why they can't be used, instead of vanishing

## What the built menu does today

All line numbers below are from the built tree,
`/nix/store/aqzp5r203asjmmamfk0iqv20f84gzfqa-omarchy-4.0.4/share/omarchy/shell/plugins/menu/`,
built from this branch's base (`7e0ceac5`).

| Route | Honours `disabled`? | Evidence |
|---|---|---|
| Click | yes | `Menu.qml:1418` `if (row.disabled) return`, and `activateIndex` checks `rowSelectable` at `:784` |
| Enter | yes | `Menu.qml:1170-1176` calls `activateIndex`, which refuses a row that is not selectable (`:524`, `:784`). The cursor also skips the row (`nextSelectable`, `:530-543`) |
| Right arrow | yes | `:1172`: Right runs only `rightEnters()`, which is true only for `menu`/`link` rows (`:760-765`, #1305). It never runs an action row at all |
| Search | yes | `matchesQuery` passes `isVisible && !isDisabled` (`Menu.qml:511`), and `MenuModel.js:330-332` returns false for that row. Disabled rows are not searchable |
| `omarchy menu summon <id or alias>` | **no** | `openRoute` (`Menu.qml:911-920`) resolves the route and runs `entry.action` for any `kind === "action"` row. It checks neither `when` nor `disabled`. `resolveRoute` (`MenuModel.js:184-198`) accepts a raw id as well as an alias |

So **summon runs a disabled row**. It runs a hidden row too: `omarchy menu
summon install.windows` runs the Arch action today, despite `when = "false"`.
None of the nine rows has an alias upstream, so the route is the raw id. That
is omacom/omarchy#15742 (open), which names `when`. The same code path skips
`disabled`.

There is a second, quieter gap. Guards are evaluated asynchronously
(`Menu.qml:1015-1075`), and before the first batch lands `whenResults` and
`disabledResults` are empty. `when` only hides a row on an explicit false
(`MenuModel.js:264`), and `isDisabled` only dims a row on an explicit true
(`:284-286`). So in that window a `when = "false"` row is visible and a
`disabled = "true"` row is selectable. Hiding and dimming have the same window.

**How a disabled row renders:** opacity 0.4 (`Menu.qml:1291`), an arrow
cursor rather than a pointer (`:1409`), and its description as the detail line
(`:654`). Its label also gets **" ✓"** appended (`MenuModel.js:289-295`),
because upstream uses `disabled` to mean "already installed". The three
existing "Not available on NixOS" rows already render this way.

**The generator** (`modules/apps.nix:1100-1130`): an override replaces the
keys it states. Every key it omits is inherited from upstream, with one
exception: when the override has `disabled`, upstream's `when` is dropped if
it calls `omarchy-pkg-*` (`:1125`). An override that omits `action` therefore
inherits the Arch action. An override with `action = ""` becomes a
childless `menu` row (`MenuModel.js:21`), which `isVisible` hides
(`:265-278`).

## Design

### 1. Five rows are dimmed and four stay hidden (open question 2)

These five rows are dimmed (`disabled = "true"`) with a reason. They are the
rows a NixOS user would go looking for. Each has the Arch action replaced by
`action = "true"`, for the reason in part 2.

| Row | Upstream `when` after the merge | Shown | Description |
|---|---|---|---|
| `install.windows` | `[[ ! -f …/windows-vm.desktop ]]`, inherited (not a package guard) | dimmed, unless that file exists | `Not available on NixOS — Omarchy's Windows VM needs rooted Docker and an FHS PATH. Use programs.virt-manager in your configuration` |
| `trigger.hardware.hybrid-gpu` | `omarchy-hw-hybrid-gpu`, inherited | dimmed, on hybrid-GPU hardware only | `Not available on NixOS — Omarchy's switch writes /usr/lib/systemd/system-sleep. Use services.supergfxd in your configuration` |
| `setup.direct-boot` | none | always dimmed | `Not available on NixOS — needs efibootmgr and an Omarchy UKI. NixOS writes its own boot entries on every rebuild` |
| `install.ai.hermes` | `! omarchy-pkg-present hermes-desktop`, dropped by `:1125` | always dimmed | `Not available on NixOS — Hermes installs itself under /usr/share/hermes-desktop, and nixpkgs has no package` |
| `install.ai.perplexity` | `! omarchy-pkg-present perplexity`, dropped by `:1125` | always dimmed | `Not available on NixOS — a pacman package nixpkgs does not carry` |

The prefix and dash copy the existing `unavailable` rows
(`modules/apps.nix:949`), so all eight dimmed rows read the same. Both options
named above exist in nixpkgs unstable (`programs.virt-manager.enable`,
`services.supergfxd.enable`).

These four Remove rows **stay hidden** with `when = "false"`:
`remove.windows`, `remove.ai.hermes`, `remove.ai.perplexity` and
`remove.browser.brave-origin`. Nothing can be installed for them to remove.
A dimmed "Remove ▸ Hermes ✓" answers no question a user has. Also, with the
package guard dropped (`:1125`), three of them would show in every Remove menu.

### 2. A dimmed row's action is `true` (closes summon)

A row with `disabled = "true"` has nothing it should ever run, so it does not
carry an action that can run. `action = "true"` is the smallest value that
keeps the row an `action` row: `""` would make it a childless menu, which is
hidden (see above). That one value closes both gaps from the first section:

- `omarchy menu summon <id>` runs `true`;
- a click in the window before the guards are evaluated runs `true`.

It closes them without patching `openRoute`. A carried patch that checked
`isDisabled` there would still lose the race: on a summon straight after the
shell starts, `disabledResults` is empty and the row reads as enabled. The
real fix belongs upstream, in #15742, which we comment on with the `disabled`
case (§11: a human posts it).

The same `action = "true"` goes on:

- **the four hidden Remove rows.** The intent's constraint is that none of the
  nine can run its Arch action, and `when = "false"` does not stop summon.
- **the three existing "Not available" rows** (`install.browser.brave-origin`,
  `install.editor.sublime` and `install.ai.grok-bot`), through one line in the
  `app ? unavailable` branch (`modules/apps.nix:946-950`). They have the same
  summon hole today. Part 3's assertion would fail on them otherwise.

The other `when = "false"` rows in the menu stay as they are. These are
`remove.development.elixir.phoenix`, `install.aur`, `update.channel.rc` and
the generator's unported Remove rows (`:1093-1099`). They are #15742's general
case, which is out of scope here.

### 3. Something can see it (§2)

`check-menu-actions.py` gets one assertion: every row whose `disabled` is
literally `"true"` has `action` exactly `"true"`. The failure message names
the row, its action and #15742. This is needed because the existing walk
cannot see a reverted action on `setup.direct-boot` or `install.ai.hermes`:
their Arch actions match no hazard pattern (#1304 spec, decision 12
verification).

### 4. Records

- `data/menu-actions.nix`: delete the nine `hidden:` entries. The dimmed rows
  no longer have `when = "false"`, so an entry for them would fail
  (`check-menu-actions.py:121-125`). The four hidden rows reach no hazard
  once their action is `true`. Their entries would still pass, but they would
  describe a hazard that is no longer there. If the owner prefers to keep
  them as documentation, they stay valid.
- `data/menu-exceptions.nix:38,64-67`: reword `install.windows`,
  `install.ai.hermes` and `install.ai.perplexity` from "hidden (#1304)" to
  "dimmed with a reason (#1320)". `check-menu-mapping.py` only requires a
  non-empty reason, so this is for accuracy (§4, a hand-maintained list).
- `tests/menu-guards.js:136`: raise the `unavailable` floor from 3 to 6, and
  update the comment at `:134-135` that says hermes and perplexity are hidden.
  The `disabled-no-when` count also rises by 2 (hermes, perplexity), and its
  floor of 30 is left alone. The three package-guarded hidden Remove rows
  (`remove.ai.hermes`, `remove.ai.perplexity`, `remove.browser.brave-origin`)
  leave `unported-remove`, because their action now differs from upstream's
  (`tests/menu-guards.js:112`). That group's floor is 0. They still count in
  `upstream-guarded-remove`.
  The plan measures every count before and after.
- `modules/apps.nix:852-861`: the `#1304: hidden` comment becomes two short
  comments, one per group, each pointing at #1320. Remove the per-row `#`
  reasons the descriptions now carry.

### Answers to the intent's open questions (recommendations; the owner decides)

1. **Is this wanted?** Recommend yes. The menu already shows three
   "Not available on NixOS" rows, so these five follow an existing pattern
   rather than adding a new one.
2. **Which rows?** The five in part 1. The four Remove rows stay hidden.

## Alternatives rejected

- **Patch `openRoute` to check `isDisabled`/`isVisible`.** This is a carried
  patch on upstream QML, re-applied at every bump. It loses the
  first-evaluation race (part 2). It is #15742's fix, and belongs upstream.
- **Keep the row's Arch action and add a `disabled:` class to the checker.**
  Summon would still run the Arch script, which breaks the intent's
  constraint.
- **`action = ""`.** The row becomes a childless menu and is hidden
  (`MenuModel.js:21,265-278`).
- **A notification as the action (`notify-send …`).** `libnotify` is not on
  the session PATH. It is only in two units' paths (`modules/home.nix:2001,2056`),
  so the action would name something that may not exist (§2). Only summon by
  raw id reaches it, and a no-op is enough there.
- **Dim all nine.** The three package-guarded Remove rows would show in every
  Remove menu (part 1).
- **Drop the ✓ on "Not available" rows (patch `labelFor`).** It is a carried
  patch for a wart the three existing rows already have. See Risks.

## Risks

- **The ✓ reads as "installed".** "Windows ✓", dimmed, with the description
  under it. That matches the three existing rows, and the description says
  "Not available". If the owner finds it misleading, the fix covers all eight
  rows and is a separate change.
- **`install.windows` disappears again** if `~/.local/share/applications/windows-vm.desktop`
  exists, for example in a home directory carried over from Arch. That is
  upstream's inherited `when`, and it is harmless.
- **Hybrid GPU shows only where `omarchy-hw-hybrid-gpu` says yes.** No VM has
  two GPUs (§3), so the dimmed rendering on real hybrid hardware is reached
  only by `verify.sh`-style manual testing. The static checks prove the
  row's fields, not that it is drawn.
- **Edge.** Not verified. The edge tree was not built. Its `Menu.qml` comes
  from upstream's #6955, and `openRoute` there is assumed to be the same as
  stable. The design does not depend on it, because `action = "true"` holds
  on either.
- **Every host on the Omarchy session.** This changes only menu rows, after a
  rebuild. Mode A is unaffected: the generated menu is part of the opt-in
  Omarchy session.

## Coexistence (§14)

None. The change edits only nixarchy's own generated menu JSONC. It sets no
NixOS option, and adds nothing to `systemPackages` or `hardware.graphics`.
The reason text names `programs.virt-manager` and `services.supergfxd` for
the user to set in their own configuration. nixarchy sets neither. No
fixture is warranted, because no failing case exists (§14's rule).

## Verification

Cheap checks only, each built one at a time under
`flock /mnt/data/vmtest/codex-build.lock`. `git add` comes before every
build (§5), and every revert uses `git checkout HEAD --` (§5).

| Check | Break (prove the break landed with `git diff`) | Expected red |
|---|---|---|
| `checks.menu-actions` (new assertion) | delete `action = "true"` from `setup.direct-boot` | `setup.direct-boot has disabled = "true" but runs omarchy-launch-floating-terminal-with-presentation omarchy-setup-direct-boot …`. The walk alone would stay green here (decision 12 verification) |
| `checks.menu-actions` (existing walk) | delete `action = "true"` from `trigger.hardware.hybrid-gpu` | the new assertion, plus `trigger.hardware.hybrid-gpu reaches omarchy-toggle-hybrid-gpu: etc-write, systemctl-system, with no entry in data/menu-actions.nix` |
| `checks.menu-actions` (assertion reaches the catalogue rows) | delete the `action = "true"` line from the `unavailable` branch | one failure each for `install.browser.brave-origin`, `install.editor.sublime` and `install.ai.grok-bot` |
| `checks.menu-guards` (floor) | revert `install.windows` to `when = "false"` | `only 5 unavailable cases, expected at least 6` |
| `checks.menu-guards` (dimmed, not hidden) | delete `disabled = "true"` from `install.ai.hermes` | `only 5 unavailable cases …` |

Then restore, and see every one of them go green. The PR carries the red
output.

- `checks.menu-actions --measure` before and after: the summary's `hidden`
  count drops from its current value by exactly the five dimmed rows.
- `nix fmt -- --ci`, `statix check .` and `deadnix --fail .`. Read
  `git diff --stat` after each `.nix` edit (§5, the nixpkgs-fmt hook).
- Read the generated menu JSONC (the `menu-actions` input) for the nine
  rows: `disabled`, `action` and `description` should be as in part 1, and
  `install.ai.hermes`/`perplexity` should have no `when`.
- **Manual, not CI** (no VM per the brief): on a desktop, Install ▸ Windows
  is dimmed with the reason, an arrow cursor, and does nothing on click,
  Enter or Right. It is absent from search for "windows". `omarchy menu
  summon install.windows` opens nothing and runs nothing. A `checks.session`
  probe would add little over the static assertion, so the plan does not
  add one.
