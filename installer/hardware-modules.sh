#!/usr/bin/env bash
# Which nixos-hardware modules this machine wants. One name per line, stdout.
#
# This is nixarchy's answer to Omarchy's install/hardware/ -- ~35 shell scripts
# gated at runtime on DMI strings, PCI ids, /proc/cpuinfo model numbers and ACPI
# HIDs. We do not write those. nixos-hardware already carries 439 machine
# modules maintained by people who own the machines, so the only part worth
# porting is the GATING, and that is this file.
#
# Only the `common-*` modules are chosen here, and that is a deliberate line.
# They key on facts a script can read without being wrong -- CPU vendor, GPU
# vendor, is-this-a-laptop, is-the-disk-rotational -- and every one of them is
# mkDefault config that a user can override. The 412 machine-specific modules
# key on DMI product strings with no machine-readable table anywhere, so
# picking one by fuzzy match risks importing dell-xps-13-9310 onto a 9315.
# Wrong quirks are worse than no quirks: they are a machine that boots to a
# black screen, and the person cannot tell it was us. Those are printed as a
# suggestion by `nixarchy doctor` instead, for a human to confirm.
#
# Every path is overridable so the whole thing can be driven against fixtures.
# checks.install's guest is one machine; these rules are about being on many.
set -uo pipefail

: "${NIXARCHY_SYSFS_PCI:=/sys/bus/pci/devices}"
: "${NIXARCHY_SYSFS_CLASS:=/sys/class}"
: "${NIXARCHY_SYSFS_BLOCK:=/sys/block}"
: "${NIXARCHY_CPUINFO:=/proc/cpuinfo}"

modules=()

# ---- CPU: microcode -------------------------------------------------------
# cpu-only rather than common-cpu-intel: the latter imports ../../gpu/intel
# unconditionally, so an Intel CPU next to a discrete-only GPU would drag in
# the whole Intel media stack for a GPU that is not there. Omarchy gates its
# CPU and GPU scripts separately for the same reason, and so does this.
case "$(grep -m1 '^vendor_id' "$NIXARCHY_CPUINFO" 2>/dev/null)" in
  *GenuineIntel*) modules+=("common-cpu-intel-cpu-only") ;;
  *AuthenticAMD*) modules+=("common-cpu-amd") ;;
esac

# ---- GPU ------------------------------------------------------------------
# sysfs, not lspci, for the reason Omarchy's own bin/omarchy-hw-nvidia-gsp
# gives: "lspci reads PCI config space and resumes runtime-suspended GPUs."
# It is also the only one of the two guaranteed to be on the installer medium.
intel_gpu="" amd_gpu="" nvidia_gpu=""
for d in "$NIXARCHY_SYSFS_PCI"/*/; do
  [ -r "$d/class" ] && [ -r "$d/vendor" ] || continue
  case "$(cat "$d/class")" in 0x03*) ;; *) continue ;; esac
  case "$(cat "$d/vendor")" in
    0x8086) intel_gpu=1 ;;
    0x1002) amd_gpu=1 ;;
    0x10de) nvidia_gpu=1 ;;
  esac
done

[ -n "$intel_gpu" ] && modules+=("common-gpu-intel")
[ -n "$amd_gpu" ] && modules+=("common-gpu-amd")

# NVIDIA is deliberately NOT selected, and it is the one omission worth
# defending. common-gpu-nvidia is not a driver choice -- the choice is between
# the open and legacy_580 packages, split at PCI device id 0x1e00 (Omarchy's
# bin/omarchy-hw-nvidia-gsp draws the same line), and on a hybrid laptop it
# also needs the two PRIME bus ids in DECIMAL. Get any of that wrong and the
# machine has no screen, which is not a failure a first boot can explain.
# `nixarchy doctor` already computes the bus ids and prints the snippet, which
# is the right place for a choice a person should see before making it.
if [ -n "$nvidia_gpu" ]; then
  echo "# nvidia: run 'nixarchy doctor' for the driver and PRIME lines" >&2
fi

# ---- chassis and disk -----------------------------------------------------
# A battery is the honest laptop test. DMI chassis_type is a string vendors
# get wrong -- Omarchy's own omarchy-hw-laptop reaches for the ACPI lid switch
# FIRST and only falls back to chassis_type, which says what they think of it.
laptop=""
for b in "$NIXARCHY_SYSFS_CLASS"/power_supply/*/; do
  [ -r "$b/type" ] || continue
  [ "$(cat "$b/type")" = "Battery" ] && { laptop=1; break; }
done

# Rotational is per-queue and authoritative; the name (sd vs nvme) is not --
# a USB SSD enumerates as sda. Any non-rotational disk is enough for fstrim to
# be worth enabling, which is all common-pc-ssd does.
ssd=""
for b in "$NIXARCHY_SYSFS_BLOCK"/*/; do
  case "$(basename "$b")" in loop* | ram* | sr* | zram*) continue ;; esac
  [ -r "$b/queue/rotational" ] || continue
  [ "$(cat "$b/queue/rotational")" = "0" ] && { ssd=1; break; }
done

# common-pc-laptop imports common-pc, and common-pc-laptop-ssd imports both of
# those plus the trim -- so exactly one of these four is ever right, and
# listing two would be importing the same module twice under different names.
if [ -n "$laptop" ] && [ -n "$ssd" ]; then
  modules+=("common-pc-laptop-ssd")
elif [ -n "$laptop" ]; then
  modules+=("common-pc-laptop")
elif [ -n "$ssd" ]; then
  modules+=("common-pc-ssd")
else
  modules+=("common-pc")
fi

printf '%s\n' "${modules[@]}"
