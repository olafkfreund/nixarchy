---
status: approved
issue: 766
intent: intent/2026-09-18-766-default-plugins.md
---

# Spec: nixarchy-pkg, -podman, -distrobox and -microvm ship with nixarchy and are on by default

## Four places this spec departs from the approved intent (decide on approval)

1. **One way to enable plugins, not two.** The intent says fresh installs are
   enabled through the vendored default `shell.json`. This spec drops that
   layer and uses the post-boot hook (D1) on fresh and existing installs alike.
   - A default `shell.json` naming a plugin that is gated off (podman,
     distrobox) would list an id with no manifest on disk. What the shell does
     with that could not be verified without running it.
   - The hook knows exactly which plugins are installed, because it is
     generated from the same config that installs them.
   - The cost: on a fresh install the four widgets appear about two seconds
     after the first login rather than with the first frame.
2. **Podman is a plain catalogue row, not `programs.nixarchy.services.podman`.**
   `data/services.nix:10-27` sets the rule: a one-line upstream toggle is
   `kind = "plain"` and gets no nixarchy option (RFC 42). Podman is exactly
   `virtualisation.podman.enable = true`. The owner still gets a switch in the
   Services menu, off by default.
3. **MicroVM is gated like the Sandbox rows it replaces**, on
   `programs.nixarchy.enable` with a runtime check (`modules/apps.nix:627-636`,
   `when = "nixarchy-vm --check"`), not on `services.microvm.enable`. Disposable
   sandboxes work without that service, and the plugin covers both kinds.
4. **Retiring `nixarchy box` needs three more things from the plugin**, beyond
   templates:
   - `promote`, which turns a live box into a declared `services.boxes.machines`
     entry (`pkgs/box.nix:224`);
   - the `--check` runtime guard the menu uses (`pkgs/box.nix:216`);
   - `list`.

   The plugin's `Model.js` has create, enter, rm, stop and upgrade only.

## Design

### D1 — enablement: a post-boot hook through upstream's own writer

- **What decides "enabled".** The shell counts a third-party plugin as enabled
  when its id appears in `shell.json`, either in `plugins[]` or as a bar layout
  entry (`shell/services/PluginRegistry.qml:135-163`).
- **Who writes `shell.json`.** The running shell writes the whole file from
  memory (`shell.qml`, `setText` plus `watchChanges`), so nixarchy never writes
  it.
- **How nixarchy enables a plugin.** It runs `omarchy plugin enable <id> right`,
  which is the shell's own `enablePlugin` IPC. The `right` places the bar widget
  in the right section (`bin/omarchy-plugin-enable:5,85-90`). An unknown id
  returns `unknown`, and the fix is `omarchy-shell shell rescanPlugins`.
- **When it runs.** Upstream's `default/hypr/autostart.lua` runs
  `sleep 2 && omarchy-hook post-boot` after `omarchy-launch-shell`, and
  `omarchy-hook` runs every file in `~/.config/omarchy/hooks/post-boot.d/`.
  nixarchy already ships one there (`modules/home.nix:1409`, `config-repo`).
  The new one is `xdg.configFile."omarchy/hooks/post-boot.d/default-plugins"`,
  generated from the resolved default set. For each id without a marker in
  `~/.local/state/nixarchy/enabled-once/<id>`, it:
  1. waits for `omarchy-shell shell ping` for up to 30 s, and exits quietly if
     the shell never answers, so it retries at the next login;
  2. runs `omarchy-shell shell rescanPlugins` once, because Home Manager may
     have linked the plugin after the shell started;
  3. if the plugin is already enabled (`omarchy-plugin-list --json`), writes
     the marker only;
  4. otherwise runs `omarchy plugin enable <id> right`, and writes the marker
     **only on success**. A failure is sent to the journal
     (`systemd-cat -t nixarchy-default-plugins`) and retried at the next login.
- **Why not a systemd unit.** A `graphical-session.target` unit runs before the
  compositor is up, and the shell exits 0 from that state
  (`modules/home.nix:1436-1446`). The post-boot hook already runs after the
  shell has started.
- **A marker means nixarchy acted once.** After that, Setup > Plugins decides
  for good, and nothing re-enables a plugin the user turned off.
