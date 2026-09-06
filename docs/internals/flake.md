# flake.nix

The reasoning behind the repository's flake, moved out of the file so it reads
as code. Every entry is reachable from a `# Why:` pointer at the line it
explains.

Deliberately **not** in the root `AGENTS.md`: that file is symlinked as
`CLAUDE.md` and loads into every session, so a thousand lines of build
reasoning there would cost context on every task that has nothing to do with
it. This page is read when somebody follows a pointer.

## What the flake is for

- **inputs** — nixpkgs is the package set; hyprland, zen-browser, microvm and
  the rest are pinned separately because they publish on their own schedule.
  Some pins are deliberate and must not be bumped by an automated job; the
  nightly review reports them and `flake-update.yml` names `nixpkgs` explicitly
  for that reason.
- **overlay** — how a package reaches a configuration. A module cannot take
  packages from `inputs.self.packages`: those are built from *nixarchy's*
  nixpkgs, and mixing instances makes `buildEnv` refuse a profile holding two
  builds of the same version.
- **packages** — the ISO, the installer, the doctor, `#try`, `#vm`.
- **checks** — 37 of them; `tests/AGENTS.md` covers what each proves.
- **nixosConfigurations** — `reference` is the machine the installer writes,
  `vm` is the smoke-test guest, `iso`/`iso-net` are the images.

## Two rules with teeth

- **A check here and in no workflow is not a check.** `build.yml` asserts every
  `checks.*` is run by some workflow, because one shipped that way and its pull
  request went green without it ever executing.
- **`self.rev` is absent on a dirty tree**, and `installer/mkFlake.nix` throws
  rather than pinning a user's machine to a store path that may be garbage
  collected. A build from an uncommitted tree fails on purpose.

---

## `flake.nix`

<a id="for-the-person-who-has-never-seen-this-repository-"></a>
### For the person who has never seen this repository and types

```nix
nixConfig = {
```

