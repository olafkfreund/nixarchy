# modules/

The NixOS and Home Manager modules. What an existing NixOS machine imports
when it adds `nixarchy.nixosModules.nixarchy`, and what the installer's own
host configuration builds on.

## Intent

One option namespace, `programs.nixarchy`, and two modes that must both keep
working:

- **Mode A** — somebody imports this into a configuration they already run.
  Everything opt-in must leave them untouched. This is the mode a refactor
  breaks quietly, because the off state is the one nobody looks at.
- **Mode B** — the installer wrote the machine, so `programs.nixarchy` is the
  whole desktop and `installerManaged` is set.

| file | what it owns |
|---|---|
| `nixos.nix` | the system: session, greeter, graphics, services, the option surface |
| `home.nix` | the Home Manager side: the seed, plugins, per-user state |
| `apps.nix` | the app catalogue and the selection model (`nixarchy-apply`) |
| `flatpaks.nix` | the software nixpkgs genuinely does not carry |
| `fleet.nix` | pull-based `system.autoUpgrade` from a remote flake, opt-in |

## Tests

| check | covers |
|---|---|
| `checks.options` | every option asserted in BOTH states — this is what protects Mode A |
| `checks.session` | a booted desktop; does not run locally, CI only |
| `checks.reference-toplevel` | the machine the installer writes, built |
| `checks.vm-toplevel` | the smoke-test guest, built |
| `checks.coexist` | an existing Hyprland configuration alongside this |

## Working here

- An option added without a `checks.options` assertion in both states is not
  finished.
- `writeShellApplication` builds a strict PATH from `runtimeInputs`. A command
  a script calls and does not declare is a runtime failure no build catches.
- The rest of this file is the reasoning that used to sit in the code, moved
  here so the modules read as code. Each one is reachable from a `# Why:`
  pointer at the line it explains — follow the anchor, and if you change the
  decision, change the entry with it.

---

## `modules/nixos.nix`

<a id="omarchys-session-launched-from-its-own-hyprland-lu"></a>
### Omarchy's session, launched from its own hyprland.lua in the store…

```nix
omarchySessionLauncher = pkgs.writeShellScript "omarchy-session" ''
```

Omarchy's session, launched from its own hyprland.lua in the store rather
than from ~/.config/hypr/hyprland.lua. Hyprland's --config takes the entry
point; the modules it requires still resolve through $HOME/.config, which
is where the Home Manager seed puts them.

Through start-hyprland rather than the Hyprland binary. Booting this on a
real laptop logged

  WARNING: Hyprland is being launched without start-hyprland.
  This is highly advised against.

start-hyprland is the watchdog Hyprland 0.56 wants supervising it, and it
is what nixpkgs' own hyprland.desktop execs. Everything after its `--` is
passed through to Hyprland, so --config still arrives where it was going.
The VM never complained because a warning is not a failure -- it took
somebody reading the journal on a machine that had actually logged in.

<a id="nixarchy-wrote-this-machine-as-a-property-of-the-c"></a>
### "Nixarchy wrote this machine", as a property of the configuration rather

```nix
installerManaged = lib.mkOption {
```

"Nixarchy wrote this machine", as a property of the configuration rather
than of the install event.

Set in exactly one place -- installer/host.nix, which is imported only by
a hosts/<name>/default.nix the installer generated. That is what makes a
machine nixarchy-shaped: snapper, nh, the registry pin, the seeded user.
So the question "did nixarchy build this?" is answered by whether that
module is in the evaluation, and re-answered at every rebuild.

Not /etc/nixos/.nixarchy-url, which used to look like the same signal and
is not one any more. `git add -A` tracks it, so it is committed, pushed,
and cloned onto every machine enrolled with `nixarchy install --from` --
including a machine the installer never touched. And an admin-authored
repo of the shape `--from` accepts carries no such file while being a
perfectly good nixarchy install. Presence stopped meaning "here", absence
stopped meaning "hands off". It survives as provenance of the *repo*.

Not a heuristic either. Sniffing flake.lock's root inputs or testing for
hosts/$(hostname) reads state the user is invited to edit, and would one
day refuse a machine to its own owner.

<a id="built-from-your-nixpkgs-through-this-flakes-overla"></a>
### Built from *your* nixpkgs through this flake's overlay, not from

```nix
default = (pkgs.extend inputs.self.overlays.default).omarchy;
```

Built from *your* nixpkgs through this flake's overlay, not from
inputs.self.packages -- which is built from nixarchy's own nixpkgs.

Those look identical and are not: every one of the ~80 runtime
dependencies would come from a different nixpkgs instance than the
rest of your system, and the first one you also install yourself makes
buildEnv refuse the profile --

  two given paths contain a conflicting subpath:
    .../tesseract-5.5.3/bin/tesseract and .../tesseract-5.5.3/bin/tesseract

-- two builds of the same version, which reads like a bug in nix until
you notice the hashes differ. Found by building a real config that had
tesseract of its own.

<a id="most-of-what-the-install-menu-offers-is-unfree"></a>
### Most of what the Install menu offers is unfree

```nix
nixpkgs.config = lib.mkIf cfg.allowUnfree (lib.mkDefault { allowUnfree = true; });
```

Most of what the Install menu offers is unfree: the browsers, the editors,
Steam, the AI clients, several of the fonts. Leaving licence policy to the
consumer sounded principled and in practice meant a new user picked an app,
ran nixarchy-apply, and watched a rebuild die on a licence error partway
through -- with nothing on screen explaining that the fix was a line in a
file they had never opened.

Behind an option rather than mkDefault, because mkDefault does not work
here: nixpkgs.config is a free-form attribute set, so `mkDefault true` on
one of its keys is stored as the override attrset itself and nixpkgs is
handed { _type = "override"; ... } where it expects a bool. mkDefault on
the whole set does resolve, but then any other nixpkgs.config key a user
sets replaces our definition wholesale and unfree silently goes away.

mkIf so that turning the option off removes the definition entirely rather
than asserting false, and mkDefault so that ours is the one that yields
wherever something else already owns nixpkgs.config. That is not
hypothetical: a NixOS VM test takes its pkgs from outside and imports
misc/nixpkgs/read-only.nix, which defines nixpkgs.config as a unique
option -- so any definition of ours, at any priority above default, makes
every runNixOSTest node fail to evaluate.

The cost is that priorities filter before merging: a user who sets any
other nixpkgs.config key, say permittedInsecurePackages, outranks this
default and drops it, and unfree goes off again. That case is not silent,
which is the only reason it is acceptable -- modules/apps.nix warns at
evaluation time when an enabled app is unfree and allowUnfree is off, and
names the fix.

<a id="etc-nixos-belongs-to-the-installed-user-installer-"></a>
### /etc/nixos belongs to the installed user (installer/install.sh

```nix
git = {
```

/etc/nixos belongs to the installed user (installer/install.sh
chown_flake_dir), and git refuses to open a repository owned by
somebody else. So does nix: its flake fetcher goes through libgit2,
which runs the same ownership check and fails the whole evaluation
with

  error: opening Git repository "/etc/nixos": repository path
  '/etc/nixos' is not owned by current user (libgit2 error code = 7)
  error: could not find a flake.nix file

-- the second line being the one people actually read, which is why
this was diagnosed three times before it was understood.

NOT every root command needs this. git and libgit2 both exempt root
when SUDO_UID names the repository's owner, so `sudo nixos-rebuild
--flake /etc/nixos#...` -- the thing a user actually types -- was
never broken by the chown. What needs the entry is root WITHOUT
SUDO_UID: root systemd units, a root login shell, `nixos-install`
from a live ISO during a rescue reinstall, and the VM test drivers,
which are root by construction and never sudo.

