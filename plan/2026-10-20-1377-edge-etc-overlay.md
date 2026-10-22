---
status: approved
issue: 1377
spec: spec/2026-10-20-1377-edge-etc-overlay.md
---

# Plan: edge knows what every file in quattro's /etc is for

Approved decisions, carried from the spec:

- **13 rows** in edge's `data/etc-overlay.nix`, in key order:
  - **installed:** `xkb/rules/evdev`, `xkb/symbols/omarchy`,
    `mpv/mpv.conf`;
  - **native:**
    - `sysctl.d/90-omarchy-arp.conf`;
    - `systemd/system.conf.d/20-mount-events.conf`;
    - `systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf`;
  - **covered:** `sudoers.d/omarchy-locale-generate`;
  - **na:** `mkinitcpio.conf.d/00-omarchy-hooks.conf`;
  - **divergent:**
    - `mise/conf.d/omarchy-tools.toml` (deliberate, #707);
    - `mise/conf.d/omarchy-agent-accounts.toml`,
      `udev/rules.d/60-omarchy-io-scheduler.rules`, and the two binfmt
      drop-ins, all pointing at one new follow-up issue.
- **Edge `modules/nixos.nix`,** for the three natives, each with a
  one-line comment naming the quattro file:
  - the ARP sysctls at `mkDefault` (`net.ipv4.conf.{all,default}.arp_ignore = 1`,
    `arp_announce = 2`), beside the existing `boot.kernel.sysctl` block
    (~line 2159);
  - `systemd.managerEnvironment.SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST = "30";`
  - `systemd.user.services."wayland-wm@".serviceConfig.KillMode = "mixed";`
- **Edge only** (stable 4.0.6 does not ship these files). The rows go
  where `main` and `edge` agree; a trial merge must keep them all.
- **On `main`, one word:** `etc-overlay` added to
  `omarchy-edge.yml:239`'s list. That is §11, so the owner merges it,
  after the rows are on `edge-candidate`.
- **Who implements:** three files, so the `coder` agent does steps 2-3;
  the lead does 1, 4 and 5.
- **Builds wait for the owner's go-ahead.**

## Steps

1. **Lead:**
   - file the follow-up issue, "Port quattro's storage, binfmt and
     agent-account /etc tuning" (milestone *Keeping the lights on*, label
     `enhancement`), naming the four files and why each was deferred
     (spec table);
   - `git worktree add --detach /mnt/data/vmtest/wt-edge1377 origin/edge-candidate`.
2. **Coder:** `data/etc-overlay.nix` in the edge worktree.
   - Insert the 13 rows in key order: `mise/…` after line ~104,
     `mkinitcpio/00-…` before `omarchy_hooks`, `mpv/…`, `sudoers.d/…`,
     `sysctl.d/90-omarchy-arp.conf` before `90-omarchy-file-watchers`,
     the `systemd/…` rows in order, `udev/…`, `xkb/…`.
   - Each reason is one or two sentences in the existing style, taken
     from the spec table.
   - Trap: `"wayland-wm@hyprland.desktop.service.d/…"` keeps its `@` in
     a Nix string; check it evaluates.
   → verify: `nix fmt`, then `nix eval` of the file's attr count, which
   is the old count + 13.
3. **Coder:** edge `modules/nixos.nix`, the three native settings above,
   each with its comment.
   Traps:
   - sysctl at `lib.mkDefault`;
   - `managerEnvironment` is an attrset, plain assignment (§7);
   - no `mkForce`.
   → verify: `nix fmt`, `git diff --stat` (two files).
4. **Lead: prove** (cheap tier, under the lock):
   - `checks.etc-overlay` on the edge worktree: red before (13 listed,
     already measured), green after, and red again with one row removed,
     naming it. Confirm the break with `git diff`.
   - Edge's verify loop in a script against the one-row-removed tree:
     `failed=etc-overlay`, exit 1.
   - `nix eval` on the reference configuration: the three settings, and
     the three `environment.etc` entries.
   - A trial merge of `origin/main`: every row and line survives.
5. **Lead: ship.**
   - Commit and push to `edge-candidate`. This waits for #1380's
     candidate if that has not promoted, so the two land in one edge run.
   - Then a PR to `main` with the one-word workflow change, `Closes #1377`,
     for the owner to merge.
   - After edge publishes, on p620: Shift+Caps composes, and
     `sysctl net.ipv4.conf.all.arp_ignore` reads 1.

## Tests

- `etc-overlay` is red, then green, then red with one row removed.
- The verify loop fails on it.
- The `nix eval` assertions hold.
- The trial merge keeps every row and line.

## Rollback

Revert the `edge-candidate` commit and the workflow PR. Edge goes back to
not checking `/etc`.

## Deviations

- **`KillMode` sits inside the existing `systemd.user.services` block** in
  edge's `modules/nixos.nix`, not as a separate dotted key, which collided
  with that block and failed evaluation. The ARP keys joined the existing
  `mkDefault` sysctl block.
- **Shipped together:** the rows and module lines went to `edge-candidate`
  in one commit with #1380 and #1385's edge parts (221b82f6). Edge
  promoted at e5867567 (run 39420415082).
- **Step 5's workflow word moved to #1383** (owner, 2026-10-20). #1383
  replaces edge verify's hand-kept check list with the generated one,
  which includes `etc-overlay`, so a one-word PR here would be overwritten.
  The proof for it (the verify loop as a script, `failed=etc-overlay`,
  exit 1) stands and is carried there.
