---
status: draft
issue: 801
intent: intent/2026-09-18-766-default-plugins.md
---

# Spec: retire the `nixarchy box` CLI

The intent is #766's, which is approved and already decided this: *"`nixarchy
box` is retired once the distrobox plugin creates boxes from nixarchy's
templates. The CLI (`pkgs/box.nix`, `nixarchy-box`), its menu rows and the
`box` verb in the `nixarchy` dispatcher go."* #801 is the tracking issue split
out of it so #766 could close.

## What #801 said was blocking, and what is actually true

#801 listed three things the panel had to gain first. Checked against the tree
rather than against the issue text (§12: search for the behaviour):

| #801's blocker | state |
| --- | --- |
| `promote` — turn a box into a `services.boxes.machines` entry | **landed.** `nixarchy-distrobox` `dd9e89c`, which is the rev `flake.nix:243` already pins |
| a `--check` equivalent — the menu's availability gate | **never needed.** `modules/apps.nix:704` already gates the Boxes row on `when = "nixarchy-plugin --enabled nixarchy.distrobox"`. `nixarchy box --check` has **zero callers** anywhere in the tree |
| `list` — machine-readable, like `nixarchy vm list --json` | **no consumer.** Nothing calls `nixarchy box list` programmatically; it is `distrobox list` printed verbatim for a human |

So nothing is blocked on `nixarchy-distrobox`, and **no work is proposed in
that repository**. The templates are already wired: `modules/services/boxes.nix`
writes `/etc/nixarchy/box-templates.ini` and `modules/home.nix:291` points the
panel's `templatesFile` at it.

The remaining question is therefore not "can the panel do it" but "does
anything still need the CLI", and the answer is a terminal habit rather than a
capability.

## Design

### 1. What goes

- `pkgs/box.nix` — the whole file.
- `nixarchy-box` in `flake.nix:973`, and the `nixarchyBox` argument threaded
  into the checks at `flake.nix:2248`.
- The `box` verb in the `nixarchy` dispatcher.
- README's two rows naming `nixarchy box create` (`:47`, `:460`), and the CLI
  half of `docs/manual/boxes.md`.

### 2. What stays, and why

- **`data/box-templates.nix`** — the single source of templates, which
  `boxes.nix` renders for the panel. A retired command cannot export it; the
  file is what both the panel and the checks read.
- **`services.boxes.machines`** — declared boxes never went through the CLI.
- **The Boxes menu row** — already the panel, already gated on the plugin.

### 3. The two checks, which is the only hard part

`checks.box-template` and `checks.box-boot` test **through the CLI** today:
`tests/box-boot.nix:95` runs `nixarchy box create`, and
`tests/box-template.nix:92` greps `${nixarchyBox}/bin/nixarchy-box` for a baked
`/nix/store` distrobox path.

They are retargeted at the path the panel takes — `distrobox assemble` against
the generated `/etc/nixarchy/box-templates.ini` — so box creation stays tested
end to end rather than losing coverage as a side effect of a deletion.

`tests/box-template.nix`'s no-baked-store-path assertion is about a **script**
and has no panel equivalent: the plugin is QML and resolves `distrobox` through
`PATH` at runtime by construction. That assertion goes with the script it was
written for, and the spec says so rather than letting it disappear quietly.

### 4. This needs a human for the workflow half

Both checks are **claimed**, not generated: named explicitly in `build.yml` at
`:1293` and `:1503`, and `generated-checks.sh` does not list them (verified —
it returns 0 matches for either name). So renaming or dropping them is a
CI-gate change, and AGENTS.md §4 and §11 say a human merges that.

The PR carries the `build.yml` edit; it does not get merged by an agent.

## Alternatives rejected

- **Write `--check` and `list --json` in `nixarchy-distrobox` first.** This was
  the plan until the callers were counted. Building two features with no
  consumer, in another repository, to unblock a deletion that is not blocked,
  is work that looks like progress.
- **Keep the CLI as a thin wrapper over the panel.** Two surfaces to keep
  working for one job, and the wrapper would still need the checks retargeted.
- **Delete the checks along with the CLI.** Coverage lost by accident. Box
  creation is the thing users do; that it happened to be tested through a
  command being removed is an implementation detail of the test, not a reason
  to stop testing it.
- **Leave the CLI in place and close #801 as won't-do.** Defensible, and
  rejected by #766's approved intent, which decided the retirement.

## Risks

- **Somebody's muscle memory.** `nixarchy box create dev` stops working. The
  manual and README must say what replaces it (Super+Alt+D, or the Boxes row),
  and the removal should be in release notes rather than only in a diff.
- **The retargeted checks might test less than the old ones.** The old ones
  exercised a script this repo owns; the new ones exercise a plugin pinned by
  rev. A plugin bump could change the create path without any check here going
  red. Worth stating in `tests/AGENTS.md` as a known reduction rather than
  discovering it later.
- **`readme-counts.sh`.** Removing README rows moves counts, and that guard
  refuses on a count it cannot spell. Run it before pushing.
- **The `box` verb's absence must be a readable error**, not a silent nothing:
  `nixarchy box` should say where boxes live now, for one release at least.

## Verification

1. `nix build .#nixarchy` — the dispatcher builds without the verb.
2. `nix flake show` no longer lists `nixarchy-box`.
3. `checks.box-template` and `checks.box-boot` pass in their retargeted form,
   and **are proved to fail** (§1) by pointing them at a template that does not
   exist — the failing output goes in the PR.
4. `checks.menu-verbs` still passes: `tests/menu-verbs.nix:135` knows the box
   rows go through `nixarchy box <verb>` and must be updated with them.
5. `readme-counts.sh` green.
6. `nixarchy box` prints a pointer rather than "command not found".
7. A booted `.#vm`: Super+Alt+D opens the panel, and a box can be created from
   a nixarchy template through it — the thing the CLI used to do.

Step 7 is by hand. Steps 1–6 are CI's, with the workflow edit merged by a
human.
