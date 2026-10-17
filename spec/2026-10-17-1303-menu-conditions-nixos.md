---
status: draft
issue: 1303
intent: intent/2026-10-17-1303-menu-conditions-nixos.md
---

# Spec: Menu conditions that give the right answer on NixOS

## Design

Five rows get conditions that ask the NixOS machine instead of Arch. Two of
them also get a setter fix, because a row that shows but does not work is
the same bug. Every change is either an override in `modules/apps.nix` or a
`--replace-fail` patch in `pkgs/omarchy/default.nix`, and each patched script
gets a `data/bin-ledger.nix` row.

### Decisions

1. **The stale-scripts problem is out of scope.** A running session keeps
   its old tree after a switch. That is the stale-session issue, filed
   separately by the lead.
2. **Hibernation: ask logind instead of mkinitcpio, and add no option.**
   - In `bin/omarchy-hibernation-available`, the term
     `[[ -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]` becomes "logind's
     `CanHibernate` answers `yes` or `challenge`" (via `busctl call
     org.freedesktop.login1 … CanHibernate`).
   - The row's action is `systemctl hibernate`, which goes through logind. So
     logind is the one thing whose answer is right by definition. It includes
     resume set up through `boot.resumeDevice`, and systemd's EFI
     `HibernateLocation` path that has no `resume=` at all. That second case
     is why `/sys/power/resume` is not the signal: before the first
     hibernation it can read `0:0` on a machine that can hibernate (Codex).
   - Upstream's `/sys/power/image_size` check, its swap-size check and its
     zram exclusion stay, so the patch is one `--replace-fail` term. They can
     only ever hide the row. logind sizes swap by its own rule, so on a
     machine where the two disagree, the row stays hidden although
     `systemctl hibernate` would work. That is accepted, and the VM is sized
     to clear both rules.
   - A `no` from polkit, for example from a shell with no seat, hides the
     row. That is correct, because the action would be refused too.
   - On this machine (zram only, systemd 261), logind answers `na`.
   - nixarchy gets no hibernation option. That would be a feature, it
     conflicts with the zram default (`modules/nixos.nix:2047`), and the
     manual already gives a recipe.
3. **Fix the manual's recipe instead of adding an option.**
   `docs/manual/troubleshooting.md:287-305` gains the `resume_offset` kernel
   parameter, found with `btrfs inspect-internal map-swapfile -r
   /swap/swapfile` (the recipe is btrfs, the installer's layout; on ext4
   the offset comes from `filefrag -v`). Without it a swap-file resume
   does not find the image.
   The `data/bin-ledger.nix` row for `omarchy-hibernation-available` changes
   from `vendor` to `patch`. Its current reason, that "unavailable … is
   right", is rewritten.
4. **Helix: override the row, and translate the name in the launcher.**
   - `setup.default.editor.helix` gets `when = "omarchy-cmd-present hx"` in
     `modules/apps.nix`. `hx` is nixpkgs' `helix.meta.mainProgram`.
   - `omarchy-launch-editor` maps a saved `helix` to `hx`, just before
     `omarchy-cmd-present "$editor" || editor="nvim"`. Its TUI case already
     lists `hx`.
   - The setter and the row's `checked` keep upstream's `helix`. That way
     state saved before the fix also works, and `omarchy-default-editor helix`
     typed at a shell works too.
   - Patching the setter to save `hx` was rejected; see below.
5. **Zen: limited to the package nixarchy ships, with `zen-beta` in both
   places.**
   - `setup.default.browser.zen` gets `when = "omarchy-cmd-present zen-beta"`.
   - `zen.desktop` becomes `zen-beta.desktop` in the setter and the reader of
     `omarchy-default-browser`, and in `omarchy-remove-browser`'s fallback.
     This joins the existing `chromium.desktop` loop
     (`pkgs/omarchy/default.nix:1375`).
   - Ground truth: nixpkgs' Firefox wrapper names the desktop file
     `${launcherName}.desktop` and sets `meta.mainProgram = launcherName`
     (`firefox/wrapper.nix:149,231-233,613`). The pinned zen-browser flake's
     `binaryName` is `zen-${name}` = `zen-beta` (`package.nix:46`, rev
     `ec2c94c9`).
   - The `when` names the same literal as the patch, on purpose. A
     `programs.nixarchy.apps.zen.package` override to another variant (say
     twilight) hides the row instead of showing one that writes a desktop
     id the package does not ship (Codex). Deriving the id from the selected
     package at runtime was rejected; see below.
6. **Snapshot rows: show them where the `home` snapper config exists, and
   decide that at evaluation.**
   - `system.recovery.snapshot` and `.snapshot.restore`
     (`modules/apps.nix:560`, `:581`) are emitted only when
     `config.services.snapper.configs ? home`.
   - `omarchy-snapshot` needs exactly that: it runs
     `snapper --config home …` (`nix-bin/omarchy-snapshot:150-174`). Having
     snapper installed is not enough (Codex).
   - On NixOS, `/etc/snapper/configs` is generated from that option, so the
     evaluation answer is the runtime answer, and a check can vary it without
     a VM.
   - A config whose subvolumes are missing still shows the rows. The refusal
     there is actionable (`omarchy-snapshot:63-120`); on Mode A, it is not.
7. **`cursor.pcf`: filter it here, and put it in the upstream write-up.**
   - In `omarchy-font-list`, the existing
     `grep -v -i -E 'emoji|signwriting|omarchy'` gains `|^cursor\.pcf$`.
   - The evidence says this is NixOS-specific in practice. On Arch, the
     cursor font is in `xorg-fonts-misc`. Only aalib, angband, ctwm, steam,
     xboard, xdotool, xosd and zutty require that package
     (archlinux.org, 2026-10-17), and none of them is in quattro's
     `install/omarchy-base.packages`. On NixOS, the X server module adds
     `font-cursor-misc` when `services.xserver.enable` is on.
   - The filter is still upstream's, so the defect goes in the upstream
     write-up. Nothing is filed unasked (§11).
   - The narrow exclusion was chosen over `:scalable=true`. That would also
     drop usable bitmap fonts, a wider change than the defect (Codex).
8. **The power-profile `volatile` fix moves to #1305**, which already has
   it.
9. **The Install rows' pacman-answered guards stay with #1301.**
10. **One cheap check, plus one VM check for the only fact a stub cannot
    supply.**
    - `checks.menu-conditions` (`tests/menu-conditions.nix`, a
      `runCommand`) covers everything except whether logind really says yes.
    - `checks.hibernate-resume` (a one-node `nixosTest`) covers that.
    - It needs KVM, so the PR proposes adding it to
      `.github/scripts/generated-checks.sh`'s `claimed` list, with a step
      in `build.yml`'s `box` job. That is a CI-gate change. The PR says so
      at the top, and a human decides whether it merges (§4, §11). Without
      that edit, the generated step would try to boot it in the `omarchy`
      job, which has no KVM.

### Coexistence (§14)

No NixOS option nixarchy sets is added or changed. The snapshot gate
*reads* the user's own `services.snapper.configs`. So a Mode A user who
configured a `home` snapper themselves gets working rows, and anyone else
gets none. This touches no merged env (`system.path`,
`hardware.graphics`), so a `tests/coexistence/fixtures.nix` fixture would
have no failing case to hold. None is added, per §14's last paragraph.

## Alternatives rejected

- **Hibernation via `/sys/power/resume != 0:0`.** This is what NixOS's
  scripted stage 1 writes when `boot.resumeDevice` is set
  (`stage-1-init.sh:485-508`). But it misses systemd's EFI
  `HibernateLocation` path, and it is a second opinion where logind is the
  first.
- **A `programs.nixarchy.hibernation` option.** That is a feature, not this
  bug, and it fights the zram default.
- **Saving `hx` in `omarchy-default-editor`.** The upstream `checked`
  (`== "helix"`) would then never tick, and a `helix` saved before the fix
  would still fall back to nvim.
- **Taking Zen's desktop id from the selected package at runtime.** The
  script would have to search `share/applications` directories, which is
  more code than the defect needs. Variants other than the shipped one
  are not supported today either.
- **`omarchy-cmd-present snapper` as the snapshot gate.** It shows the rows
  on a machine with snapper but no `home` config, where both actions fail.
- **`fc-list :spacing=100:scalable=true`.** This drops every bitmap
  monospace font, not only the cursor glyphs.
- **A two-node VM (zram-only and resume).** One node can do both: it is
  set up with resume, and taking its disk swap away gives the zram-only
  answer. This halves the boot cost in `box` (agy).
- **Setting `/sys/power/resume` by hand in the VM instead of setting
  `boot.resumeDevice`.** That would skip the NixOS boot path, which is
  the variable the check exists to vary.
- **Worrying that `services.snapper.configs.home = mkIf false …` leaves
  the `home` key present.** `attrsOf` pushes `mkIf` down and drops a
  false definition, so the key is absent. No extra case is needed (agy's
  concern, rejected).
- **Only fixture checks for hibernation.** Running a copy of the script
  with `/sys/power` relocated tests the script's arithmetic. It cannot
  test whether logind, given a NixOS resume config, says yes, which is
  the fact the fix depends on (§3).

## Risks

- **logind's `CanHibernate` may count things nixarchy cannot see**: polkit,
  `AllowHibernation=` in `sleep.conf`, the kernel lockdown mode.
  - A `no` from polkit hides the row, which is correct: the action would be
    refused too.
  - The VM pins `yes` with resume configured, and `na` after its disk swap
    is switched off. A disk-swap machine with no
    `resume=` on a BIOS VM is not pinned. It is measured during
    implementation and written into `tests/AGENTS.md`.
- **busctl missing or logind down.** The term is a positive match on
  `"yes"`/`"challenge"`, so a failed call hides the row. It never shows a
  row that cannot work.
- **Upstream reshapes one of the four patched scripts.** `--replace-fail`
  stops the build, which is the intent. The scripts are
  `omarchy-hibernation-available`, `omarchy-launch-editor`,
  `omarchy-default-browser`/`omarchy-remove-browser` and
  `omarchy-font-list`.
- **The zen-browser flake renames its variant.** Then the check comparing
  `zen-beta` with the flake package's `meta.mainProgram` goes red on the
  input bump, which is the point of the check.
- **The `box` job's runtime grows by one small VM.** That is about two
  minutes on KVM.
- **Ledger.** `check-bin-ledger.py` fails in both directions. So
  `omarchy-launch-editor` and `omarchy-font-list` each gain a `patch` row,
  `omarchy-hibernation-available` changes class, and the
  `omarchy-default-browser` and `omarchy-remove-browser` reasons are
  extended to cover Zen. Both already have `patch` rows for
  `chromium.desktop`. The
  hibernation row's `allow = "initrd-boot"` is dropped if the patched
  file no longer names mkinitcpio; otherwise the ledger check says it is
  stale.

## Verification

Every check follows §1: break, watch it fail, restore, watch it pass. The
failing output goes in the PR. Each break is confirmed with `git diff`
before reading the result. The cheap check runs under
`flock /mnt/data/vmtest/codex-build.lock`. The VM check runs only when
`gh run list` shows nothing in flight (§6).

`checks.menu-conditions` reads the **generated** menu from
`nixosConfigurations.reference.extendModules`, as `tests/menu-verbs.nix:30`
does, and the built omarchy tree. Its cases:

| Case | How it varies the variable | Break → expected failure |
|---|---|---|
| Helix row | Runs the row's `when` with a stub `hx` on PATH (expect 0), then without it (expect 1). Asserts the literal equals `pkgs.helix.meta.mainProgram`. | Revert the `when` override → `setup.default.editor.helix: when is false with hx on PATH` |
| Helix launcher and tick | `HOME` in a tmp dir with every `XDG_*` moved (§4). Runs `omarchy-default-editor helix`, then the row's `checked` (expect 0), then `omarchy-launch-editor --inline f`, with stubs `hx` and `nvim` that record their name. Expects `hx`. | Drop the launcher patch → `launched nvim, expected hx` |
| Zen row and id | Asserts `zen-beta` = the flake package's `meta.mainProgram`, and that the row's `when` names it. Runs `omarchy-default-browser zen` with a stub `xdg-settings` that records its argument (expects `zen-beta.desktop`). Runs the reader with the stub printing that id (expects `zen`). Asserts no `zen.desktop` is left in `omarchy-remove-browser`. | Revert the desktop-id patch → `setter wrote zen.desktop, expected zen-beta.desktop` |
| Hibernation answer parsing | A stub `busctl` prints `s "yes"`, `s "challenge"`, `s "no"` and `s "na"`, and then exits 1. Only the first two may make the patched term true. | Make the match accept anything non-empty → `busctl said na, row shown` |
| Snapshot rows | Two evaluations: reference plus `services.snapper.configs.home`, and reference with `services.snapper.configs = lib.mkForce {}` (test-only). Rows present in one, absent in the other. | Drop the gate → `system.recovery.snapshot present with no home snapper config` |
| Font list | `FONTCONFIG_FILE` names only `font-cursor-misc` (its fonts are under `share/fonts/X11/misc`, as on the live machine) and `dejavu_fonts`. First asserts a bare `fc-list :spacing=100` *does* list `cursor.pcf`, so the fixture cannot pass by finding nothing. Then runs `omarchy-font-list` and expects `DejaVu Sans Mono` and no `cursor.pcf`. | Drop the filter → `cursor.pcf listed as a font` |
| Manual | `tests/swap-guard.nix`'s existing grep of `troubleshooting.md` also requires `resume_offset`. | Delete the line → `the manual's swap-file recipe has no resume_offset` |

`checks.hibernate-resume` is one node. This is the configured-resume
variant §3 asks for, which no other VM boots with:

- Setup: `virtualisation.memorySize = 1024`, a 2 GiB
  `virtualisation.emptyDiskImages` disk made into swap, and
  `boot.resumeDevice` pointing at it. zram is left on, as nixarchy ships
  it.
- First: expect `omarchy-hibernation-available` to exit 0, and
  `CanHibernate` to be `yes`, asked as root.
- Then `swapoff` the disk. Expect exit 1 and `na`, because zram alone
  cannot hibernate.
- Break: set `boot.resumeDevice = ""`, or revert the script patch.
  Expected: `omarchy-hibernation-available exited 1 with resume
  configured`. Restore and re-run.

Only the device path is proven this way. The manual's btrfs swap-file
`resume_offset` recipe is checked as text, not by a real resume, and
`tests/AGENTS.md` says so (Codex).

Statics: `nix fmt -- --ci`, statix, deadnix, and the `bin-ledger` check, so
the new rows match the derived classes. Then `git show --stat` lists only
the planned files.
