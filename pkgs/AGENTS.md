# pkgs/

The Omarchy tree as a derivation, the commands this repository writes itself,
and the packages nixpkgs does not carry.

## Intent

Omarchy's source is packaged, not reimplemented. `OMARCHY_PATH` points at it in
the store and only the distro-coupled scripts — the ones that run `pacman` — are
replaced or shimmed. Tracking an upstream release is a source bump, not a
re-port, and that property is worth more than any individual fix.

| path | what it is |
|---|---|
| `omarchy/` | the vendored tree, its patches, and `nix-bin/` — the replacements |
| `omarchy/nix-bin/` | commands that replace an Arch-coupled upstream one |
| `omarchy/skills/` | what an agent on a nixarchy machine reads |
| `apps/` | packages with no nixpkgs equivalent |
| `doctor.sh`, `verify.sh`, `review.sh` | scripts spliced into derivations at build time |
| `explain.sh` | reads a Nix failure and says what it is, in the user's vocabulary |
| `box.nix`, `microvm.nix` | the container and guest runners |
| `rebuild-panel/` | the one Quickshell panel whose source is here, not an input |

**Why `rebuild-panel/` is here and every other panel is a flake input.** The
eight panels nixarchy installs (`nixarchy.pkg`, `.podman`, `.distrobox`,
`.herdr`, `.microvm`, `.devenv`, `olafkfreund.gitlab-pipelines`,
`.github-actions`) each come from their own repository, copied into place by a
`runCommand` in `modules/home.nix`. That is the right shape for a panel that
drives a tool: the tool has its own release cycle and the panel follows it.

