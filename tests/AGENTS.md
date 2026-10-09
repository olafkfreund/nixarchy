# tests/

Every `checks.<name>` in `flake.nix` is a file here.
`nix eval .#checks.x86_64-linux --apply builtins.attrNames` lists them — this
line used to carry the count, and the count was wrong by half, which is the
§4 shape: a hand-written number nothing compares.

## Intent

A check exists to fail. The recurring failure in this repository is not a
missing check but a check that runs, passes, and measures nothing — a coverage
guard that extracted zero names, a merge gate that read absence-of-failure as
green, a `cachix` step that printed "Nothing to push" at a 404.

So the bar for adding one is: **run it against the unfixed code first and watch
it fail.** A check that has never failed is a check nobody knows works.

## A sourced function does not check its package (#1112, #1124)

Extracting or sourcing a function in a `runCommand` exercises its behavior but
skips `writeShellApplication`'s build-time ShellCheck. A function check passed
while the packaged `nixarchy-verify` failed SC1007 on `local a= b=`. Build the
package itself as well as the function check after changing its shell source.

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

`checks.coexistence` (`tests/coexistence/`, AGENTS.md §14) proves nixarchy's
own fixtures still build and don't get silently shadowed — it cannot see
fonts (no known failing case) or a real host config, only what a fixture
names.

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

## A check that dies before its first echo tells you nothing at all

The section below says the floor is what catches an unparseable dispatch. It
does -- eventually. What it did first was worse, and it cost six rounds of
diagnosis on #1016.

`verbs_of` ends in `grep -oE ... | ... | sort -u`. On a dispatch it cannot
parse the `grep` matches nothing and exits 1, and under the builder's `set -e`
that killed the whole check **before a single line was printed**. The reader
got:

    error: Cannot build '...-nixarchy-menu-verbs.drv'.
           Reason: builder failed with exit code 1.

and `nix log` returned an empty log. A correct red, for an unreadable reason,
on a check whose name says "menu verbs" when the cause was a shell `case`
block three files away. Twice I read that emptiness as the check not running.

Two things fixed it, and they only work as a pair: `|| true` on the pipeline,
so an empty result is a value rather than a death, and a `floor` helper that
says which CLI came back empty and why that matters. Either alone is useless
-- `|| true` without the floor is a silent pass, and the floor without
`|| true` never executes.

The general form, which is not about this file: **a guard that aborts before
it can explain itself is only half a check.** When you add `set -e` or
`pipefail` to something that runs assertions, ask what the first failing
command prints, and whether the answer is "nothing".

## menu-verbs reads a literal line, and the spelling it cannot parse is green

`tests/menu-verbs.nix` extracts a CLI's verbs by sed-ing for

    case "${1:-}" in

and nothing else. A command with a default verb naturally wants

    case "${1:-serve}" in

which is a better spelling of the dispatch and yields an **empty verb list**.
That is not a failure: `scan` reports a row whose verb is missing from the
list, so with no list every row naming that CLI passes. The check would go on
being green while covering nothing -- for that CLI and only that CLI, which
is the part that makes it hard to notice.

The floor is the only thing between that and a silent pass:

    test "$(wc -l < remote-verbs)" -ge 3