It has to be a real config file. Passing `-c safe.directory=...` on a
git command line fixes that one git invocation and does not reach nix
at all, and the environment variables are no use either: nix opens
repositories with git_repository_open() rather than the _FROM_ENV
variant, so libgit2 leaves use_env false and ignores
GIT_CONFIG_SYSTEM and GIT_CONFIG_NOSYSTEM. libgit2 does read
/etc/gitconfig -- verified by strace of a root `nix eval`, which
opens exactly that one system path -- and that is what this writes.

Via programs.git rather than environment.etc."gitconfig" because
programs.git.config merges with a user's own git settings, where two
environment.etc definitions of the same file collide.

One limit worth knowing: the check runs against the RESOLVED path, so
an adopter who points programs.nixarchy.flake at a symlink is not
covered by this entry. Name the real directory instead. Machines this
installer writes have a real /etc/nixos, so the default is fine.

<a id="the-literal-path-above-is-not-always-enough-becaus"></a>
### The literal path above is not always enough, because the ownership

```nix
include.path = safeDirInclude;
```

The literal path above is not always enough, because the ownership
check runs against the RESOLVED directory: point
programs.nixarchy.flake at a symlink -- /etc/nixos -> a repository
in $HOME, which is how plenty of people arrange this -- and the
entry never matches what libgit2 actually opened. Measured, not
assumed: safe.directory naming the symlink is refused, naming the
real directory is accepted.

Resolving it needs the filesystem of the machine being configured,
which evaluation cannot see (and reading it at eval time would mean
IFD). So the resolved form is written at activation, and included
from here. libgit2 does follow include.path when it collects
safe.directory -- also measured -- and a missing include target is
silently ignored, which is what makes the file safe to reference
before the first activation has written it.

<a id="mise-is-in-omarchys-base-packages-and-its-dev-env-"></a>
### mise is in Omarchy's base packages and its dev-env installers lean on

```nix
nix-ld.enable = lib.mkDefault true;
```

mise is in Omarchy's base packages and its dev-env installers lean on
it heavily. It downloads prebuilt runtimes, which cannot run against
NixOS' non-standard loader, so it detects NixOS and falls back to
compiling from source -- which then fails, because there is no compiler
on the session PATH. mise's own message names the fix:

  "The automatic all_compile=true default on NixOS caused python to
   compile from source. Enable nix-ld to use precompiled binaries"

This is what makes `omarchy install dev-env` work rather than print a
wall of build errors.

<a id="minus-hyprland-itself"></a>
### Minus Hyprland itself

```nix
++ builtins.filter (d: !(lib.hasPrefix "hyprland-" (d.name or ""))) cfg.package.passthru.runtimeDeps
```

Minus Hyprland itself.

The package carries the compositor its Lua config is written against as
a runtime dependency, and putting that in systemPackages made it the
Hyprland on PATH -- so on a machine that already ran Hyprland, enabling
nixarchy silently swapped the compositor behind the user's *existing*
sessions. Its share/wayland-sessions/hyprland.desktop won the buildEnv
collision too, so `hyprland.desktop` pointed at nixarchy's build rather
than theirs. Found by building this against a real configuration; the
doctor tells people to keep their own Hyprland, and this quietly did
the opposite.

programs.hyprland already puts the right one on PATH -- ours when
nixarchy sets the option, theirs when they mkForce it -- so dropping it
here changes nothing on a clean machine and stops overriding anyone
else's. omarchy-session still runs the Lua config through
config.programs.hyprland.package, which is the same binary either way.

<a id="config-hypr-xdph-conf-which-the-package-seeds-into"></a>
### config/hypr/xdph.conf, which the package seeds into

```nix
hyprland-preview-share-picker
```

