---
status: draft
issue: 1320
spec: spec/2026-10-17-1320-dimmed-arch-only-rows.md
---

# Plan: Arch-only menu rows say why they can't be used, instead of vanishing

## Approved decisions (from the spec, carried over in full)

1. **Five rows are dimmed** (`disabled = "true"`), each with
   `action = "true"` and a one-line description:

   | Row | Description (exact) |
   |---|---|
   | `install.windows` | `Not available on NixOS — Omarchy's Windows VM needs rooted Docker and an FHS PATH. Use programs.virt-manager in your configuration` |
   | `trigger.hardware.hybrid-gpu` | `Not available on NixOS — Omarchy's switch writes /usr/lib/systemd/system-sleep. Use services.supergfxd in your configuration` |
   | `setup.direct-boot` | `Not available on NixOS — needs efibootmgr and an Omarchy UKI. NixOS writes its own boot entries on every rebuild` |
   | `install.ai.hermes` | `Not available on NixOS — Hermes installs itself under /usr/share/hermes-desktop, and nixpkgs has no package` |
   | `install.ai.perplexity` | `Not available on NixOS — a pacman package nixpkgs does not carry` |

   The dash is an em dash (`—`), the same as `modules/apps.nix:949`.
   Upstream's `when` is inherited unless it calls `omarchy-pkg-*`, which the
   generator drops for a row with `disabled` (`modules/apps.nix:1125`). So
   hybrid-gpu still shows only on hybrid hardware (`omarchy-hw-hybrid-gpu`),
   `install.windows` keeps its `.desktop` test, and hermes and perplexity
   lose their package guard and always show dimmed.
2. **Four Remove rows stay hidden** with `when = "false"`, and also get
   `action = "true"`: `remove.windows`, `remove.ai.hermes`,
   `remove.ai.perplexity` and `remove.browser.brave-origin`.
3. **Every `disabled = "true"` row runs `true`.** `omarchy menu summon <id>`
   runs a row's action whatever its `when` or `disabled` says (`Menu.qml:911-920`,
   omacom/omarchy#15742). The guards also have a window before their first
   evaluation, in which a dimmed row can be selected. `action = ""` is not an
   option: it turns the row into a childless menu, which is hidden. The three
   catalogue "Not available" rows (`install.browser.brave-origin`,
   `install.editor.sublime`, `install.ai.grok-bot`) get the same value, through
   the `app ? unavailable` branch. `openRoute` is **not** patched.
4. **A check can see it.** `check-menu-actions.py` asserts that every row
   whose `disabled` is literally `"true"` has `action == "true"`.
5. **Records.**
   - `data/menu-actions.nix` loses all nine `hidden:` entries.
   - `data/menu-exceptions.nix` rewords three entries to "dimmed with a reason (#1320)".
   - `tests/menu-guards.js` raises the `unavailable` floor from 3 to 6 and
     updates its comment.
