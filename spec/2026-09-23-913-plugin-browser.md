---
status: approved
issue: 913
intent: intent/2026-09-23-913-plugin-browser.md
---

# Spec: ship the Plugin Browser, so Add Plugin opens a searchable, sandbox-audited marketplace

## Decisions on the intent's open questions

The intent was approved with its four questions open. This spec takes one
answer each; approving the spec approves these.

1. **On by default.** The Plugin Browser is a default plugin, like pkg,
   microvm and github-actions. `programs.nixarchy.defaultPlugins.plugin-browser = false`
   turns it off (the existing switch, `modules/home.nix:632`). There is no
   service gate, because Add Plugin exists wherever nixarchy does.
2. **The agent hand-off ships on, as the plugin has it today.** `e`/`f` open
   a terminal that audits and then shows the auto-approve warning. Both
   confirms default to No (plugin #11). The hand-off is inert without a
   default agent: `nixarchy-plugin-fix` says so and exits. An off switch
   inside the plugin would be new plugin code for a risk that already sits
   behind two explicit steps. If review wants it off, that becomes a plugin
   setting in a separate issue, and this spec does not change.
3. **The id stays `io.github.olafkfreund.nixarchy-plugin-browser`.** There
   is precedent (`olafkfreund.github-actions`, `olafkfreund.gitlab-pipelines`),
   and existing installs on p620 and razer keep their state and shell.json
   entries.
4. **"Add by URL" is a second menu row, "Add Plugin from URL",** carrying
   upstream's stock action unchanged. It needs no new code, and it is still
   there when the panel is turned off.

## Design

### The input (`flake.nix`)

A new input, beside `nixarchy-devenv` and in the same form:

```nix
# Why: docs/internals/flake.md#the-plugin-browser-on-by-default-913
# A commit on master (no tags); bump it the way that page says.
nixarchy-plugin-browser = {
  url = "github:olafkfreund/nixarchy-plugin-browser/<master sha>";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The plugin flake has a single `nixpkgs` input, so `follows` is complete. It
exposes `packages.<system>.plugin` (the plugin folder, a copied file list
with no symlinks) and `packages.<system>.cli` (wrappers for
`omarchy-plugin-audit`, `omarchy-plugin-browser` and `nixarchy-plugin-fix`).
The flake's `homeManagerModules` is not used; nixarchy wires the plugin
itself.

### The default-plugin row (`modules/home.nix`, the table at ~1640)

```nix
# The Plugin Browser: Add Plugin opens it (#913). It audits a marketplace
# plugin in bubblewrap before a disabled, commit-pinned install, and the
# audit fails closed without bwrap -- so bubblewrap comes with it.
plugin-browser = {
  id = "io.github.olafkfreund.nixarchy-plugin-browser";
  src = inputs.nixarchy-plugin-browser.packages.${pkgs.stdenv.hostPlatform.system}.plugin;
  packages = [
    inputs.nixarchy-plugin-browser.packages.${pkgs.stdenv.hostPlatform.system}.cli
    pkgs.bubblewrap
  ];
};
```

The row has no `gate`. Its `packages` land on the per-user profile, which
is in the audit's fixed PATH (`/etc/profiles/per-user/$USER/bin`). That
puts `bwrap` where the audit looks, without adding a system package. The
post-boot hook enables the plugin once, as it does for every default
plugin.

### The menu rows (`modules/apps.nix`)

In the always-on block (the one holding `install.apply`):

```nix
# Add Plugin opens the Plugin Browser (#913): browse the marketplace and
# audit a plugin before it is installed. Upstream's Git-URL prompt stays,
# one row down, for a URL you already have. `when` hides this row once
# the panel is turned off; the URL row stays.
"setup.plugin.add" = {
  icon = "󰖟";
  label = "Add Plugin";
  action = "nixarchy-plugin io.github.olafkfreund.nixarchy-plugin-browser";
  when = "nixarchy-plugin --enabled io.github.olafkfreund.nixarchy-plugin-browser";
  aliases = [ "marketplace" "plugin browser" "install plugin" ];
  description = "Search the plugin marketplace; audit before installing · Super+Alt+U";
};
"setup.plugin.add-url" = {
  icon = "󰌷";
  label = "Add Plugin from URL";
  action = "omarchy-launch-floating-terminal-with-presentation 'omarchy-plugin-add'";
  description = "Install a plugin from its Git URL, without the audit";
};
```

The menu generator writes `full = upstream; full.update(out)`, so the
override keeps upstream's position for `setup.plugin.add`. The new
`add-url` id is appended. The helper `nixarchy-plugin` is used rather than a
bare toggle, as `apps.devenv` and `install.apply` do: an off plugin is named
in a notification instead of being toggled silently.
`tests/menu-verbs.nix` accepts the row because the id is installed, and the
id matches its `[a-z][-a-z.]*` pattern.

### The binding (`pkgs/omarchy/default.nix`, the seed block at ~2156)

One line in the default plugins' bind list:

```
'o.bind("SUPER + ALT + U", "Plugin browser", "nixarchy-plugin io.github.olafkfreund.nixarchy-plugin-browser")' \
```

Super+Alt+U is used neither by upstream nor by the other shipped binds.
Like them, it is in the **seed**, so new homes get it and nobody's edited
`bindings.lua` is touched. An existing home is in the same position as for
every other default-plugin key. The plan checks what the manual already
tells that user, and adds the one line if it says nothing.

### Docs

- **`docs/internals/flake.md`:** a new section, "The Plugin Browser, on by
  default (#913)", in the shape of the GitHub Actions one. It covers what
  it is, why it is a default, what `packages` carries and why (bwrap), how
  to bump the pin, and the re-login note: a changed menu row appears only
  after a re-login, because the session keeps the login-time
  `OMARCHY_PATH` tree.
- **`docs/manual/plugins.md`:** a table row (on by default · Setup ▸
  Plugins ▸ Add Plugin · Super+Alt+U) and a short section. The section
  covers:
  - the two verdicts;
  - installs landing disabled;
  - `e`/`f` and their warning;
  - the off switch;
  - that previews and the catalog come from plugins.omarchy.org at run time.

### Tests (`tests/options.nix`)

Assertions mirroring the github-actions ones at ~935:
- the plugin is in `programs.nixarchy.plugins` and the hook lists for a
  default home;
- it is absent with nixarchy off, or with the defaults off;
- `bubblewrap` is in the home's packages when the plugin is on.

## Alternatives rejected

- **Gate it behind a new service switch, off by default.** Add Plugin exists
  on every machine, so an off-by-default browser leaves the unchecked prompt
  as the default path, which is the problem the intent names.
  `defaultPlugins` already provides the off switch.
- **Put the source in this repo,** as `nixarchy.rebuild` is. That plugin is
  in-tree only because it must not drift from `nixarchy-apply`. The browser
  has its own release cycle, tests and flake checks; a pinned input is how
  the other panels are carried.
- **Rename the id to `nixarchy.plugin-browser`.** This orphans existing
  installs and their shell.json state, for a naming consistency the table
  already does without.
- **Replace Add Plugin with no URL fallback.** It removes a capability, and
  it leaves nothing when the panel is off.
- **Add the URL path inside the panel (a key that takes a URL and audits
  it).** That is better long-term, because it audits URL installs too. But
  it is new plugin code and belongs in the plugin's own repo. The second row
  is correct today and can be pointed at that path later.
- **Ship bwrap as a system package (`environment.systemPackages`).** It only
  matters to this plugin, so it belongs in the plugin's row, where turning
  the plugin off removes it.

## Risks

- **Every machine gets a new bar icon.** The plugin is `menu` +
  `bar-widget`, and enabling it places the widget. That is what the other
  default panels do, and the user can remove it from the bar.
- **The URL row installs without an audit,** exactly as today. The row's
  description says "without the audit", so the difference is visible.
- **The hand-off ships on (decision 2).** Mitigations are the warning, the
  No-default confirms, a disposable copy, no plugin text in the prompt, a
  re-audit, and the choice before install. The residual risk is a prompt
  injection that makes the agent run commands as the user while it works.
  This is stated in the manual.
- **Network at run time:** the catalog (about 8 MB, cached for 1 h) and one
  preview per opened plugin, from plugins.omarchy.org. Nothing at build
  time.
- **The plugin's own update check** is hidden on a Nix-managed install
  (`git_managed: false`, verified in the plugin), so it cannot fight the pin.
- **The pacman/yay grep in the plugin checks:** the plugin's detector
  regexes are spelled `pac[m]an` and `y[a]y`, and its own `checks.default`
  runs the same grep. This is verified again in this repo's build.
- **Hosts:** p620 and razer carry the hand wiring: an `extraEntries` row in
  `nixos_config`, and a **git clone** at
  `~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser`.
  That real directory sits where this change puts a Home Manager link, and
  Home Manager refuses to overwrite it. So those hosts must remove the clone
  (and drop the `nixos_config` module) before they take a nixarchy bump
  containing this. That is recorded in the plan, not done here.

## Verification

- `nix flake check` on the branch: `checks.options`, `checks.menu-verbs`,
  the plugin validation derivation, the pacman/yay grep, and
  `config-warnings`.
- `nix build .#checks.x86_64-linux.options` goes red with the new
  assertions reverted (mutation check).
- The built home for the test fixture has
  `~/.config/omarchy/plugins/io.github.olafkfreund.nixarchy-plugin-browser`
  linking to the input's `plugin`, and `bwrap` in `/etc/profiles/per-user/*/bin`.
- The generated `default/omarchy/omarchy-menu.jsonc` in the omarchy tree has
  `setup.plugin.add` with the helper action, at upstream's position, and
  `setup.plugin.add-url` with the stock action.
- The seed `bindings.lua` in the omarchy package ends with the Super+Alt+U
  line.
- **Desktop, once, in the install VM or on razer after a re-login:**
  - Add Plugin opens the panel;
  - Add Plugin from URL opens the stock prompt;
  - Super+Alt+U opens the panel;
  - an audit runs sandboxed.
