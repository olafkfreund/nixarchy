---
status: approved
issue: 1246
spec: spec/2026-10-12-1246-gliff-getting-started.md
---

# Plan: the site shows how to get started with gliff and Gliff-Manager, and its stale facts match the code

Work in the worktree `/mnt/data/vmtest/wt-1246`, on branch
`docs/1246-gliff-getting-started`. Never work in `/tmp`.

## Approved decisions, carried over

- **Docs, plus one check.** Pages under `docs/`, `docs/llms.txt` and
  `README.md` change. The only code is the new `checks.docs-lists`
  (`tests/docs-lists.nix` and one entry in `flake.nix`). No module, package or
  workflow changes.
- **No new manual page.** The gliff walkthrough is a subsection of
  `docs/manual/remote-desktop.md`. The three page lists (`docs/_config.yml`
  nav, `docs/llms.txt` Manual section, `docs/manual/index.md` table) are not
  touched.
- **Examples pin `v4.0.3-2`,** the release GitHub marks Latest.
- **ISO sizes are rounded:** "about 7 GB" for the offline image and "about
  2 GB" for the net one, everywhere. The measured sizes are 7.06/1.75 GB for
  v4.0.3-2 and 7.26/1.85 GB for v4.0.4-3. `the-iso.md`'s "5.8 GB file" and
  "18.3 GB closure" stay, because they are measurements of a specific build.
- **No screenshots,** because they would show private host names.
- **Every claim is re-checked against its source at the moment it is
  written.** The line numbers below were read on 2026-10-12 at `main`
  `1e765630`. Re-read them, and if something moved, find it by content.
- **House style:** `docs/AGENTS.md`. Match the surrounding prose: plain
  sentences, no marketing, bold lead-ins like the existing pages use.

## Steps

### 1. `docs/manual/remote-desktop.md`: "Your first session"

Insert `### Your first session` after the paragraph ending "gliff is a client
of a compositor that is already running." (around line 42) and before
"**Setup → Remote desktop → Manage gliff machines**". Leave every existing
paragraph as it is. Content, in order:

1. **On the machine you connect to:** `services.openssh.enable = true;`,
   rebuild, and log into Hyprland there. gliff is already installed unless
   `programs.nixarchy.preinstallsExclude` lists it.
2. **On the machine you sit at:** `ssh-keygen -t ed25519`, only if
   `~/.ssh/id_ed25519` does not exist, then `ssh-copy-id you@desk`. Say why it
   is required: the widget checks with ssh `BatchMode=yes`, so a machine that
   would ask for a password reads as "Login refused".
3. **How to name it:** `desk.local` on the same LAN, or the tailnet name with
   Tailscale. The widget lists tailnet machines under "On your tailnet".
4. **`ssh you@desk` once** to save its host key.
5. **Open the widget** from the bar or **Setup → Remote desktop → Manage gliff
   machines**, then **Add machine** and type `you@desk`.
6. **The status table,** below.
7. **Modes:** click the mode chip to cycle Auto → Headless → Mirror → each
   screen it reported. Auto means headless when nothing is plugged in there,
   and mirror when a display is. Use headless to work beside someone at that
   desk, and mirror to see its screen.
8. **Connect** with **Connect** or Enter. **Disconnect** is the same button
   once it reads "Connected". **Shift+Esc** inside a gliff window gives the
   keyboard back to your own desktop.

The status table is three columns: *The widget says* | *Meaning* | *Fix*.

| The widget says | Meaning | Fix |
|---|---|---|
| Connected · *mode* | a session is open | — |
| Not checked yet / Checking… | no answer yet | wait, or press R |
| Tailscale wants you to sign in again | Tailscale SSH needs a fresh login | the widget's fix opens the sign-in |
| Offline or not answering ssh | no ssh reply | the machine is off, asleep, or has no `services.openssh.enable` |
| Login refused for *user* | ssh refused your key | step 2, or the wrong user name |
| Host key not saved yet | first contact | step 4; the widget offers it |
| Host key changed — booted into another OS? | the key no longer matches | find out why first; then the widget's fix re-saves it |
| Hyprland runs as *A*, not *B* | someone else is logged in there | the fix switches to `A@host` |
| No Hyprland session running | nobody is logged in there | log in on that machine |
| gliff is not installed there | — | on nixarchy it is installed unless `preinstallsExclude` lists it |
| Ready · *arch* · *channel* | ready | — |
| Ready · gliff *x* there, *y* here | versions differ | update the older machine |

