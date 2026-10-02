---
status: approved
issue: 1167
intent: intent/2026-10-02-1167-user-packages-win.md
---

# Spec: a user's own package wins over the one nixarchy brings

## What was measured (2026-10-03, `nixosConfigurations.reference`, main `f0a04117`)

- **Which packages are nixarchy's:** `environment.systemPackages` has 312
  entries with nixarchy on, and 128 with `programs.nixarchy.enable = false`.
  **165 entries are nixarchy's,** the app selection included.
- **Binary overlaps,** from every entry's `bin/`, read from the caches'
  `.ls` listings (`nix store ls --store …`); nothing was built:
  - **between a nixarchy package and a non-nixarchy one:** 108 shared names,
    and *all* of them are nixarchy's `coreutils` (priority 10) against NixOS'
    `coreutils-full` (13), with `procps`/`util-linux` on two of them.
    `coreutils` wins today (lower number wins) and still wins at 10.
  - **among nixarchy's own packages:** **0.**
- **nixarchy packages that already carry a priority, from nixpkgs' own
  `meta.priority`:**
  - `neovim` and `fastfetch` at **4**, and `libreoffice-wrapped` at **−10**:
    these *beat* a user's default-priority (5) package today, so they are the
    worst case;
  - `coreutils`, `tesseract`, `gcc-wrapper` and `fuse` at 10.
- **The user's `ffmpeg-full` loses** to nixarchy's `ffmpeg`. Both are at the
  default priority, and nixarchy's comes first (index 49 against 143); proven
  in CI, run 37074375513.

**Consequence:** setting every package nixarchy brings unasked to
`lib.lowPrio` (priority 10) makes any user package at the default (5) win.
It changes no outcome between nixarchy and NixOS (the coreutils overlap
stays as it is), and none among nixarchy's own packages (they share no
binary).

## Design

### D1. `lib.lowPrio` on everything nixarchy adds to `environment.systemPackages` unasked

- **`modules/nixos.nix`:** the main `systemPackages = [ … ]` list (`:1290`
  onwards) and the Omarchy `runtimeDeps` spliced in (`:1230`). Wrap the
  module's whole contribution as `map lib.lowPrio (…)`, the shape
  `modules/home.nix:1011` already uses for #809, with a one-line comment
  pointing at #1167 and #809.
- **The other modules:** every other nixarchy module that adds system
  packages without the user naming them, found by `grep` for
  `environment.systemPackages` across `modules/`. Today that is
  `modules/services/boxes.nix:114` (`distrobox`) and
  `modules/local-ai.nix:407`. Each gets the same `map lib.lowPrio`.
- **Not wrapped: the app selection** (`modules/apps.nix:1205`, the apps the
  user picked in the installer or the menu). Owner's answer 2: they are the
  user's own choice, and keep normal priority.
- **Priorities nixpkgs already set are overwritten,** because `lowPrio` sets
  10: `neovim`/`fastfetch` (4) and `libreoffice` (−10). That is intended:
  each now yields to the user's own copy. Among nixarchy's packages it changes
  nothing (no shared binaries).

### D2. The check: `checks.options`-style, evaluation only

`tests/user-packages-win.nix` (new, cheap):
- for the reference machine, the `systemPackages` entries absent with
  nixarchy off are nixarchy's;
- of those, every one **not** contributed by `apps.nix` must have
  `meta.priority >= 10`;
- the check prints any offender's name and priority and fails.

It catches a future nixarchy module adding packages at normal priority.
Identifying `apps.nix`'s contribution: compare against a reference variant
with the app selection empty (whatever option drives `apps.nix:1205`; the
plan pins it). The reference machine's own app picks are what is tested.

### D3. The end-to-end proof is #1164's fixture

`checks.coexistence`'s `systempkg-own-ffmpeg` (#1164's branch, CI-built in
the `system` job) is the real proof: red on `main` (run 37074375513), and
green with D1.
- **#1167 merges first;** #1164 then rebases, and its CI goes green.
- **§1 for D2:** remove the `lowPrio` from one module (e.g. `boxes.nix`), and
  the check names `distrobox`.
- **§1 for D3:** with #1164 rebased on #1167, a probe that drops D1's wrap on
  the `ffmpeg` site goes red again.

## Alternatives rejected

- **A list of known overlaps** (only `ffmpeg`): the owner chose "all".
  A list fails open (AGENTS.md §4).
- **Raising the user's packages instead (`hiPrio`):** nixarchy cannot touch
  the user's list (constraint).
- **Reordering so nixarchy's packages come last:** the order is the module
  system's, not ours to control, and it is fragile.

## Risks

- **A user who relied on nixarchy's copy beating theirs** (unlikely, and
  invisible) now gets their own. That is the intended outcome.
- **A future module forgets the wrap:** D2 fails, naming the package.
- **A NixOS module package at a priority above 10 that overlaps one of
  nixarchy's** would now win where it lost before. None exists in today's
  reference closure (measured: the only overlap is `coreutils`, where
  `coreutils-full` is at 13). D2's offender list does not cover this; #1164's
  fixtures are where to add one if it appears.

## Verification

1. `checks.user-packages-win` is green with D1, and red when one module's
   wrap is removed, naming the package.
2. The reference toplevel evaluates. `checks.options`, `checks.session` and
   the rest of CI are green.
3. #1164's `checks.coexistence` is green after rebasing on this, and red when
   the `ffmpeg` wrap is dropped (probe).
4. fmt, statix, deadnix.
