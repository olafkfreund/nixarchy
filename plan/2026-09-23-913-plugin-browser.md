---
status: approved
issue: 913
spec: spec/2026-09-23-913-plugin-browser.md
---

# Plan: ship the Plugin Browser, so Add Plugin opens a searchable, sandbox-audited marketplace

This plan is self-contained: it carries every approved spec decision.

**Decisions**

- **A default plugin, on wherever nixarchy is.** Its name is
  `plugin-browser`, and it has no `gate`. The existing
  `programs.nixarchy.defaultPlugins.plugin-browser = false` turns it off.
- **The id stays `io.github.olafkfreund.nixarchy-plugin-browser`.**
- **The agent hand-off (`e`/`f`) ships on, as the plugin has it,** behind its
  warning and its two confirms, which default to No. Turning it off would
  be a plugin setting, in a separate issue.
- **Input:** `nixarchy-plugin-browser`, pinned to master
  `cd3a5607d1184d98a5ca082fd88ada6febd6b627`, with
  `inputs.nixpkgs.follows = "nixpkgs"` and a `# Why:` link to
  `docs/internals/flake.md#the-plugin-browser-on-by-default-913`. The
  flake's `homeManagerModules` is not used.
- **The table row:** `src` = `packages.<system>.plugin`, and
  `packages = [ packages.<system>.cli pkgs.bubblewrap ]`, so `bwrap` is in
  the audit's fixed PATH (`/etc/profiles/per-user/$USER/bin`), not in
  system packages.
- **Two menu rows, in `modules/apps.nix`'s always-on block:**
  - `setup.plugin.add`: icon 󰖟, "Add Plugin", with action
    `nixarchy-plugin <id>`, `when = "nixarchy-plugin --enabled <id>"`,
    aliases marketplace / plugin browser / install plugin, and description
    "Search the plugin marketplace; audit before installing · Super+Alt+U";
  - `setup.plugin.add-url`: icon 󰌷, "Add Plugin from URL", with upstream's
    stock action
    `omarchy-launch-floating-terminal-with-presentation 'omarchy-plugin-add'`
    and description "Install a plugin from its Git URL, without the audit".
- **The binding:** `o.bind("SUPER + ALT + U", "Plugin browser", "nixarchy-plugin <id>")`
  goes in the seed block of `pkgs/omarchy/default.nix`. Only new homes get
  it; the manual already tells existing homes to use the menu row or copy
  the line (`docs/manual/plugins.md:21`).
- **Docs:**
  - a `docs/internals/flake.md` section, including the re-login note;
  - a `docs/manual/plugins.md` table row and section;
  - `docs/manual/configuration.md` gets the new `defaultPlugins` name.
- **Out of scope here:** removing the hand wiring on p620 and razer. Before
  either host takes a nixarchy bump with this change, its clone at
  `~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser`
  goes (Home Manager will not replace a real directory with its link), and
  `nixos_config`'s `hosts/common/nixos/omarchy-plugin-browser.nix` is
  removed. That is a follow-up PR in `nixos_config`.

## Steps

1. **`flake.nix`:** add the input after `nixarchy-devenv` (~line 285), in the
   same form, then run `nix flake lock --update-input nixarchy-plugin-browser`.
   → verify:
   - `nix flake metadata --json | jq '.locks.nodes["nixarchy-plugin-browser"].locked.rev'`
     gives `cd3a560…`;
   - the lock node has no `nixpkgs` of its own (follows);
   - `git diff flake.lock` touches only the new node and root's input list.
2. **`modules/home.nix`:**
   - add `plugin-browser = true;` to the `defaultPlugins` default (~632),
     with one clause in the description ("…the Plugin Browser always…");
   - add the `plugin-browser` row to the table, after `devenv` (~1705),
     with the spec's comment.

   → verify: `nix eval .#nixosConfigurations.<fixture>` (the one
   `tests/options.nix` uses) lists the id in `programs.nixarchy.plugins`, and
   `home.packages` includes `bubblewrap` and the cli.
3. **`modules/apps.nix`:** the two rows in the always-on block (the one
   holding `install.apply`, ~655), with the spec's comment.
   → verify: in the built omarchy tree,
   `jq '."setup.plugin.add", ."setup.plugin.add-url"'` on the generated
   `default/omarchy/omarchy-menu.jsonc` (comments stripped) shows both rows;
   `setup.plugin.add` sits at upstream's position, and `add-url` is present.
4. **`pkgs/omarchy/default.nix`:** the bind line after `SUPER + ALT + E`
   (~2167).
   → verify: `nix build .#omarchy` succeeds, and the seed
   `share/omarchy/config/hypr/bindings.lua` contains the line.
