---
status: approved
issue: 1304
author: olafkfreund
---

# Intent: Menu rows that still run Omarchy's Arch-only or imperative scripts

## Problem

Some rows in the stock Omarchy menu still run upstream scripts unchanged. On
NixOS their code paths cannot do what the row's label says. #1304 lists them.
This draft re-reads each one against the deployed tree
(`/nix/store/zlhw6r3rqm9bjs5ll913xrfcrw3g91xc-nixarchy-omarchy-tree/bin`)
and the merged menu (`/etc/nixarchy/omarchy-menu.jsonc`). They fall into four
classes, and each class needs a different outcome. Rows marked † were not in
the issue.

**1. Removal that deletes the wrong thing, or too much.** This is the class
that matters, because it loses data.

- `remove.preinstalls` runs `omarchy-remove-preinstalls`. That script calls
  `omarchy-webapp-remove-all`, which deletes *every* `.desktop` whose `Exec=`
  is `omarchy-launch-webapp`, including web apps the user made. It also calls
  `omarchy-tui-remove-all`, which does the same to every TUI wrapper. Then it
  runs `rm -f ~/.local/bin/{codex,claude,gemini,gh,…}` with no ownership test.
  On the owner's machine `~/.local/bin/claude` is a home-manager link. Finally
  it runs `omarchy-pkg-drop` on packages pacman never installed. A gum confirm
  comes first, but it says "preinstalled", which is not what gets deleted.
- 16 of the 18 `remove.development.*` rows run `omarchy-remove-dev-env`. For
  13 of them (go, python, zig, rust, java, dotnet, ocaml, clojure, scala,
  node, bun, deno, elixir), the sibling Install row was rewired to
  `nixarchy-app-enable <attr>`. The Remove row was not, because the generator
  in `modules/apps.nix` (~line 986) only rewrites a Remove row whose `when`
  says `omarchy-pkg-present`, and these test `~/.local/share/mise/installs/*`,
  `~/.rustup` or `~/.opam`. So the Install row adds a Nix selection, and the
  Remove row deletes a mise install and leaves the selection alone. The
  remaining three (rails, laravel, phoenix) have Install rows that still use
  mise too. `phoenix` shares a case arm with `elixir`, so removing Phoenix
  uninstalls Elixir and Erlang. The python arm runs `rm -rf ~/.local/bin/uv
  ~/.local/bin/uvx`, and ocaml runs `sudo rm -f /usr/local/bin/opam`, without
  checking ownership. `php.php` and `php.symfony` were already rewired to
  `nixarchy-app-disable`, so the `pacman -Rns` arms are unreachable. The issue
  says otherwise.
- † `remove.gaming.battlenet` deletes the prefix. After a second confirm it
  also deletes every GE-Proton runtime and `~/.local/share/umu`, whatever else
  uses them. Read in the script, not run.

**2. Imperative writes that the next rebuild undoes, or that contradict
declared state.** The row says it worked. A rebuild puts the old state back,
or the declared state and the machine now disagree.

