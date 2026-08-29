# Reporting Issues and Submitting PRs

Read this when the user wants to report a bug, suggest a feature, or contribute a
fix.

**There are two projects here, and routing a report to the wrong one wastes
everybody's time.**

- **Nixarchy** — <https://github.com/olafkfreund/nixarchy> — packages Omarchy for
  NixOS. Its sphere is the NixOS module, the app catalogue, the replacement
  `omarchy-*` commands, the declarative Install/Remove/Update menus, and anything
  that behaves differently here than on Arch.
- **Omarchy** — <https://github.com/basecamp/omarchy> — the desktop itself. Its
  sphere is the shell, themes, Hyprland configuration, menus, and the `omarchy-*`
  commands Nixarchy does not replace.

## Which one is it?

Ask: **would this happen on Arch?**

- **Yes, it would happen on Arch too** -> it is Omarchy's. Reproduce it on stock
  Omarchy if you can, and report it upstream.
- **No, it is specific to NixOS** -> it is Nixarchy's. Anything involving the Nix
  store, a rebuild, `nixarchy-apply`, `apps.nix`, a missing binary at a hardcoded
  `/usr` path, or a command that works on Arch and not here.

A quick check that settles most cases — whether the failing command is one Nixarchy
replaced:

```bash
head -20 "$(which omarchy-<command>)"
```

Replacements carry a header comment explaining what they replace and why. If the
command is a replacement and it misbehaves, it is Nixarchy's. If it is upstream's
and it misbehaves in a way that has nothing to do with Nix, it is Omarchy's.

**When genuinely unsure, file it against Nixarchy.** The port is the newer and
thinner layer, and its maintainer can route it upstream with the NixOS detail
already attached. Filing a Nix-specific bug on `basecamp/omarchy` is asking people
to debug a distribution they do not run.

## Before Filing

Issues are for verified bugs, not support questions.

- **Omarchy feature ideas** -> <https://github.com/basecamp/omarchy/discussions/categories/suggestions>
- **Omarchy support / "is this a bug?"** -> the Discord at <https://omarchy.org/discord>
- **Nixarchy questions** -> a GitHub issue is fine; the project is small enough

Search first — a duplicate costs a maintainer more time than no report at all.

```bash
gh search issues --repo olafkfreund/nixarchy "<terms>"
gh search issues --repo basecamp/omarchy "<terms>"
```

Include closed issues. A matching issue closed as fixed, where the bug still
reproduces, is a regression — worth far more than another duplicate.

## Gathering Diagnostics

```bash
omarchy version
omarchy debug --no-sudo --print
```

For a Nixarchy report, this system detail matters more than CPU and GPU:

```bash
nixos-version                                    # channel and revision
nix flake metadata "${NIXARCHY_FLAKE:-/etc/nixos}"   # the pinned inputs
```

The locked `nixarchy` and `nixpkgs` revisions are usually the first thing anyone
will ask for, because they identify exactly what was built.

**Capture the problem on screen.** A screenshot or short recording is often worth
more than the description — see [`capture.md`](capture.md). Keep recordings short and
focused on the misbehavior. `gh` cannot upload media: save the capture and hand the
user the file path to drag into the web form.

For screen-recording failures specifically, rerun with
`OMARCHY_SCREENRECORD_DEBUG=true` and attach `/tmp/omarchy-screenrecord.log`.

## Filing

Never file unprompted. Show the user the exact title and body, and wait for a yes.
`gh auth status` must succeed; if `gh` is missing or unauthenticated, do not install
or authenticate it — hand the user the finished text instead.

```bash
gh issue create --repo olafkfreund/nixarchy --title "..." --body "..."
```

Include: what happened, what was expected, steps to reproduce, the versions above,
and the capture.

## Submitting a PR to Nixarchy

Nixarchy is a flake. There is no `/usr/share/omarchy` to develop against and no
`omarchy dev link` — the packaged tree is a read-only store path.

```bash
gh repo fork olafkfreund/nixarchy --clone
cd nixarchy
nix develop            # the dev shell: nixd, statix, deadnix, qemu, gh
```

Before pushing:

```bash
nix fmt                                          # nixfmt-tree; CI runs `nix fmt -- --ci`
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
nix build .#omarchy                              # the package
nix build .#checks.x86_64-linux.session          # the graphical session test
```

Checks are built one at a time by name, not with `nix flake check`. `nix run .#vm`
boots a smoke-test VM if a change needs to be seen.

A change to how Omarchy itself behaves belongs upstream, not here — Nixarchy tracks
Omarchy releases as a source bump, so a fix landed upstream arrives here for free,
whereas a patch carried here has to be re-applied at every bump.