5. **`tests/options.nix`:** `pluginBrowserIsADefault` and
   `pluginBrowserPackages`, copying `githubIsADefault` / `githubPackages`
   (~933):
   - on: the id is in `defaultHomeOn.programs.nixarchy.plugins`, and
     `hookLists` includes it;
   - off: the id is absent from `noDefaultsHome`, `defaultHome` and
     `fixtureNixarchyOff`;
   - packages: a `hasBwrap` helper (`pname == "bubblewrap"`) is true on, and
     false on `noDefaultsHome` and `defaultHome`.

   → verify: `nix build .#checks.x86_64-linux.options` is green; with the
   table row commented out it is red (mutation check), and it is restored.
6. **Docs:**
   - `docs/internals/flake.md`: the section "The Plugin Browser, on by
     default (#913)", after the MicroVMs one, in the GitHub Actions shape. It
     covers what it is, why it is a default, `packages` (cli + bwrap, and
     why), bumping the pin, and the re-login note.
   - `docs/manual/plugins.md`: a table row (on by default · Setup ▸ Plugins
     ▸ Add Plugin · Super+Alt+U) and a section covering:
     - the two verdicts;
     - installs landing disabled;
     - `e`/`f` with the auto-approve warning, and the residual prompt-injection
       risk;
     - the URL row being unaudited;
     - catalog and previews fetched from plugins.omarchy.org at run time;
     - the off switch.
   - `docs/manual/configuration.md`: the line
     `programs.nixarchy.defaultPlugins.plugin-browser = false;` after
     `devenv` (~209).

   → verify: the docs checks in `nix flake check` (links, anchors) are
   green, and the `# Why:` anchor in `flake.nix` resolves.
7. **Whole check:** `nix flake check` on the branch.
   → verify:
   - green, including `checks.menu-verbs`, the plugin validation with the
     pacman/yay grep, and `config-warnings`;
   - the PR's CI is green, and the install check runs only once the PR
     leaves draft.
8. **Desktop, once:** the install VM (`checks.install`) or razer, from this
   branch after a re-login. razer only after its clone is removed and with
   your go-ahead, since that is a system switch on a shared host, announced
   on the bus.
   → verify:
   - Add Plugin opens the panel;
   - Add Plugin from URL opens the stock prompt;
   - Super+Alt+U opens the panel (a new home);
   - opening a plugin runs a sandboxed audit.
9. **PR #915:** link the three artifacts, mark it ready, and merge by
   nixarchy's rules.
   → verify: #913 closes, and `main` has the change.

## Tests

| Command | Expected |
|---------|----------|
| `nix flake metadata --json \| jq -r '.locks.nodes["nixarchy-plugin-browser"].locked.rev'` | `cd3a5607…` |
| `nix build .#checks.x86_64-linux.options` | green; red with the table row removed |
| `nix build .#checks.x86_64-linux.menu-verbs` | green |
| `nix build .#omarchy` + grep of the seed `bindings.lua` | the Super+Alt+U line |
| generated `omarchy-menu.jsonc` | `setup.plugin.add` → `nixarchy-plugin <id>`; `setup.plugin.add-url` → the stock action |
| `nix flake check` | green |
| desktop (step 8) | all four observations |

## Deviations recorded during implementation

- **Step 5 also touches two existing test inputs.**
  - `noDefaultsHome` switches the defaults off by listing each name, and "a
    name left out counts as on", so it gains `plugin-browser = false`.
    Without that line, four cases fail (the two new ones,
    `defaultPluginsNoHookWhenEmpty` and `defaultRuntimeToolsLowPriority`).
  - The same holds for the `machine` node's `defaultPlugins` block in
    `tests/plugin.nix`: that VM needs an empty plugin directory, and without
    the line `checks.plugin` fails with "the Remove Plugin row still shows
    itself with no plugins installed". `tests/AGENTS.md` names both
    fixtures for any ungated default; they were found in step 7.
  - `defaultRuntimeToolsLowPriority`'s spelled-out `toolNames` gains
    `bubblewrap`. The CLI is a named env with no `pname`, so
    `pluginBrowserPackages` finds it by name.
- **`tests/coverage.py`: the plugin id joins `not_invocations`.** Its
  command pattern `\b(?:omarchy|nixarchy)-[a-z0-9-]+` matches after the last
  dot of `io.github.olafkfreund.nixarchy-plugin-browser`, which is the
  argument to `nixarchy-plugin`, not a command. The row's command,
  `nixarchy-plugin`, is still checked. This follows the set's two existing
  exclusions, each a name that is not an invocation.
- **Step 6 also updates `docs/index.md`.** It states the number of default
  plugins in words ("Ten ship by default: seven are always on"), and CI's
  `readme-counts.sh --check` derives that number from the repository. It
  now says Eleven and eight, and the feature list there gains the
  marketplace line.

## Rollback

- Revert the PR. Homes lose the plugin link and its packages on the next
  switch. An enabled plugin id left in shell.json then points at a missing
  folder; `omarchy plugin disable <id>` clears it. (How the shell treats a
  missing enabled plugin is not verified here.)
- A single machine can opt out without a revert:
  `programs.nixarchy.defaultPlugins.plugin-browser = false`.
