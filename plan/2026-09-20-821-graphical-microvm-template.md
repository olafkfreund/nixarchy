---
status: approved
issue: 821
spec: spec/2026-09-20-821-graphical-microvm-template.md
---

# Plan: a `hyprland` microvm template

Branch `feat/821-graphical-microvm-template`, already carrying the intent and
the spec. One commit per step, each subject a full sentence (AGENTS.md §8). A
deviation updates this file in the same commit as the code.

This is the second version of this plan. The first was written against a spec
whose central claim — that Hyprland needs no GPU — its own step 1 disproved.
The spec has been rewritten on evidence and re-approved; this file is rewritten
to match. What the disproved run *taught* is kept below, because each item cost
an iteration and none of it depends on which backend won.

## Approved decisions

Copied from the spec so this file stands alone.

- **Hyprland and the tools, nothing more.** `hyprland`, `grim`, `tesseract`,
  `wtype`, `wl-clipboard`, `foot`. No omarchy shell — no caller needs it today
  and it would be the first template importing nixarchy's own modules, against
  the bar in `data/microvm-templates.nix`.
- **virtio-gpu, not headless.** Settled by reading the sources the guest
  builds, not by preference: GBM is aquamarine's only allocator
  (`Backend.cpp:163-198`, with an upstream `TODO` on it), it is built only from
  an implementation exposing a DRM fd, and `CHeadlessBackend::drmFD()` returns
  `-1` unconditionally (`Headless.cpp:133-135`). No DRM device means no
  allocator, `start()` returns false, and Hyprland dies. The guest needs a real
  DRM node.
- **Two lines give it.** `microvm.graphics.enable = true` and
  `microvm.graphics.backend = "headless"`. The second is not optional: the enum
  defaults to `gtk` on Linux, which opens a window on the host and defeats a
  background VM. `headless` emits `-display egl-headless -device
  virtio-gpu-gl` (`lib/runners/qemu.nix:245-256`), which upstream documents as
  the value that exists so a VM can run under a systemd job.
- **`microvm.graphics.vulkan` stays `null`.** No caller needs GPU compute in
  the guest and venus pulls `hostmem` and a `blob=true` device into a template
  whose first job is to come up at all.
- **No windows on boot.** A compositor and the tools; the caller opens its own
  window set through `/mnt/host`. A fixed *monitor size* is not a window set —
  a compositor needs monitor configuration, and resolution is the variable that
  silently changes OCR numbers.
- **The template wraps Chromium and Electron** with
  `--force-renderer-accessibility`, rather than setting `QT_ACCESSIBILITY` and
  documenting the rest. Measured on p620: with the flag off the AT-SPI tree
  exposes **zero** actionable elements in every running application; with it on
  a link comes back with exact bounds and a `jump` action.
- **A systemd user service** starts the compositor, not a system service. Its
  `XDG_RUNTIME_DIR` is `/run/user/1000`, which logind creates for a real
  session and a system service would have to fake.

Two decisions the approver left to this file, stated here to be rejected here:

- **`microvm.mem = 4096`.** The spec said "raised" without a number.
  `python.nix` takes 3072 for a venv; a compositor plus a browser under test
  wants more, and 4096 is the next round figure. Cheap to change, and the
  `note` carries it.
- **If `-tcg` cannot do virtio-gpu, the hole gets documented, not papered.**
  Per §3: a row in `tests/install-matrix.py` and a sentence in
  `tests/AGENTS.md` naming what no runner can reach. Step 7 decides it on
  evidence.

## What the disproved run taught

Kept verbatim in substance, because none of it was about headless:

1. **A systemd *user* service writes nothing to the console.** The first probe
   ran as one, reported `Finished`, and produced no output anywhere — which
   read as "Hyprland failed silently" when it was "I cannot see anything a user
   unit does". Run a guest probe from the autologin shell on `ttyS0`.
2. **Redirecting to `/mnt/host` is not a reliable channel for a probe.** Two
   attempts wrote no file at all while the share was mounted. The console is
   the one channel that has never lied here.
3. **`microvm.graphics.enable = true` alone opens a GTK window on the host.**
   Now understood — it is the enum's default — and it is why step 2 sets
   `backend` in the same commit as `enable`, never in a later one.
4. **`git add` the new template before building.** Nix cannot see an untracked
   file in a git-tree flake; the error says the path *does not exist* and
   arrives inside a truncated stack trace (AGENTS.md §5). Another agent posted
   the same trap to the bus for plugin QML.