and the file already says why (*"An empty verb list makes every row below
pass, turning 'the dispatch stopped parsing' into a green check"*). It works,
but it only fires for a CLI somebody remembered to give a floor, and nothing
makes you.

So when you wire a new command in:

1. spell the dispatch `case "${1:-}" in` and handle `""` as the default verb,
   with a comment at the line saying why, or the next person will tidy it back
2. add the floor in the same edit as the `scan`
3. read the printed `<cli> accepts: ...` line and check your verbs are on it.
   A pass proves nothing until that line is non-empty and right

Found writing `nixarchy-remote` (#1015), which was spelled `"${1:-serve}"`
first.

## A drvPath in a derivation's environment is a build INPUT, not a note

`checks.hypr-rdp-builds` was written to prove a configuration **evaluates**,
by forcing `config.system.build.toplevel.drvPath`. That is the natural way to
write it and it is wrong:

```nix
pkgs.runCommand "…" { drv = cfg.system.build.toplevel.drvPath; } ''…''
```

A `.drv` path in the environment makes that derivation a dependency, so nix
did not evaluate the closure -- it **built the whole system**. The `omarchy`
job went from its usual 6-13 minutes to 45 and a timeout, twice, and the
first read was "cold cache after a flake bump" because a pin had just moved.

Measured before blaming it, which is the only reason it was found:

| | step 9, "Build every check no other job claims" |
|---|---|
| three passing runs on `main` | 6m25s, 12m40s, 12m45s |
| the branch adding this check | 54m, cut at the 45m cap |

The fix is to force the evaluation and leave nothing for nix to chase:

```nix
{ proof = builtins.stringLength cfg.system.activationScripts.setupSecrets.text; }
```

An integer. Same catch -- 3 seconds green on a good pin, 2 seconds red on the
stale one -- against 45 minutes and a timeout.

**The rule:** when a check's subject is evaluation, put a *value* in the
environment, never a store path. A path is an instruction to build. If you
want proof the forcing still happens, assert on something derived from the
value (a length, a count) so a silent change to the shape makes the check
refuse rather than pass.

**It is the same when the path is interpolated into the script.**
`checks.install-seed-shape` (#1179) first compared six systems with
`if [ "${seed.drvPath}" = "${vm.drvPath}" ]` in the `runCommand` body. The
string context made all twelve systems build inputs, and the host load hit 101
before the build was stopped, twice. Compare in Nix (`equal = a == b`, which
ignores context), and print `builtins.unsafeDiscardStringContext` copies.
**Check before building:** `nix derivation show` on the check's `drvPath`
should list no `nixos-system`, `system-path` or `linux` among its
`inputDrvs`. For that check it lists only `stdenv` and `bash`.

**And a second trap found in the same hour:** `--override-input` does NOT
reach a `builtins.getFlake` inside `--expr`. It applies to installables.

```sh
nix eval --override-input sops-nix <old> --expr 'builtins.getFlake …'  # ignored
nix build --override-input sops-nix <old> .#checks.x86_64-linux.<name> # applies
```

The first form silently evaluates the *current* input, so an experiment that
means to test an old revision tests the new one and reports whatever the new
one does. Verified by printing `f.inputs.sops-nix.rev` and finding the new
hash, after twice concluding something from it.

## A check that reads the config tree cannot see a closure that will not build

`programs.nixarchy.services.hypr-rdp` was **unbuildable for twelve days**
behind a green suite (#1030). nixarchy pinned sops-nix at a revision whose
`sops-install-secrets` called `buildGo125Module`, which nixpkgs removed on
2026-09-15. The feature requires a sops secret, so every configuration with
it enabled died -- and the error named **Go**.

`tests/options.nix` was not thin about this. It has a sops fixture, an
`rdpOn` fixture enabling hypr-rdp **with a real `passwordSecret`**, and cases
for the unit, the template, the firewall and both refusals. It still could
not see it, for the reason written in its own comment:

> Read as a list of failed assertions rather than by forcing
> `system.build.toplevel`: the point is that THIS assertion fires, and a
> config that fails to build for some unrelated reason would look identical
> from outside.

That reasoning is right for what it was written about, and its consequence is
general: **`checks.options` reads the evaluated config tree and never forces
the closure.** A package that cannot be built -- or, as here, cannot be
*evaluated* -- is invisible to every case in it, however many there are.

`checks.hypr-rdp-builds` closes that for this feature by forcing
`system.build.toplevel.drvPath`. Two things about it worth copying:

- **It costs an evaluation, not a VM.** `buildGo125Module` is an alias that
  `throw`s, so the failure arrives while the drvPath is computed. A check
  that needed a booted machine could not have caught this on the pull request
  that introduced it.
- **It is its own check, not a case in `checks.options`.** That check peaks at
  12.9 GB on the hosted runner (#747). Its fixtures are tempting; a whole
  system closure evaluation does not belong in it.

**What it still cannot see**, and this is the part to read before trusting
it. It proves the closure is describable. It says nothing about the daemon
running, and two live defects sit past it:

- **#1031** -- hypr-rdp could not create its headless output on Hyprland
  0.56, because it set the resolution with the legacy `keyword` IPC request
  that 0.56 dropped. Fixed by a carried patch (`pkgs/hypr-rdp/`), and now
  seen by `checks.session`, which starts the daemon -- see below.
- **#1033** -- enabling remote desktop takes effect only at next login: the
  unit is `WantedBy=graphical-session.target`, which is evaluated when the
  target starts, and the menu row lives in the tree `OMARCHY_PATH` pointed at
  when the session began. Needs a session that postdates a rebuild.

All three were found by a person configuring three real machines in an
afternoon. The generalisable rule is not about sops: **a feature whose tests
only read its configuration has never been built by anything, and a feature
nothing starts has never been run.**

## The two-machine one: no check here ever opens an RDP connection

`checks.session` boots one desktop. Remote desktop needs two machines -- one
with a logged-in Hyprland session and one opening an SSH tunnel to it -- and
nothing in this repository boots a pair. So the thing a user actually does
with this feature is reached by no layer, at any price.

What IS covered, and it is more than it sounds:

- `checks.secret-enroll` proves the policy append against real age keys and
  real sops: the enrolled host reads back its own secret, the first host
  **cannot** read it, and the first host's rule, anchor and comment survive.
  It carries its own self-test -- before the rule exists, sops must refuse to
  encrypt, or the check cannot show that enrolling did anything.
- `checks.options` asserts `programs.nixarchy.services.hypr-rdp` in both
  states, which is where the off state gets defended.
- `checks.session` **starts the daemon** (#1031) with a real sops secret
  generated at build time, waits for its `Display prepared` line -- logged
  only after it has set its headless output's mode -- and asserts its journal
  has no `unknown request` and the unit is active. It first asserts that the
  VM's Hyprland answers `unknown request` to `keyword`: the fix is a fallback,
  and a compositor that still accepted `keyword` would let the probe pass
  without ever taking it.

  **The first version asserted the output's size and was blind.** Hyprland
  makes a headless output 1920x1080, which is also the daemon's default, so
  "a `hypr-rdp-N` output at 1920x1080" held with the patch removed and the
  daemon crash-looping. A journal assertion beside it was blind too: `-o cat`
  drops the identifier, and the `grep hypr-rdp` that followed discarded every
  line it was meant to find. Only `is-active` went red. Both were caught by
  §1's break, not by review -- **a configured value that equals the
  platform's default cannot vary with the thing that sets it.**
- the unit's own `ExecStartPre` refuses an empty password at runtime, and
  `tests/options.nix` drives that guard against both a good and an empty
  rendered config.

What is left is an RDP client connecting and seeing a desktop. That is tested
nowhere -- `pkgs/verify.sh` has no RDP step -- and it is written down here
rather than left implicit because a documented hole gets tested by a person
and an undocumented one gets tested by a user (#1015; connecting out is
#1016). gliff, the other remote-desktop tool, is covered up to capture:
`checks.session` proves its server reaches Hyprland, creates its headless
output and negotiates a stream with a client over loopback TCP (#1226). It
cannot go further there. The VM has no `/dev/dri/renderD128`, and gliff
allocates capture buffers with GBM on it even on the CPU tier, so capture ends
in ENOENT. Frames and the GPU tier are `pkgs/verify.sh`'s `gliff-probe` rows,
on real hardware; the ssh hop is ssh's, and the session VM runs no sshd.

Worth knowing before you try to close it: `nixarchy secret enroll` itself
cannot be driven in a sandbox either. It reads the hostname from
`/proc/sys/kernel/hostname` and its recipient from
`/etc/ssh/ssh_host_ed25519_key.pub`, and a nix build sandbox has no `/etc/ssh`
and reports `localhost` -- measured, not assumed. That is why the decision and
the write live in `pkgs/sops-policy-add.nix`, so the check runs the code the
CLI runs rather than a copy of it.

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

## The one-dialog one: no VM here runs a whole switch through polkit

`checks.session` proves the rebuild's elevation reaches the Omarchy polkit
dialog: it starts `pkexec env touch` inside the greeter-logged-in Hyprland
session, reads the dialog by OCR, types the password and finds a root-owned
file (#765). It runs pkexec **once**. The promise the design rests on -- one
password per switch, because the `AUTH_ADMIN_KEEP` rule lets polkit keep the
authorisation across the three elevations nh makes -- is a claim about
retention across separate pkexec processes, and nothing here drives a real
switch from inside a session. It is checked by hand on real hardware: one
Install > Apply, count the dialogs. More than one means retention did not
hold; the answer is not a wider rule.

Two things the probe cost, both general. **polkit needs a logind session**:
it resolves the subject (`local`, `active`) and the agent's registration
through it, so a VM that starts the desktop with `systemd-run --uid=1000`
(`tests/plugin.nix`) cannot exercise anything polkit decides -- a probe there
is red on a correct build. Log in through the greeter, as `session.nix` does.
And **OCR cannot read the Omarchy theme's dialogs** any better than its
greeter: wait on a system fact the dialog causes (here, a
`polkit-agent-helper@*` unit) rather than on its text.

## The uncheckable one: no layer asserts that writing `shell.json` is safe

Because it is not, and encoding a known-broken behaviour is a check that
inverts the day it is fixed.

Writing `~/.config/omarchy/shell.json` while the shell runs — **even byte for
byte identical** — leaves the bar's IPC targets answering `Target not found`
until `omarchy-restart-shell` (#847). The cause is upstream:
`IpcHandlerRegistry::registerHandler` does not replace an incumbent handler for
a target, so after a reload a handler from a generation being torn down can
keep the target and every replacement is registered-but-unused. The full
evidence, and the report for upstream, is `docs/internals/shell-json-reload.md`.

**What `checks.session` asserts is the recovery, not the defect**: write the
file back under the running shell, `omarchy-restart-shell`, and the targets
answer again with the file unchanged. That invariant is true now and stays true
after an upstream fix, so it cannot go red for the wrong reason. A failure
there means the documented escape hatch broke — read the comment in the check
before treating it as anything else.

The defect itself is checked **by hand**, and this paragraph is what makes that
a documented hole rather than an undocumented one (§3 of the root `AGENTS.md`:
a documented hole gets tested by a human, an undocumented one gets tested by a
user). The repro is four commands:

```sh
cp -a ~/.config/omarchy/shell.json /tmp/bak
cat /tmp/bak > ~/.config/omarchy/shell.json    # same bytes
sleep 4
omarchy-shell omarchy.clock status             # "Target not found." = still broken
```

`omarchy-restart-shell` puts it back. If that last command ever answers
normally, upstream has fixed it and both this section and the check's comment
need rewriting — that is news, not a regression.

## The dictation one: a unit that is `active` is not a feature that works

`checks.options` asserts that enabling dictation creates the `voxtype` user
unit, that its `ExecStart` is a stable package path rather than the
`.voxtype-wrapped` an imperative `voxtype setup systemd` writes, and that the
config was *not* taken over as a read-only store symlink (#942).

**All three are properties of the evaluated configuration, and none of them is
dictation working.** What no check here reaches:

- a real microphone, or PipeWire offering a usable source;
- the user being in `input` — `pkgs/doctor.sh` checks it on a real machine and
  names dictation as the reason, and nothing in a sandbox can;
- Wayland text injection actually reaching the focused window, which is what
  `wtype` is pulled in for;
- whether the ~150 MB model download succeeds on a given network;
- whether the unit survives an upgrade and a garbage collection — the failure
  that produced the issue in the first place.

So a VM seeing `systemctl --user is-active voxtype` print `active` proves the
wiring and nothing else. The original bug was a feature that looked installed
and did nothing; the shape it can take *after* this fix is a daemon that runs
and still does nothing, and no check here can tell them apart.

Checked by hand on real hardware, and this is the whole list:

```sh
systemctl --user is-active voxtype     # active
systemctl --user status voxtype-model-loader   # the model actually arrived
# hold F9 and speak into a text field
voxtype configure                      # still writes ~/.config/voxtype/config.toml
```

That last line is not incidental. The config is seeded rather than managed
precisely so `voxtype configure` — which the bar's Dictation indicator runs on
click — keeps working. A change that sets `services.voxtype.settings` would fix
dictation and break the indicator in the same commit, which is why
`dictationStartsADaemon` asserts the *absence* of an `xdg.configFile` entry
rather than only the presence of a unit.

**And the stable branch is a third hole.** `services.voxtype` arrived in Home
Manager after release-26.05, so on stable `modules/home.nix` skips the bridge
behind `options.services ? voxtype` and emits a warning instead. `checks.options`
evaluates against unstable and cannot see that path; `checks.stable-eval` takes
it, but with dictation off, so the warning it guards is never rendered. What is
proven on stable is only that the name guard keeps the expression valid. Whether
the warning reads well is checked by a human — enabling
`programs.nixarchy.dictation` on a stable machine should print it and install
nothing.

## The owe one: hardware decode and the battery pause are hardware-only

`tests/session.nix`'s #1153 probe sets a real video background and locks
with one set, and proves the wiring end to end: `owed` starts, `owe status`
reports a video source with a live renderer, the desktop and the lock
screen's feed both visibly move, and the background plugin comes back once
the still returns. **None of that reaches the two questions a VM genuinely
cannot answer**, for the same reason the Graphics section of `pkgs/verify.sh`
exists at all:

- **hardware decode.** Every VM here renders on llvmpipe, so `owe
  render-status`'s `hwdec` field is always `"no"` on this renderer whether
  the fix works or not — there is no GPU to decode on, so a check that
  asserted `hwdec != "no"` would be red on every correct build;
- **the battery pause.** No VM here has a battery, so `on_battery` in `owe
  status` can never become `true`, and `battery_mode = "pause"` in
  `~/.config/owe/config.toml` has nothing to react to.

`pkgs/verify.sh`'s "Owe (video backgrounds)" section is the only place
either is checked: it reads `owe render-status`'s `hwdec` while a video is
set, and prints `owe status`'s `on_battery`/`paused` fields beside whatever
`~/.config/owe/config.toml` currently asks for, on a real machine with a
real GPU and a real battery to pull. The hwdec half is a human's own job to
set up (set a video, run `nixarchy verify`, read the value); the battery
half additionally needs the config file written and AC physically pulled,
which nothing here can do for you.

## The plugin shadow check: a state no VM can reach, and a limit it admits

`checks.doctor-plugins` fakes six homes because the state it is about cannot be
produced by any machine here: it needs a user who cloned a plugin by hand
*before* nixarchy shipped one at that id. No installer makes that, and no VM has
ever done it. Faking `$XDG_CONFIG_HOME` is the only layer that reaches it.

The fixture that matters is **`newer`**. A clone ahead of what we ship is
somebody working, not a fault -- one sat 28 commits ahead on a maintainer's own
machine -- and a rule that moved it aside would have destroyed it. The check
asserts doctor does **not** offer a fix there, and that assertion has been seen
failing: breaking the branch produces

    FAIL: newer: offered to move aside a clone that is AHEAD of ours

**What it compares, and cannot:** versions from `manifest.json`, not commits.
There is no commit to compare -- the module holds a store path and the revision
lives in the flake lock. So two diverged branches at the same version read as
"same version", and doctor says that rather than "identical". Version equality
is not content equality and the wording never claims it is.

**What no check here reaches:** nothing runs doctor automatically. A shadowed
plugin is found when somebody asks, not when it happens. That is an improvement
on a journal line nobody reads and it is not the same as being told.

## apply-confirm: what it proves, and the one assertion still unproven

`checks.apply-confirm` drives the real `nixarchy-apply` against fixture files
(#967). Three things about it are worth knowing before trusting or editing it.

**A stubbed `nh` on PATH does not work.** `writeShellApplication` prepends
`runtimeInputs` to the caller's PATH, so the declared `nh` wins over the stub.
That precedence defeats the usual trick; undeclared commands can still come
from the caller's PATH.
"Did it reach the rebuild?" is therefore read from apply's own log -- it prints
"The rebuild failed" only after invoking `nh` -- which is a proxy, not a
process observation.

**`$out` is in scope.** Capturing apply's output into a variable called `out`
made every assertion pass and then broke `mkdir -p $out`: the derivation failed
to produce its own output with nothing in the log saying why. The variable is
`log`.

**The strongest assertion is NOT yet proven to fail.** Case 4 asserts a changed
file is *not built* without confirmation. Breaking the comparison two different
ways turned the check red both times -- on "first run did not say the file was
unconfirmed" and on "the refusal did not say the file changed" -- so the check
is not blind. But neither break made case 4's own `built &&` line fire, so that
line has never been observed failing. It may be unfalsifiable in this harness
for the same reason the stub is: apply's path to `nh` is reached or not for
reasons the fixture does not fully control. Treat it as unproven until somebody
makes it go red, and do not add assertions in its shape without doing so.

## The agent-id comparison, and the two ways it could have been useless

`pkgs/omarchy/default.nix`'s menu check now asserts every
`setup.default.agent.*` row's `action` names an id `omarchy-default-agent`
accepts, parsed out of that script in the same derivation (#949). Before it,
the menu named 14 ids and the script accepted 10, and the four extra rows
printed a usage line into a detached terminal nobody sees.

**The parse is the risk, and it has two opposite tails.** Matching nothing
gives an empty set and flags every row -- loud and obvious. Over-matching gives
a set that accepts everything and passes having checked nothing -- a green
light, which is the failure this repository keeps rediscovering. So the check
**refuses an implausible count** (fewer than 10 accepted ids) rather than
reporting one, the way `readme-counts.sh` refuses at zero. Both halves were
seen failing:

    menu rows name agents omarchy-default-agent rejects: ['setup.default.agent.nosuch']
    the accepted-agent parse found 0 ids; ... This check is refusing rather than passing.

**What it cannot reach:** whether `openclaw` actually launches once installed,
and whether the three llm-agents.nix attribute names (`cursor-agent`,
`hermes-agent`, `muse-code`) are still correct. The second is a claim about
another repository printed to users, and nothing here notices when it goes
stale -- a source of quietly wrong advice rather than a broken build.

## shell-ipc-resolve: three sandbox traps, two of them already written down

`checks.shell-ipc-resolve` drives the patched `omarchy-shell` against a stub
`qs` (#963). Getting the fixture to run at all cost three attempts, and two of
the three were already recorded somewhere in this repo:

- **A heredoc inside an indented Nix string.** nixfmt strips the block's common
  indent, so the stub's shebang came out mangled, `qs` was never found, and
  every case reported "not running". CLAUDE.md section 5 says to use
  `printf '%s\n'`; `pkgs/omarchy/default.nix` does so three times for exactly
  this reason.
- **No `/usr/bin/env` in the build sandbox.** `env` gives "bad interpreter", the
  stub never runs, and the symptom is identical to the one above from a
  different cause. Already recorded in AGENTS.md section 4 against
  `tests/proof-push.nix`. The shebang is `${pkgs.bash}/bin/bash`.
- **`$out` is in scope.** Capturing the script's output into `out` made all five
  assertions pass and then failed the derivation with nothing in the log.
  `tests/apply-confirm.nix` hit this first and it is noted there; this file hit
  it again four hours later, so the note was not enough on its own.

**A PATH stub works here and does not in `apply-confirm`.** `nixarchy-apply` is
a `writeShellApplication` that prepends its `runtimeInputs`, so its declared
binary wins; `omarchy-shell` is upstream's and unwrapped, so PATH is
the whole mechanism. Same trick, opposite result, and the difference is which
side of the port the script is on.

**What no check reaches:** a real redeploy under a live session, which is the
whole bug. `checks.session` boots a desktop but does not rebuild under one.
Checked by hand on p620.

## A PATH stub loses to runtimeInputs, and it has now cost three attempts

`writeShellApplication` **prepends `runtimeInputs` to the caller's PATH**, so a
stub of a declared dependency is never reached. The declared binary wins, but
an undeclared command may still come from the caller's PATH. This precedence
defeats the obvious way to stub declared tools.

It has been hit three times in one day, each time with a different symptom:

- `tests/apply-confirm.nix` stubbed `nh`, which `nixarchy-apply` declares. The
  stub's trace never appeared, so "did it rebuild" had to be read from apply's
  own log instead.
- `tests/apply-detach-interface.nix` stubbed `systemctl`, which
  `nixarchy-apply` also declares (`pkgs.systemd`, for `--detach`). Worse: the
  never-ran case **passed for the wrong reason** -- the real `systemctl`
  reports nothing in the sandbox, which happens to be the expected answer. A
  false green, not a failure.
- `tests/shell-ipc-resolve.nix` stubbed `qs` and it **worked**, because
  `omarchy-shell` is upstream's and unwrapped. PATH is the whole mechanism
  there.

**So the rule is about which side of the port the script is on**, not about
stubbing. Ours are wrapped; upstream's are not. Before writing a stub, check
whether the command is in the target's `runtimeInputs`, and if it is, find
another observable -- the script's own output, or a file it writes.

**What `apply-detach-interface` therefore does not cover:** `--status`'s
mapping, including the `none`-not-`succeeded` case that the whole feature
exists for (a unit that never ran reads `Result=success ExecMainStatus=0`).
Only `--expect-sha256` is asserted, because it touches the file system rather
than systemd.

## wait_for_console_text rescans its whole buffer, once per arriving line

`checks.install-encrypted` never finished -- not once, in any nightly. It was
filed as eviction, then as starvation, and #937 split the nightly's install
chains to fix the starvation. None of that was it.

`wait_for_console_text`
(`nixos/lib/test-driver/src/test_driver/machine/__init__.py`):

```python
while True:
    console.write(self.last_lines.get(block=block))   # append ONE line
    console.seek(0)
    matches = re.search(regex, console.read())        # rescan the WHOLE buffer
```

With that check's pattern -- `assphrase for` with a kernel-line group between
**every character**, thirteen nested quantifiers, from #834 -- each rescan
backtracks over everything received since the wait began. **Then it feeds
back**: driver CPU grows with the buffer, starves the qemu on the same host,
the guest advances more slowly, the wait continues, the buffer grows. The
2026-09-25 nightly's target advanced **7 ms of guest time in 56 minutes**, with
the wall cost per guest millisecond doubling every line.

**The numbers are smaller than they sound**, which is the part worth
remembering: 452 lines, about 45 KB. A plain quadratic over 45 KB is nothing.
It is the *backtracking* over a growing input that costs, so "the buffer is
small" is not a reason to rule this out.

**Do not fix it by cheapening the pattern.**
`spec/2026-09-21-834-luks-prompt-race.md` measured that: joining the letters
with a loose quantifier matches a decoy containing no prompt, and a false
positive sends the passphrase to whatever is listening. The `DECOY` assertion
in the check exists to catch that edit, and it would have been the only thing
to catch it.

The fix bounds the **input**: poll a 64 KiB tail of `get_console_log()` instead.
91m52s (a timeout, so really unbounded) became **13m49s**.

**The control is what made this findable.** `checks.install` ran on the same
runner in the same minute and finished in 2m34s. Two checks, one variable --
`install-encrypted` sets `console=ttyS0` and waits on the console; `install`
does neither -- and byte-identical qemu invocations. When a VM check is
mysteriously slow, look for the sibling that is not.

**What could not be proven cheaply**, stated rather than implied: there is no
fast synthetic break. The bounded assertion sits inside the test script, which
runs about ten minutes in, so "remove the slice and watch it fail" costs a full
run. The before-state is an observed failure across three nightlies, which is
better evidence than a synthetic break anyway.

## A test file in tests/ is not a check, and the coverage gate cannot see that

`tests/shell-ipc-resolve.nix` shipped with #963 and `flake.nix` named it
**nowhere**. It had never run. Found only because #982 tried to register a
sibling beside it and the anchor was not there.

The gate in `build.yml` asserts that every entry in `checks` is built by some
workflow. It cannot assert the other direction -- that every file in `tests/`
is in `checks` -- so a test that is written, reviewed and merged without a
`flake.nix` entry is invisible to it. That is AGENTS.md section 4's headline
failure arriving through the one door the guard does not watch.

Both are registered now, and `checks.test-registration` (#1000) is the
comparison section 4 asks for: every `tests/*.nix` is imported by some `checks`
entry, or is named exempt with its reason. One exemption today --
`with-vm-cleanup.nix`, a helper four install tests import.

It matches `import ./tests/<name>.nix`, not the bare filename: a grep for the
name passes if it appears in a **comment**, and whether the file is imported is
the property. It misses a check that built its path dynamically; nothing does.

And it **refuses** rather than reports when fewer than 50 imports parse -- a
regex matching nothing would otherwise flag all 88 files, and one that
over-matched would accept everything and pass having checked nothing. Same
floor as #949's agent-id comparison and `readme-counts.sh`'s refusal at zero.

**What it still cannot reach:** a registered check that no workflow builds.
That is the existing gate's direction, and it holds.

## shell-restart-tree asserts on the script, not on a run

The patched `omarchy-restart-shell` reads `/run/current-system/etc/set-environment`
by absolute path, which a `runCommand` cannot fake. So the four cases grep the
shipped script.

**What that cannot reach:** whether the relaunched shell actually comes up on
the new tree. That needs a session that has rebuilt since login, which no check
here has. p620 is one most days, so it is a hand check.

## shell-restart-race runs the script, with a quickshell that dies slowly

`checks.shell-restart-race` (#953) runs the real `omarchy-restart-shell`,
patched and upstream's, against PATH stubs. That works because the script is
upstream's and unwrapped. The stubs model one config:

- the old instance dies at a scripted time, and `quickshell kill` blocks until
  then;
- `quickshell list` prints a block copied verbatim from a real run;
- a `hyprctl dispatch` launch "exits already running" while the old one lives.

**What it pins:** a 7 s teardown ends with one shell; upstream's script ends
with zero (the negative control); a wedged shell is reported with no second
launch; a fast teardown stays fast.

**What it cannot reach:** how long a real quickshell takes to tear down, and
whether real `quickshell list` still prints `Process ID:`. The first is a hand
check on p620: swap a plugin folder and restart at once. The second fails
toward today's behaviour, not a hang.

## Menu aliases: the words are a judgement, and nothing here checks them

`checks.options` asserts that the Nixi row carries its `when` guard and that no
second nixi row exists, and `checks.menu-verbs` asserts the actions are
commands the CLI accepts. Neither says anything about the **nine Ask rows'
aliases** added in #961, and no check here can.

Two reasons, both worth knowing before someone writes a check that looks like
coverage:

- **The matching is not ours.** The palette that searches these rows is
  nixarchy-menu, in another repository. Nothing in this tree exercises it, so
  "typing `system slow` finds *Make it faster*" is unverifiable from here.
- **The aliases are a guess about wording.** Whether a user types "lag" rather
  than "slow" is a judgement about people, not a property of the file. A check
  that asserts the alias list equals a literal would pass forever and prove
  only that somebody wrote it down twice.

So the aliases are checked by a human typing into the palette. What IS worth
guarding mechanically, and is: that adding them did not disturb the assertion
in `pkgs/omarchy/default.nix`, which requires at least ten `trigger.ask*` rows
and a floating-terminal action on each. The aliases key goes in before
`action`, so that value is untouched.

## The stub-only detach: `run --detach` never runs a real unit on a PR

`checks.microvm-template` proves `nixarchy vm run --detach` against **stub**
`systemd-run` and `dtach` (exported bash functions, because
`writeShellApplication` puts its runtimeInputs first on PATH, and a stub file
is never reached). The stubs run the launch for real, so the lock hand-off
and the timeout are real. But a real `systemd --user` unit, a real dtach
socket and a real guest behind them are not: a sandboxed derivation has no
user manager.

**Nothing exercises a real detach yet, nightly included.** `microvm-boot`
boots a *declared* machine as root, with no session user (`user = null`) and
no network for `run`'s `nix build github:...`, so it cannot host this without
a redesign. A detached VM that stops starting is found by hand, on real
hardware: `nixarchy vm run --detach <n>`, then `nixarchy vm list --json`
shows `running: true`, and `nixarchy vm console <n>` attaches.

## A detached rebuild is proven failing, never succeeding

`checks.session` runs `nixarchy-apply --detach --yes` against **real**
systemd, but aims it at a missing flake. The session VM is offline and can't
evaluate its own flake, so a rebuild that *succeeds* inside a detached unit
can't be staged there. What the check does prove:
- the unit exists;
- it keeps `Result=exit-code`;
- its output reaches the journal;
- a second detach is refused while one runs.

What only a person can prove: `nixarchy apply --detach --yes` on real
hardware, then `journalctl --user -fu nixarchy-rebuild` shows the build, the
dialog asks once, and the unit ends `Result=success`.

## The panel one: its buttons are pressed over IPC, and its pixels are not

The rebuild panel (#765 PR 5, `pkgs/rebuild-panel/`) is covered in three
places. #896 closed most of the gap that used to be here.

- `checks.qml` proves its three QML files parse -- and only that;
- `checks.apply-staging` proves the state mapping, because it is a command
  (`nixarchy-rebuild-state`) and not logic inside QML. That split exists for
  this reason;
- `checks.session` opens it with `nixarchy-plugin nixarchy.rebuild`, then
  drives its three actions over the shell's IPC and asserts what each one did:
  the unit started, the journal reached the clipboard, a terminal launched. It
  also asserts reattach after close/open, and -- the one that matters most --
  that **opening the panel starts nothing**, because every other assertion
  still passes if a regression made it rebuild on open.

Three things about how those assertions are written, each of which would
otherwise be a green light:

- **`Open full log in terminal` is NOT asserted either, and this one was
  *proven* worthless rather than suspected.** The assertion matched
  `pgrep -af omarchy-launch-floating-terminal-with-presentation`; the break ran
  in CI with `openInTerminal()` gutted and **came back green**. The pattern is
  searched across every process in the session, and something else already has
  one, so it never measured the button. The plan had warned about the adjacent
  trap -- `RebuildState` follows the unit's journal itself, so a
  `journalctl.*nixarchy-rebuild` match is satisfied by the panel's own
  follower -- and the matcher written to dodge *that* fell into a wider one.
  Retargeting it wants a before/after count of matching processes, or a marker
  only the button can produce; neither was worth two more CI round trips at the
  time, and a row that cannot fail is worse than no row.
**`Copy log` is the one action with no assertion, and that is a decision, not
an oversight.** Two CI runs put the unit's journal on the clipboard and then
compared `wl-paste` against it; both timed out while the assertions on either
side passed. The row was dropped rather than retried (§10, and the spec said so
in advance). What is *not* established is which of these is true:

- the assertion is wrong -- a trailing newline, a stale selection, or the
  journal growing between the snapshot and the copy; or
- **the button is broken.** `wl-copy` forks a daemon to serve the selection,
  and `RebuildState.copyLog()` runs it as `sh -c "journalctl … | wl-copy"`
  inside a Quickshell `Process`. If Quickshell reaps that process group when
  the `Process` finishes, the forked `wl-copy` dies with it and the clipboard
  is never served.

The second is worth ruling out **by hand on real hardware** before writing any
more of the first: press Copy log after a failed rebuild and paste somewhere.
If it does not paste, the check was right and the panel needs fixing.

Note also what the first attempt got wrong, because the shape recurs: the
assertion asserted the journal was non-empty *before* comparing, precisely so
that an emptied `copyLog()` could not pass by leaving an empty clipboard to
match an empty journal.
- **An unknown verb is asserted to fail.** `omarchy-shell` wraps `qs ipc call`,
  which exits 0 on IPC-level errors and writes them to stdout; the wrapper
  repairs that by matching `Function not found.` **per function name**. That is
  why the panel has a verb per button rather than one `invoke(action)` whose
  bad argument would return quietly -- and why the check proves the mechanism
  once rather than assuming it.

What still reaches nothing: the **rendering** -- the confirm text, the elapsed
time, the log tail. OCR is not an option (#765 PR 1 found this theme unreadable
to it, which is why the session probe waits on a `polkit-agent-helper@*` unit
rather than on text), and nothing here drives a click in the shell's QML. And
"one polkit dialog per Apply" stays where it was: a real networked switch, by
hand, on real hardware.

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

## An inventory check cannot check its own reasons

`bin-ledger` and `etc-overlay` are the same shape: a table in `data/` claiming
something about upstream's tree, and a check that diffs the table's keys against
that tree in both directions. What each proves is narrow and worth stating —
**that every path is classified and no classification is stale.** Whether the
row's *reason* is true is prose, and nothing here reads it.

That is a documented hole rather than a fixable one: "`services.resolved` is not
enabled, so there is no second mDNS responder to silence" is a claim about the
whole module system, and a check strong enough to verify forty of those is the
module system. What the check does instead is force the sentence to be written
when upstream changes, and force it to be long enough to be checkable by a
person — `etc-overlay` throws on a reason under 80 characters for that reason
alone. Reasons go stale silently; the keys cannot.

## A verb check is not an arity check

`checks.menu-verbs` proves that every verb a menu row runs is one its CLI
accepts. It never proved that the call could succeed. The Sandbox group
shipped five rows (`nixarchy-vm create`, `run`, `stop`, `rm`, `list`), and the
first four needed a VM name that no row passed. They printed usage and exited 1
for everyone, with the check green throughout (#781). They were only noticed
while planning the panel that replaced them (#766 PR E). A row that needs an
argument the menu cannot supply is not a menu row at all. Before adding one,
run its exact action string once by hand. The MicroVMs contract scan has the
same limit: it checks the verbs `Model.js` runs, not the arguments it passes.

## Default plugins are tested with stand-ins, never the real four

nixarchy's default plugins (#766) are exercised through the internal
`programs.nixarchy.defaultPluginSet`:

- `options` fills it with two fixture manifests built in the check itself;
- `plugin` fills its `defaults` node with the omteleprompt pin it already
  fetches.

Neither uses nixarchy-pkg, -podman, -distrobox or -microvm. Those arrive as
flake inputs that move with every pin bump, so a test built on them would
change for reasons unrelated to what it tests, and the mechanism would be
untestable until the first of them landed. What the stand-ins cannot show is
that a real plugin's panel opens. That belongs to the PR that adds each
plugin, and the build asserts each default's manifest id.

**Adding an UNGATED default means teaching two all-defaults-off fixtures**, and
they are in different files:

- `noDefaultsHome` (`tests/options.nix`), so `defaultPluginsNoHookWhenEmpty` can
  assert "nothing resolved, no hook";
- the `machine` node's `defaultPlugins` block (`tests/plugin.nix`), so the
  machine really has an **empty plugin directory** — several assertions there
  depend on it, including that the Remove Plugin row hides itself.

Miss the first and `checks.options` fails on that assertion's *off* half. Miss
the second and `checks.plugin` fails with `the Remove Plugin row still shows
itself with no plugins installed`. Neither message names your plugin or your own
new assertion, so both read as unrelated regressions — #765 PR 5 hit them in
that order, the second only in CI because `checks.plugin` is a booted VM. They
are §4's hand-maintained list failing closed rather than open, which is the
right direction, but only for somebody who knows where to look.

A **gated** default (podman, distrobox, devenv) does not hit either, because it
resolves to nothing on those nodes anyway. That is why the lists are shorter
than the default set, and why the trap only springs on an ungated one.

And when proving such an assertion can fail, **delete the entry rather than
renaming it.** A plugin is installed under its manifest's `id`, not its
attribute name, so a rename leaves it installed and turns a *different* check
red. Read the assertion's own value in the log (`rebuildIsADefault: on= off=`),
never the exit status alone.

One exception, about a plugin's *tools* rather than the plugin: the
`defaults` node turns the real herdr default back on (#771). What it proves is
that the `herdr` binary the entry brings is on the session's PATH and the
widget's backend reaches it, and a stand-in herdr would prove only that a
stand-in is there. It asserts the backend's answer (`"ok":true`), never the
widget's rendering, so a pin bump that changes the widget does not move it.

The `defaults` node boots only after `machine` shuts down. Two VMs up at once
is a load the runners were never measured for (AGENTS.md §6).

## The box checks moved onto a plugin, and three things went with them

#801 retired `nixarchy box`. The two box checks were retargeted rather than
deleted, but what they now exercise is not what they exercised before, and the
difference is worth stating rather than discovering.

**They MIRROR a pinned rev; they do not run it.** `box-boot` builds the argv
`Model.js`'s `createArgv()` builds -- `env DBX_CONTAINER_MANAGER=podman
distrobox create --yes --name <name> --image <image>`, with the image read out
of the generated INI the way the panel reads it. The panel is a flake input
pinned by rev, and a bump that changes `createArgv` will not move this check.
The mirror can rot silently; that is the trade.

The first attempt at this retarget ran `distrobox-assemble` against the same
INI and called it "the panel's create path". It is not one, and the error is
worth keeping because it survived a spec, a plan, five commits and a review of
my own: the panel parses that INI **in JavaScript and never hands it to
assemble**, because assemble writes each `key=value` into a file it sources as
shell. Reading the dependency's source is what caught it; nothing in this
repository could have. The panel opening at all is the plugin PR's
business (see the stand-ins section above), and `menu-verbs` asserts only that
the Boxes row names an installed plugin id.

**The cheap static half is gone.** `box-template` used to grep the built
`nixarchy-box` for a literal store path to distrobox, which is the rule
`modules/services/boxes.nix`'s header states (nixpkgs#478154): reached any way
other than by bare name, distrobox bakes a generation-specific entrypoint into
every container it creates, and garbage collection can delete that path from
under a running box. A QML panel has no generated script to grep, so that
assertion has no equivalent -- it was not moved, it was lost. What remains is
`box-boot` observing the recorded mount on a real container, which is the
stronger measurement and the one that needs `/dev/kvm`. A regression a grep
would have caught on every pull request now waits for a VM.

**Nothing asserts the retired verb still answers.** `modules/apps.nix` keeps a
`box)` case that prints a pointer at the panel. Delete that row and `nixarchy
box` falls through to `exec omarchy "$@"`, which answers a command this
project shipped with *"Unknown Omarchy command: omarchy box"* -- the #538
failure, in reverse. No check covers it. It is one `case` row, so the cheapest
honest guard would be a grep over the built dispatcher, and this paragraph is
here rather than that check because nobody has written it.

One more, adjacent and worse, found while retargeting: **`tests/demo/`'s
scenes are `packages`, not `checks`, and no workflow builds any of them.** The
`boxes` scene drove `nixarchy box` and would have gone on producing a
published GIF of a command that errors, silently, with `main` green. Anything
in there that names a command is unguarded by construction.

**`send_key` drops a key name QEMU does not know, silently** (#1223). The
driver maps a *character* (`"?"` becomes `shift-0x35`) but passes a *name* to
`sendkey` as is, and QEMU ignores names it has no code for: no error, nothing
typed. `send_key("question")` never opened the key sheet, in the `pkg`
scene or in the `services` scene copied from it, and `services` still passed
its gate twice, on transitions earned by a toast fading and the panel closing.
Send the character, and look at the verify frames of any gate that passes at
its floor. A diversity count proves the screen changed, not what changed it.

## Nothing here can watch a compositor die, or a window open on your desktop

The `hyprland` microvm template (#821) has two properties no check in this
repository can reach, and both are named here rather than closed on paper,
which is what §3 asks for.

**A dead compositor.** Hyprland runs as a *user* service in that guest, so it
never appears on the system console a VM check reads. Its unit has
`Restart=no`, `enable_stdout_logs = true` and a note telling the reader to run
`systemctl --user status hyprland` -- all asserted by evaluation, so the
mechanism that makes a failure discoverable is guarded. **Whether a killed
compositor is actually noticed by a person is not.** Two `runNixOSTest`
attempts to kill it and look wedged: the driver reported the test running with
no qemu process at all and a log untouched for 26 minutes -- CLAUDE.md §6's
"a wedged `nix build` looks exactly like a working one", exactly. The harness
was what failed, not the template.

**A window on the host.** `microvm.graphics.backend = "headless"` exists so
the VM opens nothing on the desktop of whoever runs it, and no check here has
a desktop to look at. What *is* measured is the property that makes a window
impossible: with `DISPLAY` and `WAYLAND_DISPLAY` stripped, `egl-headless` runs
and `gtk` fails with `gtk initialization failed`. Headless is not a window
nobody looked at; it is a configuration that runs where no display exists.

A related trap for anyone tempted to check the other half by hand: with the
template's `virtio-gpu-gl` attached, `-display gtk` never reaches a window at
all -- qemu refuses with `OpenGL is not supported by display backend 'gtk'`,
because this qemu is built without GL in its gtk backend.

## The screencast harness is scripts, and only its coverage is a check

`tests/demo/screencast/` (#930) sits beside `tests/demo/`, and inherits that
directory's oldest problem: **no workflow builds any of it.** AGENTS.md section
4 records the same hole for the demo scenes, where a GIF of a deleted command
would have gone on publishing with `main` green. One piece has since become a
check; the rest has not.

So what is guarded here, and by what, stated plainly:

| | guarded by | runs in CI |
|---|---|---|
| prep refuses on open windows, a stale snapshot, an unreachable shell | by hand, on a real session | no |
| restore returns `shell.json` byte-identical | by hand, hash compared independently | no |
| `verify-beats` fails a beat that did not happen | three tests against a synthetic recording | no |
| every shipped plugin is in the shot list, as an `id = "…"` field | `checks.shot-coverage` (#1062) | **yes**, on every PR |

That last row was the one worth fixing, and #1062 fixed it.
`shot-coverage.sh` is a seconds-long text comparison with no VM and no
desktop, and `checks.shot-coverage` runs it over copies of exactly
`modules/home.nix` and `shots.nix`. It went unwired for months on the
belief that a new `checks.*` entry needed a workflow edit. It does not:
`build.yml`'s generated step builds any check no job claims (AGENTS.md
section 4). While nothing ran it, three default plugins shipped without a
shot. The check proves a beat is *written*, not that it records. That is
still `verify-beats`, on a real desktop, at the next take.

What no layer can reach, and which no amount of scripting changes: whether the
recording is **good**. The gate proves each beat happened and that the cut
carries the caption it claims. Whether a viewer understands it is a person
watching, and that is the last step of the plan rather than an afterthought.

## The notification one: a file stands in for the toast, and pixels never confirmed it

`checks.session` sends a critical notification, closes it over D-Bus the way
an application does, and asserts its popup file moves from
`~/.local/state/omarchy/notifications/` into `history/` (#1032). With the
patch removed the file never moves. With the fix changed to delete rather
than archive, nothing reaches `history/`. So the check pins both the fix and
the decision that a sender's close archives, like dismiss and expire.

It is **two waits, and it had to be.** The first version tested
`test ! -e <popup> && test -e history/<popup>` in one wait, and that failed
identically whether the toast stayed or left without reaching history. It
was red for both breaks, and it could not say which break it had seen. Split,
the patch-out run fails at "left the screen" and the delete variant fails at
"reached history". **A compound assertion that goes red has proven only that
one of its halves is false.**

**The file is a stand-in for "the toast is on screen", and the stand-in was
never confirmed by pixels.** The plan asked the red run to OCR the screen
after the close and read the toast still there. Twice it could not. The
first time, earlier blocks' toasts were on screen. The second time, after
`dismissAll`, the rebuild panel from an earlier block covered most of it. The
link rests on the code: `persistPopupFile` writes the file when the toast is
inserted, and every path that takes a toast off the screen archives or
deletes it. That is a good reason, but it is not a measurement. Anybody
tempted to extend this should close the rebuild panel first, or run the
probe before that block.

Do Not Disturb is asserted off before anything is sent. Silenced
notifications never get a popup, so without that assertion the block would
pass by never showing anything.

## The branch guard: every caller run for real, and the one thing only root can show

`checks.branch-guard` (#1037) runs the helper through every rule against
throwaway repos with a local bare origin: on main, a feature branch, detached
at and away from `origin/main`, an `origin/HEAD` of `master`, an unset
`origin/HEAD`, no remote, not a repo, a `#attr` suffix, the override. Then it
runs the **real** `nixarchy-apply`, `omarchy-update` and `autoUpdate` unit
script against a checkout on a feature branch. Each refusal is proven by an
observable, not an exit code: apply leaves the checkout clean and never
reaches `nh` (with a positive control on main that does), and `autoUpdate`
leaves `flake.lock` alone and writes the doctor's note. `checks.session`
covers the `--detach` path the sandbox can't run: the parent starts the unit,
the unit refuses where the panel can see it, and `ALLOW_BRANCH_DEPLOY=1`
reaches it.

Three things it cost, all general:

- **An assertion about something that cannot happen here is a green light.**
  "`autoUpdate` leaves the lock untouched" passed with the guard deleted,
  because `nix` isn't in the sandbox and the update failed before it could
  move anything. It took a stub `nix` that edits the lock (the one
  `tests/options.nix` uses) to make that line able to fail. Before trusting
  a "nothing changed" assertion, ask whether anything *could* have changed.
- **Where a package's tools reach PATH is the property, not its closure.**
  omarchy's `runtimeDeps` are `passthru`, and its `bin/` is unwrapped, so a
  helper added there is absent from the package closure by design. It
  reaches a machine through the module's `systemPackages`, and that is what
  the check reads, passed in as a yes/no value.
- **`msg=$(cmd); rc=$?` dies under the builder's errexit** the first time
  `cmd` fails on purpose, and the check stops after its last green line with
  nothing said. `msg=$(cmd) && rc=0 || rc=$?`.

**What only a real machine showed:** a checkout owned by one user and read
by another. The sandbox has one uid. On p620, root with `SUDO_*` stripped
(as under systemd) gets `detected dubious ownership` from plain `git` on a
user-owned clone outside the system's `safe.directory`, and the helper's
`-c safe.directory` answers correctly there. `/etc/nixos` itself is trusted
system-wide by `modules/nixos.nix`, so the managed path never depended on it.

<a id="a-pipe-into-grep-q-can-fail-because-grep-matched"></a>

## A pipe into `grep -q` can fail because grep matched

`checks.manifest-has-kind` once reported "manifestHasKind not found" for a file
that contained it. `main` passed on the same source path seconds earlier, and a
re-run passed (#1058). The line was:

```sh
printf '%s\n' "$fn" | grep -q 'function manifestHasKind' || fail "not found"
```

Three facts combine:

- **`runCommand` and `writeShellApplication` run under `pipefail`**, so a
  pipeline fails if *any* stage does.
- **bash's `printf` writes line by line.** strace shows one `write()` per line,
  four for a four-line string, even at 149 bytes.
- **`grep -q` exits at the first match.** If the match is early, grep can be
  gone before the producer's next `write()`, which then takes SIGPIPE.

The result is `PIPESTATUS=141 0`. grep answered yes, and the pipeline reports
no. It is deterministic once a delay separates the writes, and it did not
reproduce in 8,000 runs on an idle workstation, even pinned to one busy CPU. It
needs the writer preempted between lines, which a 2-vCPU hosted runner in the
middle of a parallel `nix build` does. So a local loop that stays green proves
nothing here.

The safe spellings keep grep from being the one that decides when the input
ends:

- a string already in a variable: `[[ $x == *pat* ]]`, or `case` in `/bin/sh`;
- `grep -q pat <<<"$x"` or `grep -q pat file`: the shell or the filesystem
  supplies the whole input, and no producer process is left to kill;
- `grep -c`, or grep without `-q`: reads to EOF.

It only bites where **both** hold: `pipefail` is on, and the producer can
write after the matching line. #1060 read every one of the hundred sites
rather than assuming. Where `pipefail` holds:

- **on:** stdenv builders (`runCommand`, every phase: `setup.sh` sets it and
  never restores it); `writeShellApplication`; the NixOS test driver, whose
  `succeed`, `fail`, `execute` and `wait_until_succeeds` all run
  `bash -c 'set -euo pipefail; …'`; a workflow step that says
  `set -o pipefail`, or has `shell: bash` spelled out.
- **off:** a pipe inside `su user -c '…'` or `sh -c '…'` (a fresh shell);
  a GitHub Actions `run:` with no `shell:`, which is `bash -e {0}`.

And when the producer can write after the match:

- bash's `printf` and `echo` write once per line;
- an external tool buffers, and writes in 4 KiB blocks, so output under
  4 KiB is a single write at exit and cannot be cut off by an early exit;
- `gh` writes line by line, and `journalctl` is unbounded: always capture.

**The masking form is the worse one.** Under `! … | grep -q x`,
`… | grep -q x && fail`, or `machine.fail("… | grep -q x")`, a match
followed by SIGPIPE turns into a **pass**, with `x` present:

```sh
$ bash -c 'set -o pipefail; ! { printf "x\n"; sleep 0.2; printf "y\n"; } | grep -q x; echo rc=$?'
rc=0
```

In a VM driver string, capture and use a here-string:
`"out=$(journalctl -u foo); grep -q 'PAT' <<<\"$out\""`. The driver
`shlex.quote`s the whole command, so nothing else needs escaping.

**`checks.grep-q-pipefail` enforces this.** Every pipe into `grep -q`
under `tests/`, `modules/`, `pkgs/`, `installer/`, `.github/` and
`flake.nix` is either rewritten or listed in `tests/grep-q-allowlist.txt`
as `path<TAB>the line, trimmed<TAB>why it cannot fail`. It scans every
`*.nix`, `*.sh` and `*.yml` file, plus any extensionless file under those
same roots whose first line is a bash or `sh` shebang — `--include` alone
misses an extensionless script, and `pkgs/omarchy/nix-bin/` holds 37 of
our own. The key is the
line's text, not its number, so unrelated edits do not touch it. The
check fails on a new line (rewrite it, or list it with a measured reason)
and on an entry whose line is gone (delete it). It does not read
reasons: an entry with a wrong reason is a review failure, not a check
failure (see "An inventory check cannot check its own reasons" above).

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

## menu-close runs the real omarchy-menu against a stub omarchy-shell

`checks.menu-close` (#1070) runs upstream's unwrapped `omarchy-menu` unchanged;
a PATH stub stands in for `omarchy-shell`. It pins two things: the
call-before-hide order (`shell call omarchy.menu dismiss` is always tried
first) and the reply match (a reply of exactly `ok` short-circuits before
`shell hide` runs at all; anything else, or no answer, falls back to hide).
It does not pin an `ok` reply that arrives with a non-zero exit, since
`omarchy-shell` never produces one. What it does NOT
pin is `qs`'s real reply format -- only `checks.session`'s #1069 probe, against
a live shell, sees that.

## Working here

- **Dynamic VMs need bounded cleanup on failure (#714).** The pinned driver's
  `create_machine` does not register its result. `shutdown()` waits on the
  process without a timeout, `release()` joins the non-daemon serial reader
  without a timeout, and a monitor `quit` can block too. The install tests use
  `vm-cleanup.py` from `finally`: kill every owned process, then bounded waits
  for children and serial readers. On an unreapable reader, print the original
  assertion and force a failing exit rather than hang in Python's exit joins.
  Register before `start()` so partial starts are covered. The driver uses
  `Popen(shell=True)`: prefix our direct qemu commands with `exec` so the
  process handle owns qemu, not a shell. `install-teardown` drives real
  SIGTERM-ignoring subprocesses and a stuck reader; it does not boot qemu.

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
- **A `VAR=value cmd` prefix does not reach a `$(substitution)` in the same
  line**, and in `session.nix` that silently strips the session environment.
  `as_user` builds exactly that prefix (`XDG_RUNTIME_DIR=… DBUS_…=… <cmd>`),
  so `as_user('test "$(wl-paste)" = "$(journalctl …)"')` runs **wl-paste
  without XDG_RUNTIME_DIR** -- the shell expands the substitutions before
  `test` is executed, and the assignment applies only to `test`. It fails with
  `XDG_RUNTIME_DIR is invalid or not set in the environment`, which reads as a
  broken VM session rather than a broken assertion, and the assertion could
  never have passed whatever the thing under test did. Make the command that
  needs the environment *be* the command: `as_user("wl-paste > /tmp/clip")`,
  then compare the files in a separate step. #896 lost a CI round trip to this.
- **Never name a shell variable `out` in a `runCommand` script.** `$out` is the
  derivation's output path, and assigning to it means every assertion passes
  and the build then fails with *"builder failed to produce output path"* —
  which reads as a broken derivation rather than a shadowed variable. Cost one
  full build in `tests/android.nix` before the cause was obvious. `got` is the
  usual name for "what the thing under test printed".
- **`printf '%s' "$x" | grep -q` is a race under `pipefail`, and a
  `runCommand` script always has `pipefail`** (stdenv's setup sets it).
  `grep -q` exits at its first match; if the writer is still writing, it dies
  of SIGPIPE, the pipeline reports 141, and the `if` takes the *no match*
  branch. `checks.channel` failed on a hosted runner with the line it wanted
  printed in its own failure message. Reproduced with that 6 KB input: 172–200
  of 200 runs report a miss when the pipe is starved, 0 of 200 on an idle
  machine, which is why it passed locally. The inverted form is worse: a
  `wantnot`, or `… | grep -q X && fail`, **passes** with X present. Use
  `grep -q … <<<"$x"` or `[[ $x == *…* ]]` (the section above has the forms;
  relying on grep reading to EOF without `-q` is an implementation detail,
  and ugrep is not GNU grep). The same holds for `pkgs/*.sh`, because
  `writeShellApplication` sets `pipefail` too.
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
- **Run a unit's `script`, do not grep it.** `options` asserted the
  auto-update service contained the words `uncommitted changes`, and passed
  for as long as the guard refused every run on every installed machine: the
  installer never commits, so `git diff HEAD` exited 128 and read as dirty. A
  NixOS config hands you the unit's text as
  `config.systemd.services.<name>.script`; `tests/options.nix` now runs it with
  `nix` and `nixos-rebuild` stubbed on `PATH` against real `git` repositories in
  each state the installer and the job itself leave behind.
- **A command substitution that fails ends a `runCommand` with no message at
  all.** `id=$(grep -oE '#@ [a-z0-9_-]+$' "$f" | head -1 | cut -d' ' -f2)` matched
  nothing — service markers carry a trailing comment, app markers do not — and
  under `errexit` plus `pipefail` the script stopped at the assignment. The last
  line in the log was the *previous* section's success message, which reads as
  that section having failed. When a check stops after a green line with no
  error, the cause is the first `$(...)` after it; guard lookups that may miss
  with `|| true` and a `test -n` that says what was missing.
- **A line-order assertion checks where text sits, not the order anything runs
  in, so moving a function breaks it.** `installer-store-space` and
  `installer-from-repo` prove `preflight_build` runs before `format_disk` by
  comparing line numbers in `install.sh`. Moving the install phases into a new
  function defined *above* `main()` reversed the numbers while the runtime order
  was unchanged, and both went red in CI on #693. A locally chosen set of
  "relevant" checks had left both out. When you move code in `install.sh`, run
  every `installer-*` check, not the ones that look related; they are seconds
  each. And a line-order check also needs the call that reaches the moved code,
  or it stays green when nothing calls it.

## The install checks' seed is the installer template's shape, depth for depth

`checks.install`, `free-space` and `install-encrypted` install offline. They
pass only if the system the VM installs is byte for byte the one the test
seeded, `system-path` included. `system-path` hashes the ORDER of
`environment.systemPackages`, and `lib.modules` merges list definitions in
import-depth order. So the seed must import every module at the depth the
generated host does:
- nixarchy, home-manager and disko at 0;
- `host.nix`, `disk-config.nix` and the configuration values at 1;
- the hardware config, the initrd pin and `test-instrumentation.nix` at 2,
  where `configuration.nix` imports them.

All three tests build it through `tests/lib/installed-target.nix`. The seed
imports the same instrumentation text the VM gets, via `builtins.toFile`.

Each test used to carry its own copy with the last three at depth 0. That held
only while nothing else changed depth: #1176's `_file` imports wrap put
nixarchy's own module one level deeper, `xwininfo` moved from entry 21 to 0,
and the offline install tried to build `texinfo` from source.

**Measured on the helper (#1179):**
- instrumentation at depth 0 alone: still equal;
- #1176's wrap alone: still equal;
- both together: three instrumented cases differ.

So the split needs two depths to move, and a check that varies only one
cannot see it (§3).

`checks.install-seed-shape` renders the real template with `install.sh`'s own
`substitute_host_files`, and compares `system-path` against the seed for all
six cases. It is evaluation only, so the next mismatch is red on the pull
request rather than forty minutes into the install job.
`nixarchy-hardware.nix` (nixos-hardware CPU modules) is left out of the seed:
measured for both vendors, it does not change `system-path`.

The VM side renders `installer/template/host/` with `install.sh`'s own
`subst`/`substitute_host_files`, extracted with sed rather than sourced --
sourcing install.sh starts the wizard (the same pattern
`tests/installer-offline-rescue.nix:37` uses) -- then imports it inside a
`nixosSystem` the way `installer/template/flake.nix` would: real derivation
outputs, not `builtins.toFile`, so evaluating the check builds six small
IFD renders (seconds each, no VM).

`hardware-configuration.nix` is the one file `nixos-generate-config` writes
that nothing here can reproduce by substitution -- it runs on a real
machine to detect. So the VM side's stub takes the seed's own
`hardwareConfig` and `initrdPin` MODULES through `specialArgs`, not a
second text encoding of them: this compares WHERE they are imported, at
the real depth, not what `install.sh` writes INTO the file. The seed's
`initrdPin` is a bare `mkForce`; `install.sh`'s real pin additionally wraps
it in `lib.mkIf (config.boot.kernelPackages.kernel.version == "...")`, so a
kernel-version mismatch this check cannot see is still `install.sh`'s to
catch, not this one's.

<a id="byte-identical-instrumentation"></a>
### Byte-identical instrumentation

The seed imports `test-instrumentation.nix` the same way the real install
does: `builtins.toFile` writes the text once, and both sides import that
exact store path. Importing it rather than the `instrumentation` module
every test used to carry separately is what makes the seed and the
generated flake import BYTE-IDENTICAL content -- not merely equivalent
Nix, the same file. `builtins.toFile` hashes the string itself, so this is
not IFD.

<a id="why-systempath-not-toplevel"></a>
### Why `system.path`, not `toplevel`

`targetSystemFor` keeps the old shape every caller (tests/install.nix,
free-space.nix, install-encrypted.nix) already uses -- `.toplevel`,
`.diskoScript`, `.initialRamdisk`, `.etc` -- and adds `.path` beside them:
`system.path` is `config.system`'s own sibling of `config.system.build`,
not inside it. `checks.install-seed-shape` needs `.path` because #1176 is
about the ORDER `environment.systemPackages` is built in, which
`system.path`'s `buildEnv` hashes directly into its own derivation.
`toplevel` sits on top of a great deal else -- the initrd, the activation
script, hostname-bearing bits -- that can legitimately differ for reasons
this check is not about.

<a id="one-source-for-hardwareconfig-and-initrdpin"></a>
### One source for `hardwareConfig` and `initrdPin`

`tests/lib/installed-target.nix` exposes `hardwareConfig` and `initrdPin`
so `tests/install-seed-shape.nix` can reproduce the real
`hardware-configuration.nix`'s CONTRIBUTION exactly -- `mkForce` and all --
on the rendered-template side it compares against. Passed through
`nixosSystem`'s `specialArgs` there rather than serialised to text: the
same Nix values both sides import, not a second encoding of them to keep
in step.

