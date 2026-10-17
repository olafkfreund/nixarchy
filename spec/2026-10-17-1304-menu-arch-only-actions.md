---
status: draft
issue: 1304
intent: intent/2026-10-17-1304-menu-arch-only-actions.md
---

# Spec: Menu rows that still run Omarchy's Arch-only or imperative scripts

## Design

Evidence comes from the deployed tree,
`/nix/store/rla9km5silzbp6h9dcfz0pd1p90ia8r9-nixarchy-omarchy-tree`
(written `$T` below), and from the merged menu,
`/etc/nixarchy/omarchy-menu.jsonc`. Repo line numbers are at `7e0ceac5`.

There are three mechanisms, and every change below uses one of them:

- **Menu override:** an entry in `overrideSpec` in `modules/apps.nix:342`, or
  a rule in the generator in `menuDefaults` (`modules/apps.nix:963-1060`). The
  generator already carries every key an override leaves out, so an override
  that sets only `action` and `when` keeps upstream's label and icon.
  Setting `when = "false"` hides a row, in the stock menu and in
  nixarchy-menu alike.
- **Patch:** `substituteInPlace --replace-fail` in `pkgs/omarchy/default.nix`,
  next to the existing PAM patches (`:1386-1468`).
- **Replace:** a file in `pkgs/omarchy/nix-bin` that carries the upstream
  name.

Every patch and replacement changes the script's class in `data/bin-ledger.nix`,
and `checks.bin-ledger` fails until the row agrees.

### Decisions

1. **Scope and delivery.** One spec covers all four classes. They ship as
   one PR per class, in this order: class 1 (data loss), then class 2, then
   class 4, then class 3. Class 4 comes before class 3 because it only hides
   rows, and class 3 adds new routes. Neither order is forced by #1301
   (decision 13). The plan is split
   the same way.
