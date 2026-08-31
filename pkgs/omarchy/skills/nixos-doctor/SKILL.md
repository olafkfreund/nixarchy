---
name: nixos-doctor
description: >
  REQUIRED for reading system logs and taking a picture of the whole machine's
  state on NixOS — failed units, journal errors, boot problems, disk and memory,
  hardware and network health, and what changed in the last rebuild. Use at any
  time something is wrong and the cause is not yet known, when asked how the
  system is doing, for a health check or status report, when the machine is
  behaving oddly since an update, or as the first step before debugging anything
  specific. Triggers: journalctl, dmesg, system logs, check the logs, health
  check, system status, what's wrong, failed units, errors, warnings, "since the
  update", "acting weird", disk full, "not sure what broke", triage.
  For a crashed program with a core dump use `diagnose-crash`.
---

# NixOS Doctor Skill

The skill to reach for **before** you know what is wrong. It answers "what is the
state of this machine" in a fixed order, so nothing obvious gets skipped while
chasing a theory.

Two NixOS-specific advantages worth using immediately:

- **The previous working system is still on disk.** "It broke after an update" is
  answerable by diffing generations, and fixable by rolling back.
- **The whole configuration is one readable tree.** You never have to guess what
  is installed or enabled — you can read it.

## The Sweep

Run this in order. Do not skip ahead to a hunch.

```bash
# 1. What is broken right now
systemctl list-units --failed
systemctl --user list-units --failed

# 2. This boot's errors, no noise
journalctl -b -p err --no-pager | tail -40

# 3. Kernel — hardware, drivers, filesystems, OOM
journalctl -b -k -p warning --no-pager | tail -40

# 4. Resources
df -h | grep -vE 'tmpfs|/nix/store'
free -h
uptime

# 5. What changed, and when
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5
```

Those five commands identify the cause of most problems. Report what they say
before proposing a fix.

### Then, by symptom

```bash
# Boot problems
journalctl -b -1 -p err --no-pager | tail -40    # the PREVIOUS boot, if it hung
systemd-analyze blame | head -20

# Network
ip a; ip route; resolvectl status
ping -c3 1.1.1.1 && ping -c3 nixos.org           # routing vs DNS, in one line

# Hardware
sensors                                          # temperatures
journalctl -b -k | grep -iE 'error|fail|i/o|reset|thermal'
sudo smartctl -H /dev/nvme0n1                    # disk health
lsblk -f

# Memory pressure / freezes
journalctl -b | grep -iE 'oom|killed process|out of memory'
cat /proc/pressure/memory /proc/pressure/io

# Graphical session
journalctl --user -b -u hyprland --no-pager | tail -40
journalctl -b | grep -iE 'drm|amdgpu|nvidia|gpu hang'
```

## Reading the Journal Properly

The journal is the whole logging story on NixOS — there are no per-service files
in `/var/log` to grep.

```bash
journalctl -u foo                 # one unit
journalctl -u foo -b              # this boot only
journalctl -u foo -f              # follow, while you reproduce the problem
journalctl -b -1                  # the previous boot (essential after a hang)
journalctl --since "10 min ago"
journalctl --since "2024-01-15 09:00" --until "2024-01-15 10:00"
journalctl -p err                 # emerg,alert,crit,err — 0..3
journalctl -k                     # kernel only (dmesg, but persistent)
journalctl -g 'regex' --no-pager  # grep, server-side
journalctl -o json-pretty -n 1    # every field, when a message is ambiguous
journalctl _PID=1234
journalctl --disk-usage
```

Two habits that save real time:

- **`-b -1` after any hang, freeze or unclean reboot.** The evidence is in the
  boot that died, not the one you are typing in.
- **`--no-pager` plus `tail`** — otherwise output blocks waiting for a pager that
  an agent cannot drive.

Persistence across reboots is not universal. Check, and enable it if a
post-mortem is going to be needed:

```nix
services.journald.extraConfig = ''
  Storage=persistent
  SystemMaxUse=1G
'';
```

### Severity, honestly