5. **Hyprland's fatal error string is ambiguous.** `CBackend::create()
   failed!` is thrown from `Compositor.cpp:328` *and* `:340`, for two different
   failures. The `CRIT` line four lines above the throw is what tells them
   apart. Any probe here must capture Hyprland's own log, not just the
   terminate message — that ambiguity is what cost the first attempt its
   diagnosis.

## Steps

**1. Prove the guest gets a DRM node, before writing the template.** The spec
is built on this and asserts it rather than having proved it. Throwaway
template carrying only `microvm.graphics.enable`, `backend = "headless"` and a
shell, booted from the autologin console on `ttyS0`.

→ verify by `ls /dev/dri` showing a `renderD*` **and** `hyprctl version`
answering after starting Hyprland by hand from that console. Capture
`$XDG_RUNTIME_DIR/hypr/*/hyprland.log` to the console either way, per lesson 5.
→ **and prove the break**, per §1: with `graphics.enable` removed, the same
probe must produce `Cannot open backend: no allocator available` in that log.
A probe that passes both ways is measuring nothing. Both outputs go in the PR.

If the DRM node does not appear, **stop and revise the spec again** — there is
no third option behind this one, and the honest outcome would be the nested
compositor the spec records as rejected.

**2. `modules/microvm/templates/hyprland.nix`.** The real template: packages,
the two graphics lines *together* with the comment saying why `backend` is not
optional, `microvm.mem = 4096` with a comment (`python.nix` is the precedent),
the Hyprland config pinning one monitor, and the user service.

No display manager — `guest.nix` already autologins `dev` on `ttyS0`.
→ verify by step 1's probe, now against the real file.

**3. Prove no host window appears.** The property `backend = "headless"` exists
for, and the one a green build cannot show. Boot the template, confirm nothing
opens on the host's desktop, then flip `backend` to `gtk` and confirm one does.
→ verify by both observations, recorded in the PR. This is §1 applied to a
property whose failure is invisible to every automated layer we have.

**4. Accessibility.** `QT_ACCESSIBILITY = "1"` and
`GTK_MODULES = "gail:atk-bridge"` in `environment.sessionVariables`;
`services.gnome.at-spi2-core.enable` so `org.a11y.Bus` is actually running;
wrappers for Chromium and Electron adding `--force-renderer-accessibility`.

The wrappers are the one opinionated thing here and the `note` must say so —
someone expecting stock Chromium should not have to discover it.
→ verify by test 5.

**5. Make a dead compositor visible.** The spec's named risk: this is the first
template with something that can be running or not, and a VM whose compositor
died looks exactly like a working one until a capture returns nothing.

Cheapest honest answer: the `note` tells the reader to check
`systemctl --user status`, and the service is `Restart=no` so a failure stays
failed and visible rather than flapping. If step 1 shows something better and
cheap — a motd line — take it, but do not build a health system for one
template.
→ verify by killing the compositor in a booted VM and confirming the failure is
discoverable without already suspecting it.

**6. `data/microvm-templates.nix`: the entry.** `label`, `module`, `note`, in
the style of the other nine. The `note` says: what it gives, that there is **no
omarchy shell** (because "nixarchy vm" implies one), that the browsers are
wrapped, that it is the first template asking for a GPU device, and that the
closure is large — with the measured figure from step 8, not an adjective.
→ verify by `nixarchy vm templates` listing it with that note.

**7. Settle `-tcg`.** `checks.microvm-hyprland-tcg` overrides
`machineOpts.accel = "tcg"`. Whether `virtio-gpu-gl` and `egl-headless` work
without KVM, on a runner with no GPU of its own, is unknown and this plan does
not guess.
→ verify by building both variants. If `-tcg` cannot, document the hole in
`tests/AGENTS.md` and `tests/install-matrix.py` and say so in the PR. Do not
special-case the template to keep a check green — that is a check measuring the
arrangement rather than the property (§1).

**8. Measure the closure and finish the note.** `nix path-info -Sh` on the
runner. A template that takes ten minutes to realise on first run should say
so, in numbers.
→ verify by the figure appearing in the `note`.

## Tests

The existing `checks.microvm-hyprland` and `-tcg` come free from the `genAttrs`
over `data/microvm-templates.nix` (`flake.nix:1189-1214`). They prove it
builds, which is what that check is for, and prove nothing about whether the
compositor runs — hence steps 1, 3 and 5.

Run by hand in a booted VM, in this order, because each depends on the last:

1. **The DRM node exists.** `ls /dev/dri` shows a `renderD*`. Everything below
   depends on it and it is the spec's load-bearing claim.
2. **The compositor comes up.** `hyprctl version` answers; `hyprctl -j
   monitors` reports one monitor at the configured size.
3. **No host window appeared** while the VM was running.
4. **`grim` captures.** `grim -t ppm` produces a file of the expected
   dimensions. PPM rather than PNG deliberately — nixarchy-voice #26 measured
   the encode at 0.9s on a 2560x1440 framebuffer against 0.03s, and a probe
   should not spend it.
5. **A window is addressable.** `foot` inside the guest appears in
   `hyprctl -j clients` with a class and a title.
6. **The event socket works.** `$XDG_RUNTIME_DIR/hypr/*/.socket2.sock` exists
   and an `openwindow` line arrives on it when a window opens. nixarchy-voice
   #28's listener depends on this, and it is the one thing a build check can
   never reach.
7. **Accessibility is genuinely on.** A page in the wrapped browser exposes a
   link through AT-SPI with bounds and an action — the same probe that returned
   zero nodes on p620 without the flag.

Commands:

```
nix build .#microvm-hyprland          # and .#microvm-hyprland-tcg
nix flake check                        # green, including the template checks
nixarchy vm create probe --template hyprland && nixarchy vm run probe
```

**Timing, per §6.** Every step that boots a VM is a local VM build on p620,
where all four runners live. Check `gh run list` before starting one, and do
not start one while an install job is in flight — a guest-side timeout is a
hidden concurrency limit, and the cost lands on somebody else's check.

## Rollback

One branch, and the template is additive: a new module, a new catalogue entry,
nothing existing edited. `git revert` the merge and the other nine are
untouched.

Nothing persists outside the repo. A VM created from the template lives in
`~/.local/state/nixarchy/microvm/<name>/` and goes with `nixarchy vm rm`.

If step 1 disproves the DRM node, the rollback is not a revert — it is a third
spec revision, and the only option the spec has left recorded is abandoning the
VM for the nested compositor.
