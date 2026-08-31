---
name: nixos-performance
description: >
  REQUIRED for tuning this NixOS machine's performance, responsiveness, battery
  life, boot time or thermals — kernel choice and parameters, sysctl, CPU
  governor, zram and swap, I/O scheduler, filesystem mount options, memory
  pressure, and build speed. Use when the machine feels slow, stutters, runs hot,
  drains battery, boots slowly, freezes under memory pressure, or when asked to
  optimize the hardware, pick a kernel, or make Nix builds faster. Triggers:
  slow, laggy, stutter, optimize, tune, performance, latency, kernelParams,
  kernelPackages, sysctl, zram, swappiness, governor, powersave, TLP, battery,
  thermal, throttling, boot time, systemd-analyze, I/O scheduler, nofile, OOM.
  For GPU drivers use `nixos-gpu`; for a broad health check use `nixos-doctor`.
---

# NixOS Performance Skill

**Measure first. Every time.** Almost every "NixOS is slow" report has one
specific cause, and the tuning that fixes it is one option. Applying a page of
sysctl tweaks that someone posted for a database server to a laptop that is
actually thermal-throttling makes the machine worse and hides the real problem.

Everything here is route 2 in the `nixos` skill: edit the flake, rebuild. The
good news is that a bad tuning change is one `nixos-rebuild --rollback switch`
from gone, so measuring, changing one thing, and measuring again is cheap.

## Step 1: Find Out What Is Actually Slow

```bash
# Live picture — CPU, memory, I/O, per-process
btop

# Is it CPU, and is it throttling?
watch -n1 'grep MHz /proc/cpuinfo | head -8'
sensors                                  # temperatures; sustained >90C is throttling
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Is it memory?
free -h
journalctl -b | grep -i "oom\|killed process"
cat /proc/pressure/memory                # some avg10 above ~10 means real stalls
cat /proc/pressure/io                    # same for I/O — the single best "why is it stuttering"

# Is it disk?
iostat -x 1 5                            # %util near 100 = saturated
df -h                                    # a full disk is slow before it is full

# Is it boot?
systemd-analyze
systemd-analyze blame | head -20
systemd-analyze critical-chain
```

`/proc/pressure/*` (PSI) is the most under-used number on a Linux box: it says
directly how much time tasks spent stalled waiting for CPU, memory or I/O.
`avg10` near zero means that resource is *not* your problem, whatever it feels
like.

Report what you measured before changing anything.

## Kernel

```nix
boot.kernelPackages = pkgs.linuxPackages_latest;   # newest mainline
# boot.kernelPackages = pkgs.linuxPackages;        # LTS — the default, and the safe pick
# boot.kernelPackages = pkgs.linuxPackages_zen;    # desktop-latency oriented
# boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
```

- **`linuxPackages` (LTS) is the right default.** Move off it for a *reason* —
  new hardware not yet supported, a specific fixed bug — not for speed. Kernel
  version rarely explains a slow desktop.
- **A non-default kernel may not be in the binary cache**, which means compiling
  it locally on every update. `linuxPackages_zen` and `_xanmod_*` are usually
  cached; a custom `.override` is not. Warn about this before suggesting one.
- Out-of-tree modules (NVIDIA, VirtualBox, ZFS) must support the kernel you pick.
  `linuxPackages_latest` regularly breaks ZFS. The rebuild will tell you, loudly.

### Kernel parameters

```nix
boot.kernelParams = [
  "quiet" "splash"                 # cosmetic; faster-looking boot
  "mitigations=off"                # SEE WARNING BELOW
];
```

**`mitigations=off` is a security decision, not a tuning knob.** It disables
Spectre/Meltdown-class mitigations. On a single-user machine that runs no
untrusted code it can be worth 5–30% on syscall-heavy work; on anything running
other people's code, containers, or a browser you care about, it is not. Never
add it silently — state the trade-off and let the user choose.

## Memory: zram and swappiness

The single highest-value change on most machines, especially with 8–16 GB:

```nix
zramSwap = {
  enable = true;
  algorithm = "zstd";
  memoryPercent = 50;      # of RAM, compressed ~3:1, so ~50% costs ~17% real
};

boot.kernel.sysctl = {
  "vm.swappiness" = 180;              # with zram, swapping is cheap — swap eagerly
  "vm.watermark_boost_factor" = 0;
  "vm.watermark_scale_factor" = 125;
  "vm.page-cluster" = 0;              # zram is random-access; no read-ahead
};
```

**`vm.swappiness = 180` is correct for zram and wrong for disk swap.** The old
"lower swappiness is better" advice assumes a spinning disk. With zram the swap
device is RAM, so pushing cold pages into it is nearly free. If the machine has
disk swap and no zram, leave swappiness near the default 60 (or 10 on a slow HDD).

For a machine that freezes hard under memory pressure rather than killing
something, add a userspace OOM killer:

```nix
systemd.oomd.enable = true;               # on by default in recent NixOS
services.earlyoom.enable = true;          # acts sooner; good on desktops
```

A hard freeze under memory pressure is one of the few problems users report as
"my computer crashed" that has a clean, cheap fix.

## CPU frequency and power

Desktop / always-plugged-in:

```nix
powerManagement.cpuFreqGovernor = "performance";
```

Laptop — pick **one** power manager, never several:

```nix
services.tlp.enable = true;                  # most control
# OR
services.power-profiles-daemon.enable = true;  # simpler; what GNOME/KDE toggles use
services.thermald.enable = true;               # Intel only; prevents thermal shutdown
```

**TLP and power-profiles-daemon conflict.** Enabling both gives fighting daemons
and erratic frequency behaviour. NixOS will usually complain; if it does not, the
symptom is a laptop that randomly stops boosting.

```nix
services.tlp.settings = {
  CPU_SCALING_GOVERNOR_ON_AC = "performance";
  CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
  CPU_BOOST_ON_BAT = 0;
  START_CHARGE_THRESH_BAT0 = 40;    # ThinkPad-style battery longevity
  STOP_CHARGE_THRESH_BAT0 = 80;
};
```

Modern Intel and AMD use `intel_pstate` / `amd_pstate`, where only `performance`
and `powersave` governors exist — `ondemand` and `conservative` will not apply
and the option silently does nothing. Check what you actually have:

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
```

On recent AMD, `amd_pstate=active` with EPP usually beats anything you can tune
by hand.

## Storage

```nix
fileSystems."/" = {
  options = [ "noatime" ];              # skip a write on every read
};
```

For Btrfs, compression is usually a net **win** on speed as well as space — less
I/O beats the CPU cost on anything modern:

```nix
fileSystems."/".options = [ "noatime" "compress=zstd:1" "ssd" ];

services.btrfs.autoScrub = { enable = true; interval = "monthly"; };
```

SSD maintenance:

```nix
services.fstrim.enable = true;      # weekly TRIM. Prefer this to the `discard` mount option
```

`discard` (inline TRIM) can hurt latency; the weekly `fstrim` timer is the
recommended form and is what `services.fstrim` sets up.

Do not set an I/O scheduler by hand unless you have measured a problem — the
kernel picks `none`/`mq-deadline` correctly for NVMe and SATA SSDs. If you must:

```nix
services.udev.extraRules = ''
  ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
'';
```

## Nix build speed

Frequently the actual complaint when someone says "NixOS is slow".

```nix
nix.settings = {
  max-jobs = "auto";
  cores = 0;                     # all cores per job
  auto-optimise-store = true;    # dedupe by hard-linking
};

# Use the community cache instead of compiling
nix.settings = {
  substituters = [ "https://nix-community.cachix.org" ];
  trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
};
```

Then check whether you are building instead of downloading:

```bash
nix build <flake>#nixosConfigurations.<host>.config.system.build.toplevel --dry-run
```

If that prints a long "will be built" list, something in the config forces source
builds — most often a global `cudaSupport`/`rocmSupport`, or an `overlay` that
overrides a widely-depended-on package. That is the fix, not more cores.

Garbage collection keeps the store from becoming the bottleneck:

```nix
nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 30d";     # keeps a rollback window
};
```

## Desktop responsiveness

```nix
boot.kernel.sysctl = {
  "kernel.sched_cfs_bandwidth_slice_us" = 3000;
  "vm.dirty_ratio" = 10;              # write back sooner; avoids long stalls
  "vm.dirty_background_ratio" = 5;
  "net.core.default_qdisc" = "cake";  # kills bufferbloat on a home connection
  "net.ipv4.tcp_congestion_control" = "bbr";
};
```

`cake` + `bbr` is the one networking change worth making unconditionally on a
home line: it fixes the "everything lags while something downloads" problem
outright.

Raise the file-descriptor limit only if something actually hits it (`EMFILE`,
"too many open files"):

```nix
security.pam.loginLimits = [
  { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
];
```

## Boot time

```bash
systemd-analyze blame | head -20
systemd-analyze critical-chain
```

Usual offenders and their fixes:

| Slow unit | Fix |
|---|---|
| `NetworkManager-wait-online` | `systemd.services.NetworkManager-wait-online.enable = false;` if nothing needs the network at boot |
| `systemd-udev-settle` | A module still using it; usually removable |
| Long initrd | `boot.initrd.systemd.enable = true;` and trim `boot.initrd.availableKernelModules` |
| Filesystem check every boot | Expected periodically; a full check on every boot means an unclean shutdown |

`boot.loader.timeout = 1;` shaves the menu wait but keeps rollback reachable —
do not set it to `0`, that is your recovery path.

## Rules

- **Measure, change one thing, measure again.** A list of ten sysctls applied at
  once teaches you nothing and usually includes something wrong for this machine.
- **Never apply `mitigations=off` without stating what it costs.**
- **Never enable two power managers.** Pick TLP or power-profiles-daemon.
- **`vm.swappiness` high is only right with zram.** With disk swap it is a bug.
- **Warn when a kernel or flag choice means compiling instead of downloading** —
  the "optimization" can cost hours of CPU on every update.
- Prefer the option NixOS provides (`zramSwap`, `services.fstrim`,
  `powerManagement.*`) over hand-written udev rules and tmpfiles.
- Tuning changes are cheap to undo. Say so, and use `nixos-rebuild test` so a bad
  one does not survive a reboot.