config/hypr/xdph.conf, which the package seeds into
~/.config/hypr, sets
`custom_picker_binary = hyprland-preview-share-picker`.
xdg-desktop-portal-hyprland execs that name for every ScreenCast
request, so with nothing providing it the exec fails, the backend
reads selection -1 and destroys the session -- screen sharing dies
in every application, with no dialog and no error anywhere a user
looks. Upstream declares it in install/omarchy-base.packages, which
pacman honours and nothing on NixOS reads. (#202)

From nixpkgs rather than the hyprland input that supplies the portal
at programs.hyprland.portalPackage: that flake publishes only
hyprland and xdg-desktop-portal-hyprland, so there is no picker
there to match. Nothing is mismatched by taking it from nixpkgs
either -- the picker links no Hyprland library (gtk4,
gtk4-layer-shell, cairo, pango and nothing else), and the portal
reaches it by exec plus a selection line on stdout, not an ABI.

Editing the seeded xdph.conf was the other option and is the wrong
one: the file is upstream's, so the edit is undone by the next
Omarchy bump.

<a id="passed-straight-through"></a>
### Passed straight through

```nix
flatpak.uninstallUnmanaged = lib.mkDefault cfg.flatpaks.uninstallUnmanaged;
```

Passed straight through: nix-flatpak's own option carries the
behaviour, ours carries the decision and its reasoning. mkDefault so a
user who sets services.flatpak.uninstallUnmanaged directly keeps their
value -- this is a convenience over an upstream option, not a
replacement for it.

In this block rather than as its own `services.flatpak...` line
because statix rejects a second `services` key in the same attribute
set, and it is right to: two places setting services is two places to
look.

<a id="cups-avahi-and-nss-mdns-are-all-in-base-packages"></a>
### cups, avahi and nss-mdns are all in base.packages

```nix
printing.enable = lib.mkDefault true;
```

cups, avahi and nss-mdns are all in base.packages. cups-browsed was
too until 4.0.2 dropped it -- "Harden CUPS printer discovery and
administration" -- along with the unit that started it, leaving only a
hardened drop-in for machines that already had it. cups-pk-helper
replaced it for the administration half, and NixOS' own cupsd module
adds that wherever polkit is on, so nothing here has to name it.

Turning it off is not just comment maintenance: NixOS defaults
services.printing.browsed.enable to services.avahi.enable, which the
lines below set, so `printing.enable` alone did leave cups-browsed
running -- as root, with none of the User=/ProtectSystem= hardening
upstream's drop-in adds, listening for mDNS printer announcements and
creating queues from them. That is the daemon upstream deliberately
removed, so it does not stay on here by inheritance.

Only browsed goes: avahi stays on for driverless IPP discovery, which
is how modern printers are found and is what cupsd does by itself.

<a id="the-ownership-marker-for-the-shell-tools-that-cann"></a>
### The ownership marker, for the shell tools that cannot ask the module

```nix
environment.etc."nixarchy/managed" = lib.mkIf cfg.installerManaged {
```

The ownership marker, for the shell tools that cannot ask the module
system anything.

Declarative on purpose: it is in the closure, it is rewritten by every
rebuild, and a machine that stops descending from installer/host.nix
loses it in the same switch that made that true. A file the installer
wrote once could not say that -- it would survive being wrong, and a
`--from` rebuild that never created it would leave the machine looking
unmanaged for the rest of its life.

The contents are for the person who finds the file and wonders. Nothing
reads them, and nothing should start: the predicate is the file's
existence, which is the only part that is cheap to get right in every
shell script that needs it.

<a id="the-other-half-of-that-script-which-this-module-le"></a>
### The other half of that script, which this module left behind

```nix
allowedTCPPorts = [ 53317 ];
```

The other half of that script, which this module left behind.
Upstream's is not merely "turn the firewall on":

    ufw default deny incoming
    ufw allow 53317/udp
    ufw allow 53317/tcp   # "Allow ports for LocalSend."

Porting only the deny half enables a firewall that blocks the one
service Omarchy's manual promises works out of the box: "Omarchy's
firewall is closed by default except for LocalSend's port, so this
works out of the box on a fresh install." On a machine taking this
module's firewall default it did not -- Share > Receive listened on
53317 and nothing on the network could reach it.

Discovery was never the missing part: services.avahi above already
opens 5353. Only LocalSend's own transfer port was closed.

Not mkDefault: these are list options, so they merge with whatever
the user opens rather than replacing it. A mkDefault list would be
dropped whole the moment they opened a port of their own.

<a id="install-config-lockscreen-pam-sh-whose-one-line-is"></a>
### install/config/lockscreen-pam.sh, whose one line is `omarchy-apply-lock`

```nix
security.pam.services = {
```

install/config/lockscreen-pam.sh, whose one line is `omarchy-apply-lock`
-- and that writes /etc/pam.d/omarchy-lock-password. Omarchy 4's lock
screen is the Quickshell one, which names that stack itself
(shell/plugins/lock/Service.qml: `config: "omarchy-lock-password"`), and
watches the file's existence to decide whether locking is possible at
all. hyprlock appears nowhere in the tree except omarchy-upgrade-to-
quattro, which *removes* it -- so what was declared here was PAM for a
program the desktop no longer runs. On a live session:

  /etc/pam.d/omarchy-lock-password  ->  No such file or directory
  omarchy-shell lock lock           ->  missing-pam, screen stayed up

Five paths reach that no-op: SUPER + CTRL + L, Menu > System > Lock, the
idle timeout, lid close, and suspend.

An empty attrset is the whole fix. NixOS' generated stack is pam_unix
auth plus an account section, which is upstream's file with faillock and
pam_systemd_home taken out. faillock is deliberately not reproduced:
NixOS' only handle on it is `logFailures`, which emits pam_faillock with
no preauth/authfail/authsucc arguments, so nothing ever resets the
counter -- three bad unlocks would lock a user out of their own screen
for good. Upstream's deny=10 needs the raw `rules` interface, and a
lockout is a worse failure than the logging it would buy.

<a id="omarchy-path-default-systemd-user-which-upstream-i"></a>
### $OMARCHY_PATH/default/systemd/user/, which upstream installs into

```nix
user.services = {
```

$OMARCHY_PATH/default/systemd/user/, which upstream installs into
/usr/lib/systemd/user and nothing here installed anywhere -- that
directory is not a systemd search path. `systemctl --user status
bt-agent.service` answered "could not be found" on a live session, and
with it went the pairing agent, the crash watcher, the input method, the
internal-monitor recovery, and -- the one that matters -- the sleep lock,
so suspend did not lock even once the PAM stack above exists.

Declared here rather than linked out of the package, because every
shipped ExecStart is a /usr/bin path that resolves to nothing on NixOS
and the package is not this module's to patch. The bodies are upstream's:
same conditions, same ordering, same restart policy, binaries named by
store path.

omarchy-migrate-notify and omarchy-tailscale-receive are deliberately
absent. Their conditions (ConditionPathIsDirectory=/usr/share/omarchy/
migrations, ConditionPathExists=/usr/bin/tailscale) can never hold here,
and both jobs belong elsewhere on NixOS: migrations arrive with a
rebuild, and Taildrop with services.tailscale.

Each omarchy-* unit gets /run/current-system/sw on its PATH. NixOS gives
every unit a stub PATH of coreutils, findutils, grep, sed and systemd,
and unlike the copies upstream drops in ~/.config/systemd/user that stub
*overrides* the session PATH uwsm imported -- omarchy-system-sleep-
monitor would not find dbus-monitor, and none of them would find the
other omarchy-* commands they call. The system profile is where the
package's runtimeDeps already live, by the package's own design: bin/ is
a symlink farm rather than wrapped programs, so the CLI can still read
the `# omarchy:summary=` metadata out of each script.

omarchy-speaker-tuning is absent for a different reason: omarchy-audio-
tuning installs it itself, by copying the unit into
~/.config/systemd/user and running `systemctl --user enable`. Declaring
it would not race that copy -- the user directory outranks /etc -- but
`omarchy audio tuning off` disables and deletes it, and `disable` cannot
remove an [Install] symlink that lives in a read-only /etc, so the
tuning would come back at the next login with the config it needs gone.

<a id="default-systemd-user-app-slice-d-10-oomd-conf"></a>
### default/systemd/user/app.slice.d/10-oomd.conf

```nix
user.units."app.slice" = {
```

default/systemd/user/app.slice.d/10-oomd.conf. systemd-oomd is on by
default in NixOS, and with no slice marked as a candidate it has nothing
it is allowed to kill. Marking app.slice -- where uwsm-app puts every
launched application -- leaves the compositor structurally ineligible:
Hyprland runs in session.slice, so oomd takes the browser or terminal
that caused the pressure and the session survives to report it.

Deliberately not systemd.oomd.enableUserSlices, which is the obvious
switch and the wrong one: it sets the same properties on user.slice and
on the user manager's own root slice, which puts the compositor back in
the candidate pool. asDropin rather than a systemd.user.slices entry so
systemd's own app.slice definition is extended, not replaced.

Upstream's oomd.conf.d also lowers the global thresholds to 50% over 20s
from systemd's 60% over 30s. Not carried over: those are a tuning
preference, and the defaults still fire.

<a id="bluez-bluez-tools-and-bluez-utils-are-all-in"></a>
### bluez, bluez-tools and bluez-utils are all in

```nix
hardware.bluetooth.enable = lib.mkDefault true;
```

bluez, bluez-tools and bluez-utils are all in
install/omarchy-base.packages, the bar has a Bluetooth widget, and
omarchy-bluetooth-device and omarchy-bluetooth-power are two of the
commands the menu offers -- but none of it works without the service,
and nothing here was starting it. Every session logged

  quickshell.dbus.objectmanager: Failed to create
  DBusObjectManagerInterface for "org.bluez" "/"

which was written off as a VM artefact for as long as this was in the
README's known gaps. It is the same shape as UPower: the tools were
installed, the daemon was not.

<a id="our-own-splash-in-the-theme-directory-upstreams-oc"></a>
### Our own splash, in the theme directory upstream's occupies -- upstream

```nix
users.users = lib.optionalAttrs (cfg.user != null) {
```

Our own splash, in the theme directory upstream's occupies -- upstream
installs it by copying into /usr/share/plymouth/themes from
omarchy-refresh-plymouth. Nothing was doing that here, so plymouth came
up with NixOS' default theme -- the one screen every boot shows,
unbranded. The artwork in it is nixarchy's; see the option's description
and pkgs/omarchy/default.nix.

Theme and themePackages always move together, at whatever priority
bootSplash asks for. NixOS asserts the named theme exists in the package
list, so setting one without the other fails the build -- which is what
anyone reaching for `lib.mkForce boot.plymouth.theme = "omarchy"` on a
stylix machine hits, because stylix sets themePackages at normal priority
and wins it.
The one thing upstream's installer does that needs a name.

install/hardware/input-group.sh runs `usermod -aG input`, and without it
the dictation tools and controllers Omarchy offers cannot read their
devices. Skipped entirely when programs.nixarchy.user is unset, because
the alternative is guessing which of a machine's users logs into the
desktop.

<a id="docker-is-enabled-above-at-mkdefault-for-every-mac"></a>
### Docker is enabled above, at mkDefault, for every machine

```nix
++ lib.optional config.virtualisation.docker.enable "docker";
```

Docker is enabled above, at mkDefault, for every machine. Enabled and
unusable, until now: without this group every command wants sudo, and
`docker ps` answers "permission denied while trying to connect to the
Docker daemon socket" -- which reads like a broken install rather than
a missing group.

The installer has always put its user in `docker` directly
(installer/host.nix), so this was only ever wrong for someone adding
nixarchy to a machine they already run: they got the daemon and not
the access. Conditioned on the option rather than set unconditionally,
so turning Docker off does not leave a group behind that grants root
to whatever installs a socket there later.

<a id="default-fontconfig-conf-avail-50-omarchy-conf-whic"></a>
### default/fontconfig/conf.avail/50-omarchy.conf, which upstream symlinks

```nix
fonts.fontconfig.localConf = lib.mkDefault (
```

default/fontconfig/conf.avail/50-omarchy.conf, which upstream symlinks
into /etc/fonts/conf.d. Without it `fc-match monospace` on a live
session answered Adwaita Mono, so every application asking for the
generic family got a font Omarchy never chose -- and half the file's
rules had nothing to resolve to anyway, because Liberation was not
installed (see fonts.packages below).

The whole file rather than fonts.fontconfig.defaultFonts, which covers
the three generic families and nothing else: this also carries the
system-ui / -apple-system / BlinkMacSystemFont aliases that Electron and
web apps ask for by name, the emoji and Nerd Font fallback chains, and
the Arabic script rules.

localConf, not a package in fontconfig's conf.d, for two reasons:
fonts.conf includes local.conf last, so these rules win the ties they
are meant to win, and it is one mkDefault a user can take back whole.
Read from the flake input rather than from cfg.package, because
readFile on a derivation output is import-from-derivation and would
make this module unevaluatable without building Omarchy first.

<a id="default-environment-d-10-omarchy-fcitx-conf-plus-t"></a>
### default/environment.d/10-omarchy-fcitx.conf, plus the daemon that reads

```nix
i18n.inputMethod = {
```

default/environment.d/10-omarchy-fcitx.conf, plus the daemon that reads
it -- fcitx5 was not installed at all. i18n.inputMethod rather than
dropping fcitx5 into systemPackages: it is what builds fcitx5 with its
addons, writes the Qt plugin path, and sets XMODIFIERS and the GTK/Qt IM
modules. The unit that starts it is above.
Priority 1250, which is neither of the two names lib gives you, because
this option is squeezed between them. GNOME's desktop-manager module sets
type to "ibus" at mkDefault (1000) and two mkDefaults tie rather than
yield, so a host running GNOME beside this session failed to evaluate at
all -- not the wrong input method, no evaluation. One step lower is not
available either: nixpkgs' own module defines type as null at
mkOptionDefault (1500) to carry the deprecated `enabled` across, and
nullOr refuses to merge null with a value, so matching that ties in the
other direction. Sitting between the two loses to anyone with a real
opinion and still beats nixpkgs' placeholder, which is exactly the rule
this module follows everywhere else: arrive beside what is installed.

<a id="fcitx5-says-this-itself-in-a-notification-on-every"></a>
### fcitx5 says this itself, in a notification on every login

```nix
i18n.inputMethod.fcitx5.waylandFrontend = lib.mkIf usingFcitx5 (lib.mkDefault true);
```

fcitx5 says this itself, in a notification on every login:

  Wayland Diagnose -- Detect GTK_IM_MODULE being set and Wayland Input
  method frontend is working. It is recommended to unset GTK_IM_MODULE.

nixpkgs sets GTK_IM_MODULE and QT_IM_MODULE only when waylandFrontend is
off, which is its default (i18n/input-method/fcitx5.nix). Those two are
the X11-era route: with them set, GTK sends input through the legacy
module instead of the Wayland input-method protocol, which is both worse
and, in GTK4 and Electron apps, sometimes nothing at all.

Nixarchy is Wayland-only -- there is no session here where the X11
default is the right one -- so this is set rather than left to the user.

## `modules/home.nix`

<a id="what-omarchy-path-points-at-and-the-source-of-ever"></a>
### What OMARCHY_PATH points at, and the source of every file seeded below

```nix
omarchyPath = osConfig.programs.nixarchy.tree or "${cfg.package}/share/omarchy";
```

What OMARCHY_PATH points at, and the source of every file seeded below.

Read across from the NixOS module when there is one, the same way localAi
is: it is the package's own tree with the files nixarchy generates for THIS
machine in it, and the app selection those are built from is only visible
over there. The menu's defaults file is the one that matters -- it carries
the Install-row rewrites, which is how the Install menu stays off pacman
without nixarchy taking ~/.config/omarchy/extensions/omarchy-menu.jsonc,
the file upstream documents as the user's and points plugins at (#210).

A standalone home-manager configuration has no NixOS module and therefore
no selection, so it falls back to the package's tree -- the same menu
Omarchy ships, which is the honest answer when there is no selection for
the Install rows to reach.

<a id="each-declared-plugin-checked-at-build-time-against"></a>
### Each declared plugin, checked at build time against the schema the shell

```nix
validatedPlugins = lib.mapAttrs (
```

Each declared plugin, checked at build time against the schema the shell
enforces, and carrying the id its own manifest claims.

Validated with upstream's own omarchy-plugin-validate rather than a
reimplementation of it here: that script exists precisely to refuse what
the running shell would silently reject, and a second copy of those rules
in Nix would drift from it at the first upstream bump. A plugin that would
not load now fails the rebuild, with the reason, instead of being installed
and doing nothing.

The id comes out of manifest.json rather than the attribute name. It is
what the shell, the menu and every omarchy-plugin-* command key on, and a
directory named anything else would be a plugin the user cannot enable,
disable or remove by the name they see on screen.

<a id="a-plugin-that-shells-out-to-pacman-fails-the-rebui"></a>
### A plugin that shells out to pacman fails the REBUILD, not the click

```nix
hits=$(
```

A plugin that shells out to pacman fails the REBUILD, not the click.

omarchy-plugin-validate above checks the manifest and the shape the
shell requires. It does not read what the plugin RUNS, and the
marketplace is written for Arch: a widget whose QML calls
`pacman -S` or `yay -S` installs cleanly here, appears in the bar,
and fails the first time somebody presses it -- on a machine where
pacman does not exist and could not be allowed to.

This is build.yml's "no bin touches pacman outside the allowlist"
applied one layer out. That scan walks Omarchy's own bins in this
repository; nothing looked at code a USER brings in.

No allowlist here, deliberately. build.yml has one because upstream's
own Arch-only plumbing legitimately calls pacman and has to keep
working on Arch. A third-party plugin installed on a NixOS machine
has no such case: there is nothing for it to be right about.

COMMENT STRIPPING, and why it is not the shell scanner's `s/#.*//`:
QML comments with // and stripping that naively eats `https://...`,
which would hide anything after a URL on the same line. So only
WHOLE-LINE comments are removed -- `//` or `#` at the start of a
line, after optional whitespace. A trailing `// mentions pacman`
after real code still trips this, which is the safe direction for a
check about what a machine will execute.

<a id="declares-which-plugins-are-present-and-deliberatel"></a>
### Declares which plugins are *present*, and deliberately not which are on

```nix
plugins = lib.mkOption {
```

Declares which plugins are *present*, and deliberately not which are on.

Upstream already splits the two: a plugin's code lives in
~/.config/omarchy/plugins/<id>/, while whether it is enabled, and where
it sits in the bar, is recorded separately in ~/.config/omarchy/shell.json
by the running shell. Content and state are already different files, so
the content can come from the store without freezing the state.

Enablement is therefore left alone on purpose. Managing shell.json here
would mean a plugin you turned off in Setup > Plugins came back at the
next rebuild, which is the sort of thing that makes people stop using the
menu. Declare the plugin, enable it once, and your choice persists.

<a id="omarchys-desktop-is-its-hyprland-config"></a>
### Omarchy's desktop is its Hyprland config

```nix
warnings =
```

Omarchy's desktop is its Hyprland config: hyprland.lua requires
autostart.lua, which is what starts the bar, and bindings.lua, which is
every keybinding the manual documents. The seed below is --no-clobber, so
a hyprland.lua that Home Manager already owns is kept and the other seven
files land beside it, loaded by nothing.

That failure is silent and total: every Omarchy binary, menu and theme
installs, `nixarchy` looks like it worked, and the session that comes up
is the user's own with no bar and none of the keybindings. Worth a
warning rather than leaving someone to work it out from an empty bar.

<a id="whether-there-is-an-omarchy-session-entry-to-log-i"></a>
### Whether there is an Omarchy session entry to log into

```nix
hasOmarchySession =
```

Whether there is an Omarchy session entry to log into.

When there is, a home-manager-owned ~/.config/hypr is not a problem:
it is the arrangement this module is built for, and the session runs
Omarchy's config with --config regardless. Warning anyway meant every
rebuild on a machine already doing the right thing printed twelve
lines telling it to do the right thing.

Only the case that actually loses the desktop is worth a warning: no
session entry, and a hypr directory that will never load Omarchy. The
informational half is one line from the seed instead, and the doctor
says it before anyone installs at all.

`or true` is the option's default; `or false` on enable because a
standalone home-manager install has no NixOS module registering
sessions at all.

<a id="the-hyprland-toggles-tree-and-deliberately-only-fl"></a>
### The Hyprland toggles tree, and deliberately only flags.lua out of it

```nix
seed_file "${omarchyPath}/default/hypr/toggles/flags.lua" \
```

The Hyprland toggles tree, and deliberately only flags.lua out of it.

These flags are state, not config: a flag is *on* because its file is
there, so copying all of default/hypr/toggles would bring the session
up with no window gaps and every single window forced square.
omarchy-hyprland-toggle copies the other two out of $OMARCHY_PATH the
moment you ask for one, so nothing is lost by leaving them there --
upstream's own omarchy-refresh-hyprland seeds exactly this one file.

flags.lua is what makes the directory exist, and it has to exist
before the shell starts rather than before the first toggle: the bar
watches ~/.local/state/omarchy/toggles with a FileView to notice
bar-off appearing, and a watch on a directory that is not there never
fires. Hiding the bar wrote the flag and changed nothing on screen
until the shell was restarted.

<a id="and-the-two-files-that-belong-in-it-which-upstream"></a>
### And the two files that belong in it, which upstream seeds from

```nix
seed_file "${omarchyPath}/icon.txt" \
```

And the two files that belong in it, which upstream seeds from
/etc/skel. Without them the About window opens with an empty logo
column -- fastfetch's config sources about.txt as its logo -- and the
screensaver dies on the spot, because omarchy-screensaver hands
screensaver.txt to ttfx as the art to animate.

The same two sources `omarchy branding <about|screensaver> reset`
copies back, so a reset returns to exactly what was seeded. logo.txt
is this repo's NIXARCHY banner rather than upstream's, by the same
reasoning as the menu's snowflake.

<a id="the-extensions-directory-and-one-thing-to-undo-in-"></a>
### The extensions directory, and one thing to undo in it

```nix
run mkdir -p "${config.xdg.configHome}/omarchy/extensions"
```

The extensions directory, and one thing to undo in it.

This file is the user's: upstream documents it as theirs, and
shell/plugins/README.md tells third-party plugins to write it.
Nixarchy's rows are in the DEFAULTS this session reads (see
omarchyPath), so nothing here writes it and nothing arbitrates.

