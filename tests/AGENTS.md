# tests/

Every `checks.<name>` in `flake.nix` is a file here. 37 of them.

## Intent

A check exists to fail. The recurring failure in this repository is not a
missing check but a check that runs, passes, and measures nothing — a coverage
guard that extracted zero names, a merge gate that read absence-of-failure as
green, a `cachix` step that printed "Nothing to push" at a 404.

So the bar for adding one is: **run it against the unfixed code first and watch
it fail.** A check that has never failed is a check nobody knows works.

## The expensive ones, and what only they can prove

| check | proves | where |
|---|---|---|
| `install` | the installer's output boots — a real disk, real bootloader | self-hosted |
| `install-encrypted` | the LUKS path, unlocked over the serial console | self-hosted |
| `install-iso` / `-net` | the real published image, installing with no network | self-hosted |
| `free-space` | installing beside an existing OS without eating it | self-hosted |
| `session` | a booted desktop; **does not run locally**, CI only | self-hosted |
| `microvm-boot` | a guest actually boots, not just builds | `-tcg` runner |

VM tests run from `/mnt/data/vmtest`, never `/tmp` — `/tmp` is a 32G tmpfs and
a VM test that runs out of room does not fail cleanly, it wedges.

## The one nothing here can prove: a username that is not `omarchy`

`tests/install-matrix.py` is not a check. It boots a **published** `.iso` in
real qemu and installs it every way a person can — scripted, driven by hand
through the greeter, and then re-booted from its own disk to prove the result
starts.

It exists because of a hole every check above shares. All of them install as
username **`omarchy`**, which is the name the ISO's reference closure is baked
for — the one username that cannot diverge from it. On 2026-09-07 the full
matrix ran 6/6 green against the published `v4.0.2-8` offline image; the same
file, driven by hand with the username `olaf`, died in the source bootstrap:

```
hm_hmfontconfigfonts.xml -> libxml2+py -> doxygen -> cmake
  -> libarchive -> attr -> download.savannah.gnu.org
```

home-manager's per-user fontconfig file is in no baked closure, and the offline
image had `substituters = lib.mkForce [ ]`, so it could not fetch that path and
had to build it — and building anything with no compiler on the medium is the
stdenv bootstrap. Two users hit the same bootstrap by a different route, an
Intel NPU. #384 gave both images substituters; the same cells against an image
built from that fix installed and booted clean.

`installer/cd.nix` bakes `inputDerivation` for `toplevel`, `initialRamdisk` and
`etc`. home-manager is a fourth per-machine thing and is not in that list.

So, when changing what the ISO carries or how the installer writes a machine:

```
MATRIX_OFFLINE_ISO=result/iso/nixarchy-*.iso python3 tests/install-matrix.py off-free manual
```

and **type a username that is not `omarchy`**. The scripted cells cannot see
this class of bug, and adding more of them will not help.

## The cheap ones, which is where new checks usually belong

`installer-ui`, `installer-wizard`, `installer-refusal`, `installer-lock`,
`installer-store-space`, `try-preflight`, `doctor-graphics`, `dashboard-clock`,
`options`, `review-pins`, `patched-files`, `doc-options`.

These are `runCommand`s that finish in seconds and drive one decision with a
stubbed environment. Prefer one of these over extending a VM test: they are the
only way to reach a branch a VM cannot produce.

Two branches only these can reach, as illustration:

- `installer-store-space` — a live ISO's store is a RAM overlay at half the
  machine's memory. `install` cannot see it filling, because it installs onto a
  machine whose store fits.
- `dashboard-clock` — a clock that goes backwards mid-install. Every VM's clock
  is stable, so no install check can produce a negative duration.

## Working here

- **A check in `flake.nix` and in no workflow is not a check.** `build.yml` has
  a step asserting every check is run by some workflow, because
  `checks.installer-ui` shipped that way once and its PR went green without it
  ever executing.
- Assert the outcome, not the mechanism. `stat -c %U` asks the wrong machine
  when the test driver's passwd is not the target's; compare numeric ids
  against the target's own `/etc/passwd`.
- A forbid-pattern matches prose too. Forbidding a bare package name failed
  against correctly-gated code because the surrounding comment mentioned it —
  match the call, not the string.
