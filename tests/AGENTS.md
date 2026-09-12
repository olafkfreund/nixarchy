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

and **type a username that is not `omarchy`**.

**Partly closed since.** `checks.install-iso` now installs as `lovelace`, so
one automated cell finally varies this — offline, nightly, already paying for a
full image build, so a per-user rebuild costs wall clock nobody waits on.
`checks.install` keeps `omarchy` deliberately: it is PR-gated and its seeded
store is the thing under test there.

What is still uncovered, and worth typing by hand: a name with a **hyphen or a
digit**, which also stresses systemd unit naming (`home-manager-<user>.service`)
and home-manager's own paths. `install-iso` varies one variable on purpose —
a compound change makes a failure unattributable.

## The other one nothing here can prove: a disk that is not virtio

Every check installs to `/dev/vda`. Real machines are NVMe, where partitions are
`nvme0n1p1` rather than `vda1` — a different naming rule in every path that
builds a partition name.

This is not an omission that can be fixed by writing a check, and the reason is
worth knowing before you try: **qemu-vm.nix cannot make one.** `driveCmdline`
hardcodes `-device virtio-blk-pci` or `scsi-hd`, and `virtualisation.qemu.diskInterface`
is an enum of exactly `virtio | scsi | ide`. `emptyDiskImages` entries take a
`driveConfig`, but it reaches `driveExtraOpts`/`deviceExtraOpts` on those
devices — not a different device. Attaching an NVMe controller means bypassing
the framework with raw `qemu.options` and creating the image yourself, inside a
90-minute test.

So it lives in the harness instead, which drives real qemu directly:

```
MATRIX_NVME=1 MATRIX_OFFLINE_ISO=result/iso/nixarchy-*.iso \
  python3 tests/install-matrix.py off-whole-plain
```

Run it when changing anything that builds a partition name, mounts by path, or
touches `installer/disk-config.nix`. Both an online and an offline whole-disk
install through it passed on 2026-09-08, which is what "no check covers this"
is allowed to mean here: measured by a person, written down, and repeatable.

## The stub-only one: `pkg-new` never runs a real nix-init here

`tests/pkg-new.nix` drives the real `pkgs/pkg-new.sh` against **stub**
`nix-init` and `nix`, because the real ones fetch and a sandboxed derivation
has no network. The stubs are enough for the script's own promises — the
draft kept on a failed build, the placeholder cargoHash filled in from the
failed build's `got:` line, the apps.nix edit staying inside the
`#@pkgs-end` block — but they imitate nix-init's output rather than produce
it. Whether `nix-init --headless` still drafts something buildable from a
real repository, with the real GitHub API and the real hash-mismatch text,
no check here can say.

That real run lives in `.github/workflows/nightly.yml` (`pkg-new` job): it
drafts hexyl at a pinned tag with real nix-init and builds the draft.
Non-gating, per-night, filed as its own issue by the report job — a job
rather than a check for the same reason devenv-presets is (see build.yml's
comment on that job).

## The cold-cache one: nobody here can watch a network image fail to fetch

