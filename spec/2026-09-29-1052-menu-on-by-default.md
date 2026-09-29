---
status: approved
issue: 1052
intent: intent/2026-09-29-1052-menu-on-by-default.md
---

# Spec: Turn nixarchy-menu on by default

## Design

**Delete the opt-in mechanism.** Nothing else uses it, so there is nothing to
flip.

`enableByDefault` exists only for the `menu` entry (#946). After this change:

- `modules/home.nix:424` resolves a default as
  `cfg.defaultPlugins.${name} or true`. A name left out counts as on, which is
  what the option description already says about every other default.
- The `enableByDefault` option (`home.nix:726-733`) and the menu entry's
  `enableByDefault = false` (`:1837`) go.
- `menu` is not added to the `defaultPlugins` default attrset. Absent means on,
  and adding it would only be a second place to keep in sync.
- The option description (`:695-697`) and the entry's comment (`:1829-1832`)
  stop saying opt-in. They name `menu = false` as the way back to the stock
  menu.

Everything else about the entry stays as #946 built it:

- `placement = ""`: it takes `omarchy.menu`'s bar slot.
- The pre-disable of competing `omarchy.menu` clones.
- The enabled-once marker that records what the clone replaced.
- The restore path that brings the stock menu back when `menu = false` removes
  it.

**Existing machines.** With no marker, the enable-once hook enables
`nixarchy.menu` at the next login after the switch, exactly as a newly added
default. A user who turned it off in Setup > Plugins has a marker and stays
off.

**The ISO.** Defaulted from intent question 1: no special case.

- The live session is a tty installer with no Home Manager (`installer/cd.nix`),
  so it has no plugins at all.
- Installed systems resolve the defaults through `installer/host.nix`, so they
  get the menu.
- The offline ISO's reference closure therefore gains the plugin, about
  85 MiB unpacked (#946 measurement). The recorded headroom is about 0.9 GiB
  under the 7.5 GiB `iso-budget` (`installer/cd.nix:608-627`, measured
  2026-09-14).

**Menu overrides reach it.** nixarchy-menu's Omarchy provider reads
`$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`. That is
`programs.nixarchy.tree`, where `modules/apps.nix` has already merged
nixarchy's rows (Install ▸ Edit app selection and the rest), and the provider
merges the user's extension file over it with the stock `MenuModel`. No change
is needed.

**Tests** (`tests/options.nix`):

- The fixture `clone` entry drops `enableByDefault = false`. The placement,
  pre-disable and restore tests stay; they test the hook's text, not the
  default.
- `defaultPluginsEnableByDefault` and
  `defaultPluginsEnableByDefaultSurvivesOtherKeys` are deleted. The mechanism
  they test is gone.
- `menuIsOptIn` becomes `menuIsOnByDefault`:
  - on: `defaultHomeOn` installs `nixarchy.menu` and the hook lists it;
  - off: a home with `menu = false` does neither.
- `menuOnHome` is replaced by `defaultHomeOn` wherever it was used
  (`menuValidated`, `defaultHookScript`).
- `noDefaultsHome` gains `menu = false`. Without it,
  `defaultPluginsNoHookWhenEmpty` goes red.

**Tests** (`tests/plugin.nix`): the node that opts out every default to reach an
empty plugin directory gains `menu = false`.

**Counts.** `.github/scripts/readme-counts.sh` loses its third category
(`p_off`, `p_off_word`, the `default-plugins-optin` quantity). It has to: at
zero, `word_for` returns empty and the script refuses. "Always on" returns to
`p_total - p_gated`. The sentence the script matches in `docs/index.md:90`
becomes "…eleven are always on, and three turn on with their feature. Voice is
opt-in."

**Docs** that say opt-in are rewritten to say on by default, with
`menu = false` as the opt-out:

- `docs/manual/plugins.md` (:40, :373, :386-395)
- `docs/llms.txt:115`
- `docs/internals/flake.md` (#946 section, :492-540). Its heading changes, so
  the `# Why:` pointer at `flake.nix:298` moves with it.
- `docs/manual/configuration.md` (the opt-out example gains `menu = false`)

The pin stays at `2cce175`, which is v1.0.0.

## Alternatives rejected

- **Set `enableByDefault = true` and keep the field.** It leaves a field with
  no user, and readme-counts' third category counting zero, which refuses.
  YAGNI: re-adding a field for a future opt-in plugin is a small change.
- **Add `menu = true` to the `defaultPlugins` default attrset.** That attrset
  is replaced wholesale when a host sets any key (the #946 note), so a host
  with `{ podman = false; }` would lose the menu. Absent-means-on does not
  have that problem.
- **Keep the stock menu in demos and screenshots by opting them out.** The
  point is that nixarchy's menu is nixarchy-menu. The pictures should show
  it.

## Risks

- **Everyone who never chose it gets a different menu at next login.** That is
  the intent. Declining is `menu = false` or Setup > Plugins.
- **Re-enabled for someone who had `menu = true` and deleted the line.** Under
  the old default that turned it off and the restore pass removed the marker,
  so the flip turns it back on for them. Accepted: it is what "on by default"
  means for someone who did not say `false`.
- **A hand-installed, disabled copy with no marker is enabled.** This is
  existing behaviour for every default (the hook logs "hand install").
  Unchanged.
- **ISO budget.** About 85 MiB against about 0.9 GiB of recorded headroom that
  is two weeks old. `iso-budget` is nightly-only, so a breach shows the next
  morning, not on the PR.
- **Checks that drive the menu now reach nixarchy-menu.** `checks.session`,
  `tests/demo/` and `docs/capture-screenshots.sh` all route through the
  `omarchy.menu` alias, and nixarchy-menu claims every `omarchy menu summon`
  route. `checks.session` asserts menu files, not the UI; its one screenshot
  is a wide-tolerance wallpaper average. Demo scenes are packages that no CI
  job builds (§4), so a stale demo would not go red. That is a known gap, and
  re-recording them is not in scope.
- **The plugin runs unsandboxed in the shell on every machine**, as every
  default plugin does. The code is first-party and pinned.

## Verification

- `nix fmt -- --ci`, statix, deadnix.
- `bash .github/scripts/readme-counts.sh` passes with the new sentence.
- `checks.options` locally, only after `gh run list` shows no install in
  flight (it peaks at 11.5 GB).
  - Break proof: restore `enableByDefault = false` on the menu entry, watch
    `menuIsOnByDefault` fail, then restore the change.
  - Before the change: confirm `defaultPluginsNoHookWhenEmpty` fails without
    `menu = false` in `noDefaultsHome`.
- CI on the PR: `plugin`, `session`, `install`, `omarchy`.
- After merge: the next nightly's `iso-budget`.
