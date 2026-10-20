---
status: approved
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

## 2. nixi's QML errors under Qt 6.12

**What fails.** Every error is a read through the `Color` singleton from
`qs.Commons`:
- `Color.accent.r`
- `Color.menu.text`, `Color.menu.border`, `Color.menu.background`

They come from `HarnessSelector.qml` and `Ask.qml` in
`olafkfreund/nixi-nixarchy`, pinned at 245e2a3 (`flake.nix:258`). `Style.*`
from the same module still resolves, and Omarchy's own shell, which reads
`Color.menu` everywhere, logs nothing.

**Working hypothesis, to be measured first in the plan.** nixi imports
`QtQuick.Controls` and Omarchy's plugins do not (they import `QtQuick` and
`qs.Commons`, and also `qs.Commons as Commons`). If Qt 6.12's Controls
brings in a `Color` name, it shadows the singleton for an unqualified
reference, so `Color` resolves to an object without `menu` or `accent`.
The plan proves or refutes this with a two-file QML repro run under Qt
6.12's `qml` tool, offscreen, before anything is changed.

**Design (in nixi, released, then pinned here):**
- Each nixi QML file that reads the Commons singletons adds
  `import qs.Commons as Commons`, the alias Omarchy's own plugins already
  use, and refers to `Commons.Color` and `Commons.Style`.
- A qualified reference cannot be shadowed by any import, so this is
  correct whatever the exact Qt 6.12 cause turns out to be.
- If the repro refutes the shadowing hypothesis, the plan stops and the
  spec is revised. A mechanical qualify-everything change is not shipped
  on a guess.
- In nixarchy: move the `nixi` pin in `flake.nix:258` and `flake.lock`
  to the fixed commit, with the `flake.nix` comment's change list
  extended by one line.
- The `session` assertion is not touched.

**Rejected:**
- An exception for nixi in the QML-error rule: it found a real
  user-visible break, missing colours.
- Pinning Qt: that holds every app back.

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
2. `checks.session` on the bumped nixpkgs:
   - red with nixi at 245e2a3 (#1378's run is the record);
   - green with the fixed pin;
   - also green on today's nixpkgs (Qt 6.11), so it can merge before the
     bump.
3. `checks.offline-hardware-packages` on the bumped nixpkgs: red before
   (#1378's run), green with the override.
4. The next nightly bump PR goes green.
