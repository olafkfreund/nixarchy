#!/usr/bin/env python3
"""Install a PUBLISHED image, every way a person can, in real qemu.

Not a nix check and cannot be one: these boot the actual ISO a user
downloaded, with a network, and the thing being asked is whether that file
installs a machine that boots. `nix build .#checks...` answers a different
question.

Three modes, and each exists because the one before it missed something:

  matrix.py <cell>          scripted: answers file, asserts the installer
                            exited 0. Fast, unattended, and BLIND to the
                            greeter and the disk-mode menu, which it skips.

  matrix.py <cell> manual   no answers disk, nothing driving it. A person
                            drives the TUI over VNC exactly as a user does.
                            This is the mode that found #382's real cause.

  matrix.py <cell> boot     re-boots the machine a cell just installed, from
                            its own disk, no ISO. "The installer exited 0" and
                            "the machine boots" are different claims, and the
                            hardware reports are about the second one.

The cells cross the two published images with the three disk modes. `free`
gets a disk shaped like a machine that already has Windows on it -- a 512 MiB
ESP, a 40 GiB data partition, and 59.5 GiB of free space after them -- because
the installer refuses `free` under 32 GiB and a blank disk therefore tests
nothing while looking like a pass.

WHAT THIS IS FOR, and the reason it is in the repo rather than a scratch
directory:

  Every automated install check in tests/ uses username `omarchy`, which is
  the name the ISO's reference closure is BAKED for. It is the one username
  that cannot diverge. On 2026-09-07 a full 6/6 green matrix ran against the
  published v4.0.2-8 offline image; the same image, driven by hand with the
  username `olaf`, died in the stdenv source bootstrap:

    hm_hmfontconfigfonts.xml -> libxml2+py -> doxygen -> cmake
      -> libarchive -> attr -> download.savannah.gnu.org

  home-manager's per-user fontconfig file is not in any baked closure, and
  the offline image had substituters = lib.mkForce [ ], so it could not fetch
  it and had to build it. #384 gave both images substituters; re-running these
  same cells against an image built from that fix, with the same username,
  installed and booted clean.

  So: when changing anything about what the ISO carries, run the `manual`
  mode with a username that is NOT `omarchy`. The scripted cells cannot see
  this class of bug and never will.

Environment: MATRIX_ISO_DIR (where the published .iso files are),
MATRIX_OFFLINE_ISO / MATRIX_NET_ISO (override one image -- how a freshly
built ISO gets tested), MATRIX_WORK (where disks live; not /tmp, which is
tmpfs here), MATRIX_OVMF (firmware, resolved from nixpkgs otherwise).

Every VM is watchable on VNC throughout; the port is printed at startup.
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qmp import Qmp, wait_for                                    # noqa: E402

ISOS = os.environ.get("MATRIX_ISO_DIR", "/mnt/data/vmtest/isos")
WORK = os.environ.get("MATRIX_WORK", "/mnt/data/vmtest")
# Overridable so the same cells can be re-run against a freshly BUILT image
# rather than the published one. The published v4.0.2-8 offline image cannot
# fetch anything (substituters = mkForce [ ]), so any divergence from the baked
# reference -- a username that is not `omarchy`, an Intel NPU -- has to be
# built, which is the stdenv source bootstrap. #384 fixed that on main; this is
# how the fix gets tested on the path that found the bug.
OFFLINE = os.environ.get("MATRIX_OFFLINE_ISO", f"{ISOS}/nixarchy-v4.0.2-8.iso")
NET = os.environ.get("MATRIX_NET_ISO", f"{ISOS}/nixarchy-v4.0.2-8-net.iso")
# Resolved rather than pinned: a hardcoded store path is a time bomb the first
# time the pin moves and the file is garbage-collected.
OVMF = os.environ.get("MATRIX_OVMF") or (
    subprocess.run(["nix", "build", "--no-link", "--print-out-paths", "nixpkgs#OVMF.fd"],
                   capture_output=True, text=True, check=True).stdout.strip() + "/FV")
HASH = ("$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo."
        "yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/")

# name -> (iso, disk_mode, encrypt, vnc display)
CELLS = {
    "off-whole-plain": (OFFLINE, "whole", False, 10),
    "off-whole-enc":   (OFFLINE, "whole", True,  11),
    "off-free":        (OFFLINE, "free",  False, 12),
    "net-whole-plain": (NET,     "whole", False, 13),
    "net-whole-enc":   (NET,     "whole", True,  14),
    "net-free":        (NET,     "free",  False, 15),
}

# The installer refuses `free` under 32 GiB of contiguous free space, so a
# blank disk is not a dual-boot disk: the first attempt at this cell died on
# that refusal without ever reaching an install, and read like a pass.
DRIVE = r'''#!/bin/sh
step() {
  tag=$1; shift
  "$@" > /tmp/out 2>&1
  rc=$?
  cat /tmp/out > /dev/ttyS0
  echo "$tag-$rc-X" > /dev/ttyS0
  [ $rc -eq 0 ] && return 0
  # The HEAD of the log names the FIRST thing it decided to build, which is
  # the whole question. The tail only shows the cascade that followed.
  head -150 /var/log/nixarchy-install.log > /dev/ttyS0 2>/dev/null
  echo "HEADLOG-END-X" > /dev/ttyS0
  return $rc
}
echo "DRIVE-STARTED-X" > /dev/ttyS0
step INSTALL nixarchy-install --answers /a/answers
step ESP test -d /mnt/boot/EFI
step NOHASH sh -c '! grep -rq "[$]6[$]" /mnt/etc/nixos'
echo "DRIVE-DONE-X" > /dev/ttyS0
'''


def sh(*a, **kw):
    return subprocess.run(a, check=True, capture_output=True, text=True, **kw)


def make_disk(w, mode):
    raw, qcow = f"{w}/disk.raw", f"{w}/disk.qcow2"
    for p in (raw, qcow):
        if os.path.exists(p):
            os.remove(p)
    if mode == "free":
        sh("truncate", "-s", "100G", raw)
        sh("sgdisk", "-o", raw)
        sh("sgdisk", "-n", "1:2048:+512M", "-t", "1:ef00",
           "-c", "1:EFI system partition", raw)
        sh("sgdisk", "-n", "2:0:+40G", "-t", "2:0700",
           "-c", "2:Basic data partition", raw)
        print("  " + sh("sgdisk", "-p", raw).stdout.strip().splitlines()[-1])
    else:
        sh("truncate", "-s", "64G", raw)
    sh("qemu-img", "convert", "-f", "raw", "-O", "qcow2", raw, qcow)
    os.remove(raw)
    return qcow


def make_answers(w, mode, encrypt):
    d = f"{w}/a"
    os.makedirs(d, exist_ok=True)
    lines = [
        "device=/dev/vda",
        f"disk_mode={mode}",
        f"encrypt={'yes' if encrypt else 'no'}",
    ]
    if encrypt:
        lines.append("luks_passphrase=omarchytest")
    lines += ["hostname=nixarchy", "username=omarchy",
              f"password_hash={HASH}", "timezone=UTC", "keymap=us"]
    open(f"{d}/answers", "w").write("\n".join(lines) + "\n")
    open(f"{d}/drive", "w").write(DRIVE)
    img = f"{w}/answers.img"
    if os.path.exists(img):
        os.remove(img)
    sh("mkfs.vfat", "-n", "NIXANSWERS", "-C", img, "2048")
    sh("mcopy", "-i", img, f"{d}/answers", "::answers")
    sh("mcopy", "-i", img, f"{d}/drive", "::drive")
    return img


def main():
    name = sys.argv[1]
    # `manual` boots the same image onto the same disk and then gets out of
    # the way: no answers disk, no QMP typing, nothing driving it. The
    # automated cells run `nixarchy-install --answers`, which SKIPS the
    # greeter and the whole disk-mode menu -- so a bug living in the TUI is
    # invisible to every cell above. This is the path the users actually take.
    manual = len(sys.argv) > 2 and sys.argv[2] == "manual"
    # `boot` re-boots the machine a cell just INSTALLED, from its own disk,
    # with no ISO attached. Every cell above asserts the installer exited 0;
    # none of them ever booted the result. An install that reports success and
    # then produces a machine that will not boot is still a failed install,
    # and "it crashes when booting" is exactly what the hardware reports say.
    # Reuses the cell's own VARS.fd, or the EFI boot entry the installer wrote
    # would not be there to find.
    boot_only = len(sys.argv) > 2 and sys.argv[2] == "boot"
    iso, mode, encrypt, disp = CELLS[name]
    assert os.path.exists(iso), f"no such image: {iso}"
    if manual:
        disp += 10
    if boot_only:
        disp += 20
    w = f"{WORK}/{'manual-matrix' if manual else 'matrix'}/{name}"
    os.makedirs(w, exist_ok=True)
    serial, sock, vars_fd = f"{w}/serial.log", f"{w}/qmp.sock", f"{w}/VARS.fd"

    print(f"== cell {name}: {os.path.basename(iso)}, disk_mode={mode}, "
          f"encrypt={encrypt}")
    disk = f"{w}/disk.qcow2" if boot_only else make_disk(w, mode)
    answers = None if (manual or boot_only) else make_answers(w, mode, encrypt)
    sh("cp", "-f", f"{OVMF}/OVMF_VARS.fd", vars_fd)
    sh("chmod", "u+w", vars_fd)
    for p in (serial, sock):
        if os.path.exists(p):
            os.remove(p)

    print(f"== watch it live:  vncviewer 127.0.0.1:{5900 + disp}")
    vm = subprocess.Popen([
        "qemu-system-x86_64",
        "-machine", "q35,accel=kvm", "-cpu", "host", "-m", "8192", "-smp", "4",
        "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF}/OVMF_CODE.fd",
        "-drive", f"if=pflash,format=raw,file={vars_fd}",
        "-drive", f"file={disk},if=virtio,format=qcow2",
    ] + ([] if answers is None else [
        "-drive", f"file={answers},if=virtio,format=raw",
    ]) + [
        "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
        "-device", "virtio-vga", "-device", "qemu-xhci", "-device", "usb-tablet",
        "-vnc", f"127.0.0.1:{disp}",
        "-serial", f"file:{serial}",
        "-qmp", f"unix:{sock},server,nowait",
        "-name", f"nixarchy-{'manual' if manual else 'matrix'}-{name}",
        # Last, and the reason this is a comment: leaving these off boots the
        # empty disk, falls through to the UEFI boot-device menu, and sits
        # there until the timeout. Six cells ran that way before anyone
        # noticed, because "no install happened" and "the install is slow"
        # look identical from a serial log that says nothing.
    ] + ([] if boot_only else [
        "-cdrom", iso,
        "-boot", "order=d",
    ]) + [
    ],
        start_new_session=(manual or boot_only),
        # A detached VM must not inherit this process's stdout: qemu holds the
        # write end open forever, so a caller that pipes the launcher (`|
        # sed`, `| tee`) blocks on EOF that never comes. The first attempt at
        # this launched one VM and hung for good.
        stdout=(open(f"{w}/qemu.log", "w") if (manual or boot_only) else None),
        stderr=subprocess.STDOUT if (manual or boot_only) else None,
    )   # a manual VM outlives the launcher

    if manual or boot_only:
        # Deliberately does NOT wait and does NOT terminate: the VM outlives
        # this process, so a person can drive it (manual) or a screenshot can
        # be taken of what it actually put on screen (boot).
        what = ("boot it through the greeter by hand" if manual
                else "booting the machine this cell installed, no ISO attached")
        print(f"== {name}: {os.path.basename(iso)}, disk_mode={mode} -- {what}")
        print(f"   vnc 127.0.0.1:{5900 + disp}   serial {serial}   qmp {sock}")
        return 0

    try:
        if not wait_for(serial, "automatic login", 600, "the live session"):
            return 1
        time.sleep(20)
        q = Qmp(sock)
        q.key("alt", "f2")
        time.sleep(3)
        q.type("\n")
        time.sleep(2)
        for cmd in ("sudo mkdir -p /a\n",
                    "sudo mount -L NIXANSWERS /a\n",
                    "sudo sh /a/drive\n"):
            q.type(cmd)
            time.sleep(3)
        if not wait_for(serial, "DRIVE-STARTED-X", 180, "the drive script"):
            return 1
        # Generous: an offline copy is minutes, and a run that fell into the
        # source bootstrap needs long enough to SAY so rather than be killed
        # mid-build and look like a timeout.
        if not wait_for(serial, "DRIVE-DONE-X", 4200, "the install to finish"):
            print(f"!! {name}: TIMED OUT", file=sys.stderr)
            return 1
    finally:
        txt = open(serial, errors="replace").read()
        rc = "?"
        for ln in txt.splitlines():
            if "INSTALL-" in ln and ln.strip().endswith("-X"):
                rc = ln.strip().split("INSTALL-")[-1].split("-X")[0]
        print(f"== VERDICT {name}: INSTALL rc={rc}")
        vm.terminate()
        try:
            vm.wait(30)
        except Exception:
            vm.kill()
    return 0 if rc == "0" else 1


if __name__ == "__main__":
    sys.exit(main())