Most `warning` lines on a healthy Linux box are noise — firmware chatter,
ACPI complaints, unsupported hardware probes. **Start at `-p err`.** Reporting a
list of harmless warnings as findings is worse than saying nothing, because it
buries the one line that matters.

## "It Broke After an Update"

This is the strongest position NixOS puts you in. Answer it with evidence:

```bash
# What changed between the last two system generations
nix profile diff-closures --profile /nix/var/nix/profiles/system | tail -30

# When each generation was built
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# And if it is bad — go back, now
sudo nixos-rebuild --rollback switch
```

Or pick an older generation from the boot menu. A rollback is complete and
instant; there is no partial state to clean up. Offer it early rather than
debugging a broken desktop from inside the broken desktop.

`nix profile diff-closures` is a real answer to "what did that update change" —
package-by-package, with version deltas. It beats reading a changelog.

**Caveat:** a rollback restores the *system*, not mutable state. Databases,
`/var/lib` contents, model weights and home directories do not roll back. Say so
when the failing thing is stateful.

## Disk Full

Usually the Nix store, and usually not urgent to solve destructively:

```bash
df -h
du -xh --max-depth=1 / 2>/dev/null | sort -rh | head -15
nix path-info -Sh /run/current-system            # size of the current system closure
du -sh /var/log/journal
```

```bash
sudo nix-collect-garbage --delete-older-than 30d   # keeps a rollback window
sudo nix-collect-garbage -d                        # deletes EVERY old generation
sudo nix store optimise                            # dedupe by hard-linking; safe
```

**`-d` destroys the rollback safety net.** Ask first, always, and prefer the
`--delete-older-than` form. `nix store optimise` frees space with no downside and
should be offered before either.

Note that garbage collection only frees what nothing references — if the machine
is full because one closure is genuinely huge (a global `cudaSupport`, a
container image, model weights), GC will not help and the honest answer is to say
so.

## Reading the Configuration

```bash
echo "${NIXARCHY_FLAKE:-/etc/nixos}"       # where the config lives
nixos-option services.nginx                # value AND which file set it
nixos-version --json
systemctl cat foo                          # the unit Nix actually generated
ls -l /run/current-system                  # the store path in use right now
```

`nixos-option` answering "where did this value come from" is what turns "why is
this enabled" from a grep hunt into one command.

## Health Report Template

When asked for a picture of the system, report in this shape — facts first, one
conclusion, and be explicit about what is fine:

```
State:     up N days, load a/b/c, N failed units
Disk:      / at N% (X GB free), /nix at N%
Memory:    X of Y GB used, swap N%, PSI avg10 N
Errors:    <the actual err-level lines, or "none this boot">
Hardware:  temps, disk SMART, anything in the kernel log
Changed:   generation N built <date>; last change was <what>
```

If everything is fine, say that plainly. A clean bill of health is a useful
result, and padding it with warnings to look thorough is not.

## Escalating

| Finding | Go to |
|---|---|
| A specific unit failing | `nixos-services` skill |
| A program crashed / core dump | `diagnose-crash` skill |
| Slow, hot, stuttering, bad battery | `nixos-performance` skill |
| GPU not working, black screen | `nixos-gpu` skill |
| Something exposed, or a firewall question | `nixos-security` skill |
| Needs a package or option changed | `nixos` skill |
| Desktop, Hyprland, theming | `nixarchy` skill |

## Rules

- **Run the sweep before forming a theory.** The failed-units list and `-p err`
  take three seconds and are right more often than a hunch.
- **Always `--no-pager`** on journalctl, and bound the output with `tail` or `-n`.
- **Start at `-p err`.** Do not report routine warnings as findings.
- **Quote the actual log line.** A paraphrased error is not evidence, and the
  exact text is what makes the cause searchable.
- **Use `-b -1` after any hang or unclean reboot.**
- **Offer rollback early** when the timeline points at an update — it is faster
  than debugging, and losing nothing is the whole point of the design.
- **Never garbage-collect without asking**, and never with `-d` as the first
  suggestion.
- Say plainly when a check comes back clean. Do not manufacture findings.
