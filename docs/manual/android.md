---
title: Android
---

# Android

Two different things people mean by "Android on my desktop", and the honest
answer is that they are different tools:

- **Apps from the phone you already own** — mirror its screen and use it with
  the keyboard and mouse. That is [scrcpy](#scrcpy), and it is the one most
  people want.
- **Android apps with no phone at all** — a container running Android.
  That is [Waydroid](#waydroid), and it comes with a real caveat.

Neither is installed by default. Both are in the menu under
_Install > Development_ (`Super + Space`), or from a terminal.

## scrcpy

```bash
omarchy-pkg-add scrcpy
```

### Over USB, which is the easy case

Plug the phone in, turn on _Developer options > USB debugging_, accept the
prompt the phone shows, and run:

```bash
scrcpy
```

That is the whole procedure. No udev rules to write, no group to join —
nixarchy already ships what systemd needs for this, and `programs.adb.enable`
is **not** something to add: nixpkgs made it inert, and it no longer does
anything at all.

If nothing happens, look at the phone's screen. The prompt asking you to trust
this computer is easy to miss, and until you accept it `adb` sees a device it
is not allowed to talk to.

### Over Wi-Fi, which is where people get stuck

Wi-Fi is what most people actually want — the phone on the desk, not tethered
— and the sequence Android 11+ requires is genuinely confusing:

- there are **two ports**, and they are different: one to *pair*, one to
  *connect*
- the pairing port **changes every time** you open the pairing dialog
- the pairing code is valid for **seconds**, not minutes
- *pairing* and *connecting* are separate steps, and nothing on either screen
  says so

So nixarchy wraps it:

```bash
omarchy-pkg-add android-tools   # adb, which scrcpy needs for Wi-Fi
```

**One time per phone**, pair it. On the phone: _Settings > Developer options >
Wireless debugging > Pair device with pairing code_. Leave that dialog open,
and on the desktop:

```bash
nixarchy android pair
```

It finds the phone itself, asks for the six digits, and tells you plainly if
it failed — an expired code and a mistyped one look identical to `adb`, so it
says both are possible rather than pretending to know.

**Every time after that**, with _Wireless debugging_ on:

```bash
nixarchy android connect
scrcpy
```

### The other commands

| | |
|---|---|
| `nixarchy android find` | which phones are advertising, and whether they are ready to pair or ready to connect |
| `nixarchy android list` | what `adb` can see right now |
| `nixarchy android forget HOST:PORT` | end the session |

`forget` disconnects; it cannot un-pair. The phone holds the other half of
that trust, and revoking it under _Wireless debugging > Paired devices_ is
what actually revokes it.

### If discovery finds nothing

Every guide online says to run `adb mdns services`. On NixOS that prints:

```
adb: mdns is not supported by this version of adb.
```

nixpkgs builds `android-tools` without an mDNS backend, so `adb` cannot browse
the network at all. This is not something you can fix by enabling a service —
the gap is inside `adb`.

`nixarchy android` does not use it. It asks **avahi** instead, which nixarchy
already runs, and which can see exactly what `adb` cannot. So discovery works
here even though the command every tutorial names does not.

If it still finds nothing, the usual cause is that the pairing dialog is
closed. _Wireless debugging_ being on is enough to **connect**, but **pairing**
advertises only while that dialog is on screen.

You can always skip discovery and type the address the phone shows:

```bash
nixarchy android pair 192.168.1.74:41234
nixarchy android connect 192.168.1.74:33811
```

## Waydroid

```bash
nixarchy-service-enable waydroid
```

Waydroid runs Android in a container, sharing your kernel — so it needs no
phone, and it is fast, because nothing is emulated.

That is also its limitation, and it is worth knowing before you install it:
**apps compiled only for ARM will not run**, because your CPU is x86 and
nothing here translates between them. Most large apps ship an x86 build and
are fine; many smaller ones do not and simply fail to install.

We do not ship an ARM translation layer. That is upstream's to solve, and no
wrapper on this side changes it.

## Which one

**scrcpy** if you have the phone — it is your real apps, your real logins, and
your real notifications, and there is no compatibility question at all.

**Waydroid** if you do not, and if the apps you need publish an x86 build.
