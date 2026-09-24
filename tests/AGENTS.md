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

## The screencast harness is scripts, not checks, and nothing in CI runs it

`tests/demo/screencast/` (#930) sits beside `tests/demo/`, and inherits that
directory's oldest problem: **no workflow builds any of it.** AGENTS.md section
4 records the same hole for the demo scenes, where a GIF of a deleted command
would have gone on publishing with `main` green.

So what is guarded here, and by what, stated plainly:

| | guarded by | runs in CI |
|---|---|---|
| prep refuses on open windows, a stale snapshot, an unreachable shell | by hand, on a real session | no |
| restore returns `shell.json` byte-identical | by hand, hash compared independently | no |
| `verify-beats` fails a beat that did not happen | three tests against a synthetic recording | no |
| every shipped plugin is in the shot list | `shot-coverage.sh` | **no, and it could be** |

That last row is the one worth fixing. `shot-coverage.sh` is a seconds-long
text comparison with no VM and no desktop — exactly the cheap shape this file
recommends — and it is the only piece here that a pull request could run. It
is not wired, because adding a `checks.*` entry means a workflow edit and that
is a human's call (section 4, section 11). Raised rather than done.

What no layer can reach, and which no amount of scripting changes: whether the
recording is **good**. The gate proves each beat happened and that the cut
carries the caption it claims. Whether a viewer understands it is a person
watching, and that is the last step of the plan rather than an afterthought.

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
  `<<<"$x" grep -q`, or drop `-q` and send the output to `/dev/null` so grep
  reads everything. The same holds for `pkgs/*.sh`, because
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
