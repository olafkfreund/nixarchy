---
status: approved
issue: 1301
author: olafkfreund
---

# Intent: The menu decides what is installed by asking pacman, and drops the `disabled` field

## Problem

On NixOS, Omarchy's own menu shows rows it should hide and hides rows it
should show. It also lets you click rows that should be dim. There are two
separate causes. Both are in code nixarchy ships but did not write, so no
check notices either one.

**1. Package guards are answered by pacman.** Before it evaluates any
`when:` or `checked:`, `MenuModel.js` `guardHelpers()` (line 410 in the
pinned v4.0.4 source and in the deployed tree) defines bash *functions* named
`omarchy-pkg-present` and `omarchy-pkg-missing`. They are built from
`pacman -Qq` and `pacman -Qi`. A function shadows a command, so nixarchy's
Nix-aware `omarchy-pkg-present` script on PATH (`data/bin-ledger.nix:392`)
is never reached from a menu guard. On NixOS `pacman` is the refusing shim:
on this machine `pacman -Qq` prints nothing and exits 1. The set is always
empty, so inside the menu "present" is always false and "missing" is always
true.

The generated defaults (`/etc/nixarchy/omarchy-menu.jsonc`) have 47 rows
whose `when` uses these helpers:

- 41 `install.*` rows written `! omarchy-pkg-present …` are always shown.
- 6 remove rows are never shown: `remove.service.tailscale`,
  `remove.security.fingerprint`, `remove.security.fido2`,
  `remove.ai.hermes`, `remove.ai.perplexity` and `remove.browser.brave-origin`.
  `modules/apps.nix:983-1004` rewrites upstream's remove rows to read the app
  selection, but only for packages in the arch map. These six are not in it.

For a package that really is absent, the answer is right by accident. All 47
still ask the wrong source.

39 of the 41 install rows also carry nixarchy's `disabled:`. The generator
copies every upstream key that an override does not set
(`modules/apps.nix:1020-1030`), so those rows keep upstream's
`when: "! omarchy-pkg-present …"` next to nixarchy's dim condition. Today
that `when` is always true. It hides nothing only because of this bug.
Correct the guard alone, and installed apps would **disappear** from Install
instead of dimming. The two problems have to be solved together.

That code is correct on Arch, so the bug is in how nixarchy uses it. It is
not an Omarchy bug.

**2. The stock menu drops `disabled`.** `modules/apps.nix` (~:891, :917,
:933) puts a `disabled:` shell condition on 63 Install rows:

- 48 check for a command on PATH;
- 12 check for a live line in `services.nix`;
- 3 are `"true"` with "Not available on NixOS": `install.browser.brave-origin`,
  `install.editor.sublime` and `install.ai.grok-bot`.

The pinned stable Omarchy (v4.0.4, `fc7e40ba`) has no `disabled` in
`MenuModel.js` or `Menu.qml`. `normalizeItem` (`MenuModel.js:13-39`) keeps a
fixed list of keys, and `disabled` is not one of them. `guardScript` (:466)
runs only `when` and `checked`. So since #1283 made the stock menu the default
again, nothing dims:

- Install rows offer apps that are already installed. On the reporting
  machine that was 26 rows: VS Code, Cursor, Zed, Steam, Ghostty, Kitty,
  Firefox, Chrome, Brave and others. That count depends on the machine; the
  files do not determine it.
- The three "Not available on NixOS" rows can be clicked. Their override
  sets no `action`, so they inherit upstream's Arch one. For example,
  `install.editor.sublime` runs
  `omarchy-install-and-launch 'Sublime Text' sublime-text-4 sublime_text`.

The edge pin (quattro `cce8b1c`, `431c03c7` on `origin/edge`) does support
`disabled`, with `isDisabled` and a ✓ label. So this half has been solved
upstream on edge but has not reached stable. Edge still has the pacman-backed
`guardHelpers`.

**Why the suite is green.** `tests/session.nix:1520-1560` reads each row's
`disabled` from the JSON and runs it with `bash -c`. That proves the
condition gives the right answer. It does not prove the menu keeps the
condition or runs it, so it passes with both bugs present. This is the
"testing the arrangement" case in CLAUDE.md §1. Nothing runs a guard through
the menu's own `guardScript()`, so the pacman shadowing is invisible to every
check. `tests/coverage.py:104` checks only the generated text.

**Documentation that is now wrong on stable:**

- `modules/AGENTS.md:1792-1794` says a succeeding `disabled:` "leaves it
  listed but dim and unselectable, which is what upstream already uses".
- `docs/manual/development-tools.md:14` says Sublime is listed but disabled.
- `data/apps.nix:756-758` says a row "shows dim on a stock install". The
  same text reaches users through the generated `apps-template.nix`.
- `data/bin-ledger.nix:392-395` describes `omarchy-pkg-present` as the
  command that answers. It does not say that the menu shadows it.
- `data/bin-ledger.nix:380-383` and `:397-400` say no menu row reaches
  `omarchy-pkg-drop` or `omarchy-pkg-remove`. The six unmapped remove rows
  still run upstream's remove scripts (`remove.service.tailscale` runs
  `omarchy-remove-service-tailscale`). Today they are only unreachable
  because of problem 1. Correct the guard alone, and they could be shown and
  clicked.

