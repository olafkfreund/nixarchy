---
status: approved
issue: 821
author: olafkfreund
---

# Intent: a graphical microvm template, so desktop tooling can be tested off the real session

Closes #821.

## Problem

`nixarchy vm` has nine templates and all nine are headless: `shell`, `python`,
`node`, `podman`, `k3s`, `persistent`, `agent`, `agent-claude`. There is
nowhere to run a compositor, so anything that reads or drives a desktop has to
be tested against somebody's actual session.

That is not hypothetical. Work on nixarchy-voice's screen reading and window
targeting (nixarchy-voice #26, #27, #28) took every measurement on p620's live
session: spawning probe windows, launching a throwaway Chrome, moving the
pointer, and OCRing whatever was on screen at that moment.

Two costs, and the second is the one that justifies this issue.

**It is disruptive.** Driving input and opening windows on the desktop someone
is using rules out running any of it unattended, and makes each run a thing
that has to be watched.

**It is not reproducible, and it corrupted a published figure.** Full-screen
OCR measured anywhere from 1.1s to 5.3s across a single session. The variance
was screen *content*, not code — a screen with 5244 characters on it costs
several times one with 700. A figure of 3.97s went into an intent as though it
were *the* number, and had to be corrected in the spec that followed to "1-5s
depending on what is on screen". A known window set would have produced one
number and no correction.

There is a third thing a headless fleet cannot reach at all. nixarchy-voice
#31 wants to use the accessibility tree instead of OCR, and measured on p620
the AT-SPI tree exposes **zero** actionable elements in every running
application — Chrome 13 nodes of frames and no content, Electron 2, quickshell
1, terminals nothing. With `--force-renderer-accessibility` a throwaway Chrome
returned a link with exact bounds and a `jump` action. So that work is not
blocked on code; it is blocked on having a desktop configured to expose a tree,
and nobody should reconfigure their daily session to find out.

## Proposed outcome

- `nixarchy vm templates` lists a graphical template, and `nixarchy vm create
  <name> --template <it>` gives a VM that boots to a running compositor.
- It carries the tools desktop automation shells out to, so a program under
  test finds what it expects on PATH.
- Its screen is a known size with a known set of windows, so a measurement
  taken twice gives the same answer twice.
- Accessibility is on, so the AT-SPI path can be evaluated at all.
- Nothing about it requires the host's session, and nothing it does can disturb
  one.

## Affected users and systems

- `data/microvm-templates.nix` — one more entry.
- `modules/microvm/templates/` — one more module.
- `tests/` — the template check that builds every template's closure, which
  this must not break and should extend to.
- Anyone writing or testing desktop automation against nixarchy:
  nixarchy-voice #30, #31, #35, and ai-mirror.
- Not the installer, not the host modules, not any existing template.

## Constraints

- **A template is exactly a NixOS module**, plain NixOS plus whatever
  microvm.nix's options add, and no nixarchy vocabulary
  (`data/microvm-templates.nix`). A user who outgrows it copies the module into
  a flake of their own and grows it from the NixOS manual.
- **Nothing may depend on a per-VM value.** One runner per template is shared
  by every VM named from it; the name is a directory the runner is `exec`'d
  inside, never a Nix argument.
- **Persistence, if any, is a `microvm.volumes` entry with a relative image
  path**, which is what lets one closure serve two VMs with two disks.
- It imports nothing nixarchy ships beyond what `lib.mkMicrovm` already gives
  it via `modules/microvm/guest.nix`: the shared store, the host-directory
  share at `/mnt/host`, user networking, autologin, the runtime hostname.
- It must keep building under the existing template check. A template that
  cannot be built is worse than no template, because the failure surfaces at
  `nixarchy vm run` on somebody's machine.
- Memory: the 1 GiB default is microvm.nix's, and `guest.nix` does not raise
  it. A compositor plus a browser will want more, and saying so is the
  template's job (`python.nix` already does this for its own reason).

## Open questions

1. **How Hyprland gets a display in the guest, and this is the one that
   decides whether the issue is cheap or not.** aquamarine tries seatd, then
   logind, then DRM. Verified while scoping: a second Hyprland on a host whose
   session logind already owns dies with `CBackend::create() failed!`, and the
   reason — `Could not take control of session: Device or resource busy` —
   is four lines down its own log rather than in the crash. A guest owns its
   own seat, so that specific failure does not apply, but the choice remains:
   virtio-gpu and a real DRM device, or headless with no DRM at all. Headless
   is lighter and `grim` should still capture a framebuffer. Worth proving
   before the spec commits to either.

2. **Hyprland, or something smaller?** The tooling that needs this talks to
   `hyprctl` and to Hyprland's event socket, so for nixarchy-voice it has to be
   Hyprland. A generic `wayland` template on a lighter compositor would serve a
   wider audience and none of the actual callers. One template or two?

3. **How far does "known window set" go?** A template that opens windows on
   boot is opinionated in a way none of the other nine is, and the bar above
   says a template is plain NixOS. The alternative is that the template
   provides only the compositor and tools, and whoever measures opens their own
   windows through the `/mnt/host` share. The second is more in keeping; the
   first is what actually makes a measurement repeatable.

4. **Does the omarchy shell belong in it?** Without it this is "a Hyprland VM",
   not "a nixarchy VM", and bar and plugin behaviour stays untestable. With it
   the closure is much larger and the template stops being plain NixOS. The
   callers listed above need none of it today.

5. **Accessibility flags: template or caller?** `QT_ACCESSIBILITY=1` is an
   environment variable the template can set. Chrome's
   `--force-renderer-accessibility` is a launch argument, which belongs to
   whoever launches Chrome. Setting one and not the other is a half-measure
   that will be mistaken for the whole.
