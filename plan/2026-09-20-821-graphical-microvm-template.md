---
status: draft
issue: 821
spec: spec/2026-09-20-821-graphical-microvm-template.md
---

# Plan: a `hyprland` microvm template

Branch `feat/821-graphical-microvm-template`, already carrying the intent and
the spec. One commit per step, each subject a full sentence (AGENTS.md §8). A
deviation updates this file in the same commit as the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **Hyprland and the tools, nothing more.** `hyprland`, `grim`, `tesseract`,
  `wtype`, `wl-clipboard`, `foot`. No omarchy shell — no caller needs it today
  and it would be the first template importing nixarchy's own modules, against
  the bar in `data/microvm-templates.nix`.
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
- **Headless, not virtio-gpu**, unless step 1 disproves it. The runner passes
  `-nographic`, and Hyprland asks for a headless backend first and
  `MANDATORY` (`Compositor.cpp:311-313`) while `CBackend::create` returns null
  only on an empty list — so "no GPU" is not on its own a reason to fail.

## How this was approved

On "continue and close them", rather than on an explicit approval of this
file. Recorded rather than left to look like a clean gate, the same way
nixarchy-voice's #28 plan records being approved after its implementation
merged. If the instruction was not meant to carry this, step 1 is the place to
stop: it is a throwaway probe and nothing after it has been written.

## Step 1 ran and stopped the plan

As instructed: headless does not work in the guest, so the rest of these steps
are not to be executed against the current spec. See the spec's first section.

**Three things the probe taught that are worth keeping**, because each cost an
iteration:

1. **A systemd *user* service writes nothing to the console.** The first probe
   ran as one, reported `Finished`, and produced no output anywhere — which I
   misread as "Hyprland failed silently" when it was "I cannot see anything a
   user unit does". Run a guest probe from the autologin shell on `ttyS0`.
2. **Redirecting to `/mnt/host` is not a reliable channel for a probe.** Two
   attempts wrote no file at all while the share was mounted. The console is
   the one channel that has never lied here.
3. **`microvm.graphics.enable = true` opens a GTK window on the host.** Not
   what a background VM wants, and the thing to solve before virtio-gpu can be
   called a fallback.

## Steps (not executed beyond 1)

**1. Prove headless, before writing the template.** This is the whole issue and
the spec deliberately left it open: a scoping probe reported `Finished` and
wrote nothing, which is evidence about the probe, not about Hyprland.

Throwaway template + entry, built and booted, with the compositor as a **user**
service so it gets a real `XDG_RUNTIME_DIR`. The probe must report where it
failed rather than leaving silence to be interpreted: redirect Hyprland's own
stdout and copy `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` out, and write the probe
file with `install -D` so a missing directory is an error rather than a
swallowed redirect.

→ verify by `hyprctl -j monitors` naming one monitor at the configured size,
read from the host afterwards. If it fails, **stop and revise the spec** —
virtio-gpu is the recorded fallback, and the template does not quietly grow a
GPU.

**Two things that will otherwise cost an hour each**, from the scoping spike:

- **`git add` the new template before building.** Nix cannot see an untracked
  file in a git-tree flake; the error names the file but arrives inside a
  truncated stack trace. Another agent posted this same trap to the bus for
  plugin QML, and it applies identically here.
- `XDG_RUNTIME_DIR` must stay under 108 bytes or the Wayland socket exceeds
  `sun_path` and the compositor aborts one line above a C++ `terminate called`,
  which is where the eye goes. Relevant to any host-side harness, not to the
  guest.

**2. `modules/microvm/templates/hyprland.nix`.** The real template: packages,
`microvm.mem` raised with a comment saying why (`python.nix` is the precedent),
the Hyprland config pinning one monitor, and the user service.

No display manager — `guest.nix` already autologins `dev` on `ttyS0`.
→ verify by step 1's probe, now against the real file.

**3. Accessibility.** `QT_ACCESSIBILITY = "1"` and
`GTK_MODULES = "gail:atk-bridge"` in `environment.sessionVariables`;
`services.gnome.at-spi2-core.enable` so `org.a11y.Bus` is actually running;
wrappers for Chromium and Electron adding `--force-renderer-accessibility`.

The wrappers are the one opinionated thing here and the `note` must say so —
someone expecting stock Chromium should not have to discover it.
→ verify by test 5.

**4. `data/microvm-templates.nix`: the entry.** `label`, `module`, `note`, in
the style of the other nine. The `note` says: what it gives, that there is **no
omarchy shell** (because "nixarchy vm" implies one), that the browsers are
wrapped, and that the closure is large — with the measured figure from step 6,
not an adjective.
→ verify by `nixarchy vm templates` listing it with that note.

**5. Make a dead compositor visible.** The spec's named risk: this is the first
template with something that can be running or not, and a VM whose compositor
died looks exactly like a working one until a capture returns nothing.

Cheapest honest answer: the `note` tells the reader to check
`systemctl --user status`, and the service is `Restart=no` so a failure stays
failed and visible rather than flapping. If step 1 shows something better and
cheap — a motd line, a file in `/mnt/host` — take it, but do not build a health
system for one template.
→ verify by killing the compositor in a booted VM and confirming the failure is
discoverable without already suspecting it.

**6. Measure the closure and finish the note.** `nix path-info -Sh` on the
runner. A template that takes ten minutes to realise on first run should say
so, in numbers.
→ verify by the figure appearing in the `note`.

## Tests

The existing `checks.microvm-hyprland` and `-tcg` come free from the `genAttrs`
over `data/microvm-templates.nix` (`flake.nix:1189-1214`). They prove it
builds, which is what that check is for, and prove nothing about whether the
compositor runs — hence steps 1 and 5.

Run by hand in a booted VM, in this order, because each depends on the last:

1. **Headless comes up.** `hyprctl version` answers; `hyprctl -j monitors`
   reports one monitor at the configured size.
2. **`grim` captures.** `grim -t ppm` produces a file of the expected
   dimensions. PPM rather than PNG deliberately — nixarchy-voice #26 measured
   the encode at 0.9s on a 2560x1440 framebuffer against 0.03s, and a probe
   should not spend it.
3. **A window is addressable.** `foot` inside the guest appears in
   `hyprctl -j clients` with a class and a title.
4. **The event socket works.** `$XDG_RUNTIME_DIR/hypr/*/.socket2.sock` exists
   and an `openwindow` line arrives on it when a window opens. nixarchy-voice
   #28's listener depends on this, and it is the one thing a build check can
   never reach.
5. **Accessibility is genuinely on.** A page in the wrapped browser exposes a
   link through AT-SPI with bounds and an action — the same probe that returned
   zero nodes on p620 without the flag.

Commands:

```
nix build .#microvm-hyprland          # and .#microvm-hyprland-tcg
nix flake check                        # green, including the template checks
nixarchy vm create probe --template hyprland && nixarchy vm run probe
```

## Rollback

One branch, and the template is additive: a new module, a new catalogue entry,
nothing existing edited. `git revert` the merge and the other nine are
untouched.

Nothing persists outside the repo. A VM created from the template lives in
`~/.local/state/nixarchy/microvm/<name>/` and goes with `nixarchy vm rm`.

If step 1 disproves headless, the rollback is not a revert — it is a spec
revision, because "virtio-gpu instead" is a different design and the spec
records it as the fallback rather than as an implementation detail to improvise.