Except on a machine an older nixarchy already took it on, where
it is a symlink into /etc and therefore into a read-only store
path. Leaving that behind would keep the file unwritable forever
on exactly the machines this is meant to fix, and nothing would
ever say so -- which is the bug, not the symlink. So it is
removed, once, and Omarchy's own commented example seeded in its
place. Only a link into /etc/nixarchy is touched: a file, or a
link somebody else made, is theirs. #210.

<a id="agent-skills-relinked-on-every-activation"></a>
### Agent skills, relinked on every activation

```nix
${
```

Agent skills, relinked on every activation.

Upstream does this in omarchy-provision-user, which is guarded by a
`finalize-user` marker and therefore runs exactly once, ever. That is
fine on Arch, where the skill directory is a fixed path that gets
overwritten in place. Here every bump moves the package to a new store
path, so a once-only link points at the previous one -- still resolving
until it is garbage-collected, then dangling. Renaming the `omarchy`
skill to `nixarchy` made it worse than stale: the machine kept serving
the old Arch skill from a path nothing would update again.

provision-user's own --force would fix the links and also replay
/etc/skel over $HOME, which is not a thing to do for four symlinks.
So: the same loop, declaratively, on every rebuild.

Only symlinks whose target is itself a skills directory in the store
are removed. That is what distinguishes a link this module or
provision-user planted from a skill the user wrote by hand, which is a
real directory and is never touched.

