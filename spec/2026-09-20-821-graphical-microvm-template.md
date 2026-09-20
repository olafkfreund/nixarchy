---
status: draft
issue: 821
intent: intent/2026-09-20-821-graphical-microvm-template.md
---

# Spec: a `hyprland` microvm template

## What the approver decided

- **Hyprland and the tools, nothing more.** No omarchy shell. It serves every
  caller that exists today and keeps the template plain NixOS, which the bar in
  `data/microvm-templates.nix` requires. Bar and plugin behaviour stays
  untestable, and that is accepted.
- **No windows on boot.** The template gives a compositor and the tools;
  whoever measures opens their own window set through `/mnt/host`.
  Repeatability is the harness's job.
- **The template wraps the browsers** so accessibility is genuinely on, rather
  than setting an environment variable and documenting the rest.

## What was proven while scoping, and what was not

Honesty about this matters more than usual, because the first question is a
technical one that decides whether the template works at all.

**Proven:**

- A template carrying Hyprland, `grim`, `tesseract`, `wtype`, `wl-clipboard`
  and `foot` **builds**: `nix build .#microvm-hyprland` completes, producing a
  runner, so nothing about the package set fights `lib.mkMicrovm`.
- **The runner passes `-nographic`.** There is no GPU device and no DRM node in
  the guest, so the DRM backend is not available to it.
- **Hyprland always asks for a headless backend first, and demands it.**
  `src/Compositor.cpp:311-313`: headless is `AQ_BACKEND_REQUEST_MANDATORY` and
  first in the list; DRM is `IF_AVAILABLE` and Wayland is `FALLBACK`.
  `CBackend::create` (aquamarine `src/backend/Backend.cpp:60-110`) returns null
  only when the list is empty. So "no GPU" is not on its own a reason for the
  compositor to fail.
- **A boot probe ran to completion in the guest** — systemd reported
  `Finished headless Hyprland probe`.

**Not proven, and the plan's first step:**

- That a compositor was actually up. The probe wrote **nothing** to
  `/mnt/host`, although the share mounted (`Mounted /mnt/host` in the boot
  log). So either the compositor died before the probe's `exec-once`, or the
  probe's writes did not reach the share. Both are ordinary bugs in a
  throwaway probe, and neither is evidence about Hyprland.
- That `grim` can capture a headless framebuffer in this guest.

**A separate finding, recorded because it cost time and is not obvious:** a
second Hyprland on a *host* whose session logind already owns fails with
`CBackend::create() failed!`, and the actual reason — `Could not take control
of session: Device or resource busy` — is four lines down Hyprland's own log
rather than in the crash message. It nests fine if the parent's Wayland socket
is reachable through `XDG_RUNTIME_DIR`, and `XDG_RUNTIME_DIR` must stay under
108 bytes or the socket path exceeds `sun_path` and the compositor aborts.
None of that applies inside a guest, which owns its own seat; it is here so the
next person does not spend the same hour.

## Step 1 ran, and it disproved the design. This spec needs re-approving.

The plan's first step was to prove headless before writing anything. It is
proved false.

In a guest with no DRM device, Hyprland dies with:

```
HYPR: DEBUG ]: Creating the AsyncResourceGatherer!
HYPR: terminate called after throwing an instance of 'std::runtime_error'
HYPR:   what():  CBackend::create() failed!
```

It gets far enough to create its instance directory — the probe found
`.socket2.sock` — and then cannot build a backend.

**My reading in the section below is wrong and I cannot yet say why.** The
guest builds hyprland 0.56.2, the same version whose `Compositor.cpp:311-313`
asks for `AQ_BACKEND_HEADLESS` with `AQ_BACKEND_REQUEST_MANDATORY`, and whose
aquamarine `CBackend::create` appeared to return null only on an empty list.
Both readings cannot be true at once. The likeliest explanation is that the
aquamarine I read (`nixpkgs#aquamarine.src`) is not the one this Hyprland links
against, but that is a guess and it is labelled as one.

**And virtio-gpu is not a drop-in fallback.** `microvm.graphics.enable = true`
produces a qemu **GTK display** — a window on the host's desktop — which
defeats the whole premise of a VM that runs in the background unattended. It
would need `-display egl-headless` or equivalent, which is a different design
decision and not an implementation detail.

So this spec's central technical claim is dead and the next step is not
implementation. Whoever picks it up chooses between:

1. **virtio-gpu with a headless host display.** Guest gets a real DRM device,
   host gets no window. Needs proving that `egl-headless` reaches microvm.nix's
   qemu invocation, and that `grim` can capture from it.
2. **Find out why headless fails**, starting with which aquamarine the guest
   actually links and what `CBackend::create` does in *that* revision. If it is
   a packaging mismatch it may be a nixpkgs bug worth reporting rather than
   designing around.
3. **Abandon the VM** and use the nested compositor, which is recorded below as
   rejected but which *was verified working* in about two seconds.

The probe that produced this is not in the tree — it was a throwaway and it is
reverted. What is worth keeping from it is in the plan.

## Design (superseded by the section above)

### 1. `modules/microvm/templates/hyprland.nix`

Plain NixOS. Packages: `hyprland`, `grim`, `tesseract`, `wtype`,
`wl-clipboard`, `foot`. These are what desktop automation shells out to —
nixarchy-voice's capture path is `grim` piped into `tesseract`, its typing is
`wtype`, and `foot` is something to open.

