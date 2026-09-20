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
- **virtio-gpu, not headless** — decided after the first revision of this spec
  was disproved, and now proven in a booted VM. The next section is the
  evidence.

## Why this is the second revision

The first revision's central claim was that Hyprland needs no GPU, because its
backend list asks for a headless backend and marks it mandatory. The plan's
first step was to prove that before writing anything. It ran, and Hyprland died
in the guest with `CBackend::create() failed!`.

The revision written at that point recorded a contradiction it could not
resolve — Hyprland's `Compositor.cpp` asks for `AQ_BACKEND_HEADLESS` as
`MANDATORY`, aquamarine's `CBackend::create` returns null only on an empty
list, and both could not be true — and guessed that the guest must link a
different aquamarine than the one that had been read. **That guess is false,
and the contradiction was never real.** What follows is read from the exact
sources the guest builds, `hyprland` 0.56.2 and `aquamarine` 0.15.0:

- **The aquamarine hyprland links and the top-level one differ in store path
  but come from the same source tarball**, `v0.15.0`. The code that was read
  was the right code; only build inputs diverge.
- **Hyprland throws the same string from two different places.**
  `Compositor.cpp:328` throws `"CBackend::create() failed!"` when `create()`
  returns null, and `Compositor.cpp:340` throws the *identical* string when
  `m_aqBackend->start()` returns false. The backend list is built
  unconditionally with three entries, so `create()` cannot return null here.
  The guest was failing in `start()`, at line 340, and the error message gave
  no way to tell. The `CRIT` log line that distinguishes them is four lines
  above the throw — the same shape as this spec's earlier finding about
  `Could not take control of session`.
- **`start()` fails because there is no allocator, and there can only be one.**
  `Backend.cpp:163-198` builds the primary allocator from whichever
  implementation exposes a DRM fd, and GBM is the only allocator aquamarine
  has (`// TODO: obviously change this when (if) we add different
  allocators.`). `CHeadlessBackend::drmFD()` returns `-1` unconditionally
  (`Headless.cpp:133-135`). With no DRM device in the guest, nothing supplies
  an fd, `primaryAllocator` stays null, and `start()` logs `Cannot open
  backend: no allocator available` and returns false.

So headless Hyprland **cannot run without a DRM node** in this version. It is
not a packaging mismatch, not a nixpkgs bug, and not reachable by
configuration. The guest needs a real DRM device so GBM has something to
allocate from.

**And the second blocker was a default, not a design decision.** The previous
revision recorded that `microvm.graphics.enable = true` opens a GTK window on
the host, which defeats a background VM, and concluded it would need
`-display egl-headless` "which is a different design decision". It does not.
`microvm.graphics.backend` is an existing enum with three values, defaulting to
`gtk` on Linux; setting it to `headless` emits exactly
`-display egl-headless -device virtio-gpu-gl`
(`lib/runners/qemu.nix:245-256`), and upstream's own option documentation says
why that value exists:

> The `headless` backend can be started through a systemd job as it does not
> open a host window.

That makes the virtio-gpu route a template configuration change rather than new
qemu plumbing.

## What the plan's step 1 proved, and what it corrected

Six probe iterations in a booted VM. The design survived; three of this spec's
supporting claims did not, and they are corrected below rather than quietly
fixed in the implementation.

**Proven.** With the configuration in the next section, in a guest with no
host window:

```
/dev/dri:  card0   renderD128
hyprctl version  -> Hyprland 0.56.2
hyprctl -j monitors -> one "Virtual-1", 1920x1080@60, XRGB8888
grim -t ppm      -> P6 1920 1080, 6220817 bytes
```

And the break, per §1: with `microvm.graphics.enable` removed the same probe
gives `No such file or directory` for `/dev/dri` and
`CRIT: Cannot open backend: no allocator available` — the original failure,
reproduced deliberately.

**Correction 1: it is not two lines.** Two more are load-bearing, and each was
found only by running it:

- **`services.seatd.enable = true`**, with `dev` in the `seat` group. Without
  it nothing opens the DRM device at all, and aquamarine reports the result as
  `drm: Skipping device …, not a KMS device` — which is misleading:
  `CSessionDevice::supportsKMS()` returns early on `deviceID < 0` and never
  calls `drmIsKMS`. The probe's log contains neither of the two strings that
  function logs, which is how the early return was proved rather than guessed.