<a id="declared-plugins-linked-in-by-the-id-their-manifes"></a>
### Declared plugins, linked in by the id their manifest claims

```nix
run mkdir -p "${config.xdg.configHome}/omarchy/plugins"
```

Declared plugins, linked in by the id their manifest claims.

A symlink rather than a copy, and that is a supported shape rather
than a trick: upstream's scan globs "$dir"/*/ , which matches a
symlink to a directory, and omarchy-plugin-remove has an explicit
branch for one -- it offers to "Unlink" and prints where it pointed.
Its picker globs -type d -o -type l for the same reason.

Only links this module planted are cleaned up, tracked in a
.nixarchy-managed file beside them. A plugin you added yourself with
`omarchy plugin add` is a real directory that this never touches, so
the two ways of installing one live side by side.

<a id="the-first-run-theme-above-is-applied-headless-whic"></a>
### The first-run theme above is applied headless, which by design skips…

```nix
systemd.user.services.omarchy-theme-gnome = {
```

The first-run theme above is applied headless, which by design skips every
post-theme command -- including omarchy-theme-set-gnome, the one that
tells GTK and the settings portal whether this theme is light or dark.
Upstream never notices: on Arch that command runs during install with a
live session, and dconf keeps the answer forever after. Here the first
session would come up dark-themed with light GTK apps until the user
switched themes by hand.

Unlike the shell below, this needs only the session bus, not a running
compositor, so a graphical-session unit is the right shape for it. It is
a no-op on every later login, because it writes what dconf already holds.

<a id="provider-files-for-the-local-model-when-the-system"></a>
### Provider files for the local model, when the system module turned it on

```nix
home.activation.nixarchyOpencodeProvider =
```

Provider files for the local model, when the system module turned it on.

Written here rather than in modules/local-ai.nix because only the home
module knows where a user's home is, and read back out of osConfig so the
address the server binds and the address the agents dial cannot drift.
Guarded by `or null` throughout: home.nix is usable on its own, without
the NixOS module, and then there is no osConfig to read.

Both agents get a file whether or not either is the current default. They
are a few hundred bytes, and the alternative is that switching agent in
the menu silently produces one that cannot reach the model.
opencode's provider, merged into the file rather than owning it.

~/.config/opencode/opencode.json already exists on every Omarchy machine
-- it is seeded with the theme and an autoupdate setting -- so declaring
it as an xdg.configFile fails activation outright:

  Existing file '~/.config/opencode/opencode.json' would be clobbered