`microvm.mem` raised from microvm.nix's 512 default. A compositor plus a
browser under test wants more; `python.nix` already sets a precedent for a
template raising it and saying why.

**No display manager.** `guest.nix` already autologins `dev` on `ttyS0`, and a
compositor started from that session has the seat logind gave it. Adding a
greeter would be a second thing to keep working for no gain.

### 2. How the compositor starts

A systemd **user** service for `dev`, not a system service, because the
compositor belongs to the user's session and its `XDG_RUNTIME_DIR` is
`/run/user/1000` — which logind creates for a real session and which a system
service would have to fake. The probe that failed above ran as a system
service with a hand-made runtime directory, and that is one of the two
candidate explanations for it producing nothing.

The service is `wantedBy` the user's `default.target`, with lingering already
enabled in the guest (`linger-users.service` is in the boot log).

A minimal config file pins **one monitor at a fixed size**. This is not the
"window set on boot" the approver declined: a compositor needs some monitor
configuration, and resolution is the variable that silently changes OCR
numbers. Content stays the caller's.

### 3. Accessibility, including the browsers

Per the decision, the template makes a11y real rather than half-configured:

- `QT_ACCESSIBILITY = "1"` and `GTK_MODULES = "gail:atk-bridge"` in
  `environment.sessionVariables`.
- `org.a11y.Bus` reachable — `services.gnome.at-spi2-core.enable`, which is
  what actually starts the bus a client connects to.
- **Wrappers for Chromium and Electron** that add
  `--force-renderer-accessibility`, so an app launched inside the VM exposes a
  tree without the caller remembering a flag.

The measurement that makes this worth doing, from p620: with the flag off, the
AT-SPI tree exposes **zero** actionable elements in every running application.
With it on, a link comes back with exact bounds and a `jump` action.

The wrappers are the one place this template is opinionated, and the intent's
Q5 is why: setting the environment variable alone is a half-measure that reads
as "accessibility is on" and is not.

### 4. Registration

One entry in `data/microvm-templates.nix` — `label`, `module`, `note` — and the
`note` says what it gives and what it costs, like the other nine. It should say
plainly that there is no omarchy shell, because "nixarchy vm" will otherwise
imply one.

### 5. The check

`checks.microvm-hyprland` and `-tcg` come for free from the `genAttrs` over
`data/microvm-templates.nix` in `flake.nix:1189-1214`. That proves it builds,
which is what the existing check is for, and proves nothing about whether the
compositor runs — see the plan's first step.

## Alternatives rejected

- **virtio-gpu and a real DRM device.** Heavier, and unnecessary if headless
  works, which Hyprland's own backend list says it should. Kept as the
  fallback if the plan's first step disproves headless; the spec would then
  need revising rather than the template quietly growing a GPU.
- **A nested Hyprland on the host instead of a VM.** Verified working and about
  two seconds to start, against a VM boot. Put to the approver with that
  evidence and declined: it cannot carry the omarchy shell later, and it shares
  the host's fate. Recorded because it remains the cheap option for anyone who
  only wants an isolated compositor.
- **A generic `wayland` template on a lighter compositor.** Every caller talks
  to `hyprctl` and Hyprland's event socket. A smaller compositor would serve a
  wider audience and none of the actual users.
- **Opening a window set on boot.** Declined by the approver; it would make the
  template the only opinionated one of the ten.
- **Shipping the omarchy shell.** Declined; no caller needs it today and it
  would be the first template importing nixarchy's own modules, against the
  bar.

## Risks

- **Headless may not work, and that is the whole template.** The plan's first
  step is to prove it before anything else is written. If it fails, the spec
  changes rather than the implementation improvising.
- **A user service that fails at boot is invisible.** Unlike the existing
  templates, this one has something that can be running or not. It needs a way
  to tell — even `systemctl --user status` in the note — or a VM with a dead
  compositor looks exactly like a working one until a capture returns nothing.
- **Browser wrappers change how those apps launch inside the VM.** Deliberate,
  and surprising if someone expects stock Chromium. The `note` must say so.
- **The closure is much larger than any existing template.** Hyprland,
  tesseract's language data and a browser toolkit are not small. Worth
  measuring and stating in the `note`, since a template that takes ten minutes
  to realise on first run should say so.
- **`tesseract` language data.** The default package may carry only English.
  Whoever measures non-English OCR will need more, and that is a caller
  concern, not a template one — but the `note` should not imply otherwise.

## Verification

1. **Headless comes up.** In a booted VM: `hyprctl version` answers, and
   `hyprctl -j monitors` reports one monitor at the configured size. This is
   the step everything else depends on.
2. **`grim` captures.** `grim -t ppm` inside the guest produces a file of the
   expected dimensions.
3. **A window appears and is addressable.** `foot` opened inside the guest
   shows up in `hyprctl -j clients` with a class and a title.
4. **The event socket exists**, since nixarchy-voice #28's listener depends on
   it: `$XDG_RUNTIME_DIR/hypr/*/.socket2.sock` is present, and an `openwindow`
   line arrives on it when a window opens.
5. **Accessibility is genuinely on.** A page opened in the wrapped browser
   exposes a link through AT-SPI with bounds and an action — the same probe
   that returned zero nodes on p620 without the flag.
6. **The template check passes**, both the KVM and `-tcg` variants, as it does
   for the other nine.
7. **Nothing else regressed.** `nix flake check` green.

Steps 1–5 need a booted VM and are run by hand. Step 6 is CI's.