→ **Verify by:**

- **Every quoted string** matches the pinned plugin. Resolve it with
  `S=$(nix eval --raw .#nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.gliff-manager.src)`,
  then:
  - `grep -n 'machineState' -A30 $S/Panel.qml` for the statuses and their
    order;
  - `grep -n BatchMode $S/gliff-manager.sh` (expect line 50);
  - `grep -n 'Shift+Esc' $S/Panel.qml`;
  - `grep -n 'ON YOUR TAILNET\|nextMode\|resolvedMode' $S/Panel.qml`.
- **`desk.local`** rests on `grep -n 'avahi\|nssmdns4' modules/nixos.nix`
  showing both enabled.
- **The "session fix" row is left out,** because `Panel.qml` offers it only
  when `p.channel !== "nixos"`.

Traps: none beyond re-reading the source.

### 2. `docs/manual/getting-started.md`

- **a. Bug reports:** line 26, `omarchy bug-report` → `omarchy debug --no-sudo
  --print`. Line 377 already uses that form.
- **b. The offline ISO:** lines 130-133, "**Only the net image needs a
  network.**" paragraph. Keep the claim that the install needs no network, and
  add that the first rebuild of your own configuration needs a network once,
  linked to `the-iso` (source: `docs/manual/the-iso.md:75-79`).
- **c. ISO sizes:** lines 33-34, "about 1.6 GB" → "about 2 GB", and "about
  6 GB" → "about 7 GB".
- **d. Keymaps:** line 59, "Forty-five layouts" → "Forty-three layouts".
  Source: `grep -vc '^\s*#\|^\s*$' installer/brand/keymaps.txt` prints 43.
- **e. The release pin:** line 273, `v4.0.1-1` → `v4.0.3-2`.
- **f. The `#try` link:** line 381, "`#try` above" → "[`#try`](try-it-in-a-vm)"
  (there is no `#try` above on this page).
- **g. A new `## Already on your desktop` section,** between "### Then it
  gets out of the way" and "## Configuring it, once you are in". One sentence
  and a short list:
  - the guide (nixi), linked to `#the-guide`;
  - the bar widgets, linked to `plugins`. Name the package manager, GitHub and
    GitLab, herdr, Gliff-Manager, MicroVMs, Rebuild and ai-mirror, then "and
    the rest";
  - gliff, linked to `remote-desktop#your-first-session`.

  Do not rename any existing heading.

→ **Verify by:** `grep -n 'bug-report\|Forty-five\|v4\.0\.1-1\|1\.6 GB\|#try. above' docs/manual/getting-started.md`
prints nothing.

Traps: anchors `#the-guide` and `#the-iso` are linked from elsewhere. Do not
touch those headings.

### 3. The other manual pages