- **The ceiling.** A plugin added by an update made mid-session appears at the
  next login. A second trigger from the Home Manager activation is possible
  later if that proves annoying.

### D2 — the option and the gates (`modules/home.nix`)

```nix
programs.nixarchy.defaultPlugins = {        # attrsOf bool
  pkg = true; podman = true; distrobox = true; microvm = true;
};
```

Every entry defaults to true, each at `mkDefault`. Setting one false opts that
plugin out; setting all four false opts out entirely. For each resolved plugin,
the module sets `programs.nixarchy.plugins."nixarchy.<name>".src` at
`mkDefault` and puts its id in the hook's list.

| id | installed when (all AND `osConfig.programs.nixarchy.enable or false`) |
|---|---|
| nixarchy.pkg | always |
| nixarchy.podman | `osConfig.virtualisation.podman.enable` |
| nixarchy.distrobox | `osConfig.programs.nixarchy.services.boxes.enable` (PR D) |
| nixarchy.microvm | always, like the Sandbox rows |

Under standalone Home Manager `osConfig` is null, so nothing is installed
(`tests/options.nix:62-70`). Mode A therefore stays inert on the Home Manager
side, and `modeAInert` keeps covering the NixOS side.

Installation reuses `programs.nixarchy.plugins`: validation
(`home.nix:327-390`), symlink and reconcile (`:846-895`). One addition: the
validation step asserts that `manifest.json`'s `id` equals the attribute name.
Otherwise a pin that renames an id would pass validation and break every row
that names it (Codex, finding 4).

### D3 — one helper for rows and keys: `nixarchy-plugin`

`omarchy-shell shell toggle <id>` on a plugin that is installed but disabled
exits 0 and does nothing (`modules/home.nix:626-630`). Menu rows and key binds
therefore call a small `writeShellApplication` in `modules/apps.nix`:

- `nixarchy-plugin --enabled <id>` reads `~/.config/omarchy/shell.json` with
  `jq` and makes no IPC call, so it is cheap enough for a menu `when` (Codex,
  finding 5);
- `nixarchy-plugin <id>` runs `omarchy-shell shell toggle <id> '{}'` when the
  plugin is enabled. Otherwise it sends a notification saying where to turn it
  on: the Services menu for podman and boxes, Setup > Plugins for the rest.

### D4 — menu rows (`modules/apps.nix` overrideSpec)

| row | action | when | replaces |
|---|---|---|---|
| `install.packages` (new) | `nixarchy-plugin nixarchy.pkg` | `nixarchy-plugin --enabled nixarchy.pkg` | nothing; `install.search`/`install.apply` stay (`:329`, `:574`) |
| `apps.podman` (new, under the podman gate) | `nixarchy-plugin nixarchy.podman` | same shape | nothing |
| `trigger.box` (existing parent, `:588`) | `nixarchy-plugin nixarchy.distrobox` | same shape | `.enter`, `.rm`, `.create.<tpl>` (`:599-626`), in PR D |
| `trigger.vm` (existing parent, `:629`) | `nixarchy-plugin nixarchy.microvm` | `nixarchy-vm --check && nixarchy-plugin --enabled …` | `.new/.open/.stop/.destroy/.list` (`:637-671`) |

### D5 — key bindings (new installs only)

The four binds are appended to the **seed** `config/hypr/bindings.lua` in
`pkgs/omarchy/default.nix`. `seed_dir` copies it once with `--update=none`
(`modules/home.nix:711-757`), so existing homes are untouched, as decided.

```lua
o.bind("SUPER + ALT + N", "Packages", "nixarchy-plugin nixarchy.pkg")
o.bind("SUPER + ALT + O", "Podman", "nixarchy-plugin nixarchy.podman")
o.bind("SUPER + ALT + D", "Boxes", "nixarchy-plugin nixarchy.distrobox")
o.bind("SUPER + ALT + V", "Sandboxes", "nixarchy-plugin nixarchy.microvm")
```