2. **`remove.preinstalls` (the intent's Q2): nixarchy guards ownership
   locally.** `omarchy-remove-preinstalls` is replaced in
   `pkgs/omarchy/nix-bin`. The replacement keeps upstream's confirm, marker
   file and `hyprctl reload`, but changes what it deletes:
   Ownership is tested for every path, one by one, before that path is
   deleted:
   - **Launchers.** A launcher in `~/.local/share/applications` is deleted
     only when all four hold:
     - its basename is one that `$OMARCHY_PATH/applications` ships;
     - its `Exec=` is one that upstream's helpers match: `omarchy-launch-webapp`
       or `omarchy-webapp-handler` (`$T/bin/omarchy-webapp-remove-all:15`),
       or `xdg-terminal-exec --app-id=TUI.` (`$T/bin/omarchy-tui-remove-all:15`).
       Of the 16 shipped launchers that is 13: 11 web apps (two of them handlers,
       Zoom and HEY) and 2 TUIs (Disk Usage, Docker). `foot`, `imv` and `mpv`
       are shipped too, but upstream's Remove never touched them, so neither
       does this;
     - it is a regular file (`-f` and not `-L`), so that a home-manager link
       with identical content survives, since `cmp` follows links;
     - it is byte-identical to the shipped copy (`cmp -s`).

     `omarchy-refresh-applications` seeds launchers with a plain
     `cp -f --no-preserve=mode` (`$T/bin/omarchy-refresh-applications:5`).
     Nothing rewrites them, so an unmodified seed compares equal. A launcher
     the user made or edited stays. So does a seed from an older Omarchy whose
     shipped copy has since changed. The script names each file it kept.
   - **Icons are not deleted.** A leftover PNG costs nothing, and proving
     who owns an icon would need a third test.
   - The script calls neither `omarchy-webapp-remove-all`
     (`$T/bin/omarchy-webapp-remove-all:15-30`) nor `omarchy-tui-remove-all`.
   - **`~/.local/bin` entries.** Only the names on upstream's list are
     considered (`$T/bin/omarchy-remove-preinstalls:16-18`). Each one is
     deleted only if it is a regular file, not a link, whose whole content is
     the four-line stub that `omarchy-mise-install` writes
     (`$T/bin/omarchy-mise-install:52-57`):
     - `#!/bin/bash`
     - `export MISE_MINIMUM_RELEASE_AGE=0`
     - `mise use -g --quiet …`
     - `exec mise x … -- …`

     Containing `mise use -g` somewhere is not enough, because a wrapper the
     user wrote could contain it too. `cursor-agent` and `muse` get the same
     shape test, in place of upstream's per-tool greps (`:20-31`): their
     stubs come from the same `omarchy-mise-install`. A home-manager link, a
     native install or a hand-written wrapper is never touched. The Hermes
     branch is unchanged.
   - **Packages.** `omarchy-pkg-drop` is dropped: it removes nothing here,
     because `pacman -Qq` comes back empty. In its place the script prints
     that preinstalled packages are app-selection entries, removed under
     Remove ▸ App / package.

   Whether to report upstream's unowned deletions to `omacom/omarchy` is
   **pending the owner**. Nothing is filed.

   **Restore half (`install.preinstalls`, verified).** The marker this row
   writes is read only by the two rows' own `when` guards. One is
   `install.preinstalls` (`[[ -f …/preinstalls-removed ]]`), the other
   `remove.preinstalls`. Restore, `$T/bin/omarchy-install-preinstalls:9-34`,
   reseeds the launchers and then runs `omarchy-pkg-add` on the 13 packages.
   That exits 1 for any package that is not on PATH, and Restore then stops
   before `rm -f` of the marker. So once Remove has run, the pair cannot be
   reset. Restore also reseeds through `omarchy-refresh-applications`
   (`$T/bin/omarchy-refresh-applications:5-14`), which is itself a data-loss
   path:
   - its `cp -f` overwrites an edited launcher, and replaces a home-manager
     link with a regular file, because `-f` unlinks a target it cannot open;
   - `install/user/mise.sh` → `omarchy-mise-install` runs
     `rm -f ~/.local/bin/<cmd>` and writes a stub whenever nothing outside
     `~/.local/bin` provides `<cmd>` (`pkgs/omarchy/default.nix:629-632`). A
     home-manager link at `~/.local/bin/claude` is exactly that case.

   So Restore is replaced in `nix-bin` too:
   - it copies a shipped launcher only where no file or link of that name
     exists (`[[ -e $dst || -L $dst ]]` skips);
   - it writes no mise stubs, because on nixarchy the agents are Nix packages
     and a stub shadows them (#707);
   - in place of `omarchy-pkg-add` it prints the app-selection message;
   - then it clears the marker.

   Provisioning calls the same `omarchy-refresh-applications` on first login
   (`$T/bin/omarchy-provision-user`). That path is **out of scope** here, and
   is named as a follow-up for the owner to file.
3. **`remove.development.*` (the intent's Q3).** A new generator rule
   rewrites a Remove row whose Install sibling (the same id with `install.`
   in front) is overridden to `nixarchy-app-enable <app>`, or to
   `nixarchy-service-enable <id>`. The Remove row becomes
   `nixarchy-app-disable <app>`, with the apps.nix selection-grep `when` that
   today's `omarchy-pkg-present` rule writes (`modules/apps.nix:986-1004`).
   Or it becomes `nixarchy-service-disable <id>`, with the services.nix
   marker `when` the catalogue rows use,
   `grep -qE '^[[:space:]]*[^#[:space:]].*#@ <id>([[:space:]]|$)' $HOME/.config/nixarchy/services.nix`
   (`modules/apps.nix:922-936`). Rows that are already overridden are
   skipped, as the existing rule skips them. Measured on the merged menu, the rule
   catches exactly 13 development rows (go, python, zig, rust, java, dotnet,
   ocaml, clojure, scala, node→`nodejs`, bun, deno, elixir) plus
   `remove.service.tailscale`. Codex recomputed this independently and got the
   same set. In class 3's PR, decision 11 overrides `install.gaming.geforce-now`,
   and the rule then catches `remove.gaming.geforce-now` as well, giving 15. Leftover mise installs are not removed from the
   menu any more; `mise uninstall` still works. `remove.development.rails` and
   `php.laravel` stay as upstream wrote them, because their Install rows still
   install through mise. The rails arm (`ruby)`, `:17-22`) removes mise Ruby
   and `rm -f ~/.gemrc`. Upstream's own Install wrote that file with `>`
   (`$T/bin/omarchy-install-dev-env:60`), so the pair is consistent, and it is
   left alone. `remove.development.elixir.phoenix` is hidden
   (`when = "false"`), because its arm removes Elixir and Erlang
   (`$T/bin/omarchy-remove-dev-env:61-66`). Reporting that upstream is pending
   the owner.
4. **DNS (the intent's Q4).** `omarchy-dns` is patched: with a provider
   argument, it prints the declarative route before `require_root` and exits
   1. That route is `networking.nameservers`, or the resolved and
   NetworkManager options, and stock `services.resolved` takes it. So nothing
   is written to NetworkManager or `/etc` any more
   (`$T/bin/omarchy-dns:59-68,259-265`). The no-argument query that the
   `checked` guards call is untouched. The DHCP, Cloudflare and Google rows
   get the floating-terminal wrapper that Custom already has, so the
   explanation can be seen. Custom reads its servers only after
   `require_root` (`:293-295`), so it exits before asking for them.
5. **sshd (Q4).** `setup.security.sshd` becomes `nixarchy-service-enable
   openssh` and `remove.security.sshd` becomes `nixarchy-service-disable
   openssh`. Each follows the catalogue rows' shape (`modules/apps.nix:922-936`):
   - Setup always shows, and carries the marker test as `disabled`. That is
     the catalogue Install rows' dimming, which #1301 makes the stock menu
     honour (until then it is dropped, which is harmless here; decision 13). It is not a `when`, because a negated grep on a missing
     `services.nix` would read as true.
   - Remove's `when` is the positive marker test, so it shows only while the
     service is selected.

   `install.service.openssh` is the same route. The optional
   `authorized_keys` deletion goes, and with it the only upstream action the
   Remove row had beyond the daemon.
6. **Sudoless Docker (Q4).** Both scripts are patched to print instead of
   running `usermod` / `gpasswd`
   (`$T/bin/omarchy-setup-security-sudoless-docker:32`,
   `…-remove-…:17`). The message says that nixarchy's default Docker is
   rootless and needs no group, and that the rooted daemon's group is
   `users.users.<name>.extraGroups`. Both exit 1.
7. **Fingerprint and FIDO2 removal.** The existing patches are widened, and
   both scripts become guidance with no side effects:
   - Both lose `omarchy-pkg-drop` and the "completely removed" line
     (`$T/bin/omarchy-remove-security-fingerprint:26-29`, `…-fido2:27-30`).
   - Both say that the feature stays on until the options come out, then
     exit 1.
   - The fingerprint message is corrected to "turn off `services.fprintd`;
     `fprintAuth` follows it" (`modules/nixos.nix:1779`).
   - The fingerprint script stops calling `remove_lock_fingerprint_pam`
     (`:10-14`, called before the package drop), which runs
     `sudo rm -f /etc/pam.d/omarchy-lock-fingerprint`. When
     `services.fprintd.enable` is on, `modules/nixos.nix:1778-1783` declares
     that file, so the comment at `pkgs/omarchy/default.nix:1447-1450` calling
     it "a plain file the lock screen writes" is stale and is corrected.
   - FIDO2 no longer deletes `/etc/fido2` (`:22-25`) either. While
     `security.pam.u2f` is still on, deleting the registration first could
     leave a `required` u2f stack with no keys. The message gives the order:
     drop the options, rebuild, then `sudo rm -rf /etc/fido2`.

   Both rows are also overridden with a plain-bash `when` that names no
   `omarchy-pkg-*` helper:
   - fingerprint: `command -v fprintd-enroll >/dev/null`, which is on PATH
     exactly when `services.fprintd` is on;
   - FIDO2: `[[ -e /etc/fido2 ]]`, the registration its own Setup row wrote.

   Without an override, #1301's decision 4 would hide both rows for good,
   because it hides any upstream `remove.*` row that nixarchy does not
   override and whose `when` calls `omarchy-pkg-*`. With the override, the
   rows show when there is something to explain, before #1301 and after.
8. **`setup.security.fingerprint`.** The `sudo pacman -S` under
   `omarchy-pkg-missing` (`$T/bin/omarchy-setup-security-fingerprint:24-27`)
   is replaced with the `services.fprintd.enable` line and `exit 1`. The
   ledger row's `pacman` reason goes with it.
9. **Timezone (extra row, verified).** `omarchy-menu-timezone`
   (`$T/bin/omarchy-menu-timezone:9-12`) runs `sudo timedatectl` from a menu
   row with no terminal, and there is no sudoers rule
   (`data/etc-overlay.nix:171`). On every installed machine `time.timeZone` is
   set (`installer/host.nix:586`). The patch keeps the picker and replaces
   lines 10-12 (sudo, clock refresh, success notification) with one
   notification with `time.timeZone = "<tz>";` and the
   Apply step, and exits 1. Of the two records that disagree,
   `data/bin-ledger.nix:344-347` is wrong and `data/etc-overlay.nix:171` is
   right.
10. **Battle.net (extra row, verified): no change.** Remove deletes its own
    prefix, which is what the row is for. GE-Proton and `~/.local/share/umu`
    go only after an explicit confirm (`$T/bin/omarchy-remove-gaming-battlenet:28-34`).
    Whether that confirm's wording ("downloaded by umu") is too broad is an
    upstream question, pending the owner. Install already ends at
    `omarchy-pkg-add umu-launcher`, which shows its declarative line in a
    terminal. Only the menu-exceptions reason is fixed (decision 15).
11. **Class 3 rows get the route that already exists.**
    - **`install.gaming.geforce-now`** becomes `nixarchy-service-enable
      geforce-now`, the same action `install.flatpak.geforce-now` has
      (`modules/apps.nix:910-920`). `remove.gaming.geforce-now` is then
      rewritten by decision 3's sibling rule, to `nixarchy-service-disable
      geforce-now` with the marker `when`. No hand override is needed.
    - **`install.ai.ollama`** runs `setup.local-ai`'s action,
      `omarchy-launch-floating-terminal-with-presentation nixarchy-local-ai`.
    - **Fonts.** `pkgs/omarchy/nix-bin/omarchy-install-font` re-runs itself
      inside `omarchy-launch-floating-terminal-with-presentation` when stdout
      is not a terminal, but only on the not-installed path
      (`:47-50`). An installed font still switches silently, with no
      terminal.
    - **`update.firmware`: no change.** With `services.fwupd` on it works, and
      without it, it shows `omarchy-pkg-add`'s line.
12. **Class 4 rows are hidden** (`when = "false"`). The rows are
    `install.windows`, `remove.windows`, `trigger.hardware.hybrid-gpu`,
    `setup.direct-boot`, `install.ai.hermes`, `install.ai.perplexity`,
    `remove.ai.hermes`, `remove.ai.perplexity` and
    `remove.browser.brave-origin`. Each override carries a one-line `#`
    comment saying why. These rows need rooted Docker and FHS paths, supergfxd
    and `/usr/lib/systemd/system-sleep`, an Omarchy UKI, `/usr/share/hermes-desktop`,
    or a package that is not in nixpkgs. Hiding does not depend on #1301.
    The three Install rows that already carry `disabled = "true"` and "Not
    available on NixOS" (`install.browser.brave-origin`, `install.editor.sublime`,
    `install.ai.grok-bot`) are not in this list. They are nixarchy's own rows
    (`modules/apps.nix:892-896`), and whether the stock menu honours them is
    #1301's work. This spec leaves them alone.
    - **Already guidance: no change.** `setup.security.passwordless-sudo`,
      `update.config.plymouth` and `style.unlock` already explain instead of
      failing.
13. **Ordering with #1301: either may land first.** This is agreed with
    team-1301 and recorded in #1301's spec (`f504495d`).

    Six upstream Remove rows have a `when` that calls `omarchy-pkg-present`,
    which the stock menu answers from pacman, so today it is always false:
    - `remove.service.tailscale`, rewired by decision 3
    - `remove.security.fingerprint` and `fido2`, overridden by decision 7
    - `remove.ai.hermes`, `remove.ai.perplexity` and
      `remove.browser.brave-origin`, hidden by decision 12

    #1301's decision 4 hides every upstream `remove.*` row with an
    `omarchy-pkg-*` guard that nixarchy does **not** override. Its
    `checks.menu-guards` asserts exactly that scope. #1301 changes only the
    in-shell `omarchy-pkg-present` and `omarchy-pkg-missing`; every other
    `when` evaluates as before.

    So all six rows are covered whichever PR lands first:
    - **#1301 first:** each row stays hidden until the #1304 PR that
      overrides it lands, and from then on #1301's rule leaves it alone.
    - **#1304 first:** its overrides apply. None of the `when`s here calls
      `omarchy-pkg-*`, so they mean the same before #1301 and after.

    There is one order-dependent choice. A row that may merge before #1301
    cannot rely on `disabled`, because until then the stock menu drops the
    field and the row stays clickable. That is why class 4 hides with
    `when = "false"` (decision 12). Setup sshd's `disabled` (decision 5) only
    dims the row, so before #1301 it stays clickable, and a second
    `nixarchy-service-enable openssh` changes nothing.
14. **The probe (§2).** A new static check, `checks.menu-actions`
    (`tests/menu-actions.nix` running `.github/scripts/check-menu-actions.py`),
    uses the reference-plus-boxes evaluation that `tests/menu-verbs.nix:29-42`
    already builds. For every row with an `action` whose `when` is not
    literally `false`, it scans the action string itself for the hazards
    below, and collects the `omarchy-*` commands in the action. It
    then follows each of them transitively through `$T/bin`, using
    comment-stripped bodies with a visited set. Along the way it looks for
    hazards:
    - `pacman` or `yay`
    - a call to `omarchy-pkg-drop`
    - any `PATTERNS` group from `check-bin-ledger.py:85-110`, imported rather
      than copied
    - a new `home-rm` group: `rm` naming `~/`, `$HOME/` or `~/.local/`

    Every flagged row must have an entry in a new `data/menu-actions.nix`,
    `"<row id>" = "<reason>";`. The check fails both ways: a flagged row with
    no entry, and an entry for a row that is no longer flagged. It prints the
    hazard path, for example `remove.preinstalls → omarchy-remove-preinstalls:
    home-rm`. A reason starting `hidden:` is a third kind. It asserts that the
    row's merged `when` is exactly `false`, which covers the class 4 rows
    whose scripts match no pattern, such as `setup.direct-boot` and
    `install.ai.hermes`.

    The static scan reads whole script bodies. So a script that is patched to
    explain and exit before its writers (decisions 4 and 6–9) still matches,
    and its row stays flagged. Those rows get a permanent reason that names
    the decision and the behavioural check proving it, for example
    `guidance: exits before require_root (decision 4, checks.menu-guidance)`.
    Only a row that was rewired off the script (decisions 3, 5 and 11) or
    hidden drops out, and for those the stale direction forces the entry out.

    Class 1's PR introduces the check and classifies every row flagged at the
    time. A row a later PR fixes starts with the reason `pending #1304 class N`.
    That PR rewrites the reason, or deletes the entry. Class 3's PR is the
    last one, and it adds one assertion to the check: no reason may start
    with `pending`.
    Codex approximated the flagged set from the deployed scripts and the
    real `PATTERNS`: **74 of 398 rows, 24 of them only through transitive
    calls**. Fourteen of those are default-agent rows that reach an OpenClaw
    branch through shared helpers. The plan measures the real figure first.
    The check states what it cannot see:
    - an `rm` through a variable such as `rm -rf "$PREFIX"`;
    - whether a guard actually protects the path.

    So it proves that every hazardous row is classified, not that a row is
    safe. Safety is proven per row, by the `runCommand` checks below.
    It is registered in `uniformChecks` in `flake.nix:1873`, so
    `generated-checks.sh` runs it on pull requests with no workflow edit (§4).
15. **The written records are corrected in the PR whose change makes them
    true.**
    - `data/bin-ledger.nix`: the `omarchy-pkg-drop` reason says it is
      reachable and inert because `pacman -Qq` is empty. The fingerprint row
      changes per decision 8, and the timezone row per decision 9. The
      `omarchy-dns` reason drops "reverted by the next rebuild". New rows are
      added for every script patched or replaced above.
    - `data/menu-exceptions.nix`: `install.ai.ollama` and
      `install.gaming.geforce-now` leave the file if `tests/coverage.py` counts
      an override as mapped. The plan checks this first; otherwise only their
      reasons change. `install.ai.hermes` and `install.ai.perplexity` are
      treated the same way, now that they are hidden. `install.ai.perplexity`'s
      reason, if it stays, says it is a pacman package nixpkgs lacks.
      `install.gaming.xbox-cloud` says it is a web app.
      `install.gaming.battlenet` says it ends at the declarative
      `umu-launcher` line.

**Coexistence (§14).** No NixOS option is set or changed. Every change is to
menu rows and to scripts in the Omarchy tree, so nothing merges with a user's
configuration and no fixture in `tests/coexistence/` applies. A user's own
`~/.config/omarchy/extensions/omarchy-menu.jsonc` still overrides any of these
rows by id.

## Alternatives rejected

- **Hide `remove.preinstalls` outright.** That is safe, but it takes away a
  working opt-out that upstream ships. The ownership test removes the danger
  and keeps the row.
- **Delete preinstalls by basename alone.** A user who edited a seeded
  launcher, say YouTube with another URL, would lose that edit. `cmp -s` fails
  safe instead.
- **Patch `omarchy-webapp-remove-all` instead.** `remove.webapp`'s picker and
  upstream's other callers rely on its "all" meaning. Narrowing it would
  change rows nobody asked to change.
- **Keep the mise Remove rows and add Nix twins.** That doubles the menu, and
  each mise row still offers to remove an install that the Install row
  beside it no longer makes.
- **A per-row hand list of the dev rows in `overrideSpec`.** The sibling rule
  derives them, follows upstream's ids at every bump, and also fixes
  tailscale.
- **A DNS option in nixarchy.** It would be a second vocabulary for
  `networking.nameservers`. That is the RFC 42 argument `data/services.nix`
  already makes against a wrapper.
- **`disabled` + reason for the class 4 rows listed in decision 12.** After
  #1301 the stock menu honours `disabled`: the row is dimmed, gets a ✓, and
  cannot be selected or found in search. Before #1301 it is dropped and the
  row stays clickable. The two PRs may land in either order (decision 13),
  so `when = "false"` is the only choice that is safe in both. Once #1301 has
  landed, a follow-up can turn these rows into labelled `disabled` ones. The three existing `disabled` rows are a separate
  case (decision 12).
- **Probe in `checks.session`.** That needs a VM. A static walk sees every
  hazard here more cheaply, and §2 asks for the highest layer that can see
  it, which is static.
- **Extend `check-bin-ledger.py` instead of a new check.** The ledger
  answers what a script is, not which menu row reaches it. Joining them
  would make every ledger change re-evaluate the reference machine.

## Risks

- **Over-matching in the probe.** The transitive walk can reach helpers that
  match a pattern by accident, such as heredoc prose naming `usermod` (the
  same over-match `check-bin-ledger.py:83-85` accepts). Each false positive
  costs one reasoned entry. The plan measures the flagged set before
  committing to it, and if the walk flags most of the menu, it bounds the
  depth, saying so in the PR.
- **The `cmp -s` guard keeps old seeds.** After an Omarchy bump changes a
  shipped launcher, an older seeded copy no longer matches and is kept, so
  Remove ▸ Preinstalls leaves it. That is the safe direction. The script
  names each kept file.
- **The stub shape moves.** If an Omarchy bump changes the four lines
  `omarchy-mise-install` writes, every stub stops matching and is kept. That
  is the safe direction, and the script names what it kept. The plan pins
  the shape by reading it out of the built tree's `omarchy-mise-install` in
  the test, so a drift goes red rather than quietly keeping everything.
- **Provisioning still reseeds with `cp -f` and `omarchy-mise-install`.**
  The same home-manager-link hazard exists at first login
  (`$T/bin/omarchy-provision-user`), and it is out of scope here (decision
  2). It is named as a follow-up for the owner to file.
- **The sibling rule catches a pair nobody meant.** Measured today: 13 dev
  rows and tailscale. A future bump could add a pair. The generator prints
  the rows it rewrote, and `checks.menu-actions` then sees the new action.
- **Hiding class 4 removes discoverability.** A user looking for Windows VM
  finds nothing. This is the owner's to overturn (decision 12).
- **Every host on the Omarchy session.** Rows change for everyone after
  a rebuild. Nothing changes at boot, PAM or networking: DNS and Docker now
  do less, not more.
- **Edge.** The same rows ship on edge. A quattro rewrite of any patched
  script stops the edge build at `--replace-fail`, which is the intended
  failure.

## Verification

Cheap tier only (CLAUDE.md §6). Each check runs locally under
`flock /mnt/data/vmtest/codex-build.lock`, and CI runs it through
`generated-checks.sh`.

**`checks.menu-actions`: §1 proof.**
1. Break: in a scratch commit, delete the `remove.preinstalls` entry from
   `data/menu-actions.nix`, and confirm the break landed with `git diff`.
   Expected red:
   `menu-actions: remove.preinstalls reaches omarchy-remove-preinstalls: home-rm, with no entry in data/menu-actions.nix`.
2. Break: revert decision 3's generator rule. Expected red: thirteen
   `remove.development.<x> reaches omarchy-remove-dev-env: home-rm` lines,
   plus `remove.service.tailscale … systemctl-system, omarchy-pkg-drop`.
3. Break: leave a `pending #1304 class 2` entry in place after its row is
   rewired. Expected red: `entry for remove.security.sshd, which reaches no hazard: stale`.
4. Break: un-hide `setup.direct-boot`, whose entry is `hidden: …`. Expected
   red: `setup.direct-boot is listed hidden but its when is "<upstream's>"`.
5. Break, in class 3's PR: leave any `pending` reason. Expected red:
   `pending reason left after the series: <row>`.
6. Restore with `git checkout HEAD -- <files>`, not `git checkout -- <path>`
   (§5), and check that it goes green. Every red output goes in the PR.

**The data-loss guard: `checks.remove-preinstalls`, new, in a `runCommand`.**
The fixture home is `$TMPDIR/home`. `HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`
and `XDG_CONFIG_HOME` all point inside it (§4: moving `HOME` alone is not
isolation). `OMARCHY_PATH` is the built tree. `gum confirm` is a stub that
returns 0, and `hyprctl`, `update-desktop-database`, `mise` and
`omarchy-install-hermes-cli --owns` are stubs that record their arguments.
`pacman` is the package's own refusing shim (`pkgs/omarchy/default.nix:301-302`),
so upstream's `omarchy-pkg-drop` behaves as it does on a machine: an empty
`pacman -Qq`, and nothing dropped.
Every other `omarchy-*` command comes from the built tree's `bin`, which is
first on `PATH`. That way upstream's `omarchy-webapp-remove-all` and
`omarchy-tui-remove-all` really run during the break below. The script's exit
status is captured rather than piped (§1). The script never sees the real
home. Paths below are relative to `$HOME`, and the launchers live in
`$HOME/.local/share/applications/`. The fixture holds:

| file | expect |
|---|---|
| `.local/share/applications/YouTube.desktop`, byte-identical to the shipped copy | deleted |
| `.local/share/applications/Basecamp.desktop`, with its URL edited | kept |
| `.local/share/applications/MyApp.desktop`, `Exec=omarchy-launch-webapp https://example.org` (made by the user) | kept |
| `.local/share/applications/MyTui.desktop`, `Exec=xdg-terminal-exec --app-id=TUI.mytui …` | kept |
| `.local/share/applications/Zoom.desktop` → a symlink to a fixture file byte-identical to the shipped Zoom (home-manager's shape) | kept, and so is its target |
| `.local/bin/claude` → a symlink to a fixture file whose content IS the four-line mise stub (a home-manager link) | kept, and so is its target |
| `.local/bin/codex`, a regular file holding exactly the four-line stub | deleted |
| `.local/bin/gemini`, a regular, user-written wrapper that contains `mise use -g` along with other lines | kept |
| `.local/bin/gh`, a regular file with other content | kept |
| `.local/share/applications/mpv.desktop`, byte-identical to the shipped copy (not a web app or TUI) | kept |

The check asserts the set of deleted paths equals the expected set. It also
takes a `sha256sum` of every kept file before and after, and they must
match, so it can prove nothing else changed.

§1 proof:
- Break: point the check at upstream's script, `inputs.omarchy`'s
  `bin/omarchy-remove-preinstalls`. Expected red:
  `deleted files that are not preinstalls: .local/bin/claude .local/bin/gemini .local/bin/gh .local/share/applications/Basecamp.desktop .local/share/applications/MyApp.desktop .local/share/applications/MyTui.desktop .local/share/applications/Zoom.desktop`.
  Each one is reached by an upstream line: `webapp-remove-all` takes every
  web app and handler, `tui-remove-all` takes every TUI, and the `rm -f` list
  takes `claude`, `gemini` and `gh`, link or not.
- Break: drop the `Exec=` test from the launcher branch. Expected red:
  `.local/share/applications/mpv.desktop`.
- Break: remove only the `-L` test from the `~/.local/bin` branch. Expected
  red: `.local/bin/claude`, which is a link to stub content, so only the
  `-L` test protects it. Then do the same in the launcher branch. Expected
  red: `.local/share/applications/Zoom.desktop`.
- Break: loosen the stub test to `grep -q 'mise use -g'`. Expected red:
  `.local/bin/gemini`.
- **Restore half, in the same `runCommand`:** start from the Remove run's
  end state, with the marker present and `YouTube.desktop` gone. Run the
  replaced `omarchy-install-preinstalls`, with nothing stubbed but `gum` and
  `hyprctl`. Assert three things:
  - the marker is gone;
  - `YouTube.desktop` is back;
  - every kept file still hashes the same, `Zoom.desktop` is still a link,
    and `.local/bin/claude` is still a link.

  Break: run upstream's `omarchy-install-preinstalls`, with the tree's real
  `omarchy-refresh-applications`, `omarchy-mise-install` and replaced
  `omarchy-pkg-add` on `PATH`. Expected red, any of:
  - `.local/bin/claude is no longer a link`, because `omarchy-mise-install`
    finds no `claude` outside `~/.local/bin` in the sandbox;
  - `Basecamp.desktop changed`, from the `cp -f`;
  - `preinstalls-removed still present after Restore`, because
    `omarchy-pkg-add` exits 1.
- Restore and see green. Every red output goes in the PR.

**Per-decision checks, each added in the PR that makes the change.**
- **Decision 3:** covered by break 2 of `checks.menu-actions` above.
  Nothing else asserts a generated Remove action today: `tests/options.nix`
  has no per-row menu assertions.
- **Decisions 4 and 6–9: `checks.menu-guidance`, new, in a `runCommand`.**
  It runs each patched script with the arguments its row passes:
  - `omarchy-dns Cloudflare`
  - the two sudoless-docker scripts
  - the two security Remove scripts
  - `omarchy-setup-security-fingerprint`, with `omarchy-hw-fingerprint` → 0
    and `omarchy-pkg-missing` → 0
  - `omarchy-menu-timezone`, with `omarchy-menu-select` → `Europe/Oslo`

  `PATH` starts with recording stubs for `sudo`, `pkexec`, `nmcli`, `tee`,
  `usermod`, `gpasswd`, `timedatectl`, `systemctl`, `pacman`,
  `omarchy-pkg-drop` and `omarchy-notification-send`. For each script it
  asserts three things:
  - exit status 1;
  - the declarative line is present on stderr, or in the notification for
    timezone;
  - **no** writer stub was called.

  Break: revert any one patch, for example `omarchy-dns`. Expected red:
  `omarchy-dns Cloudflare called pkexec /usr/bin/omarchy-dns Cloudflare`
  (or `sudo`). Restore, and see green.
  `checks.bin-ledger` independently turns red until each patched script's
  row says `patch`.
- **Decision 11, fonts:** `checks.menu-actions` cannot see the terminal
  wrapper, so a `runCommand` runs the replaced `omarchy-install-font` with
  stdout redirected to a file. Inside it, `fc-list` is stubbed to empty and
  the floating-terminal launcher is stubbed to record its arguments. Assert
  the launcher was called. A second run, with `fc-list` returning the
  family, asserts that the launcher was **not** called and that
  `omarchy-font-set` was. Break: drop the `-t 1` branch. Red: `the
  not-installed path wrote to a non-terminal stdout and launched no
  terminal`. Break: make the branch unconditional. Red: `the installed path
  opened a terminal`.
- **Decision 12:** `checks.menu-actions` treats a `when` of `false` as
  hidden. Break: un-hide `trigger.hardware.hybrid-gpu`. Red:
  `trigger.hardware.hybrid-gpu reaches omarchy-toggle-hybrid-gpu: etc-write, systemctl-system, with no entry`.
  Those are executed lines (`$T/bin/omarchy-toggle-hybrid-gpu:39,73`), not
  prose. `install.windows` is not used for this proof: its `modprobe` match
  is help text (`data/bin-ledger.nix:718-722`). `setup.direct-boot` and
  `install.ai.hermes` match no pattern, so they are held by their `hidden:`
  entries (break 4 above).
- **The whole series:** `nix fmt -- --ci`, statix and deadnix. Read
  `git diff --stat` after every `.nix` edit (§5, the nixpkgs-fmt hook).

**What no check here can see.** These are written into the PR and into
`tests/AGENTS.md`:
- that the stock menu really hides a `when = "false"` row. That is
  MenuModel.js behaviour, `checks.session`'s concern, and #1301's to
  assert;
- that `nixarchy-service-disable geforce-now` stops activation from
  reinstalling the Flatpak. That needs a VM with Flathub, and it is not
  tested anywhere today.