- **a. `docs/manual/configuration.md`:**
  - line 17: `v4.0.1-1` → `v4.0.3-2`;
  - line 65: `https://omarchy.org/manual/plugins/` →
    `https://omarchy.org/manual/shell-plugins/`;
  - lines 208-216: replace the nine `defaultPlugins` lines with one line for
    every name in `defaultPluginSet`, in this order: `rebuild`, `pkg`,
    `flatsnap`, `menu`, `podman`, `gliff-manager`, `gitlab`, `github`,
    `hyprforge`, `herdr`, `distrobox`, `microvm`, `devenv`, `plugin-browser`,
    `omatheme`, `ai-mirror`. Each is
    `programs.nixarchy.defaultPlugins.<name> = false;`. Below the block, add
    one sentence: ai-mirror is already off where you run ai-mirror's own module
    (`programs.ai-mirror.enable`), because yours wins (`modules/home.nix:2113`).
    Source for the list:
    `nix eval --json .#nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet --apply builtins.attrNames`,
    which should give 16 names. If the count differs, the code wins, and you
    record the deviation.
  - **The services table:** after the code block that ends
    `services.tailscale.useRoutingFeatures = "client";` (around line 473), add
    a table of all 11 entries of `data/services.nix`, with columns *Service* |
    *Category* | *What you write*. The third column is the exact line
    `modules/apps.nix:283-293` writes:
    - for `kind = "bundled"`: `` `programs.nixarchy.services.<id>.enable = true;` ``;
    - for `kind = "plain"`: `` `<option joined by .>.<optionAttr or enable> = true;` ``.

    `graphics32` is therefore `hardware.graphics.enable32Bit = true;`. Generate
    the rows from
    `nix eval --json --file data/services.nix --apply 'm: builtins.mapAttrs (n: v: { inherit (v) label kind category; option = v.option or null; optionAttr = v.optionAttr or "enable"; }) m'`
    rather than typing them.
- **b. `docs/manual/index.md`:**
  - line 34: the Welcome row's link → `https://omarchy.org/manual/`;
  - line 70: Flatpak and Snap, "**differs on NixOS**" → "**nixarchy only**".
- **c. Garbage collection:**
  - `docs/manual/system-snapshots.md:40-41` and `docs/manual/try-it-first.md:42-43`:
    "below 5 GiB" → "below 3 GiB, and frees until 8 GiB are free" (source:
    `installer/host.nix:178-179`);
  - in `system-snapshots.md`, after that paragraph, add one sentence: identical
    files in the store are deduplicated on a low-priority timer that runs on
    AC power only (`installer/host.nix:182-183`, `nix.optimise.automatic`).
- **d. `docs/manual/how-this-is-tested.md:170`:** `../internals/flake.md#the-same-vm-with-room-to-run-a-model`
  → `https://github.com/olafkfreund/nixarchy/blob/main/docs/internals/flake.md#the-same-vm-with-room-to-run-a-model`.
  Confirm the anchor's heading still exists in `docs/internals/flake.md`.
- **e. ISO sizes:** `docs/manual/the-iso.md:67-68,109,113`, 6.6 GB → about 7 GB
  and 1.5 GB → about 2 GB. Line 109 keeps "18.3 GB closure", and line 169
  keeps "5.8 GB". `docs/manual/try-it-in-a-vm.md:19-20`: `~6.6 GB` → `~7 GB`,
  and `~1.9 GB` → `~2 GB`.
- **f. `docs/manual/plugins.md`:**
  - line 16: delete "Others are on their way, and" and keep the rest of the
    sentence grammatical;
  - line 366: delete the italic "*Not recorded yet…#816 pass C.*" line (#816 is
    closed).

→ **Verify by:** step 6's link sweep, and
`grep -rn 'v4\.0\.1-1\|5 GiB\|6\.6 GB\|1\.5 GB\|1\.9 GB\|welcome-to-omarchy\|manual/plugins/\|internals/flake' docs/manual/`
shows only the deliberate survivors: `how-this-is-tested`'s new absolute URL.

Traps: `the-iso.md` sizes in a table must stay aligned in the Markdown, so
check how it renders.

### 4. `docs/index.md`, `docs/llms.txt`, `README.md`

- **`docs/index.md`:**
  - line 168: `omarchy bug-report` → `omarchy debug --no-sudo --print`;
  - line 202: keep "an install needs no network", and add that the first
    rebuild needs it once, pointing to the-iso.
- **`docs/llms.txt`:**
  - lines 69-70: the same offline correction;
  - line 117 (Try It First): "until garbage collection nobody schedules" →
    "until the automatic garbage collection on an installed machine";
  - in the key-facts list (the bullets under line 50), add a bullet saying
    nixi, the guide, is on by default: a card over the desktop with a tour and
    a tutor grounded in the machine, from the snowflake in the bar or `nixi`.
    `services.nixi.enable = false` removes it. Source: `README.md:517`.