- **`hardware.graphics.enable = true`**. With a seat, the device opens and KMS
  is detected, and aquamarine then fails at `Cannot create a GBM Allocator: gbm
  failed to create a device`. GBM needs a mesa driver, and a NixOS guest has
  none under `/run/opengl-driver` until this option provides one. mesa 26.2.3
  ships `virtio_gpu_dri.so`, which is the driver this device wants.

**Correction 2: the reason given for the user service was wrong.** This spec
said a systemd *user* service is right because its `XDG_RUNTIME_DIR` is what
"logind creates for a real session". The guest's session is `Type=tty` with
`Seat=` **empty** — logind's libseat backend declines it outright
(`Backend 'logind' failed to open seat, skipping`). The decision still stands,
but for a different reason: **seatd makes the seat question irrelevant**, which
is also what lets a lingering user manager — which has no session at all — run
the compositor. The conclusion survived; the stated reason did not, and a rule
whose reason does not survive checking is one the next reader discards.

**Correction 3: a caller outside the session cannot reach the compositor.**
`HYPRLAND_INSTANCE_SIGNATURE` and `WAYLAND_DISPLAY` are exported by Hyprland to
its **children**, not to whatever starts it. Every caller of this template
drives it from outside that session, so `hyprctl` answers
`is hyprland running?` and `grim` answers `failed to create display` against a
perfectly healthy compositor. Three of the six probe iterations were lost to
exactly this. Both variables are derivable from `$XDG_RUNTIME_DIR`, and the
template's `note` must say so — otherwise every caller rediscovers it, and the
symptom reads as "the template is broken".

## Design

### 1. `modules/microvm/templates/hyprland.nix`

Plain NixOS. Packages: `hyprland`, `grim`, `tesseract`, `wtype`,
`wl-clipboard`, `foot`. These are what desktop automation shells out to —
nixarchy-voice's capture path is `grim` piped into `tesseract`, its typing is
`wtype`, and `foot` is something to open.

`microvm.mem` raised from microvm.nix's 512 default. A compositor plus a
browser under test wants more; `python.nix` already sets a precedent for a
template raising it and saying why (it takes 3072).

**No display manager.** `guest.nix` already autologins `dev` on `ttyS0`, and a
compositor started from that session has the seat logind gave it. Adding a
greeter would be a second thing to keep working for no gain.

### 2. The GPU, which is the whole reason this revision exists

```nix
microvm.graphics.enable = true;
microvm.graphics.backend = "headless";
services.seatd.enable = true;
hardware.graphics.enable = true;
users.users.dev.extraGroups = [ "video" "render" "seat" ];
```

All four are load-bearing and were each proved necessary by a probe run:

- `enable` alone would open a GTK window on the host; `backend = "headless"`
  gives the guest a `virtio-gpu-gl` device with no host window.
- `seatd` is what lets anything open that device. Without it the DRM node is
  present and unopenable, reported as "not a KMS device".
- `hardware.graphics` is what gives GBM a mesa driver. Without it the device
  opens and `gbm_create_device` fails.

Each carries a comment naming the failure it prevents, because all three
failures surface as the same Hyprland message — `CBackend::create() failed!` —
which names none of them.

`microvm.graphics.vulkan` stays `null`. Venus would be a second thing to keep
working, no caller needs it, and it pulls `hostmem` into the template's
surface.

### 3. How the compositor starts

A systemd **user** service for `dev`, not a system service, because the
compositor belongs to the user's session and its `XDG_RUNTIME_DIR` is
`/run/user/1000`, which a system service would have to fake. Note the
correction above: this is *not* because logind gives the guest a real seated
session — it does not. `seatd` is what makes the seat question irrelevant, and
it is what makes this decision work for a lingering user manager.

The service is `wantedBy` the user's `default.target`, with lingering already
enabled in the guest (`linger-users.service` is in the boot log).

A minimal config file pins **one monitor at a fixed size**. This is not the
"window set on boot" the approver declined: a compositor needs some monitor
configuration, and resolution is the variable that silently changes OCR
numbers. Content stays the caller's.

### 4. Accessibility, including the browsers

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

### 5. Registration

One entry in `data/microvm-templates.nix` — `label`, `module`, `note` — and the
`note` says what it gives and what it costs, like the other nine. It should say
plainly that there is no omarchy shell, because "nixarchy vm" will otherwise
imply one, that this is the first template that asks for a GPU device, and
**how to reach the compositor from outside its session** — `HYPRLAND_INSTANCE_SIGNATURE`
and `WAYLAND_DISPLAY`, both derivable from `$XDG_RUNTIME_DIR`. Per correction 3,
a caller that does not set them sees a healthy compositor report
`is hyprland running?`.

### 6. The check

