---
status: draft
issue: 946
author: olafkfreund
---

# Intent: nixarchy-menu can be switched on declaratively, and lands in the menu's place

## Problem

nixarchy-menu (olafkfreund/nixarchy-menu, plugin id `nixarchy.menu`,
`clonedFrom: omarchy.menu`) replaces the Omarchy menu with a Raycast-style
palette:
- it hands off to every default agent
- it has Nixi and skill-backed help rows
- it sizes itself to the output

It has a flake (`packages.<sys>.plugin`), and it has run from that Nix build on
razer since 2026-09-24. But a host only gets it by hand. Someone runs the repo's
`bin/nixarchy-menu install`, which copies the build into
`~/.config/omarchy/plugins/`. Nothing in nixarchy declares it, pins it or
rebuilds it.

The obvious fix, one more `defaultPluginSet` entry, would install it wrongly in
two ways. This is because the default-plugin machinery was built for bar
widgets, not for plugins that replace a first-party one.

**1. Placement.** The enable-once hook runs `omarchy-plugin-enable "$id" right`
for every default plugin (`modules/home.nix:1910`). For a clone, the shell first
puts it in the source plugin's bar slot
(`shell/services/PluginRegistry.qml:529`). The `right` argument then moves it
into the right-hand section (`:546`, `moveBarEntry` at `:278`). So the menu
button would leave the place where every user expects it.

**2. Competing clones.** If another `omarchy.menu` clone is already enabled,
both claim the menu:
- The old clone could be upstream's `evindor.keystroke`, or a hand install of
  this one.
- `resolveEnabledId` (`:171-178`) silently picks the first enabled clone in id
  order.
- Disabling the loser *afterwards* runs `restoreCloneSource` (`:555`), which
  brings the stock menu and its button back beside the winner.

The old clone has to be disabled **before** the new one is enabled.
nixarchy-menu's own installer already does this by hand
(`bin/nixarchy-menu install`). That is how razer was switched without a
duplicate menu.

## Proposed outcome

- **Declarative.** A host can turn nixarchy-menu on or off in its
  configuration. The plugin comes from a pinned nixarchy flake input and is
  rebuilt with the system. Nothing is installed by hand.
- **Same place.** When it is on, `Super+Space` and the bar's menu button open
  nixarchy-menu from the **same bar slot** the stock menu had. There is no
  second menu button, and the stock menu doesn't come back.
- **Hand installs taken over.** A host that already has another
  `omarchy.menu` clone enabled ends with exactly one menu: the declared one.
  A leftover hand copy of `nixarchy.menu` itself gets an explicit, documented
  way out. It is never a silent winner (open question 3).
- **Clean off switch.** Turning it off, or disabling the plugin by hand,
  restores the stock menu, as disabling any clone does today.
- **Existing users unaffected.** It stays off by default until it has run on
  razer and p620. Hosts that don't turn it on see no change.

## Affected users and systems

- **The Home Manager side** of the default plugin set (`modules/home.nix`):
  - the `defaultPluginSet` and `defaultPlugins` options
  - the enable-once hook
- **`flake.nix`:** one new input, plus a `docs/internals/flake.md` entry.
- **Anyone with a hand install:** razer (`nixarchy.menu`, copied), plus any
  host still running upstream `evindor.keystroke`.
- **Hosts that opt in:** razer first, then p620. p510 is not involved.
- **The menu data** (`omarchy-menu.jsonc`) is unchanged. nixarchy-menu reads
  the same file, and #961 already landed its half.

## Constraints

- **Existing plugins must keep working.** The hook change must not alter
  anything for the plugins already in `defaultPluginSet`: they still land
  `right`, enable once, and never fight a user who later disables them.
- **Only the same menu gets disabled.** The hook may disable a competing
  plugin only when it shares the new plugin's `clonedFrom`. Unrelated plugins
  are never touched, and each id is still enabled only once.
- **Pin rules.** The pin follows nixarchy's usual rules: `inputs.nixpkgs.follows`,
  a `# Why:` pointer, and one omarchy pin (`inputs.omarchy.follows`).
- **Plain store copy.** No runtime download and no rsync. The plugin is a
  plain store copy that passes `omarchy-plugin-validate`, as it already does.
- **Test hosts.** razer is the test host. Don't test on p620 until razer has
  passed.

## Open questions

1. **Flip to on-by-default later, or stay opt-in?** The issue proposes a
   follow-up flip after razer and p620. Should this intent commit to that
   follow-up, or leave the choice open?
2. **Competing clones generally, or menu only?** Should the "disable competing
   clones first" rule apply to every `clonedFrom` plugin in `defaultPluginSet`
   (general, and nothing else uses it today), or only to the menu entry?
3. **Hand installs at the same id.** The activation step leaves a real
   directory alone (`modules/home.nix:1110`: "is your own directory, not
   replacing it"). So razer's hand copy of `nixarchy.menu` would quietly
   outrank the declared pin, which would never take effect. The options:
   - keep that rule and document a one-time `rm` for hand installs
   - have `bin/nixarchy-menu install` refuse on a nixarchy-managed host
   - special-case this id

   Which should it be? The rule protects real checkouts, so I lean towards
   documenting the `rm` and adding the installer refusal.