- **`README.md`:**
  - line 238: the bug-report command;
  - lines 258 and 658: `v4.0.1-1` → `v4.0.3-2`. Lines 668-670 explain the tag
    scheme with `v4.0.1-*` as examples, and stay;
  - lines 323, 335-336, 360-361: sizes rounded as above;
  - line 496: ai-mirror "**Coming**" → "**On by default**".

→ **Verify by:** `.github/scripts/readme-counts.sh --check`, run as a script
under bash.

Traps:
- **The sidebar guard** (`build.yml`, "Every manual page is in the sidebar")
  greps `docs/llms.txt` and `README.md` for `manual/<page>` links. Any new
  link must name an existing page.
- **README counts** are guarded. If `readme-counts.sh` refuses, read why
  (AGENTS.md §4) rather than editing numbers to satisfy it.

### 5. `checks.docs-lists`

**Create `tests/docs-lists.nix`:**

```nix
{
  pkgs,
  pluginNames, # builtins.attrNames of defaultPluginSet
  services, # import ../data/services.nix
  doc, # ../docs/manual/configuration.md
}:
```

It is a `pkgs.runCommand "nixarchy-docs-lists"`, with `set -euo pipefail`.
Pass the expected lines in with `pkgs.writeText` (one per line), not
interpolated into a heredoc (AGENTS.md §5: a heredoc reindents the file under
`nix fmt`). There are two lists:

- plugins: `"programs.nixarchy.defaultPlugins.${n} = false;"` for each name;
- services: the same rule as `modules/apps.nix:288-291`, bundled →
  `programs.nixarchy.services.${n}.enable = true;`, plain →
  `${concatStringsSep "." option}.${optionAttr or "enable"} = true;`.
  Copy the rule with a one-line comment pointing at `apps.nix`.

For each line, `grep -qF -- "$line" "$doc"`. Collect the misses, print
`FAILED: configuration.md does not mention <line>` for each, and fail if there
are any. Fail too if either list is empty (an empty list is not a pass,
AGENTS.md §4). Add a 1–3 line header comment saying why it exists: #1246, the
plugin list drifted to 9 of 16.

**Wire it in `flake.nix`** next to `qml` (around line 2368):

```nix
docs-lists = import ./tests/docs-lists.nix {
  pkgs = pkgsFor.${system};
  pluginNames = builtins.attrNames self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet;
  services = import ./data/services.nix;
  doc = ./docs/manual/configuration.md;
};
```

**No workflow edit.** The `omarchy` job's "Build every check no other job
claims" step picks it up (AGENTS.md §4).

**Verify under the §1 contract** (cheap tier: run under
`flock /mnt/data/vmtest/codex-build.lock`):

1. Commit a known-good baseline first. A temporary subject is fine (§8).
2. Delete the `defaultPlugins.hyprforge` line from `configuration.md`. Run
   `git diff` to prove the break landed, then `git add -A` and
   `nix build .#checks.x86_64-linux.docs-lists -L`. It must fail, naming
   hyprforge. Capture the output.
3. Restore with `git checkout HEAD -- docs/manual/configuration.md`. Do not
   use `git checkout --`, because that restores the index, which holds the
   break (§5).
4. Delete the `hardware.graphics.enable32Bit` row. It must fail, naming it.
   Capture, then restore the same way.
5. Rebuild clean. It must pass.
6. Run `git diff --cached` and `git status` to confirm nothing broken is left
   staged.

Traps:
- **New files:** `git add` `tests/docs-lists.nix` before building (§5, an
  untracked file "does not exist").
- **Formatting:** run `nix fmt` after editing `.nix` files. The owner's hook
  may have run `nixpkgs-fmt`, so read `git diff --stat` (§5).
- **`statix` and `deadnix`** must stay clean.

### 6. Guards, links, rendering

Run under bash, one at a time:

- `.github/scripts/readme-counts.sh --check`;
- the sidebar guard: copy the `run:` block of "Every manual page is in the
  sidebar" from `.github/workflows/build.yml` into a scratch script with
  `#!/usr/bin/env bash` and run it;
- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
  `nix run nixpkgs#deadnix -- --fail .`;