- `setup.network.dns.*` (four rows) are worse than a revert. `omarchy-dns`
  re-runs itself as root through `/usr/bin/omarchy-dns`, by sudo or pkexec,
  with an FHS `PATH`. Three of the rows run it with no terminal. It writes
  `/etc/NetworkManager/conf.d/20-omarchy-dns.conf` and runs `nmcli connection
  modify` on every profile *before* it `tee`s `/etc/systemd/resolved.conf`.
  That file is a symlink into `/etc/static` (seen on the owner's machine), so
  under `set -e` the tee should fail and leave the run half applied. The
  NetworkManager changes are not in the flake, so a rebuild does not undo
  them. `data/bin-ledger.nix:229` says only that the switch "is reverted by
  the next rebuild". (Read in the script, not run.)
- `setup.security.sshd` / `remove.security.sshd`: setup gets past
  `omarchy-pkg-add openssh`, which exits 0 when `sshd` is already on PATH.
  Then both run `systemctl enable|disable --now sshd` plus `ufw`, which is
  not installed here. `openssh` is already in the services catalogue
  (`data/services.nix:80`), so this pair may belong in class 3. Remove can
  also delete `~/.ssh/authorized_keys` after its own confirm, which upstream
  intends.
- `setup.security.sudoless-docker` / `remove.…`: `usermod` / `gpasswd`
  against a group membership that `users.users.<name>.extraGroups` owns.
- `remove.security.fingerprint` / `fido2`: the PAM edits are already patched
  out. What is left is `omarchy-pkg-drop`, whose `pacman -Qq` comes back empty
  so it silently does nothing, and in the fido2 script `sudo rm -rf
  /etc/fido2`. Both then report the feature removed while PAM is still
  declared.
- † `remove.service.tailscale`: disables `tailscaled` with systemctl and runs
  `omarchy-pkg-drop`, while `services.tailscale` stays declared. The generator
  did not rewrite this row, because its arch map covers `data/apps.nix` only
  and tailscale moved to `data/services.nix`.
- `remove.gaming.geforce-now` runs `flatpak uninstall --delete-data` on an
  app that `install.flatpak.geforce-now` declares in `services.nix`. Whether
  the next activation reinstalls it is not verified.
- † `update.timezone` runs `timedatectl set-timezone`. The ledger notes that
  `time.timeZone` owns `/etc/localtime`, so the next rebuild reverts it
  (`data/bin-ledger.nix`).

**3. Dead ends where nixarchy already has the working route.** The row ends at
`omarchy-pkg-add`, which prints a declarative line and exits 1. But the thing
the row wants is already one click away elsewhere in nixarchy.

- `install.gaming.geforce-now` dies at `omarchy-pkg-add flatpak`, while
  `install.flatpak.geforce-now` works but cannot be reached (#1302).
  `data/menu-exceptions.nix` still says "needs a hand".
- `install.ai.ollama` → `programs.nixarchy.localAi` (`modules/local-ai.nix`),
  which the `setup.local-ai` row already drives.
- `install.gaming.battlenet` → `umu-launcher`, which is in
  `data/arch-extras.nix` and has no menu id.
- `update.firmware` is not a dead end, and the issue is wrong about it. If
  `fwupdmgr` is on PATH, the script skips `omarchy-pkg-add` and the
  `/usr/lib/fwupd` staging branch and runs `fwupdmgr refresh/update`. Only
  without `services.fwupd` does it stop at `omarchy-pkg-add fwupd`. Not run.
- `install.style.font.*` for a missing font: the replaced
  `omarchy-install-font` prints the declarative line. But the action is not
  wrapped in a terminal, so the click seems to do nothing.

**4. Genuinely unsupported on NixOS.** No declarative equivalent sits behind
the row, or it is out of scope.

- Not yet explained: `install.windows` / `remove.windows` (an exception says
  "out of scope"), `trigger.hardware.hybrid-gpu` (supergfxd and
  `/usr/lib/systemd/system-sleep`), `setup.direct-boot` (efibootmgr and an
  Omarchy UKI), `install.ai.hermes` (`/usr/share/hermes-desktop`), and
  `install.ai.perplexity` (a pacman package).
- Already replaced, so the script explains instead of failing:
  `setup.security.passwordless-sudo` (exits 1) and `update.config.plymouth`
  (`omarchy-refresh-plymouth`, exits 0). `style.unlock` makes the user pick a
  theme first and only then explains. Its `default` branch goes through
  `omarchy-plymouth-reset`, which exits 0, and any other choice reaches
  `omarchy-plymouth-set`, which exits 1. Here the defect is that the row looks
  like an action. #1304 overstates these.
- `setup.security.fingerprint` is patched for PAM, but it keeps a direct
  `sudo pacman -S` under its package check.
- Already disabled, with "Not available on NixOS": `install.browser.brave-origin`,
  `install.editor.sublime` and `install.ai.grok-bot`. They are still
  clickable only because the stock menu drops `disabled`, and that is #1301,
  not this issue.

**Why the suite is green.** The menu gates ask about Install rows and
packages, never about what an action does:

- `check-menu-mapping.py` looks only at Install rows whose `when` says
  `omarchy-pkg-present <arch>`.
- `tests/coverage.py`, run by `checks.options`, maps every Install leaf to an
  app or an exception, and checks only that the commands a row names exist
  (from the agy review; only the Install filter was re-checked).
- The Remove rewrite in `modules/apps.nix` is a generator, not a gate. It keys
  on the same `omarchy-pkg-present` spelling, and on `data/apps.nix` only.
- `check-bin-ledger.py` does scan every script for pacman and for writes to
  `/etc` and `/boot`. It is green because each of these scripts carries an
  `allow =` or `pacman =` reason, and nothing compares that reason with the
  menu. An `rm` in `$HOME` is not a pattern it looks for at all.

So nothing follows a Setup, Remove, Update or Style action into its script.
Some of those written reasons are wrong:

- `omarchy-setup-security-fingerprint` has the `pacman` reason *"A menu row
  modules/apps.nix overrides away, so nothing on this system reaches the
  pacman path inside it."* `setup.security.fingerprint` is not overridden,
  and the script keeps `sudo pacman -S`. `omarchy-pkg-drop` has the same
  reason, and it is reached from at least six live rows. Its pacman call is
  harmless only because `pacman -Qq` comes back empty. (For
  `omarchy-remove-dev-env` the reason holds, since its two pacman arms are
  overridden.)
- `data/menu-exceptions.nix:50` points `install.ai.ollama` at
  `programs.nixarchy.services.local-ai`, an option that does not exist.
- `data/menu-exceptions.nix` calls `install.ai.perplexity` a web app. Its
  action is `omarchy-install-and-launch`, which calls `omarchy-pkg-add`. It
  says GeForce NOW and Xbox Cloud need a hand. Xbox Cloud only writes a web
  app (Codex).

## Proposed outcome

Every visible menu row on a nixarchy machine does one of the following:

- **Class 1:** removes only what that row installed. A user's own web apps
  and TUIs, and files managed by home-manager or the Nix store, survive every
  Remove row. Where the install was declarative, Remove changes the selection,
  as its sibling Install row does.
- **Class 2:** makes the change declaratively (the selection, or the
  services catalogue), or says before it runs that the change will not
  survive a rebuild. It never reports a success the rebuild will reverse.
- **Class 3:** goes straight to nixarchy's existing route, in one click, as
  its siblings already do.
- **Class 4:** is hidden, or reads as guidance before the click. It is not an
  action that fails in a terminal.

And nobody has to remember any of it:

- A check goes red when a visible row's action reaches one of these four
  outcomes again, whatever its `when` says. The spec decides how.
- The ledger and exception reasons above say what is true.

## Affected users and systems

- Everyone on the stock Omarchy menu, which has been the default since #1283.
  The optional `nixarchy.menu` plugin reads the same merged rows.
- `modules/apps.nix` (the override spec and the Remove generator),
  `data/menu-exceptions.nix`, `data/bin-ledger.nix`, `data/services.nix` /
  `data/arch-extras.nix` where a route already exists, `pkgs/omarchy/default.nix`
  and `pkgs/omarchy/nix-bin` if a script is patched or replaced, and
  `tests/session.nix` or a static check for the probe.
- Mode A users who import `nixosModules.nixarchy` reach these rows only once
  they turn the Omarchy session on. Not verified per option.
- Edge carries the same rows. Whether quattro changed any of them is not
  checked.

## Constraints

- **Data-loss safety comes first.** No Remove row may delete a web app, TUI
  wrapper or `~/.local/bin` entry that the user created, or one that
  home-manager or the Nix store owns. A guard that is not certain leaves the
  file in place. Class 1 is not finished until a check can see a user-made web
  app and a home-manager link survive.
- **Mode A.** Nothing here may change an imported configuration that has not
  opted in. `tests/options.nix` asserts both states.
- **§2: a bug found by hand is not fixed until something can see it.** The
  probe sits at the highest layer that reaches the defect. That is a static
  check over the generated menu and the scripts it calls where one can see
  it, and `checks.session` otherwise. It must follow actions, not
  `when` spellings, which is how this class escaped every gate. §1 also
  applies: break a fixed row and watch the check go red.
- **§11 routing.** A defect that would also happen on Arch belongs upstream at
  `omacom/omarchy`, not in a patch here. Candidates are the `elixir|phoenix`
  arm, `remove-preinstalls` deleting user web apps, TUIs and unowned
  `~/.local/bin` files, and Battle.net removal deleting shared runtimes. They
  may still need a nixarchy guard until upstream ships a fix, because the
  data loss is here now. Nothing is filed upstream by an agent. A human
  decides.
- Guidance has to be visible. A row that explains instead of acting needs a
  terminal or a notification to show it in. `install.style.font.*` and three
  of the DNS rows run with neither today.
- Patches use `--replace-fail`, so an Omarchy bump that moves the text stops
  the build rather than shipping a half-patched script (`pkgs/AGENTS.md`).
- Overrides keep upstream's label and icon. A partial override renders the raw
  id (`modules/apps.nix` menuDefaults; #1305 item 1).
- Ordering with #1301: fixing `omarchy-pkg-present` in the menu's guard
  helpers makes the fingerprint, fido2, tailscale, brave-origin, hermes and
  perplexity Remove rows reachable for the first time. Those rows must be safe
  before, or together with, that fix.

## Open questions

1. One PR, or one sub-issue per class? Class 1 is data loss and could go
   first on its own. Classes 2–4 are mostly rewiring and labelling, and they
   touch the same generator.
2. For `remove.preinstalls`, should nixarchy guard ownership itself (delete
   only what a marker or the install script says it wrote), hide the row,
   or wait for upstream? This needs a decision on whether to raise it
   upstream, which only a human can do.
3. For the Remove rows that target mise (`remove.development.*`): should they
   become `nixarchy-app-disable <attr>`, as their Install siblings are
   `nixarchy-app-enable`? Or should they stay for the mise installs that
   `install.development.{rails,laravel,phoenix}` still create, and gain a
   Nix-side twin?
4. Class 2 on DNS, sshd and sudoless Docker: rewire them to the services
   catalogue or a new option, or label them as one-off, rebuild-reverts
   actions? The DNS sudoers rule was already declined
   (`data/etc-overlay.nix:154`).
5. Should the rows Codex found and the issue did not (`remove.gaming.battlenet`,
   `remove.service.tailscale`, `update.timezone`, and `install.preinstalls`,
   which is Codex's and not re-read) be in scope here, or filed separately?
6. Class 4 presentation: hide on NixOS, or keep the row disabled with a
   reason? Only the second needs #1301's `disabled` fix first.