## Proposed outcome

On every channel nixarchy ships, with whichever menu is active:

- an install row says the app is already there when it is installed or
  selected, and offers it when it is not (whether "says" means dim or hidden
  is open question 2);
- a remove row appears when its app is present, and only then;
- a row marked as not available on NixOS cannot be run, and no row runs an
  Arch install or remove path because a guard answered wrongly;
- a check fails when a guard's answer inside the menu differs from what is
  actually installed or selected. It is shown failing against today's tree
  before the fix lands (CLAUDE.md §1);
- the documentation above describes what the menu actually does.

## Affected users and systems

- **Users:** everyone on stock `omarchy.menu`, which is every machine
  installed since #1283, and anyone who switched back to it. A user who
  imports the module with `programs.nixarchy.enable = false` (Mode A) gets no
  menu defaults and is unaffected.
- **nixarchy-menu users are affected too, and the issue says otherwise.**
  In the build on this machine (`09xk34h0…-nixarchy-plugin-nixarchy.menu`),
  `providers/OmarchyMenu.qml` imports `omarchy-menu-model/MenuModel.js`. That
  file is byte-identical to the deployed stock one. The plugin parses rows
  with its `parseMenuJsonc`, so `normalizeItem` has already dropped
  `disabled`. It runs `guardScript`, so it gets the same pacman helpers.
  `NixarchyMenu.qml:961` reads `row.disabled === true`, a boolean that a
  shell-string field would never satisfy. So that build has both problems.
  The issue says nixarchy-menu "reads" `disabled`; that build does not.
  **Not checked:** whether a newer nixarchy-menu revision differs.
- **nixi** also imports `MenuModel.js` (`modules/nixos.nix:1376`). What it
  uses from the file was not checked.
- **Channels:** stable (v4.0.4) has both problems. Edge and dev have problem 1,
  and edge has upstream's own `disabled`. Behaviour on every dev revision was
  not checked.
- **Code:**
  - `modules/apps.nix`, the generator, the override rows and the arch map;
  - `pkgs/omarchy/default.nix`, if the tree is patched there;
  - `tests/session.nix`;
  - `modules/AGENTS.md`, `data/apps.nix`, `data/bin-ledger.nix` and the
    manual.

## Constraints

- **Mode A is untouched.** Everything stays behind `programs.nixarchy.enable`,
  and the off state in `tests/options.nix` keeps passing.
- **The user's menu extension still wins.**
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` is merged over the
  defaults, row by row (#210). Nothing may write to it.
- **Remove rows stay tied to the selection** for apps nixarchy manages. This
  is the `modules/AGENTS.md` rule (dim-when-the-app-is-in-the-selection):
  deselecting is the only removal nixarchy performs, and an app that came
  from the user's own configuration is not the menu's to remove.
- **Edge carries the upstream `disabled` support.** Stable must not be
  changed in a way that conflicts with it, and edge carries must keep applying
  (#1278).
- **Upstream routing (CLAUDE.md §11).** The pacman lookup is correct on Arch.
  Changing it upstream is not ours to file. Any change carried against the
  vendored tree follows `pkgs/AGENTS.md` (`--fuzz=0` or `--replace-fail`, so
  an Omarchy bump that moves the code fails the build). Never file upstream
  from this work.
- **How this stays visible (CLAUDE.md §2, §3).** The check has to judge
  rows the way the menu judges them. Running the condition strings by
  themselves, as today's check does, is not enough. It has to be shown
  failing on the current tree for both problems. The installed state has to
  vary, with at least one app present and one absent, or a check cannot
  tell "present is always false" apart from a correct answer.
- **Speed.** `guardScript` is written as one batch for speed (the comment at
  :462-465). The fix must not run a separate process per row.

## Open questions

1. **Which rows must the package guards be right for?** Two options:
   - only the rows in nixarchy's generated defaults;
   - also rows a user or a plugin adds in
     `~/.config/omarchy/extensions/omarchy-menu.jsonc` with
     `omarchy-pkg-present`.

   The second asks more of the fix, and it touches the vendored menu code.
2. **On stable, should an installed app's row look dim (with edge's ✓), or is
   hiding it acceptable until stable reaches an Omarchy release that reads
   `disabled`?** Dim is what edge, the manual and `data/apps.nix` describe.
   Hidden means stable and edge look different.
3. **For the six remove rows nixarchy does not map, what counts as
   present?** These are tailscale, fingerprint, fido2, hermes, perplexity
   and brave-origin. Today they are hidden by accident, and their actions are
   upstream's remove scripts. Brave Origin cannot be installed here at all.
   Should these rows appear at all, and if they do, do they run upstream's
   scripts? That question overlaps #1304 (Arch-only actions).
4. **Are nixarchy-menu and nixi in scope?** Both load the same `MenuModel.js`.
   nixarchy-menu lives in its own repository.
5. **Overlaps.** #1303 covers other `when`/`checked` conditions that are
   wrong on NixOS. Should it share the check asked for here, or have its own?
   #1304 covers the actions in question 3. #1305 is bugs in Omarchy's own
   menu code and is not in scope.