`checks.microvm-hyprland` and `-tcg` come for free from the `genAttrs` over
`data/microvm-templates.nix` in `flake.nix:1189-1214`. That proves it builds,
which is what the existing check is for, and proves nothing about whether the
compositor runs — see the plan's first step.

**The `-tcg` variant is a question this spec cannot answer.** It overrides
`microvm.qemu.machineOpts` with `accel = "tcg"`; whether `virtio-gpu-gl` and
`egl-headless` work without KVM, and on a runner with no GPU of its own, is
unknown. If it does not, the honest outcome is a documented hole — §3's rule —
rather than a template that quietly drops its GPU under tcg.

## Alternatives rejected

- **Headless, no GPU.** This spec's first revision. Disproved above: GBM is
  aquamarine's only allocator and the headless backend supplies no DRM fd.
  Recorded in full rather than deleted, because the failure is invisible from
  the error message and the next person will otherwise read the same backend
  list and reach the same wrong conclusion.
- **Finding out whether headless is a nixpkgs bug worth reporting upstream.**
  It is not a packaging bug — same source tarball, and the constraint is in
  aquamarine's own design with an upstream `TODO` sitting on it. There is
  nothing to report.
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
- **`microvm.graphics.vulkan = "venus"`.** No caller needs GPU compute in the
  guest, and it adds `hostmem` and a `blob=true` device to a template whose
  first job is to come up at all.

## Risks

- **`egl-headless` may need something of the host's that a runner lacks.** It
  is a qemu display backend that still wants EGL. Proved working on p620;
  whether it survives a CI runner is the `-tcg` question above, and it is now
  the largest remaining unknown in this spec.
- ~~**virtio-gpu in the guest needs mesa to offer a GBM-capable render node.**~~
  Settled by the probe: `card0` and `renderD128` both appear, and
  `hardware.graphics.enable` supplies the driver GBM needs.
- **A user service that fails at boot is invisible.** Unlike the existing
  templates, this one has something that can be running or not. It needs a way
  to tell — even `systemctl --user status` in the note — or a VM with a dead
  compositor looks exactly like a working one until a capture returns nothing.
  And a **user** service writes nothing to the console: the probe that cost the
  first revision an iteration ran as one and reported `Finished` having
  produced no output anywhere. Probes run from the autologin shell on `ttyS0`.
- **Browser wrappers change how those apps launch inside the VM.** Deliberate,
  and surprising if someone expects stock Chromium. The `note` must say so.
- **The closure is much larger than any existing template.** Hyprland,
  tesseract's language data, a browser toolkit and now mesa are not small.
  Worth measuring and stating in the `note`, since a template that takes ten
  minutes to realise on first run should say so.
- **`tesseract` language data.** The default package may carry only English.
  Whoever measures non-English OCR will need more, and that is a caller
  concern, not a template one — but the `note` should not imply otherwise.

## Verification

1. **The guest has a DRM node.** `ls /dev/dri` inside the booted VM shows a
   `renderD*`. Everything else depends on this, and it is the claim this
   revision is built on.
2. **The compositor comes up.** `hyprctl version` answers, and
   `hyprctl -j monitors` reports one monitor at the configured size.
3. **No window appeared on the host** while the VM was running — the property
   `backend = "headless"` exists for, and the one a passing build cannot show.
4. **`grim` captures.** `grim -t ppm` inside the guest produces a file of the
   expected dimensions.
5. **A window appears and is addressable.** `foot` opened inside the guest
   shows up in `hyprctl -j clients` with a class and a title.
6. **The event socket exists**, since nixarchy-voice #28's listener depends on
   it: `$XDG_RUNTIME_DIR/hypr/*/.socket2.sock` is present, and an `openwindow`
   line arrives on it when a window opens.
7. **Accessibility is genuinely on.** A page opened in the wrapped browser
   exposes a link through AT-SPI with bounds and an action — the same probe
   that returned zero nodes on p620 without the flag.
8. **The template check passes**, both the KVM and `-tcg` variants, as it does
   for the other nine — or the `-tcg` hole is documented in `tests/AGENTS.md`
   and `tests/install-matrix.py` per §3.
9. **Nothing else regressed.** `nix flake check` green.

Steps 1–7 need a booted VM and are run by hand. Step 8 is CI's.

Per §1, step 2 is only worth anything if it can fail: removing
`microvm.graphics.backend = "headless"` must produce a host window, and
removing `microvm.graphics.enable` must reproduce `Cannot open backend: no
allocator available` in the guest log. Both breaks go in the PR.
