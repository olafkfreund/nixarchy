---
status: draft
issue: 1302
author: olafkfreund
---

# Intent: Every generated menu row is reachable by browsing, and a check says so

## Problem

#1302 reports rows that cannot be reached by browsing the menu. The report came
from a static resolver run over the live menu on p620. That menu has two
layers. The first is `/etc/nixarchy/omarchy-menu.jsonc`: nixarchy's defaults
merged with the host's own `programs.nixarchy.menu.extraEntries`. The second
is the user's hand-written `~/.config/omarchy/extensions/omarchy-menu.jsonc`,
which overrides the first by id. Reading it against the code splits the
report into three groups.

**Ours, and real:**

- **`install.flatpak.geforce-now` is an orphan.** `modules/apps.nix:909-920`
  generates one `install.flatpak.<name>` row per entry in `data/flatpaks.nix`.
  Nothing generates `install.flatpak`. MenuModel.js infers a row's parent by
  dropping the last segment of its id, and Menu.qml lists a row only on the
  screen whose id equals that parent (`Menu.qml:589`). So the declarative
  GeForce NOW row (`nixarchy-service-enable geforce-now`) can only be found by
  search. Upstream's `install.gaming.geforce-now` is visible under
  Install > Gaming instead, and `data/menu-exceptions.nix:52` leaves it
  unmapped. Whether that row works is #1304's question. The fact that the
  working row is hidden is this one's. This has been true since #129
  (`570281aa`). Every row the Flatpak catalogue adds later inherits it.