and takes the whole home-manager generation down with it, not just this
file. `force = true` is worse: it would throw away the user's own opencode
settings and Omarchy's theme wiring to install a provider block.

So the provider is merged in with jq, on every activation, leaving every
other key alone. Same reasoning as the pi settings below, arrived at the
same way: both files already have an owner.

<a id="pi-keeps-its-configuration-in-pi-agent-not-under-x"></a>
### pi keeps its configuration in ~/.pi/agent, not under XDG

```nix
home.activation.nixarchyPiProvider =
```

pi keeps its configuration in ~/.pi/agent, not under XDG.

supportsDeveloperRole is the field that has to be right. pi sends system
instructions in the `developer` role to reasoning-capable models, and
Ollama -- like vLLM and SGLang -- rejects a role it does not know. Every
request then fails with an error that does not name the cause.
pi's provider. Merged for the same reason, though less urgently: nothing
in Omarchy writes models.json today. Doing it the same way means a future
version that does cannot break activation, and means a user's own extra
providers survive.

<a id="same-extension-point-on-the-other-hook-omarchy-alr"></a>
### Same extension point, on the other hook Omarchy already runs

```nix
xdg.configFile."omarchy/hooks/post-boot.d/config-repo" = {
```

Same extension point, on the other hook Omarchy already runs:
default/hypr/autostart.lua ends its startup with `omarchy-hook post-boot`.

A notification rather than a window. On a machine the installer built,
/etc/nixos is a repository with one staged, never-committed tree -- so
there is something real to say -- but a terminal that seizes the screen on
a first-ever boot arrives before the user has signed in to anything, which
makes the one answer they can give "dismiss". The nudge is a notification
they can act on when they are ready, and the script's own --check decides
whether there is any point showing it: already committed and pushed, no
agent chosen yet, or already answered once, and it stays quiet.

It stays quiet for one more reason now, and it is the important one. This
module reaches every machine that imports it, including one where somebody
added nixarchy to a configuration of their own -- and on that machine
/etc/nixos is theirs. --check asks /etc/nixarchy/managed before anything
else and answers "no nudge", so the hook exits 0 having said nothing.

Two conditions, two messages. The first push is a different thing to say
than the fortnight of changes that piled up after it, and a notification
whose text does not match what clicking it will do is worse than none.

<a id="left-at-home-managers-own-default-everywhere-else-"></a>
### Left at Home Manager's own default everywhere else, which is

```nix
enableSystemdUnit = lib.mkDefault false;
```