The network reinstall image (#483) is only honest for a closure the caches
hold, and every store CI touches is warm and every closure it installs is
cached. So the failure the feature is about — a target that formats, then
cannot fetch an unfree or locally built path — cannot be produced by any
layer here. What IS covered: the prediction's classification against real
`nix path-info` shapes (`substitutable`), the build-machine verdict wiring
(`reinstall-iso`), and the target-side plan report with plans nix really
prints (`installer-store-space`). What is not: a real `reinstall-iso-net`
image, booted against real caches, missing a real unfree package. That run
needs a human with vscode in their closure and a machine to lose; until one
reports back, the prediction is tested and the event it predicts is not.

## A fixture that quotes an error is a fixture that goes stale

`explain` recognises Nix error messages, and the obvious way to test that is a
directory of captured traces. It is the wrong way, and the reason generalises
past this check.

An error message is not ours. nixpkgs reworded the buildEnv collision from
``collision between `a' and `b'`` to `two given paths contain a conflicting
subpath` — same failure, different words — and Nix reworded the untracked-file
error from `path '…' does not exist` to `Path '…' is not tracked by Git`, which
is a better message and matches nothing the old matcher looked for. A captured
trace keeps passing through both rewordings, because the fixture and the
matcher agree with each other while both have stopped describing the machine in
front of the user. That is §1's green light with a different coat on.

So `tests/explain.nix` produces every error inside the check, from the real
producer: a real git repository with a real untracked file, `lib.evalModules`
with two definitions of one option, nixpkgs' own `buildenv/builder.pl` against
two colliding trees, `stdenvNoCC.mkDerivation` with an unfree licence. Nothing
is quoted. If nixpkgs rewords one again, the fixture changes under the check
and the check goes red — which is the whole point.

Two mechanics that make this possible, and one that nearly stopped it:

- **Nested `nix` evaluation works in a build sandbox.** Point `NIX_STORE_DIR`,
  `NIX_STATE_DIR` and `NIX_LOG_DIR` at `$PWD`, and `nix-instantiate --eval`
  and `nix eval` both run. Full nixpkgs evaluation is available offline
  because `${pkgs.path}` is already an input. Nothing is built, so this stays
  a seconds-long check.
- **A failing derivation cannot be a check's dependency**, so a build-time
  error has to be produced by running the builder rather than by building.
  `buildenv/builder.pl` reads its arguments from `NIX_ATTRS_JSON_FILE`; hand
  it a JSON file naming two trees and it prints the real collision.
- **`NIXPKGS_ALLOW_UNFREE` is read through `builtins.getEnv`.** A nixarchy
  desktop exports it, so the unfree fixtures succeed when you run them by hand
  and fail correctly in the sandbox. Every fixture that depends on nixpkgs
  policy asserts the raw Nix message before asserting anything about our
  output — a fixture that quietly starts succeeding otherwise leaves the thing
  under test reading an empty string, and "recognised nothing" is
  indistinguishable from "there was nothing to recognise".

## The cheap ones, which is where new checks usually belong

`installer-ui`, `installer-wizard`, `installer-refusal`, `installer-lock`,
`installer-store-space`, `try-preflight`, `doctor-graphics`, `dashboard-clock`,
`options`, `review-pins`, `patched-files`, `doc-options`, `explain`.

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
- **The harness is a module too, and it outranks you.** `qemu-vm.nix` is merged
  into every nixosTest node and does not only add virtio devices — it CHANGES
  config at priority 10, above any plain assignment.
  `networking.wireless.enable = mkVMOverride false` (`qemu-vm.nix:1504`)
  silently re-created the exact production misconfiguration a test existed to
  prove fixed, with the identical journal line — and that line was read as "the
  fix does not work" for most of a day. It was the test that did not work.
  Before concluding a node reproduces a production failure, evaluate the
  **node's merged config**, not the module you wrote and not the production
  system it copies from. And treat an identical error message as a hypothesis
  about the cause, never as an identification of it.
- A forbid-pattern matches prose too. Forbidding a bare package name failed
  against correctly-gated code because the surrounding comment mentioned it —
  match the call, not the string.
- **A tool that prints its verdict last fails every assertion at once when
  it dies, and says nothing about dying.** `doctor-graphics` asserts on the
  doctor's snippet, which the doctor prints after every other section, and the
  doctor runs under `errexit`. So any host read between the Graphics section
  and the end that fails -- and the fixture pins none of them -- kills the
  doctor, the snippet is never printed, and the check reports five `no
  /intelBusId/ in the output` lines that read exactly like five wrong GPU
  rules. The harness had `|| true` on the doctor, so the one number that
  would have said "it died" was thrown away (#645). Capture the exit status
  as part of the output and assert on it first; and when a case fails, print
  the full transcript plus the host state the fixture does not control, because
  a check that disagrees with itself across two runners and cannot say what
  differed is one people learn to re-run until green.
- **Never name a shell variable `out` in a `runCommand` script.** `$out` is the
  derivation's output path, and assigning to it means every assertion passes
  and the build then fails with *"builder failed to produce output path"* —
  which reads as a broken derivation rather than a shadowed variable. Cost one
  full build in `tests/android.nix` before the cause was obvious. `got` is the
  usual name for "what the thing under test printed".
- **`step`-style helpers truncate their capture file before running the
  command.** In `tests/install-iso.nix` a `grep` placed inside `step` reads the
  file `step` is about to write, so it always sees an empty one. Copy the
  output first (`cp /tmp/out /tmp/eval`) and grep the copy.
- **A driver that waits only for the success marker turns every failure into a
  timeout.** The guest prints `TAG-$rc-X` for any exit code; waiting for
  `TAG-0-X` meant a failing step's `-1-X` scrolled past unmatched and the
  driver blocked until timeout on a marker that could never appear —
  reporting `action timed out after 120s` two minutes after the guest had
  printed the reason. Wait for `TAG-\d+-X`, then read the code out of
  `get_console_log()`.
- **A single column-zero line changes the indentation of a whole `''` string,
  and the failure lands somewhere else entirely.** Nix strips the *common*
  leading whitespace off an indented string at parse time. Adding one literal
  line at column zero — an `${lib.optionalString ...}` opener written flush
  left is the easy way to do it — drops that common indent to nothing, so
  every other line in the script keeps the four spaces it used to lose. The
  script still runs; what breaks is an indented heredoc terminator, because
  `<<STUB` (unlike `<<-`) only matches a terminator at column zero. In
  `tests/microvm-template.nix` the result was the stub-`nix` heredoc running to
  end of file and bash reporting `nixarchy: command not found` on a line five
  hundred away from the edit. If a `runCommand` script starts failing in a
  region you did not touch, diff `nix eval --raw .#checks.<system>.<name>.buildCommand`
  before reading the shell — and indent interpolation openers to match their
  surroundings. `nix fmt` does not catch this; it happily formats both.
- **Grep the spelling the script CONTAINS, not the value it resolves to.** A
  check meant to prove every call to a root-only helper goes through `sudo`
  greped for the helper's *store path* — which appears on exactly one line, its
  assignment. The loop iterated once, matched the arm that skips the
  assignment, and passed with the `sudo` deleted from every call. The script
  spells those calls `"$HOST_SOPS"`. Same shape as the forbid-pattern note
  above and worth stating the other way round: after writing a loop over
  `grep` output, **count what it iterated and assert a floor**, because a loop
  that reads zero of the right lines satisfies every case in silence.
- **Break the product, not the assertion, and watch which assertion fires.**
  Two of this repository's newest checks were wrong in ways only that found:
  one matched `$(` immediately followed by `sops`, and the real bug put an
  environment assignment in between; one counted `sops -d --extract` when half
  the calls go through a wrapper whose name merely *ends* in `sops`. Both
  reported green on the broken code, and both were caught because §1's
  break-it-first contract was actually run rather than described.