6. **Out of scope:** the " ✓" on disabled rows (the owner accepted it), the
   other `when = "false"` rows (#15742's general case), and edge.
7. **Coexistence:** none. Only nixarchy's generated menu JSONC changes.

Hand-off: there are four file-editing steps across five files, so the
`coder` agent takes steps 1-4 (CLAUDE.md model split). The lead runs steps 0
and 5-7.

## Steps

0. **[lead] Baseline.** Before any edit, on `92781236`, record what the
   checks print now:
   ```bash
   cd /mnt/data/vmtest/wt-1320
   for c in menu-actions menu-guards; do
     flock /mnt/data/vmtest/codex-build.lock nix build --no-link .#checks.x86_64-linux.$c || exit 1
     nix log .#checks.x86_64-linux.$c | tail -3
   done
   ```
   Expect a `menu-actions: N rows with an action, F flagged, H hidden` line,
   and the menu-guards counts JSON with `"unavailable":3`. Keep both for the
   PR.
   Traps: these are cheap `runCommand` checks, so they may run at any time,
   one at a time, under the lock (§6 tiers). Do not pipe `nix build` into
   `tail`: the pipeline would report `tail`'s status (§1).

1. **[coder] `modules/apps.nix:852-861` and `:946-950`; `data/menu-actions.nix`.**

   a. Replace lines 852-861 (the comment `# #1304: hidden on NixOS; …` and the
      nine `.when = "false"` lines) with:
      ```nix
        # #1320: dimmed with a reason. `true` because `omarchy menu summon <id>`
        # runs a row's action whatever its when or disabled says (omacom/omarchy#15742).
        "install.windows" = {
          disabled = "true";
          action = "true";
          description = "Not available on NixOS — Omarchy's Windows VM needs rooted Docker and an FHS PATH. Use programs.virt-manager in your configuration";
        };
        "trigger.hardware.hybrid-gpu" = { … same shape, its description … };
        "setup.direct-boot" = { … };
        "install.ai.hermes" = { … };
        "install.ai.perplexity" = { … };
        # #1320: hidden, since nothing can be installed to remove; `true` for the same reason.
        "remove.windows" = { when = "false"; action = "true"; };
        "remove.ai.hermes" = { when = "false"; action = "true"; };
        "remove.ai.perplexity" = { when = "false"; action = "true"; };
        "remove.browser.brave-origin" = { when = "false"; action = "true"; };
      ```
      Each description is the exact string from decision 1.
   b. In the `app ? unavailable` branch (`:946-950`), add
      `action = "true";` beside `disabled = "true";`, with one comment line:
      `# summon would run upstream's action otherwise (omacom/omarchy#15742)`.
   c. In `data/menu-actions.nix`, delete the nine `hidden: … (decision 12)`
      entries: `install.ai.hermes` (:7), `install.windows` (:18),
      `remove.ai.hermes` (:19), `remove.ai.perplexity` (:20),
      `remove.browser.brave-origin` (:21), `remove.windows` (:37),
      `trigger.hardware.hybrid-gpu` (:80-81), `setup.direct-boot` (:95) and
      `install.ai.perplexity` (:96). Leave every other entry, and the
      `hidden:` entry for `remove.development.elixir.phoenix`.

   Verify:
   ```bash
   cd /mnt/data/vmtest/wt-1320 && nix fmt && git diff --stat && git add -A
   flock /mnt/data/vmtest/codex-build.lock nix build --no-link .#checks.x86_64-linux.menu-actions
   nix log .#checks.x86_64-linux.menu-actions | tail -1
   ```
   Expect green. The `hidden` count should be the baseline minus 5, and
   `flagged` should be unchanged.

   Also read the generated rows:
   ```bash
   # the exact menu file the check reads (tests/menu-actions.nix's `menu` input)
   m=$(nix eval --raw .#checks.x86_64-linux.menu-actions.menu) || exit 1
   nix build --no-link "$m" || exit 1
   grep -E '"(install\.windows|trigger\.hardware\.hybrid-gpu|setup\.direct-boot|install\.ai\.(hermes|perplexity)|remove\.(windows|ai\.hermes|ai\.perplexity|browser\.brave-origin)|install\.(browser\.brave-origin|editor\.sublime|ai\.grok-bot))"' "$m"
   ```
   Expected:
   - all twelve rows have `"action":"true"`;
   - the five dimmed rows and the three catalogue rows have `"disabled":"true"`;
   - `install.ai.hermes` and `install.ai.perplexity` have no `when`;
   - hybrid-gpu has `"when":"omarchy-hw-hybrid-gpu"`;
   - the four Remove rows have `"when":"false"`.

   Traps:
   - **§5, the nixpkgs-fmt hook:** after editing `apps.nix`, run `nix fmt`
     and read `git diff --stat`. A diff of hundreds of lines is the hook;
     `nix fmt` reverts it.
   - **§5, flake inputs:** a flake sees only staged files, so `git add`
     before the build.
   - **Generator:** an override that omits `action` inherits the Arch one,
     and `action = ""` hides the row. Use exactly `"true"`.
   - **`data/menu-actions.nix`:** a `hidden:` entry for a row whose `when`
     is not `false` fails the check (`check-menu-actions.py:121-125`). That is
     why all five dimmed entries must go in this same step.

2. **[coder] `.github/scripts/check-menu-actions.py:112-113`.** Directly after
   `errors = []`, add:
   ```python
   # A dimmed "Not available" row must run nothing: summon ignores disabled (omacom/omarchy#15742).
   for rid, row in sorted(menu.items()):
       if str(row.get("disabled", "")).strip() == "true" and row.get("action") != "true":
           errors.append(f'{rid} has disabled = "true" but runs {row.get("action")!r}; '
                         f"omarchy menu summon {rid} would run it (omacom/omarchy#15742)")
   ```
   It goes in the error block, not the measuring loop, so `--measure` is
   unchanged.

   Verify: `git add -A`, then build `checks.x86_64-linux.menu-actions` under
   the lock. Expect green. The new assertion is proved red in step 6.

   Traps: §1. A green result here proves nothing until step 6 has made it fail.

3. **[coder] `tests/menu-guards.js:134-136`.**
   - Change `unavailable: 3` to `unavailable: 6`.
   - Replace the comment at `:134-135` with:
     `// package-guarded is 0 on stable: hermes and perplexity are dimmed by`
     `// #1320, and a disabled row drops its package-guard when. Edge still has three.`
   - Leave `disabled-no-when` at 30, even though it rises by 2.

   Verify: `git add -A`, then build `checks.x86_64-linux.menu-guards` under
   the lock, and run `nix log … | tail -1`.
   Expect green, with:
   - `"unavailable":6`;
   - `"disabled-no-when"` at the baseline plus 2;
   - `"unported-remove"` at the baseline minus 3;
   - `"upstream-guarded-remove"` unchanged.

   Traps:
   - **The floors are minimums, so a count that rises never goes red.** Only
     the `unavailable` floor carries this change. If it reads anything other
     than 6, stop and report it rather than adjusting the floor to match.
   - **§1 read backwards:** if a different count fails, ask what it asserts
     before changing it.

4. **[coder] `data/menu-exceptions.nix:38` and `:64-67`.** Reword three
   entries:
   - `install.windows`: `"a Windows VM helper needing rooted Docker; dimmed with a reason (#1320)."`
   - `install.ai.hermes`: `"dimmed with a reason (#1320): upstream installs a binary with its own installer under /usr/share/hermes-desktop; nixpkgs has no hermes"`
   - `install.ai.perplexity`: `"dimmed with a reason (#1320): a pacman package nixpkgs does not carry, not a web app"`

   Verify:
   ```bash
   nix fmt && git diff --stat
   grep -n '1320' data/menu-exceptions.nix
   ```
   Expect three lines. `check-menu-mapping.py` needs only a non-empty
   reason, and `tests/options.nix:2343` reads only the names.

   Traps: §5 (`nix fmt`; the file is `.nix`).

5. **[lead] Lint and review the coder's diff against this plan.**
   ```bash
   nix fmt -- --ci && nix run nixpkgs#statix -- check . && nix run nixpkgs#deadnix -- --fail .
   git diff --stat 92781236
   ```
   Expect exactly these six paths:
   - `modules/apps.nix`
   - `data/menu-actions.nix`
   - `data/menu-exceptions.nix`
   - `.github/scripts/check-menu-actions.py`
   - `tests/menu-guards.js`
   - this plan, if it deviated

   Commit the code as one known-good baseline before step 6. The subject is
   a full sentence, with no `wip:` (§8).

6. **[lead] §1 break proofs.**
   - Run each break from the committed baseline.
   - Prove the break landed (`git diff` shows exactly that line).
   - `git add -A`, then build the one named check under the lock, and capture
     its red output.
   - Restore with `git checkout HEAD -- <file>`, not `git checkout --` (§5).
   - Confirm `git status` is clean before the next break.

   | # | Break | Check | Expected red |
   |---|---|---|---|
   | B1 | delete `action = "true";` from `setup.direct-boot` | `menu-actions` | `setup.direct-boot has disabled = "true" but runs 'omarchy-launch-floating-terminal-with-presentation omarchy-setup-direct-boot'; omarchy menu summon setup.direct-boot would run it`. The old walk alone stays green here |
   | B2 | delete `action = "true";` from `trigger.hardware.hybrid-gpu` | `menu-actions` | B1's message for hybrid-gpu, plus `trigger.hardware.hybrid-gpu reaches omarchy-toggle-hybrid-gpu: …, with no entry in data/menu-actions.nix` |
   | B3 | delete `action = "true";` from the `unavailable` branch | `menu-actions` | three lines: `install.browser.brave-origin`, `install.editor.sublime` and `install.ai.grok-bot` |
   | B4 | make `install.windows` `{ when = "false"; action = "true"; }` | `menu-guards` | `only 5 unavailable cases, expected at least 6` |
   | B5 | delete `disabled = "true";` from `install.ai.hermes` | `menu-guards` | `only 5 unavailable cases, expected at least 6`. B1's assertion does not fire, because the row is no longer disabled |

   If a break stays green:
   - first prove the break applied (§1);
   - then grep for a second place that provides the same property (§1).

   For B5, `install.ai.hermes` falls back to upstream's package-guard `when`.
   That is expected, and is why the floor is what catches it.

7. **[lead] PR.**
   - Link the intent, spec and plan, and paste the red output from B1-B5 into
     the template's §1 section.
   - Say which steps the coder did.
   - Use `Closes #1320`.
   - Comment on omacom/omarchy#15742 with the `disabled` case only if a human
     asks (§11).
   - Check that the build log lists `menu-actions` and `menu-guards` as run
     (§4). Do not edit a workflow.

## Tests

| Command | Expected |
|---|---|
| `nix build --no-link .#checks.x86_64-linux.menu-actions` | green; summary `hidden` = baseline − 5, `flagged` unchanged |
| `nix build --no-link .#checks.x86_64-linux.menu-guards` | green; `unavailable: 6`, `disabled-no-when` +2, `unported-remove` −3 |
| `nix fmt -- --ci`, statix, deadnix | clean |
| B1-B5 (step 6) | each red as tabled, green after restore |

Manual, on a desktop after a rebuild. This is not CI, and runs no VM:

- Install ▸ Windows is dimmed, with its reason and an arrow cursor, and does
  nothing on a click, on Enter or on Right.
- Searching "windows" does not list it.
- `omarchy menu summon setup.direct-boot` opens and runs nothing.

## Rollback

Revert the implementation commit. That restores the nine `when = "false"`
overrides, the `hidden:` entries, the old floor and the old checker. Nothing
outside the generated menu changes, so a rebuild is the whole undo, and no
user state needs cleaning.
