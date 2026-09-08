---
title: How this is tested
---

# How this is tested

Nixarchy is a port. Omarchy ships a new release and this repository has to
follow it without breaking the machines already running. That is the whole
engineering problem, and most of what is written here exists to solve it.

This page is the honest version: what runs, when, what it proves, and — the
part usually left out — what it does **not** prove.

## The shape of it

Nine workflows. Five run nightly on their own clock, one runs weekly, and the
rest run on what you push.

| when | what runs | what it is for |
|---|---|---|
| every pull request | `build`, `install check` | does this change break the desktop, or the installer |
| 03:00 daily | `nightly` | the things that need real hardware: installs, ISOs, MicroVMs |
| 04:00 daily | `omarchy` | has upstream released? adopt it |
| 05:00 daily | `update` | have the pinned apps moved? |
| 06:00 daily | `review` | write down what needs attention |
| 07:00 daily | `flake-update` | what a *user's* `nix flake update` would get |
| 06:00 Mondays | `build` again | the same checks against a lock nobody touched |
| on a tag | `release` | build the image, publish it, prove it attached |

The split matters. A pull request must answer quickly, so the slow and
hardware-bound work moves to the night. What the night finds becomes an issue
rather than a blocked merge.

## Following Omarchy

At 04:00 the `omarchy` workflow asks GitHub for the newest Omarchy release. If
it is newer than the pin, it bumps the flake input and then tries to prove the
port still holds:

- **the vendored tree builds** — every one of upstream's commands is present,
  shebangs patched, the `bin/` symlink farm intact
- **every `substituteInPlace` anchor still matches**. This port edits upstream
  scripts in place; an anchor upstream rewrote is a patch that silently stops
  applying. `--replace-fail` turns that into a build failure instead
- **every menu row it overrides still exists**
- **a booted session renders its wallpaper** — a real desktop in qemu,
  screenshotted, its average colour compared to the wallpaper's own. Without
  this a green run meant little: the desktop once rendered pure black while
  every other check passed, because an image wider than `GL_MAX_TEXTURE_SIZE`
  draws nothing and Qt still reports it Ready

It also **reads the release**: what packages it adds and drops, what upstream's
own notes say, what changed in the config tree seeded into `~/.config`, and
which of the files this port patches upstream touched. All of that lands in the
pull request body, so adopting a release is reading rather than archaeology.

### What happens when a release adds something new

Most releases add an application, a menu row, or a coding agent. That is normal,
and until recently it **blocked the bump** — the check that verifies every
Install row maps to something in this port would fail, and the whole adoption
stopped behind a question nobody had been asked yet. A security release once sat
unadopted for three days that way.

Now the bump **asks**. Unmapped rows become a checklist in the pull request:

> **Install rows that need a decision**
>
> - [ ] `install.ai.hermes` installs `hermes-desktop`, which `data/apps.nix` or
>       `data/services.nix` does not map

Each has exactly two answers, and both are one line:

- **it is an app** — add it to `data/apps.nix` with its `menuId` and its nixpkgs
  attribute
- **it is not** — record *why* in `data/menu-exceptions.nix`

That second file is the interesting one. Both gates that ask this question read
it, so the decision is recorded once. Before it existed the answer lived only in
the test, and recording it satisfied one check while leaving the other red on the
same row — one problem wearing two faces. An exception with an empty reason is
rejected, because "we decided" and "nobody looked" must not look alike.

The row still cannot reach `main` unmapped: the same script runs as an ordinary,
fatal gate on the pull request. What changed is *when* it blocks.

### The names are checked, not assumed

Omarchy 4.0.3 added an agent called **openclaw**, and nixpkgs has a package by
that name. It is also the name of a well-known Captain Claw reimplementation.
Mapping the wrong one would have installed a platformer for someone asking for an
AI assistant, and nothing would have complained.

The same trap already had a victim: `hey` in nixpkgs is an HTTP load generator,
not the HEY CLI, which is why this port ships `hey-cli`. Both cases are written
down next to the entries so the next person meets the warning before the mistake.

## Verifying the port itself

Every check lives in the flake, so anyone can run the same thing CI runs:

```sh
nix build .#checks.x86_64-linux.<name>
```

They fall into layers:

**Does it evaluate and build** — the vendored tree, the system closures, the ISO
images, every packaged application.

**Does it behave** — dozens of VM tests that boot a real machine: the desktop
session, the installer's screens at every width, plugins from real repositories,
a MicroVM, a container, wireless with a simulated radio.

**Does it install** — the part that matters most and is hardest to fake. A VM
partitions a blank disk, installs, boots the result *on its own bootloader*, and
asserts a rebuild builds nothing. Encrypted installs unlock at the passphrase
prompt. One test installs beside an existing operating system in free space and
asserts the neighbour survived.

**Does the prose still tell the truth** — the counts in the README are derived
from the code and compared. So are the option paths quoted in this manual: a
worked example that has rotted is worse than no example, and one sat here for
months because prose is not built.

### No check may be defined and never run

There is a gate whose only job is to notice a check nobody runs. It reads every
check in the flake, subtracts the ones a job claims by name, and builds the rest
in one go. Add a check and it is picked up automatically; the last two new checks
needed no workflow edit at all.

It also fails in the other direction — a job claiming a check that no longer
exists — because a list that only agrees with itself proves nothing.

## What is deliberately not proven

**No machine here is real.** Every install test runs in qemu with a virtual
disk and a virtual NIC. That has cost this project real bugs: a guest reports a
virtualisation type, so `nixos-generate-config` skips the firmware and microcode
lines it writes on bare metal — and no VM ever exercised them. Installed
machines shipped with no firmware at all, and Wi-Fi worked during the install
and vanished on reboot. The tests were green throughout.

The lesson is written into `AGENTS.md` as its own section: *a check that cannot
vary proves nothing about the variable it holds constant.* Several checks now
deliberately vary the thing they are about — two machines differing only by
hostname, two usernames, two disk modes — because a test that pins a value
cannot tell you anything about it.

**The offline image is not currently published.** It carried the whole system
closure and promised an install with no network; it stopped keeping that promise,
and rather than ship an image whose only reason to exist is broken, it is
withdrawn until the check that installs from it offline is green. The network
image is unaffected and is what people install from.

## If you want to look

- `.github/workflows/` — the workflows, each with its reasoning in comments
- `flake.nix` — every check, and why each exists
- `tests/` — the VM tests; most files open with the bug they were written for
- `data/menu-exceptions.nix` — the rows this port deliberately does not map
- `AGENTS.md` — the rules the checks are written against

The commit messages are part of the documentation. When something here was wrong,
the commit that fixed it says what was wrong, how it was found, and what would
have caught it sooner.