**Conflicts checked:**
- **Upstream defaults:** none. Every `SUPER + ALT + …` bind in
  `default/hypr/**` is F, G, K, S, comma, SLASH, SPACE, RETURN, TAB, Home, the
  arrows, the mouse wheel, or `code:10-21,34,35` (digits, minus, equal,
  brackets). N=code 57, O=32, D=40 and V=55 are not among them.
- **nixarchy's repo:** none.
- **The owner's machine:** already binds N and V to the same actions by hand
  (`~/.config/hypr/bindings.lua:338`, `microvm-binds.lua:5`), so there is no
  conflict.
- **nixarchy-microvm's own `homeManagerModules.default`** writes a V bind.
  nixarchy does not import that module.

Upstream's seed file stays unpatched in place: the four binds are appended with
an asserted anchor, the same style as the QML splices (`default.nix:1845-1919`).

### D6 — flake inputs (`flake.nix`, beside nixi at `:129-180`)

```nix
nixarchy-pkg       = { url = "github:olafkfreund/nixarchy-pkg/<rev>";       inputs.nixpkgs.follows = "nixpkgs"; };
nixarchy-podman    = { url = "github:olafkfreund/nixarchy-podman/<rev>";    inputs.nixpkgs.follows = "nixpkgs"; }; # default branch is master
nixarchy-distrobox = { url = "github:olafkfreund/nixarchy-distrobox/<rev>"; inputs.nixpkgs.follows = "nixpkgs"; };
nixarchy-microvm   = { url = "github:olafkfreund/nixarchy-microvm/<rev>";   inputs.nixpkgs.follows = "nixpkgs"; };
```

- Each input is re-exported as `packages.<sys>.nixarchy-<name>` beside `nixi`
  (`flake.nix:821`), and the module refers to that.
- `lib.inputSources` (`:1351`) carries each whole input tree onto the ISO. The
  size is measured with `nix path-info -S` on each input's `outPath` and
  recorded in `docs/internals/flake.md`. The nightly `iso-budget` is the gate.
- No cache-allowlist entries. They are file copies, and `cache-budget` confirms
  that.
- **Pin-bump procedure,** written into `docs/internals/flake.md`: change the rev
  in the URL, `nix flake lock --update-input <name>`, read the upstream diff,
  and run `checks.plugin` and `checks.menu-verbs`. `review.sh:415` reports
  tagless pins as healthy, so it cannot be relied on.

### D7 — retiring `nixarchy box` (PR D, after the plugin prerequisites)

- **Templates** are generated from `data/box-templates.nix` as
  `environment.etc."nixarchy/box-templates.json"`. The plugin reads that file,
  and there is no second copy.
- **Removed:**
  - `pkgs/box.nix`;
  - `packages.nixarchy-box` (`flake.nix:839`);
  - the `box)` verb (`modules/apps.nix:2995`) and its install (`:2922`);
  - the `trigger.box.*` rows;
  - the `nixarchy box` scans in `tests/menu-verbs.nix:117-118`;
  - the demo scene lines (`tests/demo/default.nix:519-561`), rewritten to drive
    the panel or dropped;
  - the `pkgs/verify.sh:1003-1040` wording.
- **Retargeted, with names kept:** `checks.box-template` and `checks.box-boot`
  keep their names, so `build.yml` needs no gate change. Their content changes:
  - box-template asserts that the generated JSON names real, pinned images;
  - box-boot creates a box the way the plugin does: `distrobox create` from a
    JSON template as a rootless user, and the same offline-enter assertion.
- **Human action (§4, §11):** the comments on the `build.yml` steps at `:1293`
  and `:1503` describe `nixarchy box create`. The PR proposes the new wording;
  a human merges the workflow edit.

## Alternatives rejected

- **nixarchy writes `shell.json` at activation**, as nixi does
  (`nixi hm-module.nix:206`, `enable-card.py`). That races the running shell's
  whole-file writer (Codex, finding 1).
- **Patch the vendored default `shell.json`.** See deviation 1.
- **A `graphical-session.target` oneshot.** It runs before the compositor, and
  the shell refuses (`home.nix:1440`).
- **Keep `nixarchy box` beside the panel.** The owner decided on retirement.
- **Import the plugins' own Home Manager modules** (microvm has one). They
  would be a second owner of `~/.config/hypr`. nixarchy seeds that directory
  and never manages it.