- **the link sweep:**
  `grep -oh 'https://omarchy.org/manual/[^)]*' docs/manual/*.md docs/index.md README.md | sort -u | while read u; do c=$(curl -s -o /dev/null -w '%{http_code}' -L "$u"); [ "$c" = 200 ] || echo "$c $u"; done`
  prints nothing;
- **rendering:**
  `nix shell nixpkgs#jekyll -c jekyll build -s docs -d <scratch>/site`. If the
  theme or gems make that fail, record it as a deviation and check the two new
  tables by reading the Markdown, then on the live site after merge.

### 7. Commit and PR

- One commit, with a full-sentence subject (no prefix), for example: "The site
  walks through a first gliff session, and its stale facts match the code".
  Squash the step 5 baseline into it.
- Check `git merge-base origin/main HEAD` against current `origin/main`, and
  rebase if `main` moved (§9).
- Open the PR, filling in the template. It must:
  - link the intent, spec and plan;
  - include the step 5 failing outputs;
  - list which steps the coder did;
  - use `Closes #1246`.
- Before opening, read new messages on the agent bus (§9). Post only if
  something non-obvious was learned.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.docs-lists -L` | passes. It fails naming the item with one plugin line or one services row removed |
| `.github/scripts/readme-counts.sh --check` | passes |
| the sidebar guard script | passes |
| `nix fmt -- --ci`, statix, deadnix | clean |
| the link sweep | no output |

## Rollback

Revert the squashed commit. Nothing outside `docs/`, `README.md`,
`tests/docs-lists.nix` and the one `flake.nix` entry changes, and no deployed
machine reads any of them.

## Deviations recorded during implementation

- **Step 1:**
  - The tailnet heading is quoted as "ON YOUR TAILNET", because the widget
    renders it in capitals (`Panel.qml:675`).
  - Add machine is described as the field (placeholder `user@host`) plus Enter
    or the **Add machine** button, because it is an icon button.
  - avahi is at `modules/nixos.nix:1588-1590`, not 635-639 (the spec cited the
    `data/services.nix` comment's stale numbers). The fact holds.
- **Step 3e:** `the-iso.md` also said the net image is small "rather than
  5.6". That became "rather than 7" under the same rounding rule.
  `the-iso.md`'s paragraph is wrapped so that "The 68 selectable apps are the
  exception" stays on one line, because `readme-counts.sh`'s `apps-iso`
  pattern needs it that way.
- **Step 5:**
  - `docs-lists` sits after the `qml` entry, before the next comment block,
    so `qml` is not separated from its own comment.
  - The §1 breaks were restored by copying a saved `configuration.md` back
    (confirmed identical with `cmp`) rather than `git checkout HEAD --`,
    because the coder agent cannot commit a baseline.
- **Steps 1–6** were done by the `coder` agent. The commit and the PR are the
  session model's.
- **After the independent review:**
  - `checks.docs-lists` matched lines anywhere on the page, so the OpenSSH and
    Tailscale rows could vanish unseen (both lines also appear in the text
    above the table). Plugin lines now match a whole line (`grep -qxF`), and
    services match their table cell (`| \`<line>\` |`). The §1 proof was
    re-run with the Tailscale row removed, and it fails naming it.
  - `remote-desktop.md` gains `### Managing your machines` after the status
    table, so the existing paragraphs (the clipboard warning among them) no
    longer sit under "Your first session".
  - Step 8 says Connect and Disconnect are icon buttons, and that on a
    warning row they run the fix (`primaryAction`).
  - The two adjacent "The ISO" links are relabelled or dropped.
  - **The release pin:** `v4.0.3-2` predates gliff and `defaultPlugins`
    (`git grep` at the tag finds neither). By the user's decision the pin
    stays, and each pinned example (`configuration.md`, `getting-started.md`,
    README twice) gets one sentence pointing to `main` until a later release
    is marked Latest.
  - `tests/AGENTS.md` gains "A list check must look where the item lives",
    the general lesson from the review finding. This follows the repo's
    write-back rule ("same PR").
