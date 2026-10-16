---
status: approved
issue: 1283
intent: intent/2026-10-15-1283-stock-menu-default.md
---

# Spec: Omarchy's own menu is the default; nixarchy-menu is one click away

## Design

### Installed is one decision, turned on is another

`modules/home.nix` resolves default plugins once (`resolvedDefaults`, ~:486).
The same list (`defaultIds`) feeds two things: the plugin links, which install
a plugin, and the post-boot hook, which turns it on once (~:2140). The menu
needs to be in the first list but not the second.

- **`programs.nixarchy.defaultPlugins.menu` keeps its meaning: is
  nixarchy-menu installed.** Default `true`, as today; `false` still leaves
  it out entirely.
- **New option `programs.nixarchy.menu.default`**, an enum `"omarchy"` or
  `"nixarchy"`, default `"omarchy"`. It decides only which menu a machine
  starts on, at the first login that has the plugin:
  - `"nixarchy"`: nixarchy-menu stays in the hook's enable-once list, which
    is today's behaviour;
  - `"omarchy"`: nixarchy-menu is installed but left out of that list, so the
    stock `omarchy.menu` stays on and no marker is written.

  It sits under the existing `programs.nixarchy.menu` namespace, beside
  `menu.extraEntries`. An option named for the menu is plainer than a
  third value on `defaultPlugins`, and it leaves the other default plugins'
  type alone.
- **In code:** `defaultIds` (installed) stays as it is. A second list,
  `enableOnceIds`, is `defaultIds` minus `nixarchy.menu` when
  `menu.default == "omarchy"`. The hook's `todo` loop reads
  `enableOnceIds`. Its "gone clone" restore loop keeps reading `defaultIds`,
  since nixarchy-menu is still declared.

**Existing machines are not migrated.** A machine that already has the
`enabled-once/nixarchy.menu` marker keeps nixarchy-menu on, because nothing
in the hook ever disables a plugin. One that never ran the hook since #1052
starts on the stock menu. That is the new default, and it is correct.

### The switch: Setup ▸ Defaults ▸ Menu

A new group in `modules/apps.nix`'s override rows, beside upstream's
`setup.default.agent` and `setup.default.dictation`. Its rows exist only when
nixarchy-menu is installed (a Nix-level `lib.optionalAttrs` on
`defaultPlugins.menu` and nixarchy being on):

| id | label | action | checked |
|---|---|---|---|
| `setup.default.menu` | Menu (title "Default Menu") | parent | none |
| `setup.default.menu.omarchy` | Omarchy | `omarchy-plugin-disable nixarchy.menu` | `! nixarchy-plugin --enabled nixarchy.menu` |
| `setup.default.menu.nixarchy` | Nixarchy | `omarchy-plugin-enable nixarchy.menu` | `nixarchy-plugin --enabled nixarchy.menu` |

- **The shell does the switching.** `omarchy-plugin-enable/-disable` are the
  same IPC writers the post-boot hook uses. nixarchy-menu is a clone of
  `omarchy.menu`, so the shell's own `setEnabled` disables the source when
  the clone is enabled, and `restoreCloneSource` restores it when the clone
  is disabled. Nothing writes `shell.json` (#847).
- **The call is the hook's own.** The hook runs `omarchy-plugin-enable <id>`
  with no placement argument when placement is `""`, which is the menu's
  (`modules/home.nix` ~:2248), and `omarchy-plugin-disable <id>`. The rows run
  exactly those commands. The hook also turns off any *other* enabled clone
  of `omarchy.menu` before enabling ours. The row does not, because a
  machine with a second menu clone has chosen it by hand. The spec accepts
  that a click there swaps clones rather than restoring the stock menu.
- **No rebuild and no terminal**, so the rows run the commands directly, the
  way upstream's Default Agent rows do.
- **Always a menu.** Disable restores the stock menu in the same shell call,
  and the row that runs it lives in whichever menu is active, so Super+Space
  opens a menu after either click. The plugin check confirms that both
  directions leave exactly one menu loaded.

### Docs

- The manual page that covers the menu (found while planning; `menu.md`,
  `plugins.md`, or wherever #1052's "on by default" is described) says:
  - Omarchy's menu is the default;
  - nixarchy-menu is installed;
  - _Setup ▸ Defaults ▸ Menu_ switches between them;
  - `programs.nixarchy.menu.default = "nixarchy"` makes it the first-login
    choice;
  - `defaultPlugins.menu = false` removes it.
- The option's own description says the same, and `modules/AGENTS.md`'s
  "The default plugins are on from the first login" gains a line for the
  exception.

### Coexistence

`menu.default` is a new nixarchy option, not one a user also sets in NixOS.
The menu rows sit inside `mkIf cfg.enable`. No `tests/coexistence/` fixture,
for the reason #1278's spec gives: no option here can collide.

## Alternatives rejected

- **Option A, `defaultPlugins.menu = false` by default.** It removes
  nixarchy-menu entirely: switching would mean editing configuration and
  rebuilding. The owner chose B.
- **A third value on `defaultPlugins`** (`true | false | "installed"`). It
  changes the type for every default plugin to serve one, and every reader of
  `cfg.defaultPlugins.${name}` would need to learn the new value.
- **Migrating existing machines to the stock menu.** Ruled out by the owner.
  It would also mean the hook disabling a plugin a user turned on, which it
  has never done.
- **A terminal command or a Nix option for switching.** The shell already
  switches clones at runtime. A rebuild is what this task removes.
- **Putting the rows under Setup ▸ Plugins.** That screen lists every plugin.
  This is a "which one of these do I use" choice, which is what the Defaults
  group holds.

## Risks

- **The first login on a new machine after this lands still has nixarchy-menu
  installed.** A theme or bind that assumes nixarchy-menu would meet the stock
  menu instead. The binds call `omarchy-menu`, which reaches whichever menu
  is enabled (`tests/session.nix` ~:784 says so), so that should hold. The
  `session` check proves it on the stock default.
- **A check that assumes nixarchy-menu is on by default goes red.** The known
  one is `tests/options.nix` ~:1207, which asserts "on by default". It is
  retargeted to the new default rather than satisfied, and the PR says so.
  §1, read backwards.
- **The `checked` probe costs a process per menu open.**
  `nixarchy-plugin --enabled` reads `shell.json` and does not call IPC. It is
  the same probe the gliff-manager row already uses.

## Verification

| Check | Proves | Fails when |
|---|---|---|
| `tests/options.nix` | `menu.default` defaults to `"omarchy"`. With it, nixarchy-menu is linked but not in the hook's enable-once list. With `"nixarchy"`, it is in both. `defaultPlugins.menu = false` removes it from both and removes the menu rows. Mode A has neither | the enable-once list ignores the option |
| `tests/menu-verbs.nix` (or the check that holds generated rows) | the three rows exist only when nixarchy-menu is installed, run `omarchy-plugin-enable/-disable nixarchy.menu`, and carry `checked` | a row is dropped, its action changes, or it appears when the plugin is not installed |
| `tests/plugin.nix` (VM) | enabling then disabling `nixarchy.menu` through the rows' own commands leaves exactly one menu loaded each time, and `omarchy-menu summon` draws the `omarchy-menu` layer after each | the clone restore breaks, or a click leaves no menu |
| `tests/session.nix` (VM) | unchanged probe: Super+Space opens a menu, now on the stock default | the stock default does not open |