Left at Home Manager's own default everywhere else, which is
`cfg.containers != { } && cfg.package != null` -- true the instant
`machines` is non-empty, so leaving this unset would turn it on.
Refused outright: its ExecStart is
`${cfg.package}/bin/distrobox-assemble create --file ...`, a literal
/nix/store/... path baked straight into the unit file -- the exact
GC-survival hazard (nixpkgs#478154) modules/services/boxes.nix's own
comment documents distrobox itself must never be reached through.
`nix-collect-garbage` can delete that path out from under this unit
the same way it can out from under a running box. It also hardcodes
uid 1000 in the cleanup it runs first
(`rm -rf /tmp/storage-run-1000/...`), a second, independent reason to
leave it off. `nixarchy box` (a later issue) is how a machine picks
up a declared container -- by calling `distrobox-assemble` itself,
by bare name, the way the module comment already requires.

## `modules/apps.nix`

<a id="the-command-each-app-puts-on-path-so-the-menu-can-"></a>
### The command each app puts on PATH, so the menu can tell "you already…

```nix
appBinary =
```

The command each app puts on PATH, so the menu can tell "you already have
this" from "you have not installed it".

meta.mainProgram rather than the attribute name: it is right where the two
differ, and they differ often -- obs-studio puts `obs` on PATH, not
`obs-studio`. It is metadata, so this reads it without building anything.

tryEval because an unfree package throws at *evaluation* when allowUnfree
is off, and spotify and obsidian are both unfree. Without it, adding this
would have broken evaluation for everyone who has not opted into unfree --
a far worse outcome than the dim row it is here to draw. Falling back to
the app's own name is the same guess omarchy-pkg-present already makes.

`ours` apps are answered by cfg.apps.<name>.package -- the very derivation
the row would install, including any override the user put on it -- and
NOT by a lookup in `pkgs`, which cannot see them: this module's pkgs
carries no nixarchy overlay (modules/services/default.nix says why), so
the lookup returned null for every app this repo packages and the
fallback answered with the app id. That was `command -v zen` for a
package whose only binary is zen-beta, so the row never dimmed on a
machine that HAS Zen. nixarchy-doctor hit the same trap and fixed its
copy first, by probing final.nixarchy-apps (flake.nix); this is the
menu's half, asserted by tests/coverage.py against the flake's packages.

<a id="the-curated-list-as-search-rows"></a>
### The curated list as search rows

```nix
optionsJsonPath =
```

The curated list as search rows: id, label, category, note. Notes are
flattened because the index this feeds is tab-separated and a note with a
newline in it would silently become three broken rows -- the same reason
templateRow collapses them.
The NixOS option index, or "" when this system has no manual to take it
from. `system.build.manual` is defined under documentation.nixos.enable,
which is on by default but off in every NixOS test node -- so a hard
reference here evaluates fine on a real machine and fails the session
check, which is exactly how it got through review.

Built rather than fetched, but built by nixpkgs: it substitutes from
cache.nixos.org, so it costs a 2.6 MiB download rather than an evaluation
of every option on the machine.

<a id="flatpaks-go-in-services-nix-rather-than-a-fourth-f"></a>
### Flatpaks go in services.nix rather than a fourth file

```nix
flatpakIndexRows = pkgs.writeText "nixarchy-flatpak-rows.tsv" (
```

Flatpaks go in services.nix rather than a fourth file.

They are applications, so apps.nix is the tempting home -- and the wrong
one: that file's header promises "Applications available through the
Omarchy menu, as NixOS configuration", meaning software from nixpkgs with
everything that implies. A flatpak is a different tier with weaker
promises, and mixing the two would make the file quietly dishonest.

services.nix already holds things that are decisions about the machine
rather than packages, which is what enabling a flatpak is: it turns on a
daemon, adds a remote, and installs software the store does not hold.
Curated flatpaks as picker rows, plus the one row that reaches the rest of
Flathub. Written whole in Nix rather than transformed by awk at index time
like the app rows: there are a handful of these and the preview text is
prose, so a template is clearer than a transformation.

Five tab-separated fields, matching every other source: kind, name,
summary, option type (unused here), preview.

<a id="services-and-system-settings-as-nixos-configuratio"></a>
### Services and system settings, as NixOS configuration

```nix
{ ... }:
```

Services and system settings, as NixOS configuration.

The companion to apps.nix. An app is a package; a service is a decision
about the machine. Uncomment what you want -- or pick it from the menu --
then run

    nixarchy-apply

Two kinds of line appear below and the difference is deliberate:

  programs.nixarchy.services.X   nixarchy bundles several options here,
                                 because turning the thing on usefully
                                 takes more than one.

  services.X.enable              the real NixOS option, because there was
                                 nothing for nixarchy to add. This is the
                                 line every wiki page will show you, and
                                 it is the same line here.

This file is a NixOS module and nothing stops you writing any option in
it. Upstream's own settings work alongside ours -- if you enable
syncthing below, `services.syncthing.settings.folders` still does what
its documentation says.

This file is yours. Nothing regenerates or overwrites it once created;
the current full list is always at /etc/nixarchy/services-template.nix.

<a id="anything-at-all"></a>
### Anything at all

```nix
{ ... }:
```

Anything at all.

apps.nix is a list nixarchy generated and services.nix is a catalogue it
curated. This file has neither, because at some point the answer to "how
do I do X on NixOS" is a NixOS option nobody put on a list, and a curated
desktop that has no room for that is a cage.

It is an ordinary NixOS module. Every option in nixpkgs is available:

  services.openssh.settings.PermitRootLogin = "no";
  boot.kernelParams = [ "quiet" ];
  users.users.you.extraGroups = [ "dialout" ];

`nixarchy-search` writes here when you pick an option from it. Nothing
else touches this file.

If you find yourself writing the same thing here on every machine, that
is worth an issue -- it probably belongs in the catalogue.

<a id="applications-available-through-the-omarchy-menu-as"></a>
### Applications available through the Omarchy menu, as NixOS configuration

```nix
{ ... }:
```

Applications available through the Omarchy menu, as NixOS configuration.

Every app is listed and every line is commented out. Uncomment what you
want -- or pick it from the menu, which uncomments it for you -- then run

    nixarchy-apply

to copy this into your flake and `nixos-rebuild switch`. Enable as many as
you like before applying; nothing is built until you do.

This file is yours. Nothing regenerates or overwrites it once created;
the current full list is always at /etc/nixarchy/apps-template.nix.

The `#@ name` markers are how the menu finds a line to uncomment. Keep
them and you can reformat, reorder and annotate this file freely.

<a id="the-menu-defaults"></a>
### ── The menu defaults ───────────────────────────────────────────────────

```nix
overrideSpec = pkgs.writeText "nixarchy-menu-overrides.json" (
```

── The menu defaults ───────────────────────────────────────────────────
Rewrites Omarchy's Install menu, in the DEFAULTS rather than in the user's
extension. Menu.qml reads two files and merges the second over the first:

  defaults   $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc
  user       ~/.config/omarchy/extensions/omarchy-menu.jsonc

Nixarchy used to generate the second one and symlink it into /etc, which
put the port in the slot upstream documents as the user's -- and which
shell/plugins/README.md tells third-party plugins to write. A plugin's row,
or a row somebody typed, could not survive there, and nothing said so.

But we build the package OMARCHY_PATH points at, so the defaults are ours
to write: `omarchyTree` below is that tree with this one file replaced.
Then the user's file is free, upstream's merge does the rest in the
direction it was designed for, and there is nothing to arbitrate. See #210.

A failing `when:` hides a row outright (MenuModel.js isVisible); a
succeeding `disabled:` leaves it listed but dim and unselectable, which is
what upstream already uses for "you have this installed".
The override rows, as data. Deliberately WITHOUT label or icon: those are
copied from upstream's own menu at build time by the script below, so a
rename upstream follows through instead of being frozen into this repo.

<a id="beside-roll-back-because-they-are-the-two-halves-o"></a>
### Beside Roll back, because they are the two halves of the same

```nix
"system.backup" = {
```

Beside Roll back, because they are the two halves of the same
question: a generation brings this machine back on this disk, and a
pushed configuration brings it back on any other one.

Reachable deliberately rather than only by notification. The command
existed for a while with no way to reach it except a nudge on a boot
you happened to act on, or knowing its name -- which meant the answer
to "I changed things, is that backed up?" was to remember a command.

`when` rather than letting the row refuse when clicked: on a machine
nixarchy did not write, nixarchy-config-repo declines and explains
why, and a menu row whose only possible outcome is that explanation
is not worth drawing. /etc/nixarchy/managed is the same predicate the
command itself gates on -- see modules/nixos.nix.

<a id="the-off-disk-half-beside-the-on-disk-one"></a>
### The off-disk half, beside the on-disk one

```nix
"trigger.home-backup" = {
```

The off-disk half, beside the on-disk one.

A snapshot and a backup read as the same thing to someone who has
not lost a disk yet, so the two pairs sit together deliberately:
snapshots are instant and local, these two survive the hardware.
The descriptions are where that difference is actually said.

`when` hides both rows on a machine nixarchy did not install --
the same gate the script itself enforces, so an imported
nixosModules.nixarchy is not offered a thing that will refuse.
A row that exists to say no is worse than no row.

<a id="the-sandboxes-group-226"></a>
### The Sandboxes group (#226)

```nix
"trigger.vm" = {
```

The Sandboxes group (#226). A nested `trigger.vm`, not a new root
section -- `trigger.ask` above is the same shape, a new parent
under an upstream root, and there is no precedent here for a root
of our own. `full = dict(upstream); full.update(out)` in
menuDefaults above means a totally new id like this one is
APPENDED, so it lands after System and About at the end of the
list -- the ordering #226 documents, not something coded here.

Two gates, both needed. This `lib.optionalAttrs cfg.enable` is the
Nix-level one: belt-and-braces, since every row in this file
already lives inside `config = lib.mkIf cfg.enable (...)` above --
stated explicitly so a reader does not have to trace that back.
The runtime one is the parent's own `when` below: whether *this
login* can open /dev/kvm is only knowable now, not at rebuild
time -- `nixarchy-vm --check` (pkgs/microvm.nix) always exits 0,
so nothing here is actually gated on hardware; the fallback to a
software CPU is what makes that true on every nixarchy machine.

`nixarchy-vm` itself is installed unconditionally (this file,
below -- same as `nixarchy dev init`), so there is no
`programs.nixarchy.services.microvm.enable` to gate this on:
#221 designed the disposable half to need no root and no rebuild,
so nothing about it is opt-in.

<a id="dim-when-the-app-is-in-the-selection-or-already-on"></a>
### Dim when the app is in the selection *or* already on PATH

```nix
disabled =
```

Dim when the app is in the selection *or* already on PATH.

The second half is the case nixarchy could not see before: an
app the user installed themselves, in their own
systemPackages or home.packages, which the selection knows
nothing about. The row offered to install something they
already had, and taking it would have written a second
declaration for it.

Remove rows deliberately do NOT gain this. They stay bound to
the selection, because deselecting is the only removal
nixarchy is allowed to perform -- an app that arrived from
the user's own configuration is not this menu's to take away.

<a id="the-services-catalogue-as-menu-rows"></a>
### The services catalogue, as menu rows

```nix
// lib.listToAttrs (
```

The services catalogue, as menu rows.

Most of these are ids upstream does not ship -- Omarchy's menu has no
"turn on SSH" row because on Arch that is not a menu's business. The
generator takes a new id as long as the override names the row itself,
which is why label and icon are here; install.search arrived the same
way. Where upstream DOES have a row, the catalogue entry carries its
menuId and this overrides it in place -- tailscale is that case, and
carrying the id across is what keeps the generator from failing on a
row nothing maps.

<a id="the-tree-omarchy-path-points-at"></a>
### The tree OMARCHY_PATH points at

```nix
omarchyTree = pkgs.runCommand "nixarchy-omarchy-tree" { } ''
```

The tree OMARCHY_PATH points at: the package's own share/omarchy, with
exactly one file replaced.

Built here rather than in pkgs/omarchy because the rewrites depend on the
machine's app selection, which is per-configuration, not per-package. The
idiom is flake.nix's nixarchy-plymouth: mirror a subtree out of the omarchy
package rather than rebuild the package for one file.

Symlinks at the shallowest level that works, and real files in the one
directory being changed. That matters for more than size: upstream's own
scripts copy out of $OMARCHY_PATH at runtime (omarchy refresh, the
migrations, omarchy-plugin-clone), and a symlink FARM would hand them
links into a read-only store path where they expect files. Symlinking whole
directories instead keeps everything inside them a real file, which is what
`cp -r $OMARCHY_PATH/config/.` copies.

<a id="the-doctor-and-verify-which-until-now-were-flake-a"></a>
### The doctor and verify, which until now were flake apps only

```nix
(pkgs.extend inputs.self.overlays.default).nixarchy-doctor
```

The doctor and verify, which until now were flake apps only.

`nixarchy doctor` has always been an advertised subcommand, and on
every machine where you can type `nixarchy` it answered "The doctor
is not installed". The dispatcher below already has
`if command -v nixarchy-doctor` and routes to it -- a branch nothing
could take, because nothing installed it.

Running from the flake is unchanged: that entry point exists so the
doctor can be run BEFORE nixarchy is an input anywhere, and
installing it does not take that away.

Through the overlay on the user's own pkgs, never
inputs.self.packages -- see the note on programs.nixarchy.package in
modules/nixos.nix for what mixing nixpkgs instances does to buildEnv.

<a id="uncomments-one-app-in-config-nixarchy-apps-nix"></a>
### Uncomments one app in ~/.config/nixarchy/apps.nix

```nix
(pkgs.writeShellApplication {
```

Uncomments one app in ~/.config/nixarchy/apps.nix. Matching is on
the `#@ <id>` marker, not a line number or a label, so the file
survives being reformatted, reordered or annotated by hand.
What the catalogue offers that your file has never heard of.

The seeded files are written once and never touched again, which is
correct -- they are the user's, and overwriting one would silently
undo a selection. The consequence is that an entry added after a
machine was installed never appears on it: no `#@` marker, so
nixarchy-app-enable answers "no app 'x' in $file" and the menu row
is dead. Until now the only way to find that out was to diff
against /etc/nixarchy/apps-template.nix by hand, and nothing said
so.

<a id="the-answer-to-i-want-a-package-the-menu-does-not-o"></a>
### The answer to "I want a package the menu does not offer"

```nix
(pkgs.writeShellApplication {
```

The answer to "I want a package the menu does not offer". Upstream's
`omarchy pkg add` runs pacman; there is no imperative equivalent
here, so this does the declarative thing instead -- appends the
attribute to a list in the same file the menu already edits, so
one `nixarchy-apply` builds curated apps and extras together.

It deliberately does NOT touch the user's own NixOS configuration,
which nixarchy does not own. ~/.config/nixarchy/apps.nix is already
a full NixOS module, so a systemPackages list can sit beside the
app selection with no new file and no new option.

<a id="search-everything-this-machine-could-install-and-r"></a>
### Search everything this machine could install, and route the choice

```nix
(pkgs.writeShellApplication {
```

Search everything this machine could install, and route the choice
to whichever writer is right for it.

The three kinds are not interchangeable and the whole point of one
picker over them is that you do not have to know which is which:
an app becomes programs.<name>, a package becomes a systemPackages
entry, an option becomes a line of its own. Picking Firefox from
the app rows and picking `firefox` from the package rows are
genuinely different configurations, and the rows say so.

The index is built from this system's own nixpkgs and its own
options, not from search.nixos.org. It is slower to build and it
cannot go stale against the machine, which is the trade that
matters: an index that offers a package nixarchy-pkg-add will then
refuse is worse than no index.

<a id="ask-flathub-org-directly"></a>
### Ask flathub.org directly

```nix
flathub_search() {
```

Ask flathub.org directly.

NOT `flatpak search`, which is columnar with no JSON output and
needs both a configured remote and a downloaded appstream cache
-- so it answers nothing on a machine that has not set flatpak
up yet, which is exactly the machine asking.

This is the one thing in the picker that needs a network. The
index itself is still built entirely from local sources, so the
other three kinds keep working on a machine with none; only
this row fails, and it says so.

<a id="one-name-for-the-commands-this-repo-adds-and-a-way"></a>
### One name for the commands this repo adds, and a way through to

```nix
(pkgs.writeShellApplication {
```

One name for the commands this repo adds, and a way through to
the 431 it vendors.

Not a rename of Omarchy. Upstream's commands keep upstream's name,
because they are upstream's -- `omarchy theme set` is the same
script here as on Arch, and a bug in it is a bug to report there.
What this names is the other half: the commands nixarchy wrote,
which until now were binaries on PATH with nothing tying them
together and no way to discover them.

Anything this does not own falls through to omarchy unchanged, so
`nixarchy theme set catppuccin` works and does exactly what
`omarchy theme set catppuccin` does. The fallthrough is the point:
you should not have to know which half of the desktop you are
talking to before you can type a command.

<a id="where-the-selection-lands"></a>
### Where the selection lands

```nix
base="$flake"
```

Where the selection lands: this machine's directory when the
flake has one, the flake root when it does not.

That second case is every machine installed before the hosts/
layout existed. Their flake is their own -- the README calls it
"a flake you own" -- so nothing migrates it, and this one
conditional is the entire cost of leaving them alone.

Keyed on the directory existing rather than on the hostname
matching anything: a repo that has hosts/ but not one for THIS
machine is a repo being edited from somewhere else, and writing
a stray directory into it would be worse than writing the file
where it has always gone.

<a id="a-flake-cannot-read-a-file-outside-its-own-tree-so"></a>
### A flake cannot read a file outside its own tree, so the

```nix
srcdir="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
```

A flake cannot read a file outside its own tree, so the
selection is copied in rather than imported from $HOME.

Three files now, into $flake/nixarchy/, with nixarchy-apps.nix
left as a module that imports them. That last part is the whole
reason for the indirection: the README has been telling people
to add `imports = [ ./nixarchy-apps.nix ];` since the beginning,
and on a machine nixarchy does not own, asking them to add two
more lines is not a thing this project gets to do. The name they
already wrote keeps working and gains two files behind it.

Safe to overwrite because nixarchy-apps.nix has always been a
copy this script regenerates, never something the user wrote --
and the copy it used to hold is written to nixarchy/apps.nix in
the same run, before the stub replaces it.

<a id="stage-what-was-written-or-a-flake-in-a-git-worktre"></a>
### Stage what was written, or a flake in a git worktree cannot see

```nix
if [ -e "$flake/.git" ]; then
```

Stage what was written, or a flake in a git worktree cannot see
it. This is not a nicety: git makes untracked files invisible to
the evaluator, so a fresh nixarchy/services.nix fails with "path
does not exist" -- the trap installer/mkFlake.nix documents and
the installer works around by staging at install time.

Guarded, and still guarded after #356 chowned /etc/nixos to the
installed user. This no longer fires on a machine this
installer wrote -- staging succeeds there now -- but it is not
dead code: an own-flake adopter keeps whatever ownership their
configuration already has, and `--from-repo` installs onto a
tree somebody else created. A failure to stage should still
print the fix rather than abort an apply that has already
copied everything correctly.

<a id="whether-anything-in-the-flake-actually-imports-it"></a>
### Whether anything in the flake actually imports it

```nix
importers=$(grep -rl 'nixarchy-apps\.nix' "$flake" \
```

Whether anything in the flake actually imports it.

Copying the selection in is only half the job: a flake cannot
read a file outside its own tree, so the copy is necessary, and
importing it is the user's. Nothing checked that, so a machine
that never added the import got the full ceremony -- the menu
marking apps enabled, this script reporting a copy, a rebuild
running to completion -- and installed nothing, every time. It
took someone asking why `dictation.enable = true` never
installed anything to notice.

Excludes the copy itself, which of course contains its own name
nowhere but is matched by the filename glob.