`nixarchy.rebuild` (#765 PR 5) drives *this repository's* `nixarchy-apply
--detach`, and the two are one contract: the unit's name, `RemainAfterExit`,
and the properties `nixarchy-rebuild-state` reads. Split across two repos,
nothing asserts both ends and a skew is a panel that shows the wrong state
with both sides green. Here, `checks.qml` parses it and
`checks.apply-staging` tests its state mapping against the very script that
starts the unit. Follow this only for a panel that is inseparable from
something here; take a flake input otherwise.

## The trap that has cost the most here

**`writeShellApplication` builds a strict PATH from `runtimeInputs`.** A command
a script calls and does not declare is a runtime failure no build catches — and
it does not read as "missing command", it reads as whatever the script concludes
from the failure.

`doctor.sh` carries the canonical example in a comment on its `runtimeInputs`:
an undeclared `vainfo` does not report "vainfo is missing", it reports "no VAAPI
driver answered", which is a different and much worse answer to hand someone. It
ran anyway during development, from the author's own PATH.

Before adding a command to any script here, add it to that derivation's
`runtimeInputs`. If the script parses JSON, that means `jq` — reaching for `sed`
on JSON is how a check starts confidently reporting wrong things the first time
nix reformats a file.

## `writeShellApplication` also sets `errexit`

The `runtimeInputs` trap above is the expensive one. This is its sibling, and
it cost an hour here: the wrapper is `set -o errexit -o nounset -o pipefail`,
so a script that runs fine as `bash pkgs/thing.sh` can die at the first
command substitution once it is packaged.

`nixarchy explain -- <command>` did exactly that. `err=$("$@" 2>&1)` captures
the output of a command that is failing — that is the entire point of the
form — and under `errexit` the script exited there, before printing anything,
with the wrapped command's status. Which reads as the tool never having run.
`err=$("$@" 2>&1) || status=$?` is the fix; a script's own `set -uo pipefail`
does **not** turn `errexit` back off.

The general shape: **anything that deliberately runs a failing command has to
say so at the call site.** And a script whose whole job is to be handed
failures is one where every path is that path — so exercise the packaged
binary, not the source file. The bug survived a green check suite because
every assertion fed the script on stdin, and stdin never fails.

## A long build phase is one indented string, and it strips one indent

`pkgs/omarchy/default.nix`'s `installPhase` is a single `'' ... ''` string, and
Nix removes the *smallest* indentation shared by every line in it, once, for
the whole string. One line anywhere with less indent (a multi-line
`--replace-fail` argument sitting at four spaces) means everything else keeps
sixteen. So a heredoc added at the phase's usual depth fails twice: its
`EOF` is never at column 0, so it never ends, and inline Python gets
indentation it did not ask for (#764). Put anything more than a line or two of
code in its own file beside `default.nix`, as `check-logo.py` and
`nixarchy-plymouth-frames.py` are, and call it with `python3 ${./file.py}`.
That also avoids escaping `\n` and `${` inside the string.

**Counting columns of the banner art counts bytes in the builder.** Every block
glyph is three bytes of UTF-8, and the sandbox's locale is C, so `awk
length()` and `wc -c` read an 87-column banner as roughly 250. Count
characters (`len()` in Python with `encoding="utf-8"`).

## `writeShellApplication`'s bash has no `compgen`, and an `if` hides that

The shell it wraps is nixpkgs' plain `bash`, not `bashInteractive`, and that
build has no programmable completion, so `compgen` does not exist. A script
that works in your terminal fails when packaged. Inside an `if`, the failure
does not even stop the script under `errexit`: `if compgen -G "$dir/*"` reads
"command not found" as a false condition. #762's volume guard did exactly that,
so it let every case through, and only the check saw it. Use a glob loop
(`for f in "$dir"/*; do [ -e "$f" ] && ...`) or `find`. The same goes for any
builtin you learned in an interactive shell: run the packaged binary, not the
source file.

## Patching upstream

Everything is patched with `--replace-fail`, so an Omarchy bump that rewords a
line a patch depends on **fails the build** rather than quietly restoring Arch
instructions. Only `SKILL.md` and `contributing.md` are replaced outright, where
the guidance is wrong here rather than merely misspelt.

CI additionally asserts that no skill code block contains a `pacman`, `yay`,
`/usr/share/omarchy` or Arch-debuginfod line. Prose may contrast with Arch on
purpose; a fenced block is what an agent copies.

<a id="hyprforge-s-hook-lives-in-the-store-hyprland-lua"></a>

### Hyprforge's hook lives in the store hyprland.lua (#1059)

Hyprforge saves to `~/.config/hypr/hyprforge.lua` and expects
`~/.config/hypr/hyprland.lua` to load it. Its Connect button adds one optional
`require` there. nixarchy's session never reads that file: `modules/nixos.nix`
starts Hyprland with `--config` on the store's `config/hypr/hyprland.lua`. So
on nixarchy, Connect alone saves settings that vanish at the next login.

The same line therefore goes into the store file, after
`require("hypr.autostart")`, the place Hyprforge itself picks:

- **It is optional.** `require_optional.module` is Omarchy's own helper, and a
  machine that never opened Hyprforge has no file, so nothing changes.
- **It is Hyprforge's exact text**, so a new home's seeded copy reads as
  connected and the banner never shows. An existing home keeps its older
  seeded copy (the seed never overwrites). There Connect still offers itself,
  and clicking it edits a file the session ignores, which is harmless.
- **It is per-system, not per-plugin.** Turning Hyprforge off leaves a saved
  `hyprforge.lua` applied until it is deleted, as upstream's Connect line
  would.

`checks.session` writes the file and reads the option back through
`hyprctl`. That is the only layer that can see "saved but never loaded" (§2).
<a id="omarchy-restart-shell-waits-for-the-old-shell-to-be-gone-953"></a>

### omarchy-restart-shell waits for the old shell to be gone (#953)

A CARRIED patch, not reported upstream (the owner's decision). Upstream stops
the running shell with:

```sh
while timeout 5 quickshell kill -p "$CONFIG_DIR" --any-display >/dev/null 2>&1; do :; done
```

Its comment promises that a kill "only returns once it has fully exited, so the
no-duplicate launch below can't race a dying shell". `timeout 5` breaks that
whenever teardown is slow:

- a plugin-heavy shell measured about 14 s;
- one in the middle of a plugin hot-reload, which a Home Manager switch that
  swaps a plugin folder starts, stalls for 8–30 s.

So the client gave up, the relaunch ran beside the dying shell, the new one
printed "already running" and exited, and then the old one finished. On p620
on 2026-09-29 that meant no shell and no bar for 17 minutes. Upstream's own
readiness poll, about 12 s, then gave up too, so nothing recovered.

Two `--replace-fail` edits fix it:

- **The exit wait.** Loop while `quickshell list -p "$CONFIG_DIR"` still names
  an instance, re-issuing the kill, bounded by `OMARCHY_SHELL_EXIT_TIMEOUT`
  (60 s). Past the bound, say so and exit 1 **without** launching, because a
  second shell beside a live one exits by construction. The list output is
  captured and matched, never piped into `grep -q`
  (tests/AGENTS.md#a-pipe-into-grep-q-can-fail-because-grep-matched).
- **Readiness.** A deadline of `OMARCHY_SHELL_READY_TIMEOUT` (60 s) instead of
  20 attempts, because a fresh plugin-heavy shell takes 30–60 s to answer IPC.

**When to drop it:** once upstream waits for the old instance itself.
`checks.shell-restart-race` runs upstream's unpatched script as its negative
control, and goes red when that script stops ending with zero shells. That red
is the signal, not a regression.

<a id="omarchy-menu-close-never-starts-dictation-1070"></a>

### omarchy-menu close never starts dictation (#1070)

A CARRIED patch. Upstream's `omarchy menu close` is
`exec omarchy-shell shell hide omarchy.menu`, which reaches the enabled
clone's `close()`. nixarchy-menu (on by default) turns `close()` into the
hotkey's second tap: with voice on, that starts dictation rather than
closing. A script that closed the menu -- `checks.session`'s own #1069 probe,
and any user script calling `omarchy menu close` -- started a recording. p620
was measured in exactly that state (voice on) on 2026-09-29.

The fix asks the menu to dismiss itself first, over IPC, and only falls back
to upstream's `hide` when there is no `dismiss()` to answer:

```sh
if [[ $(omarchy-shell shell call omarchy.menu dismiss "{}" 2>/dev/null) == ok ]]; then exit 0; fi
exec omarchy-shell shell hide omarchy.menu
```

**The `call` reply rule (read from `omarchy-shell`/`shell.qml`, not
guessed):** `shell call` exits 0 far more often than it fails. It answers the
string `"unknown"`, still exit 0, when the target plugin has no such method --
which is the stock menu's state, since only nixarchy-menu defines `dismiss()`.
It exits 1 (or times out) only on an IPC-level failure: no connection, no
reply, or qs's own `Target not found.` / `Function not found.` literals for
the **IPC handler's** functions, never the plugin's. So the patch matches the
**reply**, not the exit status -- `|| falls back` on a failing `omarchy-shell`
would never trigger for the one case it needs to catch (the stock menu
answering `unknown` with a perfectly good exit 0).

`tests/menu-close.nix` stubs `omarchy-shell` to prove the call-before-hide
order and the reply match, for both an enabled and a stock menu.
`tests/session.nix`'s #1069 probe is the only layer that pins the real `qs`
reply format this depends on.

**When to drop it:** never, unless upstream grows an explicit close verb of
its own, distinct from hide.

<a id="display-text-size-on-a-managed-config-948"></a>
### `display text size` on a config it cannot edit (#948)

`omarchy display text size N` edits the terminal configs with `sed -i`. On Arch
those are ordinary files in `$HOME` and it works. Here they can be Home Manager
symlinks into the store, and sed dies with

    sed: couldn't open temporary file /nix/store/sedXXXXXX: Read-only file system

while the shell and GTK sizes still apply -- a partial result and an error
nobody can act on. Ours rather than upstream's: the port made the files
read-only. Same discriminator as #963 and #982.

**Two fixes that look right and are not.** `sed --follow-symlinks` writes to the
store target, which is equally read-only -- upstream's kitty branch already does
this and it does not help. And letting `sed -i` replace the symlink with a real
file appears to work while quietly taking the file out of Home Manager's
management, so the next rebuild fights it. That is worse than the error.

**The guard is its own file**, `pkgs/omarchy/text-size-managed-guard.sh`, spliced
in with `--replace-fail`. Inline was tried first and refused: the install phase
was 1,910 bytes from `MAX_ARG_STRLEN` (#997), and the failure said only
"Argument list too long". A path costs about 60 bytes; the block cost 1,630.

**There is no nixarchy option to name in the message.** nixarchy *seeds* these
files and never manages them, so on a stock machine they are real files and the
existing edit works. They are symlinks only where the user manages them
themselves, so the message points at wherever they declare it rather than
inventing a `programs.nixarchy.*` that does not exist.

<a id="the-tree-a-restarted-shell-runs-982"></a>
### The tree a restarted shell runs (#982)

`omarchy-restart-shell` relaunches through `hyprctl dispatch exec_cmd`, and
Hyprland spawns that child with **its own** environment, fixed at login. So a
rebuild changed `OMARCHY_PATH` and a restart still came up on the old tree:
generated menu data only took effect at the next re-login, which is how #961's
Ask aliases shipped and were invisible on razer.

The script already read the session's `OMARCHY_PATH` for the **kill**, under a
comment noting that the user manager receives Hyprland's environment at session
start. That read was used for the kill and discarded for the launch.

**The session value is not fresh either.** `environment.sessionVariables` reach
a login shell through `/etc/set-environment` and never reach a RUNNING user
manager, so `systemctl --user show-environment` answers with the login-time path
too. Measured on p620: `/run/current-system` said `h2qc3mkc...`, the user
manager said `rp5i87d4...`. That is why the patch reads the generated file.

**Only the launch changes.** The kill keeps the session value, because the
running shell registered under the login-time path -- killing by the new one
finds nothing and leaves two shells.

**Ours, though the script is upstream's.** On Arch `OMARCHY_PATH` is
`/usr/share/omarchy`: stable across upgrades, so inheriting a login-time value
is correct and free. The port made it a store path that moves every rebuild.
Third symptom of that one fact, after #963 and the workaround already at line 8.

<a id="the-browser-theme-policy-and-why-402-broke-it"></a>
### The browser theme policy, and why 4.0.2 broke it here

The theme accent stopped reaching the browser in 4.0.2. The session
check caught it: /etc/chromium/policies/managed/color.json was never
written, and wait_until_succeeds sat on it for the full 900 seconds.

4.0.1 wrote the policy inline from omarchy-theme-set-browser, as the
user, into whichever policy directories existed -- and the NixOS
module creates those four owned by browserThemeUser (the tmpfiles
rules in modules/nixos.nix) precisely so that unprivileged write
lands. 4.0.2 moved it into a new privileged helper, which sudo- or
pkexec-escalates to root, pins PATH to FHS directories that hold none
of install/mktemp/rm here, and installs color.json as root:root under
an /etc/sudoers.d rule naming a /usr/bin path. None of those three
exist on NixOS, so every path through it fails.

So the escalation goes and the write is the user's again, which is the
arrangement the tmpfiles rules already provide and the one that has
been shipping. Upstream is hardening against a `chmod a+rw` policy
directory writable by every account on the machine; ours is 0755 owned
by one named desktop user who is in wheel already, so routing the same
write through a NOPASSWD sudo rule would move it rather than restrict
it. Keeping upstream's shape -- root-owned directories plus
security.sudo.extraRules on the store path -- was considered and
rejected for that: it makes the module, the package and every VM user
agree on one path, and buys nothing this configuration does not have.

The PATH pin is kept rather than deleted, retargeted at the store, so
a hand-run `sudo omarchy-theme-set-browser-policy` still resolves its
coreutils. The color validation, the symlink refusal and the atomic
install are upstream's and untouched -- they are the half of 4.0.2
that does work here.

Moved here from `pkgs/omarchy/default.nix`'s install phase by #997, with a
`# Why:` pointer left at the code.

<a id="the-agent-skills-upstream-writes-for-arch"></a>
### The agent skills, which upstream writes for Arch

Agent skills. omarchy-provision-user symlinks every directory under
default/agents/skills/ into ~/.claude/skills, ~/.agents/skills and
~/.pi/agent/skills (upstream also does ~/.codex/skills; patched out
below, since Codex reads ~/.agents/skills and listed each skill twice),
so whatever is here is what an AI agent on this machine is told to do.
Upstream's are written for Arch: they point at /usr/share/omarchy, and
their decision framework answers "install a package" with `omarchy pkg
add`, a script this repo replaced with one that deliberately refuses.
Shipping them unchanged means an agent confidently doing imperative
things a rebuild then wipes -- the one failure mode that looks like
success.

The `omarchy` skill is renamed to `nixarchy`, so the skill an agent
loads is named for the system it is actually on, and a new `nixos`
skill owns packages and system changes. `diagnose-crash` keeps its
name: bin/omarchy-agent-crash reads that path literally.

SKILL.md and contributing.md are replaced outright -- their guidance
is wrong here, not merely misspelt -- while the rest are patched, so
an upstream edit to a line we depend on fails the build instead of
quietly shipping Arch instructions again.

The Default Agent menu, made to stop lying.

Upstream's tick is `[[ "$(omarchy-default-agent)" == "claude" ]]`
-- purely "you picked this". On Arch that is also "this is
installed", because picking installs it there and then. Here the
build is a rebuild, so the two came apart and the menu showed
Claude ticked beside a terminal saying `claude: command not found`.

Every agent's menu id is also the command it installs, which is what
lets one loop do all nine. --replace-fail, so a row upstream renames
stops the build rather than silently keeping the old meaning.

No backslash before the ampersands: substituteInPlace is a literal
string replacement, not sed, and escaping them put `\&\&` into the
JSON -- which parses as an invalid control character, not as a shell
`&&`. The jsonc is re-parsed at the end of this phase for that reason.

Moved here from `pkgs/omarchy/default.nix`'s install phase by #997: that phase
was 1,910 bytes from `MAX_ARG_STRLEN`, and 56% of its 129 KB was comments. The
code it explains carries a `# Why:` pointer back to this anchor.

### A patch needs its ledger row in the SAME change

`checks.bin-ledger` compares `data/bin-ledger.nix` against what the package
actually ships: a row is a claim that the shipped file differs from upstream's,
and the build decides whether it does. Add a `substituteInPlace` without a row
and it refuses:

    omarchy-shell: shipped as `patch` and has no row.

**This was missed three times in one session** -- `omarchy-shell` (#963),
`omarchy-display-text-size` (#948) and `omarchy-restart-shell` (#982, where a
`vendor` row had to become `patch`). Each time the check caught it, and each
time it caught it on `main` rather than on the branch, because the patch was
merged without waiting for the `omarchy` job.

So: **when you add or change a `substituteInPlace` in this file, edit
`data/bin-ledger.nix` before you commit.** The row says why this port diverges,
and it is the only place that answer is written down. `--seed` prints a
skeleton.

Two failure shapes, not one:

- **no row at all** -- a newly patched command;
- **a `vendor` row where the build now produces `patch`** -- a command that was
  vendored unchanged and has just started diverging. The message names both
  directions, and the second is easy to miss because the row exists.

### The first patch to `omarchy-shell` (#963)

`omarchy-shell` matched the running Quickshell instance by **config path**. On
Arch that is `/usr/share/omarchy` -- one stable path across upgrades, so the
match is correct and there is nothing to send upstream. Here it is a store path
that changes on every rebuild, so after a redeploy the caller holds the new one,
the running shell registered under the old one, and every IPC call misses. The
symptom is a plugin keybind that silently does nothing on a machine that looks
fine.

The replacement tries the caller's path **first**, so a machine that has not
rebuilt since login never reaches the new code, and falls back to
`qs ipc -i <instance>` resolved from `qs list --all`.

**Measured before it was written:** a stable symlink in front of `OMARCHY_PATH`
does not work. `qs` matches the path as given, not canonicalised, so the symlink
is a different string and finds nothing.

`--replace-fail`, like everything else here, so an Omarchy bump that rewords
that line fails the build rather than quietly restoring the store-path match.

### Aether's lockfile

Kept because the patch it describes came off at 4.29.9 and may have to go back
on, and because the shape generalises to any `buildNpmPackage` here.

Upstream's `frontend/package-lock.json` was out of sync with its
`package.json`, so `npm ci` — which `buildNpmPackage` uses, correctly, being
the only npm mode that installs exactly what is locked — refused outright:

    npm error `npm ci` can only install packages when your package.json and
    package-lock.json ... are in sync.
    npm error Missing: @emnapi/core@1.11.3 from lock file
    npm error Missing: @emnapi/runtime@1.11.3 from lock file

Those are optional native transitive dependencies npm omits when the lock is
generated on another platform. Regenerating needs a network, which a sandboxed
build has not got, so the corrected lock was carried as a patch, produced with
`npm install --package-lock-only` against the tagged source.

**The part worth keeping.** It was applied to the *source*, with
`applyPatches`, and not inside `buildNpmPackage` — because `fetchNpmDeps` reads
the lock from `src`. A patch applied within the package fetches against the old
lock and builds against the new one, which surfaces as a hash mismatch that
looks like a stale `npmDepsHash` and is not.

**How it retired, and why that took a day.** The patch stops applying when
upstream's lock changes, which is the notification working as designed — but it
fails during `nix run .#update`, which bumps every pinned app in one pass, so
the whole update looks broken rather than one app (#743). Before rewriting such
a patch, check whether it is still needed at all: run `npm ci` against the new
tag's unpatched lock, and against the old tag's as a control. Here the new one
succeeded and the old one failed with the error above, which is what a fix
being unnecessary looks like.

<a id="a-rebuild-built-whatever-branch-the-checkout-was-on"></a>
## A rebuild built whatever branch the checkout was on (#1037)

`nixarchy-apply`, `omarchy-update` and `autoUpdate` all build
`programs.nixarchy.flake`, whatever branch it has checked out. On a machine
where coding agents share the config checkout, that is how an unmerged,
unpushed branch was switched onto a live desktop, twice
(olafkfreund/nixos_config#2052). `branch-guard.nix` is the one answer all
three ask first, so they cannot disagree:

- the default branch is `refs/remotes/origin/HEAD`, else `main`. It is read
  from local refs only, because apply runs offline;
- it proceeds on that branch, or on a HEAD detached exactly at
  `origin/<default>` (nixos_config#2056's rule, so both tools give one
  checkout the same answer);
- it proceeds with no remote, outside a git checkout, or for a flake
  reference that isn't a directory;
- `ALLOW_BRANCH_DEPLOY=1` is the override, the same name nixos_config uses.
  **Not** `apply --yes`: the rebuild panel runs `apply --detach --yes` every
  time, so `--yes` would pass straight through.

**Where each caller asks, and why there:**

- `apply`: **after** its read-only modes (`--status`, `--json`, the journal
  follow), which must still answer on a branch, and **before** the first
  write, so a refusal leaves the checkout untouched. Not in the `--detach`
  parent: the panel starts that and ignores its output, so a refusal there
  would start no unit and the click would do nothing (#1033's defect). The
  unit refuses instead, which the panel shows as a failed rebuild, and
  `ALLOW_BRANCH_DEPLOY` is forwarded into it.
- `omarchy-update`: before the #356 writability prompt, so it never offers
  to `chown` a checkout it is about to refuse.
- `autoUpdate`: before `nix flake update`, so a refused run doesn't move the
  lock on somebody's branch either. It calls the helper **by store path**,
  because `tests/options.nix` runs that script under a `PATH` of its own.

**`-c safe.directory` is belt and braces, not the thing that makes root
work.** `modules/nixos.nix` already trusts `programs.nixarchy.flake`
system-wide, so root's git reads the user-owned `/etc/nixos`. The `-c`
covers a `NIXARCHY_FLAKE` pointed somewhere the system config doesn't name,
and reaches only the helper's own git calls.

## Tests

| check | covers |
|---|---|
| `omarchy` | the tree builds, and the README's counts still match it |
| `omarchy-runtime` | the replaced commands run |
| `patched-files` | every `--replace-fail` patch still applies |
| `etc-overlay` | the 40 files of upstream's `/etc` tree are each classified in `data/etc-overlay.nix` — the rows classed `installed` are what `modules/nixos.nix` puts in `/etc`, and the manifest is where "ignored on purpose" is written down for the rest |
| `doctor-graphics` | the doctor's GPU rules, against fixture machines |
| `doctor-ldd` | the doctor's dynamic-link check, against binaries built broken |
| `dashboard-clock` | the install dashboard against a rewound clock |
| `explain` | the error explainer, against errors produced inside the check |

## Why the install phase says so little

These sections were inside `pkgs/omarchy/default.nix`'s `installPhase`,
which is one shell string handed to `execve`. At 127,703 bytes it was
2,181 from `MAX_ARG_STRLEN`, and 54% of it was explanation -- so #948's
approved work was refused for want of 2 KB (#997). Root `AGENTS.md` §7
already says long blocks move here and leave a `# Why:` pointer; this is
that, applied to the ten largest.

**`checks.install-phase-budget` now says when to do it again.** It fails once
the phase passes **123,000** bytes: 8,058 short of the 131,058 a value can
have (`MAX_ARG_STRLEN` 131,072, less `installPhase=` and its NUL), so red
means tidy up, not a broken build. It measures only this phase, and it
retires itself, failing with a message that says so, if the package ever
moves to `__structuredAttrs`, which takes the phase out of the environment
and the limit with it. The budget is one line in
`tests/install-phase-budget.nix`. The figure moves by 12 bytes with git
state, because `nixarchyRev` is spliced in twice and a dirty tree adds
`-dirty` to each.

## The web-app keybinding upstream breaks, and the one-word fix

Upstream's bug, carried here because it breaks every web app keybinding
and the fix is one word.

`xdg-settings get default-web-browser` does not read the mime database
when $BROWSER is set. It takes $BROWSER as a command name and returns
the FIRST .desktop under ~/.local/share/applications whose Exec matches
it -- and a Chrome user has one of those per installed web app, all
reading `Exec=google-chrome-stable --app-id=...`. So on a machine with
`export BROWSER=google-chrome-stable` in its shell rc, this returns
whichever PWA sorts first. Observed on a real host: it answered
`chrome-aamlbainilhgmgbgbgcbcihnfgcnkgbd-Default.desktop`, which is
Lidarr. That matches no arm of the case above, so every web app fell
back to chromium -- a browser the user was not logged into -- and Email,
Calendar and the rest opened nothing they recognised.

Upstream already knows: omarchy-launch-browser, omarchy-default-browser
and omarchy-remove-browser all guard the same call with `env -u BROWSER`.
omarchy-launch-webapp is the one place they missed, and it is the one
every SUPER+SHIFT web app binding goes through.

Not NixOS-specific -- it breaks the same way on Arch -- so it belongs
upstream, and --replace-fail is what makes this a loan rather than a
fork: when they fix it, this line stops matching and the build fails,
which is the reminder to delete it.

## chromium-browser.desktop is renamed on three more paths that name it

The same chromium-browser.desktop rename as omarchy-launch-webapp, on
the three other paths that name the file rather than launch it.

provision-user is the one that mattered. `xdg-settings set
default-web-browser chromium.desktop` exits 2 -- "one of the files
does not exist" -- under `set -euo pipefail`, so it aborted on the
line BEFORE the xdg-mime patch above, which is why that patch had
never once run on any machine. In a clean $HOME, against nixpkgs' own
entry:

  chromium.desktop          exit 2
  chromium-browser.desktop  exit 0

omarchy-default-browser names it twice and both halves were broken by
it: `omarchy default browser chromium` exited 1 having set nothing,
and the no-argument read fell through to printing the raw desktop id
instead of "chromium" -- which is the string the menu shows as the
current browser. omarchy-remove-browser only writes the fallback, and
its `|| true` swallowed the failure, so removing Chrome quietly left
the machine with a default browser that resolves to nothing.

## Nothing may sed /etc/pam.d

Nothing may sed /etc/pam.d.

/etc/pam.d/sudo and /etc/pam.d/polkit-1 are symlinks into
/etc/static/pam.d, and GNU `sed -i` does not follow a symlink: it
writes a temporary file and renames it over the link, so the entry
stops being NixOS-managed and becomes a stale regular file holding a
copy of the stack. Two of the four scripts here do that on the way in
and two on the way out, and the way out is the one that fires unasked:
its guard is `grep -q pam_u2f.so /etc/pam.d/sudo`, which is TRUE on a
machine that enabled u2fAuth the NixOS way -- so Remove FIDO2 detached
the stack of a user who never ran Setup at all.

The edit was inert either way. It inserts a bare `pam_u2f.so`, and
every module NixOS names in these stacks is an absolute store path;
the detached file is then silently restored by the next rebuild. So it
read as a no-op that quietly broke /etc in between.

The functions go rather than being emptied, and their call sites are
replaced separately: `setup_pam_config` is then a single occurrence in
each file, so what is left is a one-line anchor that cannot be broken
by how this Nix string happens to be indented.
A range that stops matching deletes nothing, and the --replace-fail
below would then rewrite the header instead: check both ends.

## The SDDM greeter theme, and why it is not omarchy-refresh-sddm's copy

The SDDM greeter theme. Upstream installs this with omarchy-refresh-sddm,
which copies default/sddm/omarchy into /usr/share/sddm/themes -- a path
NixOS has no writable version of. Putting it in the package instead means
the greeter travels with the Omarchy release it came from, and
services.displayManager.sddm.theme = "omarchy" is all the module needs.

Without it SDDM falls back to its stock theme and the login screen is a
blue gradient with a placeholder avatar, which is the first thing anyone
sees of the system.
The boot splash. Upstream ships a complete Plymouth theme -- the script,
the logo and the progress assets -- and installs it with
`sudo cp -r ... /usr/share/plymouth/themes/omarchy` from
omarchy-refresh-plymouth. Nothing did that here, so boot.plymouth.enable
came up with NixOS' default theme and the one place a user cannot miss
was the one place that was not branded.

NixOS collects themes from boot.plymouth.themePackages by looking in
share/plymouth/themes, so putting it there is the whole of it.

## enable-user-units.sh enables six units in one call, so one absent unit loses all six

install/user/first-run/enable-user-units.sh enables six user units in ONE
`systemctl --user enable --now` under `set -euo pipefail`, so one absent
unit fails the whole command:

  Failed to enable unit: Unit omarchy-migrate-notify.service does not exist

Two of them are deliberately absent -- modules/nixos.nix explains that
omarchy-migrate-notify and omarchy-tailscale-receive can never satisfy their
ConditionPath* on NixOS. What was missed is that upstream's first-run still
NAMES them.

omarchy-provision-first-run marks itself done only when EVERY step
succeeded, so that one failure meant the marker was never written and
first-run ran again at every login -- re-showing the welcome notification
for the life of the machine. Reported as "this appears after each reboot";
the log had been saying so all along:

  Failed: enable user systemd units (exit code: 1)
  One or more first-run steps failed; first-run will retry next login

Replaced wholesale rather than patched: the unit list is a
continuation-line command, and a whitespace-exact multi-line
--replace-fail is the kind of patch an upstream reindent breaks. The grep
is the drift detector --replace-fail would otherwise have given for free.

## The rest of the lock screen theme: track, bar, passphrase field and dots

And the rest of the theme: the progress track and its bar, the
passphrase field, the padlock beside it and the dot that stands for
one typed character.

None of the five carries a name or a mark, so unlike the wordmark
there is nothing to derive from upstream -- they are drawn, in
nixarchy-plymouth-chrome.py, in the Tokyo Night palette the
background already uses. Drawing rather than copying is the point:
"no Omarchy artwork is reachable from the boot splash" is not
satisfied by files that merely look different, and it is not
satisfied by upstream's files either.

They are generated here rather than committed as PNGs. Five binary
blobs in the tree are five things no diff can review and no one can
re-derive; a script is 200 lines that say why every number is what it
is. It costs one python3 and five magick calls in a build that
already runs both for the wordmark.

The sizes are not free. omarchy.script divides by 84 and 96 to scale
the lock against the entry field, and centres the bar in the track by
their size difference, so the lock keeps upstream's dimensions and
the bar is deliberately smaller than the box. See the script.

## A keep-loaded plugin lost its shell API the first time shell.json changed

A keep-loaded plugin (the Podman menu) lost its shell API the
first time shell.json changed, and read barConfig as null
until the shell restarted (#877). manifestHasKind tested
kinds with Array.isArray. A manifest read through a QML
property carries kinds as a Qt sequence -- length 2,
"menu,bar-widget", Array.isArray false -- so the plugin's
scoped API was recorded `no-menu`, re-checked as `menu` by
prunePluginApis against the plain-JS manifest, revoked for
the mismatch, and the plugin kept the destroyed object.
Confirmed on razer with log lines in a copy of shell.qml.

CARRIED, and meant to be dropped, like the #749 block above:
AGENTS.md section 11 puts Omarchy fixes upstream, and this is
carried only at the owner's request until it lands there.
Delete it the moment upstream reads kinds without
Array.isArray. The whole function is the needle, so a
reworded one fails this build. checks.manifest-has-kind runs
the result against a real Qt sequence.
printf, not a multi-line literal: pkgs/AGENTS.md#a-long-build-phase-is-one-indented-string-and-it-strips-one-indent

## `omarchy plugin remove` rebuilt every plugin twice and took the bar with it

`omarchy plugin remove` rebuilt every installed plugin TWICE,
leaving the bar gone for ~53 s on a machine with 40 of them
(#893). One removal starts two reloads: the watcher fires
once per deleted file and is debounced through
localPluginReloadTimer (150 ms), while the rescanPlugins IPC
the remove script sends afterwards calls reloadPlugins()
straight away. The second call lands mid-scan, sets
pluginReloadPending, and onScanFinished throws the half-built
first pass away ("Object or context destroyed during
incubation" x18) and repeats it. Sending the IPC through the
same timer merges the two into one reload.

CARRIED, and meant to be dropped, like the #877 and #749
blocks above: AGENTS.md section 11 puts Omarchy fixes
upstream, and this is carried at the owner's request until it
lands there. Delete it the moment upstream debounces the IPC.
The whole function is the needle, so a reworded one fails
this build.
printf, not a multi-line literal: pkgs/AGENTS.md#a-long-build-phase-is-one-indented-string-and-it-strips-one-indent

## A layout-only shell.json save rebuilt every plugin and froze the bar

A layout-only shell.json save -- moving one bar icon --
rebuilt every panel, menu and overlay plugin, froze the bar
for 28-75 s on a machine with 52 of them, and flooded the
journal with ~99 IpcHandler re-registrations (#901).

Two causes, one per patch below. onShellConfigChanged fires
pluginsChanged() -- the "the set of plugins changed" signal --
for ANY save. And its panel listener assigns
shell.panelEntries a fresh JS array, which is an
Instantiator's model: QML does not diff a JS array, so every
delegate is destroyed and recreated even when the contents
are identical.

CARRIED, and meant to be dropped, like the #749, #877 and
#893 blocks above: AGENTS.md section 11 puts Omarchy fixes
upstream, and this is carried at the owner's request until it
lands there. Delete it the moment upstream diffs the list.
The whole block is the needle, so a reworded one fails this
build.
printf, not a multi-line literal: pkgs/AGENTS.md#a-long-build-phase-is-one-indented-string-and-it-strips-one-indent

## A notification its sender closed never left the screen

`CloseNotification` from the app that posted a notification only
forgot the shell's live reference (#1032). The popup row stayed,
and a critical one -- duration 0, so no timer -- stayed until
someone dismissed it by hand; the id was forgotten too, so the
sender could not replace it either. nixarchy-voice had already
stopped closing its own cards to work around it.

`902-notification-sender-close.patch` takes Quickshell's close
reason and, for `CloseRequested` only, removes the popup through
`removePopup`. So it is archived to history exactly as dismiss
and expire are: `removePopup` already states that rule ("leaving
the screen for any reason ... becomes the newest history entry"),
and `removePopupsByOriginalId`, which deletes, is for replacement.
`checks.session` sends a critical notification, closes it over
D-Bus, and watches its popup file move into `history/`.

CARRIED, and meant to be dropped, like the #901 patch above:
AGENTS.md section 11 puts Omarchy fixes upstream, and this is
carried at the owner's request until `omacom/omarchy` fixes the
same handler. `--fuzz=0`, so a reworded handler fails this build.

## omarchy-shell finds its instance by config path, which moves here

#963: omarchy-shell finds the running instance by CONFIG
PATH. On Arch that is /usr/share/omarchy -- one stable
path, so the match is correct and cheap. Here it is a
store path that changes on every rebuild, so after a
redeploy the caller holds the new one, the running shell
registered under the old one, and every IPC call misses:
a plugin keybind that silently does nothing.

Not sent upstream, because there is no bug upstream. This
is a consequence of the port making the path unstable.

Path FIRST: a machine that has not rebuilt since login
never reaches the fallback, so the ordinary case cannot
regress. The fallback asks qs which instances exist and
selects by id, which survives the path moving.

Measured before it was written: a stable symlink in front
of OMARCHY_PATH does NOT work -- qs matches the path as
given, not canonicalised, so the symlink is simply a
different string and finds nothing.
Why: pkgs/AGENTS.md#the-tree-a-restarted-shell-runs-982
Why: pkgs/AGENTS.md#display-text-size-on-a-managed-config-948

The guard is a FILE, not an inline block: this phase was
1,910 bytes from MAX_ARG_STRLEN when #948 first tried it
inline, and the build failed with "Argument list too
long" naming nothing (#997). A path costs ~60 bytes.

