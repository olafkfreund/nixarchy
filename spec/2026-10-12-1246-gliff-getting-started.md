---
status: draft
issue: 1246
intent: intent/2026-10-12-1246-gliff-getting-started.md
---

# Spec: the site shows how to get started with gliff and Gliff-Manager, and its stale facts match the code

Decisions carried from the approved intent: the gliff walkthrough lives in
`remote-desktop.md` (no new page, the three lists are untouched); examples pin
`v4.0.3-2`, the release GitHub marks Latest; the services table is included.

Every fact below was checked on 2026-10-12 against `main` at `1e765630`, the
pinned Gliff-Manager source (`nixarchy-gliff-manager-0.1.0-nixarchy.2`) and the
published releases. The source is named beside each fix.

## Design

### A. gliff: a first session, in `remote-desktop.md`

Add a `### Your first session` subsection inside "Between two nixarchy machines:
gliff", after the `services.openssh.enable` paragraph (line 42) and before the
"Manage gliff machines" paragraph. The existing reference paragraphs stay as
they are. Steps:

1. **On the machine you connect to:** `services.openssh.enable = true;`,
   rebuild, and log into its Hyprland session. If gliff was removed there with
   `preinstallsExclude`, it needs gliff back.
2. **On the machine you sit at:** an SSH key, and the key on the target:
   `ssh-keygen -t ed25519` (only if `~/.ssh/id_ed25519` is missing), then
   `ssh-copy-id you@desk`. This is required, not a convenience: the widget
   probes with `-o BatchMode=yes` (`gliff-manager.sh:50`), so a target that
   would ask for a password reads as "Login refused".
3. **How the target is named.** On a LAN, `desk.local` (avahi with nssmdns4 is
   on for every nixarchy machine, `modules/nixos.nix:635-639`). On a tailnet,
   the MagicDNS name, and the widget lists tailnet machines under "On your
   tailnet" (`Panel.qml:675`). The implementation re-reads the line numbers
   before it cites them.
4. **`ssh you@desk` once in a terminal** to save the host key. The widget
   offers the same thing as its fix for "Host key not saved yet".
5. **Add it in the widget:** open it from the bar or **Setup ▸ Remote desktop ▸
   Manage gliff machines**, then **Add machine** and type `you@desk`.
6. **Read its status**, using the table below.
7. **Pick a mode.** Click the mode chip to cycle Auto, Headless, Mirror, then
   each screen the machine reported (`nextMode`, `Panel.qml:118`). Auto picks
   headless when nothing is plugged in there and mirror when a display is
   (`resolvedMode`, `Panel.qml:96`). Use headless to work beside someone at
   that desk, and mirror to see what is on its screen.
8. **Connect, and disconnect.** Use **Connect**, or Enter. **Disconnect** is
   the same button once the machine reads "Connected". Inside a gliff window,
   **Shift+Esc** gives the keyboard back to your own desktop (`Panel.qml:866`).

**The status table** has one row per verdict in `machineState`
(`Panel.qml:128-155`), in the order the widget checks them, each with what it
means and the fix:

| The widget says | Meaning | Fix |
|---|---|---|
| Connected · *mode* | a session is open | — |
| Not checked yet / Checking… | no probe has come back | wait, or press R to recheck |
| Tailscale wants you to sign in again | Tailscale SSH needs a fresh login | the widget's fix opens the browser sign-in |
| Offline or not answering ssh | no ssh reply within the timeout | the machine is off, asleep, or has no `services.openssh.enable` |
| Login refused for *user* | ssh refused the key | step 2, or the wrong user name |
| Host key not saved yet | first contact | step 4 (the widget's fix) |
| Host key changed — booted into another OS? | the key no longer matches | check why before you trust it; the widget's fix re-saves it |
| Hyprland runs as *A*, not *B* | someone else is logged in there | the fix switches the target to `A@host` |
| No Hyprland session running | nobody is logged in there | log in on that machine |
| gliff is not installed there | gliff is missing on the target | on nixarchy it is installed unless `preinstallsExclude` removes it |
| Ready · *arch* · *channel* | everything checks out | — |
| Ready · gliff *x* there, *y* here | versions differ | update the older machine |

The "session fix" row is left out because it is never offered on NixOS
(`Panel.qml:153`, `p.channel !== "nixos"`).

No screenshot (intent constraint: it would show private host names).

### B. Getting Started: what is already on your desktop

Add a short `## Already on your desktop` section to `getting-started.md`
between "Then it gets out of the way" and "Configuring it, once you are in".
It is one sentence and a list of links, not a feature tour:

- the guide (nixi), linked to `#the-guide`;
- the bar widgets, linked to `plugins` (the package manager, GitHub and GitLab,
  herdr, Gliff-Manager, MicroVMs, Rebuild, ai-mirror and the others);
- gliff, linked to `remote-desktop#your-first-session`.

Existing headings and anchors are unchanged. `#the-guide` is linked from the
README, and `#the-iso` is linked from elsewhere on the page.

### C. Facts, each against its source

| # | Where | Now | Becomes | Source |
|---|---|---|---|---|
| 1 | `getting-started.md:26`, `index.md:168`, `README.md:238` | `omarchy bug-report` | `omarchy debug --no-sudo --print` | `omarchy-debug` in the omarchy package; `troubleshooting.md:126` already says so |
| 2 | `getting-started.md:130-133`, `index.md:202`, `llms.txt:69-70` | "installs with no network at all" | keep "installs offline", add "its first rebuild needs a network, once", linked to `the-iso` | `the-iso.md:75-79` (#1218) |
| 3 | `getting-started.md:273`, `configuration.md:17`, `README.md:258`, `README.md:658` | `v4.0.1-1` | `v4.0.3-2` | `gh release list`: Latest. README 668-670 explain the tag scheme with `v4.0.1-*` as worked examples, and stay |
| 4a | `system-snapshots.md:40-41`, `try-it-first.md:42-43` | "below 5 GiB" | "below 3 GiB, and frees until 8 GiB are free" | `installer/host.nix:178-179` |
| 4b | `llms.txt:117` | "garbage collection nobody schedules" | collection is automatic on installed machines | same |
| 4c | `system-snapshots.md`, after the GC paragraph | dedup mentioned nowhere | one sentence: identical store files are deduplicated on a low-priority timer that runs only on AC power | `installer/host.nix:182-183` (#1136) |
| 5a | `how-this-is-tested.md:170` | link into `internals/flake.md`, which is excluded from the site (`_config.yml:27`) | an absolute GitHub blob link to the same file and anchor | `_config.yml:22-27` |
| 5b | `manual/index.md:34` | `omarchy.org/manual/welcome-to-omarchy/` (404) | `https://omarchy.org/manual/` | curl, 2026-10-12 |
| 5c | `configuration.md:65` | `omarchy.org/manual/plugins/` (404), not in the issue, found while checking | `https://omarchy.org/manual/shell-plugins/` | curl, 2026-10-12 |
| 6 | `configuration.md:208-216` | 9 of the defaults | all 16, in `defaultPluginSet`'s order, with the ai-mirror exception noted | `modules/home.nix:1911-2113` |
| 7a | `getting-started.md:59` | "Forty-five layouts" | "Forty-three" | `installer/brand/keymaps.txt`: 43 entries (#1127) |
| 7b | `getting-started.md:33-34`, `the-iso.md:67-68,109,113`, `README.md:323,335-336,360-361`, `try-it-in-a-vm.md:19-20` | 6, 6.6, 1.5, 1.6, 1.9 GB | "about 7 GB" offline, "about 2 GB" net, everywhere | v4.0.3-2: 7.06 / 1.75 GB; v4.0.4-3: 7.26 / 1.85 GB |
| 8a | `getting-started.md:381` | "`#try` above", with no `#try` above | link to `try-it-in-a-vm` | the page outline |
| 8b | `plugins.md:16` | "Others are on their way" | removed | — |
| 8c | `plugins.md:366` | "Not recorded yet … #816 pass C" | removed, since #816 is closed and nothing is recorded | `gh issue view 816` |
| 8d | `manual/index.md:70` | Flatpak and Snap: "differs on NixOS" | "nixarchy only" | upstream has no such page; the label means the same as the other nixarchy-only rows |
| 8e | `README.md:496` | ai-mirror: **Coming** | **On by default** | `modules/home.nix:2100-2113` |
| 9 | `configuration.md`, after line 473 | no list of services | a table of all 11 entries: label, category, and the line you write | `data/services.nix` |
| 10 | `llms.txt` key facts | no nixi | one bullet: nixi, the guide, on by default, `services.nixi.enable = false` removes it | `README.md:517` |

**Rounding the ISO sizes (7b)** is deliberate. The sizes change with every
release, and an exact figure is stale by the next one. Approximate figures
hold until the image crosses a whole gigabyte.

`the-iso.md:169`'s "one 5.8 GB file" and `:109`'s "18.3 GB closure" are
measurements of a specific build, and stay. They are not in the issue, and
re-measuring them needs an ISO build.

### D. A check for the two lists that drifted

The plugin opt-out list drifted from 16 to 9 because it is a hand-maintained
list with no comparison (AGENTS.md §4, "a hand-maintained list fails OPEN"). The
new services table is the same shape. So add `checks.docs-lists`, a
`runCommand` that fails, naming the missing item, when:

- a name in `defaultPluginSet` (from `nixosConfigurations.vm`, as
  `flake.nix:2372` already reads it) has no
  `programs.nixarchy.defaultPlugins.<name>` line in `configuration.md`;
- an attribute in `data/services.nix` has no row in the services table.

This touches `tests/docs-lists.nix` and one line in `flake.nix`'s `checks`, but
no workflow. The "Build every check no other job claims" step runs it on pull
requests (§4). That goes slightly past the intent's "docs only", which is why
it is called out here for approval rather than assumed.

## Alternatives rejected

- **A new `gliff.md` page.** Rejected at intent approval, because it means
  changing the three lists, and gliff already has a home.
- **Generating the services and plugins tables at build time.** Jekyll on
  classic Pages cannot evaluate Nix, and a generated-file commit step is a
  workflow change. The check in D gives the same guarantee with no build
  machinery.
- **Exact ISO sizes, updated every release.** That is one more
  hand-maintained number, which goes stale by the next release.
- **Linking `how-this-is-tested.md` to a published copy of `internals/`.**
  `_config.yml` excludes it on purpose. A GitHub link is what the other
  internals pointers do.
- **Documenting the "session fix".** Rejected because it is never offered on
  NixOS.

## Risks

- **The README is guarded by `readme-counts.sh`.** Edits to rows and numbers
  could trip it. Run it before pushing.
- **The three lists:** no page is added or renamed, so they are unaffected.
  The guard in `build.yml` still runs.
- **Anchors:** `#your-first-session` is new. No existing heading changes, so
  no inbound link breaks.
- **Gliff-Manager is a fork that moves.** The status table describes
  `0.1.0-nixarchy.2`. A later fork bump that rewords a status leaves the table
  stale, with nothing red. That is accepted, and the bump's own PR is where it
  gets caught; checking it is not worth a QML parser.
- **`checks.docs-lists` evaluates the vm config.** That is evaluation only, in
  the same class as other `vm`-reading checks, not `options`' 11.5 GB.

## Verification

- **Facts:** every row in C re-checked at implementation time against the
  cited source. Line numbers are re-read, not trusted from this spec.
- **Links:** every `omarchy.org/manual/*` URL on the site returns 200
  (`curl -sL -o /dev/null -w '%{http_code}'` over the grep, as done for this
  spec, where it found 5b and 5c).
- **`checks.docs-lists`, under the §1 contract:**
  1. Delete one `defaultPlugins.<name>` line and see the check fail, naming it.
  2. Delete one services row and see it fail, naming it.
  3. Restore, with `git checkout HEAD --`, and see it pass.

  The failing output goes in the PR.
- **Guards:** `readme-counts.sh`, the manual-pages-in-sidebar check (as
  `build.yml` runs it), `nix fmt -- --ci`, `statix` and `deadnix` all pass.
- **Rendering:** Jekyll builds locally, or the PR's Pages preview does, and the
  new section and both tables render.
