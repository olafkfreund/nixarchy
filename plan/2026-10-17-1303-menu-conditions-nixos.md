---
status: approved
issue: 1303
spec: spec/2026-10-17-1303-menu-conditions-nixos.md
---

# Plan: Menu conditions that give the right answer on NixOS

Worktree `/mnt/data/vmtest/wt-1303`, branch `fix/1303-menu-conditions-nixos`,
based on `origin/main` `7e0ceac5`. All line numbers below were read at that
commit. Work only in this worktree.

## What was decided (from the approved spec)

Five menu rows ask Arch instead of the NixOS machine. Each fix is an override
in `modules/apps.nix` or a `substituteInPlace --replace-fail` patch in
`pkgs/omarchy/default.nix`, and every patched script gets a
`data/bin-ledger.nix` row.

1. **Out of scope:** stale scripts in a session started before a switch
   (#1306); the power-profile provider's missing `volatile` (#1305); the
   Install rows' pacman-answered `omarchy-pkg-present` guards (#1301).
2. **Hibernate** (`system.hibernate`, `when = "omarchy-hibernation-available"`).
   - In `bin/omarchy-hibernation-available` line 15, the term
     `[[ -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]` becomes a check
     that logind's `CanHibernate` answers `yes` or `challenge`.
   - The row's action is `systemctl hibernate`, which goes through logind,
     so logind's answer is right by definition. It covers
     `boot.resumeDevice` and systemd's EFI `HibernateLocation`.
     `/sys/power/resume` was rejected: it reads `0:0` on an EFI-only setup
     before the first hibernation.
   - Upstream's `/sys/power/image_size` test, its swap-size test and its
     zram exclusion stay; they can only hide the row.
   - A polkit `no` hides the row, which is correct: the action would be
     refused too.
   - No nixarchy hibernation option.
3. **The manual** (`docs/manual/troubleshooting.md:285-305`) gains the
   `resume_offset` kernel parameter: from `btrfs inspect-internal
   map-swapfile -r` on btrfs, from `filefrag -v` on ext4. The
   `omarchy-hibernation-available` ledger row goes from `vendor` to `patch`,
   loses `allow = "initrd-boot"` (the file no longer names mkinitcpio) and
   gets a new reason.
4. **Helix** (`setup.default.editor.helix`).
   - Its `when` becomes `omarchy-cmd-present hx`. `hx` is nixpkgs'
     `helix.meta.mainProgram`.
   - `omarchy-launch-editor` maps a saved `helix` to `hx` before its
     `omarchy-cmd-present "$editor" || editor="nvim"`.
   - The setter `omarchy-default-editor` and the row's `checked` keep
     upstream's `helix`.
5. **Zen** (`setup.default.browser.zen`).
   - Its `when` becomes `omarchy-cmd-present zen-beta`.
   - `zen.desktop` becomes `zen-beta.desktop` in `omarchy-default-browser`
     (setter line 28 and reader line 15) and in `omarchy-remove-browser`
     (line 63). The wrapper names the desktop file after `meta.mainProgram`,
     which is `zen-beta` for the pinned flake (measured: `nix eval --raw
     .#packages.x86_64-linux.zen-browser.meta.mainProgram` prints
     `zen-beta`).
   - The literal is the same in both places on purpose: an overridden Zen
     package hides the row instead of showing one that writes a desktop id
     the package does not ship.
6. **Snapshot rows** (`system.recovery.snapshot`,
   `system.recovery.snapshot.restore`) are emitted only when
   `config.services.snapper.configs ? home`, decided at evaluation.
   - That is the config `omarchy-snapshot` uses (`snapper --config home`).
   - A machine with a config but missing subvolumes still shows them,
     because that refusal is actionable.
7. **`cursor.pcf`.** In `omarchy-font-list`, the `grep -v -i -E
   'emoji|signwriting|omarchy'` gains `|^cursor\.pcf$`. This is not filed
   upstream; the PR body records it for the maintainer.
8. **Checks.**
   - `checks.menu-conditions` is a `runCommand` that reads the generated
     menu and the built tree.
   - `checks.hibernate-resume` is a one-node `nixosTest`.
   - The KVM CI wiring for the VM check is its own commit, proposed for a
     human to merge.
9. **Coexistence (§14).** No option nixarchy sets is added or changed. The
   snapshot gate only reads the user's own snapper config. No merged env is
   involved, so no fixture is added.

## Standing rules for every step

- **Build tiers (CLAUDE.md §6).**
  - Cheap checks run one at a time under
    `flock /mnt/data/vmtest/codex-build.lock`.
  - Building the `omarchy` package also needs
    `pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` to print `0`
    and the 1-minute load (`cut -d' ' -f1 /proc/loadavg`) to be below 12.
  - A VM check (`hibernate-resume`, or step 1's measurement) runs only when
    `gh run list --limit 8 --json status -q
    '[.[]|select(.status!="completed")]|length'` prints `0`. Otherwise wait,
    or leave it to CI.
- **Build by drv (§5).** Evaluate first, then build the drv:

  ```
  drv=$(nix eval --raw .#checks.x86_64-linux.<name>.drvPath)
  nix build "$drv^*" --print-build-logs
  ```

  Never pipe a `nix build` whose status you need. If you must, run
  `set -o pipefail` first.
- **New files.** `git add` a new file before nix can see it (§5).
- **After any `.nix` edit**, run `nix fmt`, then `git diff --stat`. A hook
  may have rewritten the file in `nixpkgs-fmt` style; `nix fmt` reverts
  that. If `--stat` shows hundreds of lines on a file you changed by a few,
  stop and investigate.
- **No heredoc and no embedded newline inside a Nix `''` string.** Use one
  line, or `printf`.
- **Shell scripts** start with `#!/usr/bin/env bash` and `set -euo
  pipefail`.
- **Never `cmd | grep -q`.** `checks.grep-q-pipefail` rejects it, and under
  pipefail it can fail spuriously. Capture first (`out=$(cmd)`), then
  `grep -q … <<<"$out"`.
- **Comments.** One to three lines at the line they protect (§7); longer
  reasoning goes in `tests/AGENTS.md`.
- **Plan step comments.** Name the step being executed in each commit body:
  `Plan step N`.

## Deviations during implementation

- **Load gate waived (2026-10-17).** The owner said "don't wait for load, run
  the builds now". Step 1's VM and step 2's package build ran with the
  1-minute load above 12. The p620-build and CI-idle gates were still
  checked, by the lead.
- **Step 1 used `--no-link`**, so no `result` link was left in the scratch
  directory. Measured: `resume` gave `yes` with disk swap and `na` with zram
  only; `noresume` gave `na` and `na`. So step 9's break 8 may also delete
  `boot.resumeDevice`.

- **Step 3: one word in a moved comment.** The `snapshot.restore` comment
  said `home-backup.restore` was "below". After the move it is above, so the
  word was changed. Everything else was moved byte for byte.

- **Step 8: actionlint ran without shellcheck.** `nix run nixpkgs#actionlint`
  hung on p620 at 0.2% CPU for 10 minutes, and was killed by pid. It was
  re-run with `-shellcheck= -pyflakes=` and exited 0. The new step is a single
  plain `run:` command, and CI runs the full lint. The commit subject also drops
  the plan's `CI:` prefix (CLAUDE.md §8).

- **Step 10: statix flagged step 5's line.** `tests/hibernate-resume.nix:5`
  assigned `omarchy = (pkgs.extend …).omarchy;`, and statix [04] asks for
  `inherit (…) omarchy;`. The plan says to amend step 5, but rewriting that
  commit needs an interactive rebase, which this environment cannot run. So
  the fix is its own commit, and the squash merge folds it in.

## Steps

0. **Preflight. No edits.**
   - `git -C /mnt/data/vmtest/wt-1303 status -s` prints nothing.
   - `git log -1 --format=%s` is the plan-approval commit.
   - `git merge-base origin/main HEAD` prints `7e0ceac5…`.
   - Read the agent bus (`read_new` on `#nixarchy-agents`) and note
     anything relevant in the PR body.

   Traps: none.

1. **Measure the logind assumption before writing any code.**
   - This is a VM: run it only when CI is idle (rule above).
   - Write `/mnt/data/vmtest/scratch-1303/measure-resume.nix`, outside the
     repo, so it is not a check:

     ```nix
     { pkgs }:
     pkgs.testers.runNixOSTest {
       name = "measure-resume";
       nodes = {
         resume = {
           virtualisation.memorySize = 1024;
           virtualisation.emptyDiskImages = [ 2048 ];
           zramSwap.enable = true;
           boot.resumeDevice = "/dev/vdb";
         };
         noresume = {
           virtualisation.memorySize = 1024;
           virtualisation.emptyDiskImages = [ 2048 ];
           zramSwap.enable = true;
         };
       };
       testScript = ''
         q = "busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate"
         start_all()
         for m in [resume, noresume]:
             m.wait_for_unit("multi-user.target")
             m.succeed("mkswap /dev/vdb && swapon /dev/vdb")
             print(m.name, "resume=", m.succeed("cat /sys/power/resume").strip(),
                   "state=", m.succeed("cat /sys/power/state").strip(),
                   "image_size=", m.succeed("cat /sys/power/image_size").strip())
             print(m.name, "swaps:", m.succeed("cat /proc/swaps"))
             print(m.name, "with disk swap:", m.succeed(q).strip())
             m.succeed("swapoff /dev/vdb")
             print(m.name, "zram only:", m.succeed(q).strip())
       '';
     }
     ```

   - Run it:

     ```
     cd /mnt/data/vmtest/wt-1303 && nix build --impure --print-build-logs \
       --expr 'import /mnt/data/vmtest/scratch-1303/measure-resume.nix { pkgs = (builtins.getFlake "git+file:///mnt/data/vmtest/wt-1303").inputs.nixpkgs.legacyPackages.x86_64-linux; }' \
       > /mnt/data/vmtest/scratch-1303/measure.log 2>&1; echo "exit=$?"
     ```

   - Then read it:

     ```
     grep -E 'resume=|with disk swap:|zram only:' /mnt/data/vmtest/scratch-1303/measure.log
     ```

   - **Gate.** The `resume` node must print a `resume=` that is not `0:0`,
     `with disk swap: s "yes"` and `zram only: s "na"`.
     - If it does not, **stop**. Report to the lead with the log, and do
       not adapt the design.
     - The `noresume` line is recorded for step 7's `tests/AGENTS.md`
       section, whatever it says.

   Traps: a VM, so the CI-idle gate applies. `/tmp` is a tmpfs: use
   `/mnt/data/vmtest`. If the build fails rather than printing, that is a
   failure to report, not a "no".

2. **Patch the five scripts, and update the ledger, in one commit.**
   - In `pkgs/omarchy/default.nix`, directly after the `chromium.desktop`
     loop's `done` (line 1378) and before the blank line and
     `# Why: pkgs/AGENTS.md#nothing-may-sed-etcpamd` (line 1380), insert,
     at the loop's indentation:

     ```
                         # nixarchy's Zen is the flake's beta, which installs zen-beta.desktop (#1303).
                         for f in omarchy-default-browser omarchy-remove-browser; do
                           substituteInPlace $out/share/omarchy/bin/$f \
                             --replace-fail 'zen.desktop' 'zen-beta.desktop'
                         done

                         # nixpkgs' helix installs `hx`: a saved `helix` fell back to nvim (#1303).
                         substituteInPlace $out/share/omarchy/bin/omarchy-launch-editor \
                           --replace-fail 'omarchy-cmd-present "$editor" || editor="nvim"' \
                             '[[ $editor == helix ]] && editor=hx; omarchy-cmd-present "$editor" || editor="nvim"'

                         # Ask logind, which runs `systemctl hibernate`, not Arch's mkinitcpio drop-in (#1303).
                         substituteInPlace $out/share/omarchy/bin/omarchy-hibernation-available \
                           --replace-fail '[[ -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]' \
                             '[[ $(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null) =~ ^s\ \"(yes|challenge)\"$ ]]'

                         # The X11 cursor glyph font is monospace to fontconfig, and is no text font (#1303).
                         substituteInPlace $out/share/omarchy/bin/omarchy-font-list \
                           --replace-fail "'emoji|signwriting|omarchy'" "'emoji|signwriting|omarchy|^cursor\.pcf$'"
     ```

     Every replacement is one line, so nixfmt has no common indent to
     lower. Check that the block contains no `''` (two single quotes in a
     row): that would end the Nix string.
   - In `data/bin-ledger.nix`:
     - `"omarchy-default-browser"` (lines 205-208): append to `reason`:
       ` It also names zen.desktop; nixarchy's Zen is the zen-browser flake's beta, which installs zen-beta.desktop, so the setter set a desktop id that does not exist and the reader never answered zen (#1303).`
     - `"omarchy-remove-browser"` (lines 471-475): append to `reason`:
       ` Its Zen fallback compared against zen.desktop, which nixarchy's Zen does not install; it names zen-beta.desktop (#1303).`
       Keep `allow`.
     - `"omarchy-hibernation-available"` (lines 246-250): replace the whole
       row with:

       ```
         "omarchy-hibernation-available" = {
           class = "patch";
           reason = "It decided hibernation was set up by testing for /etc/mkinitcpio.conf.d/omarchy_resume.conf, which only Omarchy's Arch installer writes, so a NixOS machine with swap and boot.resumeDevice never saw the Hibernate row. That term asks logind's CanHibernate instead -- the same authority `systemctl hibernate` uses. Upstream's image_size, swap-size and zram terms stay (#1303).";
         };
       ```

     - New row, inserted immediately before `"omarchy-games-retro-cores"`
       (line 238):

       ```
         "omarchy-font-list" = {
           class = "patch";
           reason = "Its fc-list :spacing=100 also matches X11's cursor glyph font, which fontconfig reports as family `cursor.pcf` wherever font-cursor-misc is installed -- NixOS adds it with services.xserver.enable. The grep -v that already drops emoji fonts also drops that family (#1303).";
         };
       ```

     - New row, inserted immediately after the `"omarchy-launch-browser"`
       row (lines 307-310):

       ```
         "omarchy-launch-editor" = {
           class = "patch";
           reason = "omarchy-default-editor saves `helix`, but nixpkgs' helix installs only `hx`, so the launcher's omarchy-cmd-present fell back to nvim. A saved `helix` is read as `hx` (#1303).";
         };
       ```

   - Verify:
     - `nix fmt; git diff --stat` shows only `pkgs/omarchy/default.nix`
       (about 20 lines) and `data/bin-ledger.nix`.
     - Build the package under the package tier:
       `drv=$(nix eval --raw .#packages.x86_64-linux.omarchy.drvPath); nix build "$drv^*" --print-build-logs -o /mnt/data/vmtest/scratch-1303/omarchy`.
       A `--replace-fail` that does not match fails here, naming the
       pattern.
     - Then, with `B=/mnt/data/vmtest/scratch-1303/omarchy/share/omarchy/bin`,
       each must print a match:
       - `grep -n 'zen-beta.desktop' $B/omarchy-default-browser $B/omarchy-remove-browser`
         (3 lines);
       - `grep -n 'editor=hx' $B/omarchy-launch-editor`;
       - `grep -n 'CanHibernate' $B/omarchy-hibernation-available`;
       - `grep -n 'cursor' $B/omarchy-font-list`.
     - And this must print nothing:
       `grep -n 'mkinitcpio\|zen\.desktop' $B/omarchy-hibernation-available $B/omarchy-default-browser $B/omarchy-remove-browser`.
     - Then the ledger check, which is cheap:
       `flock /mnt/data/vmtest/codex-build.lock sh -c 'drv=$(nix eval --raw .#checks.x86_64-linux.bin-ledger.drvPath) && nix build "$drv^*" --no-link --print-build-logs'`.
       It must pass. If it names a stale `allow` or a missing row, fix the
       ledger, not the check.
   - Commit: `Menu conditions: Zen, Helix, hibernation and font-list scripts answer for NixOS (#1303)`, with `Plan step 2` and the trailer.

   Traps:
   - The omarchy package build tier.
   - `--replace-fail` must match upstream bytes exactly. The anchors above
     were read from the built 4.0.4 tree, lines 15, 21, 6, 15/28 and 63.
   - The nixfmt hook (§5).
   - `''` inside the block.

3. **Override the Helix and Zen rows, and gate the snapshot rows.** All in
   `modules/apps.nix`.
   - **Helix and Zen.** Immediately before `"install.aur" = {` (line 617),
     inside the same attrset, add:

     ```
             # Upstream gates these on Arch's binary names (#1303): nixpkgs' helix
             # installs `hx`, nixarchy's Zen is the flake's `zen-beta`. The setter and
             # launcher patches in pkgs/omarchy/default.nix name the same binaries.
             "setup.default.editor.helix".when = "omarchy-cmd-present hx";
             "setup.default.browser.zen".when = "omarchy-cmd-present zen-beta";
     ```

     The merge script in `menuDefaults` (lines 1018-1027) copies every
     other key (label, icon, checked, action) from upstream's row, so
     `when` alone is a complete override.
   - **Snapshot rows.**
     - **Cut** the comment block and row at lines 552-566 (the comment
       starting `# Explicit \`parent\`` through `"system.recovery.snapshot.restore" = { … };`)
       and the following blank line 567.
     - **Cut** lines 578-586 (the comment starting `# Upstream's snapshots
       are taken by its updater` through `"system.recovery.snapshot" = { … };`)
       and blank line 587.
     - Then, after the attrset's closing `}` (line 846, directly before
       `# Why: modules/AGENTS.md#the-default-plugins-are-on-from-the-first-login`),
       insert:

       ```
             # Snapshots need the `home` snapper config omarchy-snapshot drives;
             # only the installer sets one, so Mode A gets no rows that only refuse (#1303).
             // lib.optionalAttrs (config.services.snapper.configs ? home) {
               <the two cut blocks, unchanged, comments included>
             }
       ```

       It joins the existing `//` chain the same way the
       `lib.optionalAttrs` that follows it does.
   - Verify:
     - `nix fmt; git diff --stat modules/apps.nix`: under about 40 lines.
     - `git diff modules/apps.nix` shows the two rows moved byte for byte.
     - Evaluation, which is cheap:

       ```
       nix eval --json .#nixosConfigurations.reference.config.services.snapper.configs --apply builtins.attrNames
       ```

       prints `["home","root"]` (reference imports `installer/host.nix`).
     - Build the reference menu:

       ```
       drv=$(nix eval --raw '.#nixosConfigurations.reference.config.environment.etc."nixarchy/omarchy-menu.jsonc".source.drvPath'); nix build "$drv^*" -o /mnt/data/vmtest/scratch-1303/menu
       ```

     - Then
       `grep -n '"system.recovery.snapshot\|"setup.default.editor.helix"\|"setup.default.browser.zen"' -A4 /mnt/data/vmtest/scratch-1303/menu`
       shows both snapshot rows, `"when": "omarchy-cmd-present hx"` and
       `"when": "omarchy-cmd-present zen-beta"`. Helix and Zen still carry
       `label`, `checked` and `action`.
   - Commit: `Menu: Helix and Zen rows look for the binaries nixpkgs installs, snapshot rows need a home snapper config (#1303)`, with `Plan step 3`.

   Traps:
   - The menu derivation builds the omarchy package (package tier).
   - The nixfmt hook.
   - `config` is already a module argument here (`modules/apps.nix:3`);
     add no new argument.
   - `tests/demo/screencast/shots.nix:339` expects `Roll back|recovery|snapshot`,
     an alternation that `Roll back` still satisfies. Leave it alone.

4. **`checks.menu-conditions`.**
   - Create `tests/menu-conditions.nix`:

     ```nix
     { inputs, pkgs }:
     # Menu conditions that must answer for the NixOS machine, not Arch (#1303).
     # Why: tests/AGENTS.md#menu-conditions-and-hibernate-resume
     let
       inherit (pkgs) lib;
       system = pkgs.stdenv.hostPlatform.system;
       reference = inputs.self.nixosConfigurations.reference;
       noSnapper = reference.extendModules {
         modules = [ { services.snapper.configs = lib.mkForce { }; } ];
       };
       menuOf = c: c.config.environment.etc."nixarchy/omarchy-menu.jsonc".source;
     in
     pkgs.runCommand "nixarchy-menu-conditions"
       {
         nativeBuildInputs = [
           pkgs.python3
           pkgs.fontconfig
         ];
         menu = menuOf reference;
         menuNoSnapper = menuOf noSnapper;
         bin = "${reference.config.programs.nixarchy.package}/share/omarchy/bin";
         hxBinary = pkgs.helix.meta.mainProgram;
         zenBinary = inputs.self.packages.${system}.zen-browser.meta.mainProgram;
         FONTCONFIG_FILE = pkgs.makeFontsConf {
           fontDirectories = [
             pkgs.font-cursor-misc
             pkgs.dejavu_fonts
           ];
         };
       }
       ''
         bash ${./menu-conditions.sh}
         touch $out
       ''
     ```

   - Create `tests/menu-conditions.sh`. It is a separate file so its
     heredoc and quoting stay out of a Nix string:

     ```bash
     #!/usr/bin/env bash
     # Run by tests/menu-conditions.nix (#1303). Env: menu menuNoSnapper bin hxBinary zenBinary.
     set -euo pipefail
     fail=0
     sect=0
     bad() { echo "  FAILED  $*" >&2; fail=1; sect=1; }
     # ok prints only when its section had no failure; each section starts with sect=0
     ok() { [ "$sect" = 1 ] || echo "  ok      $*"; sect=0; }

     # field <menu> <row-id> <key>: the value, "" if the key is absent, __absent__ if the row is.
     field() {
       python3 - "$@" <<'PY'
     import json, re, sys
     raw = open(sys.argv[1]).read()
     raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
     raw = re.sub(r",(\s*[}\]])", r"\1", raw)
     rows = json.loads(raw)
     print(rows[sys.argv[2]].get(sys.argv[3], "") if sys.argv[2] in rows else "__absent__")
     PY
     }

     work=$(mktemp -d)
     export HOME=$work/home
     export XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state \
       XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
     mkdir -p "$HOME" "$XDG_CACHE_HOME"
     unset EDITOR VISUAL BROWSER
     stubs=$work/stubs
     mkdir -p "$stubs"
     stub() { printf '#!%s\n%s\n' "$BASH" "$2" >"$stubs/$1"; chmod +x "$stubs/$1"; }
     plain=$bin:$PATH
     stubbed=$stubs:$bin:$PATH
     # status <PATH> <expr>: the exit status of a menu expression under that PATH
     status() { if env PATH="$1" bash -c "$2"; then echo 0; else echo 1; fi; }

     # --- Helix: the row looks for the binary nixpkgs installs -----------------
     when=$(field "$menu" setup.default.editor.helix when)
     [ "$when" = "omarchy-cmd-present $hxBinary" ] || bad "setup.default.editor.helix: when is '$when', not omarchy-cmd-present $hxBinary"
     [ "$(status "$plain" "$when")" = 1 ] || bad "setup.default.editor.helix: when is true with no $hxBinary on PATH"
     stub "$hxBinary" 'echo hx >>"$HOME/launched"'
     stub nvim 'echo nvim >>"$HOME/launched"'
     stub omarchy-notification-send ':'
     [ "$(status "$stubbed" "$when")" = 0 ] || bad "setup.default.editor.helix: when is false with $hxBinary on PATH"

     # --- Helix: choosing it ticks the row and opens hx, not nvim --------------
     PATH=$stubbed omarchy-default-editor helix || bad "omarchy-default-editor helix exited non-zero"
     checked=$(field "$menu" setup.default.editor.helix checked)
     [ "$(status "$stubbed" "$checked")" = 0 ] || bad "setup.default.editor.helix: not ticked after choosing it"
     PATH=$stubbed omarchy-launch-editor --inline "$work/f" || bad "omarchy-launch-editor exited non-zero"
     launched=$(cat "$HOME/launched" 2>/dev/null || echo nothing)
     [ "$launched" = hx ] || bad "launched $launched, expected hx"
     ok "Helix shows with hx, ticks, and opens hx"

     # --- Zen: row, setter and reader agree with the package -------------------
     [ "$zenBinary" = zen-beta ] || bad "the zen-browser package installs $zenBinary, and the patch and row name zen-beta"
     when=$(field "$menu" setup.default.browser.zen when)
     [ "$when" = "omarchy-cmd-present $zenBinary" ] || bad "setup.default.browser.zen: when is '$when'"
     [ "$(status "$plain" "$when")" = 1 ] || bad "setup.default.browser.zen: when is true with no $zenBinary on PATH"
     stub "$zenBinary" ':'
     [ "$(status "$stubbed" "$when")" = 0 ] || bad "setup.default.browser.zen: when is false with $zenBinary on PATH"
     stub xdg-settings 'if [ "$1" = set ]; then echo "$3" >"$HOME/xdg-set"; else cat "$HOME/xdg-get"; fi'
     PATH=$stubbed omarchy-default-browser zen || bad "omarchy-default-browser zen exited non-zero"
     wrote=$(cat "$HOME/xdg-set" 2>/dev/null || echo nothing)
     [ "$wrote" = "$zenBinary.desktop" ] || bad "setter wrote $wrote, expected $zenBinary.desktop"
     echo "$zenBinary.desktop" >"$HOME/xdg-get"
     read_back=$(PATH=$stubbed omarchy-default-browser) || bad "omarchy-default-browser (read) exited non-zero"
     [ "$read_back" = zen ] || bad "reader printed $read_back, expected zen"
     checked=$(field "$menu" setup.default.browser.zen checked)
     [ "$(status "$stubbed" "$checked")" = 0 ] || bad "setup.default.browser.zen: not ticked when $zenBinary.desktop is the default"
     remove=$(cat "$bin/omarchy-remove-browser")
     if grep -q 'zen\.desktop' <<<"$remove"; then bad "omarchy-remove-browser still names zen.desktop"; fi
     ok "Zen shows with $zenBinary, and sets and reads $zenBinary.desktop"

     # --- Hibernate: only yes or challenge from logind shows the row -----------
     [ "$(field "$menu" system.hibernate when)" = omarchy-hibernation-available ] || bad "system.hibernate no longer asks omarchy-hibernation-available"
     avail=$(cat "$bin/omarchy-hibernation-available")
     if grep -q mkinitcpio <<<"$avail"; then bad "omarchy-hibernation-available still names mkinitcpio"; fi
     term=$(grep -o '\[\[ \$(busctl [^]]*\]\]' <<<"$avail" || true)
     [ -n "$term" ] || bad "omarchy-hibernation-available has no busctl CanHibernate term"
     for answer in yes challenge no na; do
       printf 's "%s"\n' "$answer" >"$HOME/busctl-answer"
       stub busctl 'cat "$HOME/busctl-answer"'
       want=1
       case $answer in yes | challenge) want=0 ;; esac
       [ "$(status "$stubbed" "$term")" = "$want" ] || bad "busctl said $answer, row shown=$([ $want = 0 ] && echo no || echo yes)"
     done
     stub busctl 'exit 1'
     [ "$(status "$stubbed" "$term")" = 1 ] || bad "busctl failed, row shown"
     ok "Hibernate shows only for yes and challenge"

     # --- Snapshot rows: present with a home snapper config, absent without ----
     for id in system.recovery.snapshot system.recovery.snapshot.restore; do
       [ "$(field "$menu" "$id" label)" != __absent__ ] || bad "$id absent with a home snapper config"
       [ "$(field "$menuNoSnapper" "$id" label)" = __absent__ ] || bad "$id present with no home snapper config"
     done
     ok "snapshot rows follow services.snapper.configs.home"

     # --- Font list: the cursor glyph font is not a font ------------------------
     all=$(fc-list :spacing=100 -f '%{family[0]}\n')
     grep -qx 'cursor.pcf' <<<"$all" || bad "fixture: fc-list does not see cursor.pcf, so this case proves nothing"
     list=$(PATH=$plain omarchy-font-list) || bad "omarchy-font-list exited non-zero"
     grep -qx 'DejaVu Sans Mono' <<<"$list" || bad "DejaVu Sans Mono missing from the font list"
     if grep -qx 'cursor.pcf' <<<"$list"; then bad "cursor.pcf listed as a font"; fi
     ok "the font list drops cursor.pcf and keeps DejaVu Sans Mono"

     [ "$fail" = 0 ] || exit 1
     echo "menu conditions answer for the NixOS machine"
     ```

     The case lines inside `field`'s heredoc must start at column 0 in
     the real file. The indentation above belongs to this document.
   - In `flake.nix`'s `uniformChecks` list (starts line 1873), insert
     `"menu-conditions"` directly before `"menu-verbs"` (line 1985), with
     a one-line comment:
     `# Menu when/checked answers on NixOS, not Arch. See tests/menu-conditions.nix and #1303.`
   - Write step 7's `tests/AGENTS.md` section now, so that the `# Why:`
     anchors in steps 4 and 5 never point at nothing in any commit.
     Everything it needs is known from step 1.
   - `git add tests/menu-conditions.nix tests/menu-conditions.sh flake.nix tests/AGENTS.md`.
   - Verify (cheap tier; the omarchy package is already built):

     ```
     flock /mnt/data/vmtest/codex-build.lock sh -c 'drv=$(nix eval --raw .#checks.x86_64-linux.menu-conditions.drvPath) && nix build "$drv^*" --no-link --print-build-logs'
     ```

     It ends with `menu conditions answer for the NixOS machine`, and all
     five `ok` lines are printed.
   - Then check that `checks.test-registration` still passes, the same
     way.
   - Commit: `checks.menu-conditions: the Helix, Zen, Hibernate, snapshot and font rows, against stand-ins that vary each one (#1303)`, with `Plan step 4`.

   Traps:
   - New files must be `git add`ed.
   - `#!/usr/bin/env bash` and `set -euo pipefail`.
   - No `| grep -q`.
   - `HOME` and every `XDG_*` must be moved (§4, hermetic).
   - The stubs work because these upstream scripts are unwrapped
     (`tests/AGENTS.md`, "A PATH stub loses to runtimeInputs"): check that
     none of them gained a wrapper.
   - `fc-list` needs a writable cache, so `XDG_CACHE_HOME` is set.
   - `zen-browser`'s licence: the planner's `nix eval --raw
     .#packages.x86_64-linux.zen-browser.meta.mainProgram` printed
     `zen-beta`. If an evaluation here refuses it as unfree, re-run it
     with `env -u NIXPKGS_ALLOW_UNFREE` before concluding anything (§1).

5. **`checks.hibernate-resume`.**
   - Create `tests/hibernate-resume.nix`:

     ```nix
     { inputs, pkgs }:
     # The Hibernate row on a machine with resume configured, and without (#1303).
     # Why: tests/AGENTS.md#menu-conditions-and-hibernate-resume
     let
       omarchy = (pkgs.extend inputs.self.overlays.default).omarchy;
       # Only the script, so the guest does not carry the whole tree.
       avail = pkgs.runCommand "omarchy-hibernation-available" { } ''
         install -m755 ${omarchy}/share/omarchy/bin/omarchy-hibernation-available $out
       '';
     in
     pkgs.testers.runNixOSTest {
       name = "nixarchy-hibernate-resume";
       nodes.machine = {
         virtualisation.memorySize = 1024;
         virtualisation.emptyDiskImages = [ 2048 ];
         zramSwap.enable = true;
         boot.resumeDevice = "/dev/vdb";
       };
       testScript = ''
         q = "busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate"
         machine.wait_for_unit("multi-user.target")
         machine.succeed("mkswap /dev/vdb && swapon /dev/vdb")
         answer = machine.succeed(q).strip()
         assert answer == 's "yes"', f"resume configured: CanHibernate said {answer}"
         status, _ = machine.execute("${avail}")
         assert status == 0, f"omarchy-hibernation-available exited {status} with resume configured"
         machine.succeed("swapoff /dev/vdb")
         answer = machine.succeed(q).strip()
         assert answer == 's "na"', f"zram only: CanHibernate said {answer}"
         status, _ = machine.execute("${avail}")
         assert status != 0, "omarchy-hibernation-available exited 0 with only zram"
       '';
     }
     ```

   - What the second half proves: with only zram, upstream's swap-size
     term is already false, so the script exits non-zero before `busctl`
     runs. That half proves the row disappears with zram, which is a true
     and wanted claim. It is not a test of the busctl term: step 4's stub
     cases test that, and this check's first half proves logind's `yes`
     (agy).
   - In `uniformChecks`, insert `"hibernate-resume"` directly after
     `"hardware-modules"`, with the comment
     `# The Hibernate row's logind answer, in a VM with resume configured (#1303). Needs KVM.`
   - `git add tests/hibernate-resume.nix flake.nix`.
   - Verify only when CI is idle:

     ```
     drv=$(nix eval --raw .#checks.x86_64-linux.hibernate-resume.drvPath); nix build "$drv^*" --print-build-logs
     ```

     It must pass. If CI is never idle, commit anyway and say in the PR
     that the check's first run is CI's.
   - Commit: `checks.hibernate-resume: a VM with boot.resumeDevice sees the Hibernate row, and loses it with only zram (#1303)`, with `Plan step 5`.

   Traps:
   - VM tier.
   - `git add`.
   - The test script is a Nix `''` string: no heredoc, and no `''`.
   - Until step 8's CI commit lands, the generated step would try this
     check in the `omarchy` job, which has no KVM. Steps 5 to 8 are pushed
     together, never step 5 alone.

6. **The manual and its guard.**
   - `docs/manual/troubleshooting.md`, the swap-file block (lines 296-305):
     - After the line
       `boot.resumeDevice = "/dev/disk/by-uuid/<the root filesystem's UUID>";`
       add:
       `boot.kernelParams = [ "resume_offset=<the offset below>" ];`
     - After the paragraph that starts "Size it at least your RAM" (ends
       line 305), add:

       > A swap *file* also needs its offset on that partition, or the
       > machine hibernates and then boots fresh: the kernel looks for the
       > image at the start of the partition. On btrfs,
       > `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile`
       > prints it; on ext4 it is the first `physical_offset` in
       > `sudo filefrag -v /swapfile`. Once you have rebuilt and rebooted,
       > **System › Hibernate** appears in the menu.

   - `tests/swap-guard.nix`: after the `hibernat` grep block (lines
     57-61), add:

     ```
       grep -q 'boot.kernelParams = \[ "resume_offset=' ${../docs/manual/troubleshooting.md} || {
         echo "  FAILED  the manual's swap-file recipe has no resume_offset" >&2
         exit 1
       }
       echo "  ok      and its swap-file recipe sets resume_offset"
     ```

   - Verify:
     `flock /mnt/data/vmtest/codex-build.lock sh -c 'drv=$(nix eval --raw .#checks.x86_64-linux.swap-guard.drvPath) && nix build "$drv^*" --no-link --print-build-logs'`
     prints the new `ok` line. If `checks.doc-options` exists for quoted
     options, run it too; it should pass, because `boot.kernelParams` is
     real.
   - Commit: `The manual's hibernation recipe sets resume_offset, and swap-guard holds it (#1303)`, with `Plan step 6`.

   Traps: the nixfmt hook on `tests/swap-guard.nix`; the cheap tier.

7. **The holes in `tests/AGENTS.md`.** This section is written in step 4
   and committed there; this step only checks it against what step 5
   actually ran.
   - Its content: a section appended at the end,
     `## menu-conditions and hibernate-resume`, with the anchor
     `<a id="menu-conditions-and-hibernate-resume"></a>` above it, as the
     file's other sections do. It says:
     - `menu-conditions` varies each row's input with PATH stubs. That is
       sound because upstream's scripts are unwrapped. It reads the
       generated menu, as `menu-verbs` does.
     - `hibernate-resume` proves logind says `yes` with `boot.resumeDevice`
       on scripted stage 1, and `na` with zram alone. Paste the step-1
       measurement here, including the `noresume` node's answer.
     - **Holes:**
       - the swap-file `resume_offset` recipe is checked as text only;
         no VM resumes from a file;
       - systemd's EFI `HibernateLocation` path is not booted by any VM;
       - Zen is supported for the shipped beta package only: another
         variant hides the row by design.
   - Verify: `grep -n 'menu-conditions-and-hibernate-resume' tests/AGENTS.md`
     shows the anchor, and both `.nix` files' `# Why:` lines point to it.
   - If step 5's run changed anything the section says, amend it in a
     commit: `tests/AGENTS.md: hibernate-resume as it ran (#1303)`, with
     `Plan step 7`. Otherwise there is no commit.

   Traps: none.

8. **The CI-gate commit: proposed, for a human to merge.** This is a
   commit of its own.
   - `.github/scripts/generated-checks.sh`: in `claimed` (lines 37-42),
     append `hibernate-resume` after `wifi-hwsim` on line 37.
   - `.github/workflows/build.yml`, in the `box` job, directly after the
     `wifi-hwsim` step (ends line 1760), add:

     ```yaml
           # checks.hibernate-resume is a nixosTest and needs the /dev/kvm set up above (#1303).
           - name: A VM with resume configured sees the Hibernate row
             if: needs.gate.outputs.relevant == 'true'
             run: .github/scripts/build-unless-proven.sh .#checks.x86_64-linux.hibernate-resume
     ```

   - Verify:
     - Run `actionlint .github/workflows/build.yml` under the cheap tier
       (via `nix run nixpkgs#actionlint`).
     - `bash .github/scripts/generated-checks.sh generated` no longer
       prints `hibernate-resume`, and still prints `menu-conditions`.
   - Commit: `CI: build checks.hibernate-resume in the box job, which has KVM (#1303) -- proposed, a human merges`, with `Plan step 8`.

   Traps:
   - §4/§11: this is a CI-gate change. Make it, flag it, and do not
     merge it yourself.
   - The claimed list is checked both ways by `build.yml`: the name must
     also appear in a workflow, which this step's `run:` line does.

9. **§1 proofs: break, red, restore, green.** Run after steps 2-8 are
   committed; that commit is the known-good baseline. For each row below:
   1. Make the break.
   2. `git diff` to prove it landed.
   3. Stage nothing. Every file broken here is already tracked, and the
      flake reads tracked files from the working tree.
   4. Build the check by drv with `--no-link`, and capture the red output
      to `/mnt/data/vmtest/scratch-1303/proof-<n>.log`. Under `set -e`,
      write it as
      `if nix build "$drv^*" --no-link --print-build-logs >proof-<n>.log 2>&1; then echo "STILL GREEN: break <n>"; fi`.
      A red build is the expected outcome, not an abort.
   5. Restore with `git checkout HEAD -- <path>`. Not `git checkout --`,
      which restores the index: §5.
   6. Confirm `git status -s` is clean.
   7. Rebuild and see it pass.

   | n | Break | Check | Expected red line |
   |---|---|---|---|
   | 1 | `modules/apps.nix`: delete the `"setup.default.editor.helix".when` line (the row falls back to upstream's) | menu-conditions | `setup.default.editor.helix: when is 'omarchy-cmd-present helix', not omarchy-cmd-present hx` |
   | 2 | `pkgs/omarchy/default.nix`: delete the `omarchy-launch-editor` substituteInPlace (3 lines) | menu-conditions | `launched nvim, expected hx` |
   | 3 | `pkgs/omarchy/default.nix`: delete the Zen loop (4 lines) | menu-conditions | `setter wrote zen.desktop, expected zen-beta.desktop` |
   | 3a | `pkgs/omarchy/default.nix`: Zen loop's `for f in …` names only `omarchy-default-browser` | menu-conditions | `omarchy-remove-browser still names zen.desktop` |
   | 3b | `modules/apps.nix`: delete the `"setup.default.browser.zen".when` line | menu-conditions | `setup.default.browser.zen: when is 'omarchy-cmd-present zen-browser'` |
   | 4 | `pkgs/omarchy/default.nix`: widen the hibernation regex to also accept `na` (see the note below the table) | menu-conditions | `busctl said na, row shown=yes` |
   | 5 | `modules/apps.nix`: change `configs ? home` to `true` | menu-conditions | `system.recovery.snapshot present with no home snapper config` |
   | 6 | `pkgs/omarchy/default.nix`: delete the font-list substituteInPlace (2 lines) | menu-conditions | `cursor.pcf listed as a font` |
   | 7 | `docs/manual/troubleshooting.md`: delete only the `boot.kernelParams = [ "resume_offset=…" ];` line, keep the prose | swap-guard | `the manual's swap-file recipe has no resume_offset` |
   | 8 | `pkgs/omarchy/default.nix`: delete the hibernation substituteInPlace (3 lines), so the mkinitcpio test is back | hibernate-resume (VM: CI idle only) | `omarchy-hibernation-available exited 1 with resume configured` |

   - Breaks 2, 3, 4 and 6 change the omarchy package: each rebuilds it
     under the package tier.
   - Break 4, spelled out because a table cannot hold a bare pipe: in the
     replacement string, change the group `(yes` PIPE `challenge)` to
     `(yes` PIPE `challenge` PIPE `na)`, where PIPE is a plain `|` with no
     backslash. A backslash before the pipe makes it a literal character in
     bash's `=~`, so the break would turn yes and challenge red instead.
   - Break 8 reverts the script, not `boot.resumeDevice`. Deleting
     `boot.resumeDevice` is a valid second break only if step 1's
     `noresume` node printed `with disk swap: s "na"`; otherwise it
     would stay green for a reason unrelated to the check (Codex).
   - The setter and reader of `omarchy-default-browser` are one
     `--replace-fail` over one file, so they cannot be broken apart; 3
     covers both.
   - Break 8 runs only when CI is idle. If it never is, write
     "§1 proof for hibernate-resume pending an idle runner" in the PR.
     Never claim it.
   - A green result after a break means either the break did not land
     (check `git diff`), or the property is provided twice (grep the tree
     for a second source; §1).
   - No commit in this step. The logs go in the PR body.

   Traps:
   - `git checkout HEAD --`.
   - Prove each break landed.
   - Package and VM tiers.
   - Run the loop under `#!/usr/bin/env bash` if you script it.

10. **Statics, and the shape of the branch.**
    - Run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .` and
      `nix run nixpkgs#deadnix -- --fail .`.
    - `git log --oneline origin/main..HEAD` shows the intent, spec and
      plan commits, then steps 2-8. Step 8 is last.
    - `git show --stat` of each commit lists only its step's files.

    Traps: a `nix fmt -- --ci` that fails once and then passes is the
    hook being reverted (§5); amend the step that introduced it.

11. **Rebase if #1302 or anything else has landed, then re-check.**
    - `git fetch origin`, and read the status. `gh pr view 1302 --json state,mergedAt`.
    - If `origin/main` moved, `git rebase origin/main`. #1302 edits
      `modules/apps.nix` beside the snapshot rows: resolve by keeping its
      change and our move of the two rows into the `optionalAttrs` block.
    - After the rebase, `git merge-base origin/main HEAD` equals
      `git rev-parse origin/main`.
    - `git show --stat` of each commit lists only its own files (§5, the
      #922 trap).
    - Re-run `checks.menu-conditions` and `checks.bin-ledger` under the
      cheap tier.

    Traps: a stacked-PR conflict is resolved by cherry-picking our
    commits, not by merging `main` in (§8).

12. **PR. Only after the owner says to push.**
    - Title: `Menu rows ask the NixOS machine: Hibernate follows logind, Helix and Zen find their binaries, snapshots need snapper, and cursor.pcf is not a font (#1303)`.
    - The body follows `.github/PULL_REQUEST_TEMPLATE.md`. It **opens**
      with a box saying commit 8 changes CI gates
      (`generated-checks.sh`, the `box` job) and is proposed: a human
      merges it.
    - Then:
      - links to `intent/`, `spec/` and `plan/`;
      - which steps the coder did and which the lead finished;
      - each §1 red output from step 9 (captured lines);
      - the step-1 measurement;
      - a "For upstream, not filed" list: the Arch-only `when` on
        Hibernate, Helix and Zen, and `omarchy-font-list` not excluding
        the cursor font;
      - out of scope: #1301, #1305, #1306;
      - the closing line `closes #1303`.
    - Describe a skip-CI marker only in words, never literally (§8).
    - After pushing, check that `gh pr view <n> --json headRefOid` matches
      the pushed commit before reading any check (§6), and run
      `gh pr view <n> --json mergeable`.
    - Before the PR, post to `#nixarchy-agents` if something here cost
      time, for example the logind measurement result. Do not post
      progress.

    Traps:
    - Closing keywords (§8).
    - No literal skip marker.
    - `--json mergeable` before saying it will merge.

## Tests

| Check | Tier | Expected |
|---|---|---|
| `checks.menu-conditions` | cheap, after the package is built | five `ok` lines, then `menu conditions answer for the NixOS machine` |
| `checks.bin-ledger` | cheap | passes with the three changed rows and two new ones |
| `checks.swap-guard` | cheap | the new `resume_offset` ok line |
| `checks.test-registration` | cheap | passes: both new tests are in `uniformChecks` |
| `checks.hibernate-resume` | VM, CI idle only, then the `box` job | `yes` and exit 0 with disk swap; `na` and non-zero with zram only |
| `nix fmt -- --ci`, statix, deadnix, actionlint | statics | clean |

Each check's red output, from step 9, goes in the PR.

## Rollback

- Each step is its own commit.
- `git revert` of step 8 removes the CI wiring alone. The check then
  falls back to the generated step, so revert step 5 with it.
- Reverting steps 2 and 3 restores upstream's behaviour exactly: the rows
  are hidden again, and the snapshot rows show everywhere.
- No state on users' machines is written by any of this. A Helix choice
  saved as `helix` keeps working either way.
