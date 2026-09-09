---
name: nixos-android
description: >
  REQUIRED for running Android apps on nixarchy — mirroring a phone with scrcpy,
  or running Android in a container with Waydroid. Use for setting either up,
  connecting a phone over USB or Wi-Fi, the adb pairing dance, and when an
  Android app will not start or a phone will not connect. Triggers: Android,
  Waydroid, scrcpy, adb, mirror my phone, phone on my desktop, APK, Play Store,
  wireless debugging, adb pair, adb connect, unauthorised device, "run Android
  apps on Linux", emulator. For general hardware or driver problems use
  `nixos-doctor`; for adding either package to the machine use `nixos`.
---

# Android on nixarchy

Two answers, and they fail in opposite directions. Pick before configuring.

| | scrcpy | Waydroid |
|---|---|---|
| what it is | mirrors and controls **a real phone you own** | runs Android **in a container** on this machine |
| needs a phone | yes | no |
| ARM-only apps | **work** — they run on the phone | **do not run** (see below) |
| banking, DRM, attestation | **work** — real device, real attestation | usually refuse: it is a container |
| Play Store | whatever the phone has | not included by default |
| cost | a USB cable, or a pairing dance | a container runtime and a large image |

**If the person owns the phone and wants their apps, scrcpy is almost always
the better answer**, and it needs nothing configured beyond the package.
Waydroid is for running Android *without* a phone.

## Do not set `programs.adb.enable`

Most NixOS advice about Android says to. **It does nothing now**, and nixpkgs
says so when a system using it is built:

> The option definition `programs.adb' no longer has any effect; please remove
> it. This option is no longer needed as systemd 258 handles uaccess rules
> automatically.

Measured against the current pin: with it set, `services.udev.packages` is
unchanged, `services.udev.extraRules` is byte-identical, no `adbusers` group
appears, and the `etc` derivation is the same store path.

**So USB permissions need no configuration at all.** If a device shows as
`unauthorized`, that is the *phone* not having accepted the RSA prompt — not a
udev rule and not a group. Look at the phone's screen.

## scrcpy

Install through the menu (*Install ▸ Utility ▸ scrcpy*), or declaratively:

```nix
programs.nixarchy.apps.scrcpy = true;
```

### Over USB — try this first

1. On the phone, enable **Developer options** (tap *Build number* seven times),
   then **USB debugging**.
2. Plug it in and accept the RSA prompt **on the phone**.
3. Run `scrcpy`.

That is the whole procedure. No udev rules, no groups, no extra packages.

### `adb` is not on your PATH, and that surprises people

`scrcpy` is a wrapper that puts `adb` on the path **of its own process only**.
So `scrcpy` works, and typing `adb` in a shell says "command not found".

Fine for USB. Wireless pairing needs `adb` in *your* shell, so add it:

```nix
environment.systemPackages = [ pkgs.android-tools ];
```

`android-tools` is deliberately not in the app catalogue: the catalogue derives
a command name from the package, and this one ships `adb`, `fastboot` and a
dozen others under an attribute called `android-tools` — so the machinery would
report it missing on a machine that has it.

### Over Wi-Fi — the part that actually goes wrong

Android 11+ uses **two different ports** and a code on a timer. Getting this
wrong is the usual reason people give up.

1. On the phone: *Developer options ▸ **Wireless debugging*** ▸ on.
2. Tap **Pair device with pairing code**. The phone shows a six-digit code and
   an address ending in a **pairing port**.
3. Pair, using **that** port:

   ```
   adb pair 192.168.1.50:37419
   ```

   It asks for the code. **The code expires in seconds** — have it on screen
   before running this.
4. Now connect, using the **other** port, the one on the main Wireless
   debugging screen:

   ```
   adb connect 192.168.1.50:5555
   ```

5. `scrcpy`

**The two ports are different, and the pairing one changes every time.** Using
the connect port for `adb pair` fails with a message that does not say so.

Pairing is remembered; connecting is not. After either machine reboots, step 4
alone is usually enough.

Discovery, instead of reading numbers off a screen:

```
adb mdns services
```

That needs mDNS resolution on the network. If it lists nothing while the phone
is definitely advertising, the problem is name resolution, not pairing — fall
back to typing the address.

### When it fails

```
adb devices -l
adb kill-server
journalctl -b -k | grep -i usb
```

| symptom | cause |
|---|---|
| `unauthorized` | the phone has not accepted the RSA prompt — look at the phone |
| `offline` | usually a stale wireless connection; `adb disconnect`, then reconnect |
| pair fails instantly | the code expired, or the connect port was used |
| nothing from `adb mdns services` | mDNS, not adb — try the address by hand |
| black screen, phone fine | the app blocks screen capture (banking, DRM) |

## Waydroid

```nix
virtualisation.waydroid.enable = true;
```

That is genuinely all the configuration. It puts `waydroid` on PATH and adds
the `waydroid-container` service. It adds **no kernel modules**: `binder` comes
from the mainline kernel, which a stock nixarchy kernel is. A custom kernel may
not have it.

After the rebuild, the image is downloaded once:

```
waydroid init
waydroid session start
waydroid show-full-ui
```

`waydroid first-launch` does init-then-start in one step if it has not been
initialised yet. Other subcommands worth knowing: `status`, `session`,
`container`, `app`, `shell`, `logcat`, `log`.

### Say this before they install it

**ARM-only apps will not run.** Waydroid executes Android on *this* machine's
kernel with no CPU emulation — that is why it is fast — so an app built only
for ARM has nothing to run on. It would need a translation layer (libhoudini,
libndk) that Waydroid does not ship and nixpkgs does not package. A large share
of popular apps are ARM-only, so "it installed and the app crashes immediately"
is the expected outcome for those, not a misconfiguration.

**No Play Store** by default: the image is GAPPS-free. A feature for some
people and a surprise for others.

**Attestation fails.** Banking and DRM apps generally detect the container and
refuse. That is the class scrcpy exists for.

### When it fails

```
waydroid status
waydroid log
```

If `waydroid init` cannot download, that is a network problem rather than a
Waydroid one. If the container starts and no UI appears, check that `waydroid
status` reports a **session** as well as a container — they are separate
things, and `session start` is a separate step.

## Rules

- **Never tell someone to set `programs.adb.enable`.** It is inert, and the
  advice sends them hunting udev rules when the real answer is a prompt on the
  phone's screen.
- **Ask which of the two they want before configuring either.** Installing
  Waydroid for somebody who has the phone in their pocket is a large download
  to arrive at the worse answer.
- **State the ARM limitation before the install, not after the crash.**
- Both are declarative here. Neither needs an imperative installer, and nothing
  installed imperatively survives a rebuild.