## Risks

- **Existing installs where the owner disabled a plugin by hand** get it
  enabled once, because no marker exists yet. This is accepted by the intent.
- **A shell that never answers `ping`** means no marker is written and the hook
  retries at the next login. It degrades to "not enabled yet" and never to a
  broken session.
- **`omarchy-plugin-list --json` and `enablePlugin` are upstream IPC.** An
  Omarchy bump could change them. `checks.plugin` (VM) exercises the real
  calls.
- **nixarchy-pkg's Apply** pipes `printf 'n\ny\n'` into `nixarchy-apply`. That
  only misanswers where `nixarchy-preview` is missing, and it ships in the
  omarchy package on every nixarchy machine, so it is not a blocker. #765's
  `--yes` supersedes it.
- **ISO growth** from four more input trees. Measured in PR B and checked
  against `iso-budget`.
- **The distrobox cut-over depends on the plugin's roadmap** (deviation 4). PR D
  waits for it, and until then Boxes keep working as today.

## Verification

Every check below is broken first, with the failing output kept for the PR
(§1). Local runs of `checks.options` (8 min / 11.5 GB) and of VM checks happen
only when `gh run list` shows no install in flight (§6).

| check | case | break that must turn it red |
|---|---|---|
| `options` | `homeWith {}` (no osConfig): no `nixarchy.*` plugin src, no hook file | drop the `osConfig.programs.nixarchy.enable` gate |
| `options` | `homeOn {} {}`: pkg and microvm present; podman and distrobox absent | drop the podman or boxes condition |
| `options` | `homeOn { virtualisation.podman.enable = true; }`: podman present | gate podman on boxes only |
| `options` | boxes on, podman forced false: distrobox present, podman absent | read podman from boxes instead of the option |
| `options` | `defaultPlugins.pkg = false`: pkg absent and not in the hook list | ignore the option |
| `options` | the hook text lists exactly the resolved ids | hardcode the four ids |
| `plugin` (VM) | fresh home, first login: resolved ids `enabled` in `omarchy-plugin-list --json`, widgets in `bar.layout.right` | hook exits before enabling |
| `plugin` (VM) | pre-seeded user `shell.json`: the hook enables in a live session | write `shell.json` directly instead of IPC |
| `plugin` (VM) | `omarchy plugin disable nixarchy.pkg`, then re-login: stays disabled | write the marker before the enable, or ignore it |
| `plugin` (build) | a manifest id that differs from its attribute name fails validation | remove the id assertion |
| `menu-verbs` | new scan: every `nixarchy-plugin <id>` in the menu is an installed manifest id; floor ≥ 2 | rename a row's id |
| `box-template`, `box-boot` | retargeted as in D7 | point a template at an unpinned image; create via a store-path distrobox |

`tests/plugin.nix:138` already sets `services.nixi.enable = false` so an empty
plugin directory stays reachable. It gains `defaultPlugins` set all false for
that case, and a second machine for the default-on cases.

## PR sequence

| PR | scope | depends on |
|---|---|---|
| A | `defaultPlugins`, post-boot hook, `nixarchy-plugin`, manifest-id assertion, tests with a fixture plugin, `modules/AGENTS.md` rule reversal | spec + plan approved |
| B | nixarchy-pkg input, default, `install.packages`, N bind, menu-verbs scan, ISO measurement, flake.md entry | A |
| C | podman plain catalogue row (`data/services.nix`), podman plugin, `apps.podman`, O bind | A |
| E | microvm input, default, `trigger.vm` panel row replacing children, V bind; #762 stays its own issue | A |
| D | box-templates JSON, distrobox plugin, retire `nixarchy box`, retarget box checks, D bind, docs | A + plugin: templates from JSON, promote, check, list |

E comes before D because D waits on the plugin repo. The docs change in the PR
that changes each thing: `docs/manual/{configuration,boxes,sandboxes,other-packages,getting-started}.md`,
the README feature table (and `readme-counts.sh` if a count moves), and
`tests/AGENTS.md`. Each shipped plugin also gets a Discussions announcement.
