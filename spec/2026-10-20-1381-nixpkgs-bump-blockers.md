---
status: draft
issue: 1381
intent: intent/2026-10-20-1381-nixpkgs-bump-blockers.md
---

# Spec: the nightly nixpkgs bump merges when nothing it changes is broken

Three independent fixes, shipped as three PRs, each `Refs #1381`, with the
last to merge carrying `Closes #1381`. The next nightly bump opens a fresh
PR. #1378 is left to the bot. Both points were approved with the intent.

## 1. `copilot-handoff`: a negative control that does not depend on timing

**Why it is flaky.** The control restores `| head -100` at the end of
`copilot-handoff.sh`'s five-stage pipeline
(`.github/scripts/copilot-handoff.sh:43-48`), and expects the stub's
500-line log (`tests/copilot-handoff/gh:31-35`) to make an upstream stage
die of SIGPIPE. That only happens if `head` exits *while an earlier stage
still has output to write*. The stages each read about 30 KB, which fits
within one 64 KiB pipe buffer, and on a fast or idle runner they finish
before `head` has read 100 lines. Then nobody writes after `head` exits,
nobody gets SIGPIPE, and the control "passes". That is exactly #1378's
failure.

**Design.** Make SIGPIPE certain by making the upstream output larger
than every pipe buffer between the stages:
- In `tests/copilot-handoff/gh`, emit **20 000** matching lines instead of
  500, which is about 1.3 MB.
- Every stage's output is then far more than 64 KiB, so stages are still
  writing, blocked on a full pipe, when `head -100` exits, and their next
  `write()` gets SIGPIPE whatever the scheduling. It is deterministic by
  size, not by speed.

**Also changed:**
- `tests/copilot-handoff.nix`'s two comments that say 500.
- Its failure message ("raise the line count"), which now names the
  pipe-buffer reason.

The fixed script (`sed -n '1,100p'`) reads to EOF, so it is unaffected,
apart from reading 1.3 MB in a sandbox, which takes milliseconds.

**Rejected:**
- A `sleep` in a stage: that is still timing.
- Asserting on `PIPESTATUS` directly: it does not test the shipped
  script.
- Dropping the control: §1 forbids a check that cannot fail.

## 2. Qt 6.12's `Color` singleton shadows ours: every QML plugin, not only nixi (revised 2026-10-20)

**Measured** (plan step B1, a repro under Qt's `qml` tool, offscreen,
in `/mnt/data/vmtest/qt612-repro`). A module singleton named `Color`,
referenced unqualified:

| | Qt 6.11.2 | Qt 6.12.0 |
|---|---|---|
| `import QtQuick` + `import Commons` → `Color` | our singleton (`Color_QMLTYPE`) | **`QQuickColor`**, Qt's own new singleton: `Color.menu` is `undefined` |
| the same, with `QtQuick.Controls` too | ours | `QQuickColor` |
| `import Commons as Commons` → `Commons.Color` | ours | **ours** |

So the shadowing comes from `QtQuick` itself, not `QtQuick.Controls`; the
original hypothesis was wrong in that detail. The qualified fix works on
both versions. Upstream hit the same thing and fixed it the same way:
omacom/omarchy#14553, "Qualify shell palette references for Qt 6.12".
Omarchy has no unqualified `Color.` left, which is why its shell logged
nothing.

**The scope is wider than nixi.** A scan of every flake input's QML for an
unqualified `Color.` finds 16 plugin repositories, all
`olafkfreund/*`: ai-mirror, nixarchy-devenv, -distrobox, -flatsnap,
-ghtui, -gliff-manager, -gltui, -herdr, -hyprsettngs, -menu, -microvm,
-pkg, -plugin-browser, -podman, -voice, and nixi-nixarchy. It also finds
nixarchy's own `pkgs/rebuild-panel/{Panel,RebuildView}.qml`.
`checks.session` caught only nixi because nixi is the only one of these
panels the VM test opens. On Qt 6.12 every other one would render
without its palette, with nothing red.

**Design:**