- **`summon backup` and `summon restore` open the wrong thing.**
  `resolveRoute` (MenuModel.js:176-190) returns an exact id first, then the
  first alias in file order. `trigger.ask.backup`
  (`pkgs/omarchy/default.nix:151`, "Back up my config", which asks the AI
  agent) declares both words. It comes before `system.recovery`
  (`modules/apps.nix:532`, "Backup and recovery", added for #542), which
  declares the same two. So both commands run the agent prompt, not the
  recovery menu. This was verified against the live file.
- **`summon rollback` opens the agent too.** `trigger.ask.update`
  (`pkgs/omarchy/default.nix:150`, "What changed?") has the alias `rollback`.
  `system.recovery.rollback` declares no aliases, and its id is not
  `rollback`, so `resolveRoute` returns the Ask row. Only one row declares
  this alias, so a duplicate-alias rule alone would not catch it. The issue
  did not report it either.
- **Alias resolution ignores `when`.** `resolveRoute` returns the first
  matching row whether or not it is shown. `summon backup` resolves to
  `trigger.ask.backup` even on a machine with no default agent, where Ask is
  hidden (`trigger.ask`'s `when`). On a machine that has gliff but no
  FreeRDP, `summon connect` resolves to `setup.remote.connect`, which is
  hidden there by its own `when`.

**Ours, but harmless or a matter of taste.** The other alias collisions the
issue lists resolve to a sensible first row on a machine where every row is
shown: `why` goes to `trigger.ask.logs`, `ai` to `trigger.ask`, `app` to
`apps`, `remote` and `rdp` to `setup.remote`, `gliff` to
`setup.remote.gliff` (ahead of `setup.remote.gliff-manager`), and `connect`
to `setup.remote.connect`. Aliases also
feed search, where duplicates are the point. A collision matters only when the
first match is the wrong destination for that word.

**Not ours, or not true:**

- **The two restore rows are reachable.** `system.recovery.snapshot.restore`
  and `system.recovery.home-backup.restore` set
  `parent = "system.recovery"` explicitly (`modules/apps.nix:552-575`), so
  they are siblings of the backup and snapshot actions. The reason is written
  down at `modules/AGENTS.md:1840-1851`. The issue's resolver ignored the
  explicit `parent`. The rule it describes is real, though: a row with an
  `action` is a leaf (`kind = value.action ? "action" : …`), and any row whose
  effective parent is an action is unreachable.
- **`capture.meet`, `capture.note` and `capture.upload` are the host's own
  rows.** They come from `extraEntries` in the owner's
  `/etc/nixos/hosts/common/nixos/omarchy-gog.nix`, not from this repository.
  They are still orphans, and nixarchy merges them without comment
  (`modules/apps.nix:938`).
- **The `toggle`, `nixpkgs` and `options` collisions** come from the user's
  hand-written extension file. That file
  also has the action-with-children shape the issue describes:
  `trigger.record.library` sits under the action `trigger.record`.

**What lets all of this ship.** No check resolves each row's effective parent.
`build.yml`'s "Verify the generated menu defaults and app template" step,
`tests/menu-verbs.nix` and `pkgs/omarchy/check-menu.py` all parse the
generated menu. They check that it is valid JSON, how its actions and verbs
are wired, and its labels. None of them asks whether the parent exists,
whether the parent is a menu rather than an action, or whether an alias
summons the row it was meant for. The option's own documented example,
`"personal.notes"` (`modules/apps.nix:1203`), is itself an orphan. A user
copying it gets a row they can only find by search. The same option's
description says "Upstream reads a single extension file, so nixarchy manages
it" (`modules/apps.nix:1210`). The generator's own header says the opposite:
the user's extension file is untouched, and `extraEntries` goes into the
defaults file.

## Proposed outcome

- Under Install, browsing reaches the declarative Flatpak rows, GeForce NOW
  among them, without search.
- `omarchy menu summon backup`, `summon restore` and `summon rollback` open
  the destination the approver picks (open question 2), not a row the word
  reached by accident. Every alias nixarchy ships summons the row it was
  written for.
- A check on the generated menu fails, naming the row, when a row nixarchy
  ships:
  - has an effective parent that does not exist (`root` is synthesised and
    always exists);
  - has an effective parent that does not open as a submenu (an action);
  - has an alias that summons a different row from the one intended.
- A user's own `extraEntries` orphan is handled the way open question 3
  decides. Whichever way that goes, the option's example and description are
  no longer wrong.

## Affected users and systems

- Everyone on the stock `omarchy.menu` with `programs.nixarchy.enable`. The
  Flatpak rows and the `backup`/`restore` summons change for them.
- Users of `menu.extraEntries`, if the outcome includes rebuild-time feedback
  on their rows.
- `modules/apps.nix` (Flatpak rows, `system.recovery` aliases, the
  `extraEntries` example), `pkgs/omarchy/default.nix` (the `trigger.ask.*`
  and `setup.remote.*` aliases), and the menu checks (`build.yml`'s step,
  `tests/menu-verbs.nix`, or a sibling).
- The `nixarchy.menu` replacement plugin reads the same rows. Whether its
  parent and alias rules match MenuModel.js has not been checked.

## Constraints

- **The check runs against the generated `/etc/nixarchy/omarchy-menu.jsonc`,
  not against `modules/apps.nix`.** That is the file the desktop reads (§2).
  It also has to use MenuModel.js's rules: an explicit `parent` wins,
  otherwise the parent is the id minus its last segment, and `action` makes a
  row a leaf. A check that ignores explicit `parent` reports the two restore
  rows, as the issue did, and would be wrong.
- **The check must be proven to fail (§1)** for each class it claims:
  orphan, row under an action, and wrong alias destination. The failing
  output goes in the PR. It names the offending ids rather than printing a
  count (§4).
- **It runs on pull requests** as a `checks.<name>` entry or within an
  existing one (§4). It is cheap: evaluation plus a script, no VM.
- **Mode A is untouched.** Without `programs.nixarchy.enable`, nixarchy emits
  no menu (`modules/apps.nix:1268`), and nothing here may change that.
- **The user's hand-written extension file is theirs.** It is not generated,
  and nixarchy must not rewrite it. At most nixarchy tells the user about it.
- **Upstream rows are upstream's (§11).** If the check finds a defect in a row
  Omarchy ships, it is routed upstream or listed as a known exception. It is
  not patched here unprompted. #1305 owns changes to the stock menu code.
- **A user's `extraEntries` must not fail their rebuild by surprise.** Any
  feedback on user rows is a warning, not an assertion, unless the approver
  decides otherwise.
- **Existing ids keep working.** Ids are routes (`summon <id>`) and keys in
  user extension files. Nothing that works today as `summon <id>`, or as an
  override in a user's extension file, may stop working.

## Open questions

1. **How do the Flatpak rows become reachable?** Options: add an
   `install.flatpak` "Flatpak" submenu row; give each generated row an
   explicit `parent` (`install`, or the matching category such as
   `install.gaming`); or rename the ids. Each one changes what Install looks
   like, so the approver should pick.
2. **Which rows should `backup`, `restore` and `rollback` summon?** The recovery menu
   rows (drop those aliases from the `trigger.ask.*` rows) or the agent prompts (drop
   them from `system.recovery`, and leave `rollback` unclaimed there)? And should the other shared aliases (`why`,
   `ai`, `remote`, `rdp`, `connect`, `gliff`, `app`) be allowed as they are,
   or be cut down to one owner each? And does alias resolution skipping hidden
   rows belong here, or with #1305, since that means changing upstream's
   `resolveRoute`?
3. **What happens with a user's `extraEntries` orphans and action parents?**
   A NixOS `warnings` entry at evaluation, a line in a doctor command, or
   nothing beyond fixing the option's example?
4. **Does the check cover the `nixarchy.menu` plugin's parent and alias rules,
   or only stock `omarchy.menu`?** If the two resolve differently, one check
   cannot speak for both.
5. **Does #1302 close on this,** given that two of its four headline claims
   are false positives or host-local? Or is it retitled to what remains?