For the person who has never seen this repository and types
`nix run github:olafkfreund/nixarchy#try` (or #doctor, or #vm): without
this, nothing tells their nix that this flake's packages and closures
are already built and cached, and Hyprland alone becomes a compile.
nixConfig is honoured only from the flake you invoke -- the same rule
the sops-nix comment below leans on from the other side -- so the
module's `programs.nixarchy.binaryCaches` cannot reach a bare `nix run`;
only this can. Nix asks before trusting either entry (or accepts them
silently for users already trusting the caches), and a "no" costs
nothing but the download it was offered.

What this does NOT cover, measured rather than assumed: the ISO images
themselves are not pushed to cachix -- they ship as release assets --
so `#try` detects that case with a dry-run and falls back to the
release download instead of leaning on these substituters.

<a id="deliberately-unpinned-unlike-hyprland-sops-nix-and"></a>
### Deliberately UNPINNED, unlike hyprland, sops-nix and microvm below, and

```nix
home-manager = {
```

Deliberately UNPINNED, unlike hyprland, sops-nix and microvm below, and
not for lack of tags (home-manager has none; its releases are
`release-XX.XX` branches that pair with STABLE nixpkgs, which is not
what this flake tracks). master is co-developed against
nixpkgs-unstable, and nixpkgs above is itself a branch ref: one `nix
flake update` moves both to their tips together, which is the only
pairing home-manager tests. Pinning one side of that pair would CREATE
skew -- a frozen home-manager evaluating renamed and removed nixpkgs
attrs a few updates from now -- which is the exact failure pinning is
supposed to prevent. Pin this the day nixpkgs is pinned, and not before.

<a id="omarchy-4-x-configures-hyprland-through-the-lua-ap"></a>
### Omarchy 4.x configures Hyprland through the Lua API that landed in

```nix
hyprland.url = "github:hyprwm/Hyprland/0bd11c7a04a63d2785abd53363f09d552175d67d";
```

Omarchy 4.x configures Hyprland through the Lua API that landed in
0.55; nixpkgs is still on 0.54.3.

Pinned to a COMMIT, not the v0.56.2 tag, because that tag does not build
against its own flake.lock: its CMakeLists asks for
`find_package(glaze 7...<8)` while nix/overlays.nix feeds it the
glaze 8.0.0 from its locked nixpkgs. find_package fails, CMake falls
back to cloning glaze over the network, and the sandbox has none.
Upstream dropped the version bound after tagging, and v0.56.2 is the
newest tag, so there is no fixed tag to move to.

A commit is just as reproducible as a tag. Bump it deliberately; never
track a branch here, or `nix flake update` could break the bar on its
own while the Lua bindings are still moving.

Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`: hyprwm asks
consumers not to override it, and doing so forfeits their binary cache
and rebuilds the compositor from source. See nix.settings in
modules/nixos.nix for the matching substituter.

<a id="declarative-flatpaks-for-the-software-nixpkgs-genu"></a>
### Declarative Flatpaks, for the software nixpkgs genuinely does not carry

```nix
nix-flatpak.url = "github:gmodena/nix-flatpak/v0.7.0";
```

Declarative Flatpaks, for the software nixpkgs genuinely does not carry.

nixpkgs' own services.flatpak is infrastructure only -- the daemon, the
portals, polkit, FUSE -- and manages no applications. It does not even
add the flathub remote. So the honest answer this repo has been giving
is data/arch-extras.nix's `note = "then: flatpak install flathub ..."`,
which is advice to do the one thing this project exists to prevent:
install something imperatively that will not survive a rebuild.

This adds `services.flatpak.packages`, overloading the same option
namespace nixpkgs uses -- worth knowing, because a reader will look for
`packages` in nixpkgs' module and not find it.

Declared, not reproducible, and the distinction is real: the app IDS are
in your configuration and travel to a new machine, but the BITS are
whatever Flathub serves that day unless every entry pins a commit.
Rollback restores the list, not the version. Upstream nixpkgs has
declined to bless the equivalent (PR #347605, open since October 2024)
on exactly that objection. We take it anyway, because the alternative on
offer is a shell command in a comment.

No `follows`: v0.7.0 has no inputs at all, which makes this the cheapest
kind of dependency -- nothing to override, nothing to drift.

<a id="zen-is-not-in-nixpkgs-and-upstream-maintains-its-o"></a>
### Zen is not in nixpkgs and upstream maintains its own flake, which tracks

```nix
zen-browser = {
```

Zen is not in nixpkgs and upstream maintains its own flake, which tracks
Zen's releases far more closely than a derivation here ever would.

Pinned to a COMMIT because upstream's only tags are automated
`twilight-*` build tags, not releases of the flake -- main is the
release channel, the same position sops-nix and microvm already hold in
this file. What makes the pin worth its bump burden here is that this
flake's default.nix couples to nixpkgs' wrapFirefox SIGNATURE: at this
rev it overrides both the `ffmpeg_7` and `ffmpeg_8` formals, so it
needs a nixpkgs that declares both -- ours does -- and a branch ref
here hands whatever main has become to every downstream lock, against
whatever nixpkgs THEY have, where an eval throw is a break our CI
structurally cannot see (#320 was this, in one direction; stable
consumers hit it in the other). A commit makes the pair deliberate.

What the pin costs: Zen security releases stop arriving on their own.
Bump this routinely alongside `nix flake update`, and expect the bump
to become MANDATORY the day nixpkgs drops its `ffmpeg_7` formal, when
this rev's override starts throwing. Never track a branch here.

<a id="the-rdp-server-behind-the-remote-desktop-feature-1"></a>
### The RDP server behind the remote-desktop feature (#159)

```nix
hypr-rdp = {
```

The RDP server behind the remote-desktop feature (#159). Not in nixpkgs
-- nothing under that name as of 2026-09 -- and the two RDP servers that
are there cannot serve Hyprland: krdp needs the
org.freedesktop.portal.RemoteDesktop interface, which
xdg-desktop-portal-hyprland 1.4.1 does not advertise, and xrdp only
reaches Wayland through a wayvnc chain built from an unreleased commit.
So nixarchy carries the package until nixpkgs does.

The cost, stated rather than hidden: a flake input lands in EVERY user's
lock, including the Mode A machine that will never enable RDP. It is one
more ref `nix flake update` can move and one more repository that has to
keep existing. That is paid because the thing it buys -- reaching this
desktop from a Windows machine with nothing installed on it -- has no
other implementation at all, at any price. See the alternatives survey
on #159; every other route is closed, not merely worse.

What this project is taking on: v0.1.5, six months old, one primary
author. The protocol stack is not theirs -- it is IronRDP, Devolutions'
maintained Rust implementation -- so what this author owns is the
Hyprland glue: capture, input, audio, clipboard. That is a real
dependency on a small project, and a bad rebuild here breaks the machine
you are remote to, from where you cannot fix it. Hence a tag. Never a
branch, and bump it deliberately.

The input has a named exit: when hypr-rdp lands in nixpkgs, delete this
and point the module at pkgs.hypr-rdp.

That exit is now IN FLIGHT rather than hypothetical -- NixOS/nixpkgs#560204
("hypr-rdp: init at 0.1.5") is open. When it merges and reaches the nixpkgs
revision this flake pins, the deletion is:

  1. remove this input and its `follows`
  2. modules/services/hypr-rdp.nix: `inputs.hypr-rdp.packages.${system}...`
     becomes `pkgs.hypr-rdp`
  3. check nothing else reads `inputs.hypr-rdp` (grep; the module is the
     only consumer today)

Do NOT delete it merely because the nixpkgs PR merged: a merge into
nixpkgs master is not the same as being present in the revision we pin,
and removing the input before then leaves the module reaching for an
attribute that does not exist yet. The condition is `pkgs.hypr-rdp`
evaluating against OUR lock, not a green tick on a pull request.

`follows` is right here and wrong for hyprland above -- upstream's
pkg/nix/package.nix is a plain rustPlatform.buildRustPackage whose
cargoHash does not depend on which nixpkgs supplies ffmpeg, and they
publish no binary cache to forfeit by overriding it.

<a id="declarative-secrets-adopted-for-one-concrete-reaso"></a>
### Declarative secrets, adopted for one concrete reason rather than as a

```nix
sops-nix = {
```

Declarative secrets, adopted for one concrete reason rather than as a
general capability. #121 deliberately did not take a secrets mechanism
("a separate decision with a key-management story attached"), and #122
got away without one because `hashedPasswordFile` is consumed by NixOS
itself, so the cleartext could live outside git and be pointed at.

hypr-rdp removes that dodge. It reads its password from exactly two
places -- an inline string in config.toml, or `-p` on the command line,
which is world-readable in /proc/*/cmdline. Verified against v0.1.5:
src/config.rs resolves `args.password.or(config.password)` and nothing
else, there is no `password_file`, and clap reads no environment
variable for it. So the secret has to end up INSIDE a config file, and
something has to put it there at runtime from material safe to commit.

That requirement is what picks sops-nix over agenix. agenix delivers
files of raw secrets and has no templating, so composing one into a TOML
would mean a hand-rolled per-service ExecStartPre shim -- the exact hack
this is meant to avoid. `sops.templates` is that shim, upstreamed, with
the mode and owner declared. Everything else between the two is taste.

Pinned to a COMMIT because sops-nix publishes no release tags at all --
its only tag, `assets`, is from 2021 and is not a release. master is the
release channel. This is the same call flake.nix already makes for
hyprland above: a commit is exactly as reproducible as a tag. Bump it
deliberately; never track a branch.

What this costs a user's lock: ONE node. sops-nix declares exactly one
input, nixpkgs, which follows ours, so nothing transitive arrives. (Its
dev inputs live in a private flake under dev/ that consumers never see.)
Its nixConfig asks for cache.thalheim.io, which does NOT apply to us --
nixConfig is honoured only from the flake you invoke, not from inputs --
so no substituter and no trust is granted by taking this.

Inert on import, which is what makes it safe for Mode A: both halves of
the upstream module are gated, `lib.mkIf (cfg.secrets != { })` and
`lib.mkIf (config.sops.templates != { })`. A machine that defines
neither gets no unit, no activation script and no package. nixarchy sets
no sops scalar of its own -- `sops.age.sshKeyPaths` already defaults to
the ed25519 keys from services.openssh.hostKeys upstream -- so the
mkDefault rule in modules/services/default.nix never even arises here.
tests/options.nix asserts the inertness rather than trusting this note.

<a id="221-222"></a>
### #221/#222

```nix
microvm = {
```

#221/#222: the foundation of the sandboxes epic. A guest whose
`/nix/store` is a 9p share of the HOST's store -- `microvm.storeOnDisk
= false`, computed by upstream itself the moment
`microvm.shares` contains a `source = "/nix/store"` entry -- so no
image is ever built for a template and the closure a user runs is
store paths the host already had.

`follows = "nixpkgs"`, and deliberately not the reflex hyprland.url
above declines: microvm.cachix.org (this flake's own `nixConfig`,
inert unless a consumer opts in -- which nothing here does) carries the
non-qemu hypervisors, and every guest this repo builds is qemu. What a
user actually downloads on first launch is the template CLOSURE, built
from THIS lock and served by nixarchy.cachix.org -- following buys
nothing to forfeit there. What it buys instead is disko's argument, not
hyprland's: a guest and host that share glibc, systemd and openssh
store paths rather than each carrying a second copy, because the same
nixpkgs built both.

Pinned to a COMMIT. The newest tag, v0.5.0, is from April 2024 and
predates options modules/microvm/guest.nix depends on (`microvm.shares`
gained fields since); upstream publishes no newer tags and treats
`main` as its release channel -- the same position sops-nix already
takes in this file, for the same reason. Bump it deliberately; never
track a branch.

Lock cost, stated rather than hidden: TWO nodes for this one input, not
one. microvm.nix declares `nixpkgs` (which follows ours, so nothing
transitive) and `spectrum`, a `flake = false` tree it reads only to
patch cloud-hypervisor's graphics support -- a hypervisor nothing in
this repo will ever build, on a patch nothing here will ever apply.
`spectrum` still lands in every user's flake.lock, including the Mode A
machine that never asked for a VM at all. Paid because the alternative
-- vendoring a runner ourselves -- is the copy-upstream-and-keep-it-green
trade #221 already surveyed and rejected.

<a id="which-nixarchy-built-this-machine-208-for-nixarchy"></a>
### Which nixarchy built this machine (#208), for nixarchy-version

```nix
nixarchyRev = self.shortRev or self.dirtyShortRev or "unknown";
```

Which nixarchy built this machine (#208), for nixarchy-version.

`self` is the only place the answer exists, and it is only reachable
here -- pkgs/omarchy/default.nix cannot see the flake it belongs to --
so the two values are computed once and threaded into the package.

Not a tag: a flake cannot know its own, and the ordinary consumer
flake.nix tracks main and has none. Not a hand-kept literal beside
omarchyVersion either; that is the class of stale string #201 had to
fix. A rev cannot go stale.

`dirtyShortRev` is what a working copy with uncommitted changes gets
instead of `shortRev` -- it reads "800af40-dirty", which is the honest
thing for a machine built from someone's checkout to say. Neither
exists when the source is not a git tree at all, hence the last
fallback.

<a id="vainfo-for-the-graphics-section"></a>
### vainfo, for the Graphics section

```nix
libva-utils
```

vainfo, for the Graphics section. Declared because
writeShellApplication builds a strict PATH, and an undeclared
vainfo does not read as "vainfo is missing" -- it reads as "no
VAAPI driver answered", which is a different and much worse
answer to hand someone. It ran anyway while this was being
written, from the developer's own PATH, which is exactly how
that goes unnoticed.

No pciutils: the GPUs come from /sys/bus/pci, the same way the
Bluetooth check reads /sys/class/bluetooth, and sysfs hands over
the PCI address already in the form the bus IDs need.

<a id="nixarchy-apps-first-then-the-top-level"></a>
### nixarchy-apps first, then the top level

```nix
path = final.lib.splitString "." (app.attr or name);
```

nixarchy-apps first, then the top level. Apps
this repo packages live under nixarchy-apps, so
probing only the top level returned null for every
one of them and the fallback answered with the
attribute name. That is right by luck when the
attribute matches the binary -- once, omacut,
ttfx -- and wrong when it does not: `zen` for a
package installing bin/zen-beta, `hey-cli` for one
installing bin/hey. Both were reported as absent
on machines that had them.

<a id="podman-info-podman-inspect-for-the-boxes-section"></a>
### podman info / podman inspect, for the Boxes section

```nix
podman
```

podman info / podman inspect, for the Boxes section. Safe to
pin here -- unlike distrobox, podman does not resolve anything
relative to argv[0], so a /nix/store path to it carries none of
pkgs/box.nix's hazard. distrobox itself is deliberately NOT
here: it is looked up by bare name (`command -v distrobox`),
the same wrapper-only rule that command's own header explains.
hyprctl is deliberately not here either -- the client has to
match the RUNNING compositor, which the session's PATH carries
and this list cannot; the Graphics section's comment in
verify.sh makes the argument.

<a id="not-built-here-upstreams-own-flake-re-exported-int"></a>
### Not built here -- upstream's own flake, re-exported into the overlay

```nix
zen-browser = zen-browser.packages.${final.stdenv.hostPlatform.system}.default;
```

Not built here -- upstream's own flake, re-exported into the overlay
so nixarchy-doctor can find it.

The doctor asks pkgs for an app's meta.mainProgram to learn which
command it puts on PATH, and falls back to the attribute name when
the lookup fails. zen-browser lived only in packages.<system>, so
the lookup returned null and the fallback answered "zen" -- a
command that does not exist, because this package installs
bin/zen-beta. The doctor could never report Zen as present.

Exactly the vscode/code trap the doctor was written to avoid, reached
by a different road: not a wrong mainProgram, but a package the probe
could not see. The Install menu's copy of the probe had the same bug
for longer -- it reads cfg.apps.<name>.package instead of this
overlay; see appBinary in modules/apps.nix.

<a id="nixpkgs-retroarch-is-retroarch-with-cores-built-wi"></a>
### nixpkgs' `retroarch` is `retroarch-with-cores` built with an

```nix
retroarch = final.retroarch.withCores (
```

nixpkgs' `retroarch` is `retroarch-with-cores` built with an
EMPTY core list, so installing it gives an emulator that can run
nothing. `retroarch-full` is the obvious fix and the wrong one:
it pulls unfree cores, and an unfree package in the app list
aborts the whole rebuild rather than failing on its own.

So: every core Omarchy's own picker offers that nixpkgs ships
under a free licence, minus the two that dwarf the rest.
snes9x and genesis-plus-gx are unfree, hence bsnes and blastem
for those systems.

<a id="the-rdp-daemon-re-exported-from-its-own-flake-so-t"></a>
### The RDP daemon, re-exported from its own flake so the module that

```nix
hypr-rdp = inputs.hypr-rdp.packages.${final.stdenv.hostPlatform.system}.hypr-rdp;
```

The RDP daemon, re-exported from its own flake so the module that
will run it (#156) can say `pkgs.hypr-rdp` and never mention an
input. Built by upstream's pkg/nix/package.nix against OUR nixpkgs,
through the `follows` on the input.

This indirection is what makes the input's exit cheap: when nixpkgs
carries hypr-rdp, delete the input and this attribute, and every
`pkgs.hypr-rdp` in the tree keeps resolving -- to nixpkgs' own.

Lazy, so a machine that never enables RDP never builds it. Being in
the overlay is not being on the system.

<a id="nixpkgs-is-on-0-3-0-whose-session-lock-aborts-on-d"></a>
### nixpkgs is on 0.3.0, whose session lock aborts on DPMS

```nix
quickshell = final.quickshell.overrideAttrs (_: rec {
```

nixpkgs is on 0.3.0, whose session lock aborts on DPMS.

WlSessionLock::updateSurfaces reached qFatal -- "Tried to show
lockscreen surfaces without active lock" -- when screens slept and
woke while locked. quickshell dies, and because the Wayland
session-lock protocol deliberately keeps the compositor locked when
its lock client disappears, the machine is left blank with nothing to
type a password into. Reboot is the only way out. Seen three times in
one night, ~65-70 MB of coredump each.

v0.3.1 fixes it, and says so in as many words: "Fixed session lock
crashes on sleep, wake, DPMS, and unlocking." Three commits touch
wayland/lock; 897fcdaa is this one -- it null-checks the wayland
output and skips placeholder screens instead of asserting.

overrideAttrs rather than a fork: nixpkgs keeps the build, the Qt
wrapper and the dependency set, and only the tag moves. Passed here
rather than set on the overlay, so a machine using quickshell for
something of its own keeps nixpkgs'.

DELETE THIS once nixpkgs ships >= 0.3.1.

<a id="the-boot-splash-and-nothing-else-on-the-disk-with-"></a>
### The boot splash, and nothing else on the disk with it

```nix
nixarchy-plymouth = final.runCommand "nixarchy-plymouth-theme" { } ''
```

The boot splash, and nothing else on the disk with it.

The omarchy package already carries share/plymouth/themes/omarchy,
and on a desktop that is the right place for it: the machine has the
package anyway. The live image does not. It deliberately does not
import nixosModules.nixarchy (see installer/cd.nix), so naming the
desktop package in boot.plymouth.themePackages would be the only
reason it were there -- and nixpkgs' plymouth module puts
themePackages into environment.etc, so the named package joins the
system closure whole: 411.9 MiB on an image budgeted at 2.00 GiB,
which is GitHub's limit on a release asset rather than a preference.
These assets are 180 KiB.

Copied out of the same package rather than assembled again, so the
theme is built in exactly one place and the image's splash cannot
differ from the installed one. Nothing is rewritten here:
omarchy.plymouth already points at /etc/plymouth/themes/omarchy, so
this output has no store references and costs only its own size.

<a id="nix-run-github-olafkfreund-nixarchy-verify-from-in"></a>
### `nix run github:olafkfreund/nixarchy#verify`, from inside a running

```nix
install = pkgsFor.${system}.writeShellApplication {
```

`nix run github:olafkfreund/nixarchy#verify`, from inside a running
Omarchy session. Everything in checks/ runs in a machine with no GPU,
no Bluetooth radio, no network and no sound; this asks the questions
that leaves unanswered.
`nix run github:olafkfreund/nixarchy#install`, as root, from a NixOS
live ISO. Formats ONE disk with installer/disk-config.nix, writes the
generated flake to /mnt/etc/nixos and runs nixos-install against it.

Every answer ends up as text in that flake: the machine it produces
belongs to the flake, not to this script.

<a id="nix-run-release-notes-from-tag-to-ref-what-changed"></a>
### `nix run .#release-notes <from-tag> <to-ref>` -- what changed for

```nix
release-notes = pkgsFor.${system}.writeShellApplication {
```

`nix run .#release-notes <from-tag> <to-ref>` -- what changed for
someone running nixarchy, between two releases. release.yml puts its
output above the download instructions on the release page.

An app for the same reason `review` is one: it evaluates the option
set at two revisions and asks GitHub what upstream shipped, and a
check has neither a network nor a second checkout. The half that
needs neither is checks.release-notes, which drives this whole script
against a fixture repository.

It carries omarchy-package-delta.sh rather than reimplementing it:
the question "what did this Omarchy release add and drop" already has
an answer here, and two of them would disagree eventually.

<a id="nix-run-devenv-presets-scaffolds-every-preset-in"></a>
### `nix run .#devenv-presets` -- scaffolds every preset in

```nix
devenv-presets =
```

`nix run .#devenv-presets` -- scaffolds every preset in
data/devenv-presets.nix with the real `nixarchy dev init`, then asks a
real devenv to evaluate what it wrote.

This is the whole safety net under that catalogue. `lines` is a
string, so a preset that names an option devenv renamed is a valid Nix
file and a broken project, and nothing in `nix flake check` would ever
say so. It runs the command rather than reproducing what it does,
because a check that scaffolds its own devenv.nix tests a copy.

NOT in `checks`, and that is not an oversight. #150 proposed it as one
on the reasoning that a full `devenv shell` needs the network but
evaluation does not. That is wrong, twice over: evaluating a devenv
project fetches the inputs devenv.yaml names
(github:cachix/devenv-nixpkgs/rolling), and devenv's own flake reaches
them through import-from-derivation -- `nix flake show
github:cachix/devenv` fails with `allow-import-from-derivation is
disabled` before it prints anything. A sandboxed derivation has
neither, so `checks.devenv-presets` could not run at all. A workflow
job that has a network does, and build.yml has one.

<a id="screencasts-of-a-real-session-scene-by-scene-see"></a>
### Screencasts of a real session, scene by scene -- see

```nix
inherit
```

Screencasts of a real session, scene by scene -- see
tests/demo/default.nix. Not checks: each boots a desktop, drives
it and encodes a GIF, which is minutes of work nobody wants on
every push.

  nix build .#demo                 the full tour (mp4 + gif)
  nix run   .#demo-record -- <s>   re-record ONE scene's GIF and
                                   drop it in docs/img/features/
  nix run   .#demo-verify -- f.gif audit any GIF: sampled frames
                                   must change, and must OCR to
                                   what the scene claims to show

<a id="nix-run-update-rewrites-the-pinned-versions-and-ha"></a>
### `nix run .#update` -- rewrites the pinned versions and hashes in

```nix
update =
```

`nix run .#update` -- rewrites the pinned versions and hashes in
place. CI runs it nightly and opens a PR (update.yml).

Derived, not enumerated: every nixarchy-apps package carrying a
passthru.updateScript is run, so a new hand-pinned package is
covered the day it lands, without an edit here. This line used to
name `once` alone -- beside a comment claiming once was the only
hand pin -- while hey-cli sat pinned with an updateScript nothing
reached, and needed a human (#195, 2026-09-05).

`nix eval .#update.pinned` lists the covered attributes; update.yml
builds exactly those after a rewrite, off the same set. A package
pinned by hand WITHOUT an updateScript is still invisible to this
-- as of this writing only grok-bot, whose Cursor CDN pin has no
queryable "latest" (pkgs/review.sh probes its age instead).

<a id="a-vm-that-installs-onto-a-blank-disk-with-a-networ"></a>
### A VM that installs onto a blank disk, WITH a network -- which

```nix
installer-vm =
```

A VM that installs onto a blank disk, WITH a network -- which
checks.install cannot have, because it is a sandboxed derivation and
its whole point is that a rebuild afterwards cannot fetch anything.
See installer/vm.nix.

Wrapped rather than exported raw: the generated run script creates
two sparse qcow2 images and only discovers they do not fit hours
later, from inside the guest. installer/vm-preflight.sh checks first
and says so. The sizes come from the configuration itself so the
check cannot drift away from what the VM actually asks for.

<a id="the-front-door"></a>
### The front door

```nix
try =
```

The front door: `nix run github:olafkfreund/nixarchy#try` boots
the installer ISO in a local UEFI VM, wizard and all, for someone
who knows nothing about this repository. `-- --net` takes the
network image instead.

Deliberately NOT depending on the ISO derivation: referencing it
here would make `nix run .#try` download -- or worse, silently
build -- 5.6 GB before the script's first line ran. The script
resolves the image itself at runtime, dry-run first, so "this is
a download of X" or "STOP, this would be a source build" is said
BEFORE either happens. See installer/try.sh for the rest of the
refusals; checks.try-preflight exercises each of them.

Also not a wrapper around .#installer-vm: that VM answers the
wizard itself from a baked answers file -- a test harness, and
exactly the thing a person trying nixarchy must not get.

<a id="two-runners-per-data-microvm-templates-nix-entry-b"></a>
### Two runners per data/microvm-templates.nix entry, both built by

```nix
// lib.concatMapAttrs (
```

Two runners per data/microvm-templates.nix entry, both built by
`lib.mkMicrovm` above from the same template and the same
modules/microvm/guest.nix -- only `microvm.cpu` differs between
them.

`microvm-<t>` passes nothing extra: `cpu = null` is upstream's own
default, which on x86_64-linux means `-enable-kvm -cpu
host,+x2apic,-sgx` (lib/runners/qemu.nix in the pinned commit --
`-enable-kvm` is added exactly when `cpu == null`). That is what
nearly every user runs, and #221 says outright it is not provable
in CI without nested virtualisation.

`microvm-<t>-tcg` sets `microvm.cpu = "max"`. The same `cpu !=
null` branch that changes the `-cpu` argument ALSO removes
`-enable-kvm` from the same conditional -- one option, both
effects -- which is what makes this the runner a host with no
`/dev/kvm` (including nixarchy running inside a VM) can boot, and
the one CI builds. No separate "disable kvm" option exists to set;
there is only this one.

machineOpts on the -tcg variant, and every entry is load-bearing:

  - `pit = "on"`, `pic = "on"`. Upstream's default microvm machine
    sets both off, which is correct under KVM -- kvmclock is the
    guest's clock -- and fatal under TCG, which has no kvmclock:
    with no PIT, no PIC and no HPET on this machine type, early
    timer init has nothing to calibrate from, and the kernel
    triple-faults or wedges right after "Poking KASLR", outcome
    depending on where KASLR happened to land. Measured on a real
    A/B: the shipped runner under forced TCG produced zero output
    for five minutes; the same runner with pit/pic on booted to a
    login prompt in 2m13s. `-cpu qemu64` wedged identically, so
    the CPU model was ruled out.

  - `accel = "tcg"`, PINNED -- not upstream's `kvm:tcg` fallback
    chain. The fallback is how the wedge above shipped unnoticed:
    qemu silently takes KVM wherever /dev/kvm exists (including
    inside a test VM on a host with nested virtualisation), so
    every local run of the "-tcg" artifact was measuring a KVM
    boot, and the one environment that exercised real TCG was CI
    -- at the moment something first tried to boot it. This
    variant's entire reason to exist is hosts with no /dev/kvm; a
    KVM host should run the normal runner. Do not "optimise" the
    fallback back in: an artifact that never runs as what its
    name promises is how this bug lived long enough to gate a PR.

  - the rest reproduce upstream's x86 defaults (machineOpts
    REPLACES the whole set, so omitting one is turning it off).
    `pcie = "on"` because the 9p shares sit on virtio-pci.

<a id="the-same-vm-with-room-to-run-a-model"></a>
### The same VM with room to run a model

```nix
vm-big = nixpkgs.lib.nixosSystem {
```

The same VM with room to run a model.

`.#vm` is a smoke test and is sized like one: 8GB, and an ephemeral
root, which is right for catching a broken desktop and wrong for
anything to do with programs.nixarchy.localAi. Two reasons, and the
second is the one that is not obvious:

  - 8GB does not hold a useful model. qwen3:8b is 5.2GB of weights
    before any cache.

  - diskImage = null puts the root on a tmpfs, so the weights live in
    RAM. They are then paid for twice, once to store and once to load,
    out of the same pool -- and the service is OOM-killed while every
    visible number says it had room. Observed, not theorised.

So this one has a real disk, which also means a pulled model survives
a restart rather than being re-downloaded every time.

  nix run .#vm-big
  ssh -p 2224 omarchy@localhost      (password: omarchy)

It writes nixarchy-vm-big.qcow2 into the working directory and REUSES
it, which is the point here and is exactly what .#vm avoids. Delete
that file to start clean.

<a id="one-module-that-imports-the-machines-own-two-rathe"></a>
### One module that imports the machine's own two, rather than two

```nix
{
```

One module that imports the machine's own two, rather than two
entries in this list. It has to be shaped this way, because the
generated flake's hosts/<name>/default.nix is shaped this way:
`imports` inside a module and entries in `modules` are merged in
different orders, so the flat form gives a different
environment.systemPackages ORDER -- same packages, same closure,
different list -- and system-path hashes that order into
chosenOutputs. A different system-path is a different toplevel,
and on an ISO with no network the installed machine can no longer
copy the one baked here: it has to build it, which means stdenv,
which means the source bootstrap from hex0-seed.

Nothing about the packages differs. Only the order does, and only
the order has to.

<a id="one-closure-per-template-shared-by-every-vm-a-user"></a>
### One closure per template, shared by every VM a user ever names from

```nix
lib.mkMicrovm =
```

One closure per template, shared by every VM a user ever names from
it. #221's "the name is never a Nix argument" is exactly what makes
this possible: `template` and `modules` are the only things this
function is allowed to vary on, and neither is a per-VM value.

`template` is a path from data/microvm-templates.nix -- plain NixOS
plus microvm.nix's own options, per that catalogue's bar.
modules/microvm/guest.nix is what every template gets underneath it,
imported here rather than by each template file so a template cannot
forget it. `modules` exists for exactly one caller below: the `-tcg`
packages, which add `microvm.cpu = "max"` without a second template.

Returns `declaredRunner`, upstream's own name for
`config.microvm.runner.${config.microvm.hypervisor}` -- a package,
which is what `packages.<system>.microvm-<template>` has to be.

<a id="both-images-against-the-budgets-recorded-in-instal"></a>
### Both images, against the budgets recorded in installer/cd.nix

```nix
iso-budget =
```

Both images, against the budgets recorded in installer/cd.nix.

A check rather than a comment because a number nobody enforces is a
number that drifts. The nightly runs this; it costs nothing beyond
the ISO builds it already does.

The iso-net budget is the load-bearing one, and it is not a taste
question: GitHub refuses a release asset over 2 GiB, so an iso-net
that crosses it stops being publishable as a single file and
release.yml would have to start splitting it. Failing here says so
while there is still something to do about it, rather than at the
next tag.