1. **Each affected repository** gets the same mechanical change:
   - add `import qs.Commons as Commons`;
   - qualify every `Color.` as `Commons.Color.` (match `\bColor\.`, never
     `textColor.`);
   - `Style.` may stay unqualified, since Qt 6.12 adds no `Style`;
   - one PR per repository, merged by the owner, then released at a
     tag or commit.
2. **`pkgs/rebuild-panel`** gets the same change, in this repository.
3. **One nixarchy PR** moves all 16 pins (`flake.nix` + `flake.lock`),
   each pin comment gaining a line.
4. **A new guard, `checks.qml-color-qualified`** (cheap, `runCommand`): it
   greps the QML of every plugin nixarchy ships (each plugin input's
   source, and `pkgs/rebuild-panel`) for an unqualified `Color.`, and
   fails naming each file and line. This is §2's rule: the session check
   saw one panel of seventeen, so the class of bug gets a probe that sees
   all of them. It also catches the next plugin someone adds.

`checks.session`'s QML-errors assertion is not touched.

**Rejected:**
- **Rewriting plugin QML at nixarchy build time** (a `sed` over plugin
  sources): it fixes the symptom here, leaves every repository broken for
  anyone using it elsewhere, and is a carried patch on 17 trees.
- **Holding Qt at 6.11:** that holds back the whole nixpkgs bump.

## 3. The VirtualBox guest-additions collision

**What is known.** `reference-hardware` enables
`virtualisation.virtualbox.guest.enable = true` (`flake.nix:1761`), on
purpose, so the offline ISO carries what a VirtualBox guest needs. On the
bumped nixpkgs, the system's aggregated module tree fails with
`two given paths contain a conflicting subpath:
lib/modules/7.2.11/modules.builtin.alias.bin`, between
`VirtualBox-GuestAdditions-7.2.20-7.2.11` and `linux-7.2.11-modules`.
That is a real break for any nixarchy machine running as a VirtualBox
guest, not only for the check. No nixpkgs issue or PR mentions it, and
no virtualbox or kernel-module packaging commit stands out between
fe13242 and 09063bd.

**Design: measure, then choose the smallest of three.** The plan's first
step fetches both store paths from cache.nixos.org, which is a
substitution, not a build, and lists what guest additions puts under
`lib/modules`. Then:
- **(i) The extra file is depmod output that guest additions should not
  ship.** Override the guest-additions package to delete the
  `modules.builtin*`/`modules.*.bin` files from its output, via
  `postInstall` in an overlay that only `virtualisation.virtualbox.guest`
  uses. Then draft a nixpkgs issue for your approval, because the bug is
  theirs.
- **(ii) A nixpkgs fix already exists on a later master.** Wait for the
  next nightly bump, and do nothing here.
- **(iii) Anything else.** Stop and revise the spec.

**Coexistence (§14):** the override only changes a package's output files
that the kernel already provides. A user's own VirtualBox guest
configuration gets the same package. No fixture applies.

## Risks

- **Item 2 depends on a nixi release.** nixi is a separate repository
  with the same maintainer; its PR is merged there first.
- **Item 3 (i) changes a kernel-module package output** on every
  VirtualBox guest. `checks.offline-hardware-packages` exercises exactly
  that tree.

## Verification (§1)

1. `checks.copilot-handoff`:
   - with 20 000 lines, green;
   - its control is red against `head -100`, run 20 times in a row with
     no pass;
   - with the stub back at 500 lines, reproduce the original flake on the
     runner class that showed it, or document that the old control passed
     on #1378's run (already observed).
2. **Qt 6.12 shadowing:**
   - `checks.qml-color-qualified` is red today, listing the 17 trees, and
     green once every pin and `rebuild-panel` is qualified. It is red
     again with one `Commons.Color.` reverted, naming that file.
   - `checks.session` on the bumped nixpkgs is green with the new pins.
     #1378's run is the red.
   - Every repository's own change is checked by building nixarchy's
     check against its new commit.
3. `checks.offline-hardware-packages` on the bumped nixpkgs: red before
   (#1378's run), green with the override.
4. The next nightly bump PR goes green.
