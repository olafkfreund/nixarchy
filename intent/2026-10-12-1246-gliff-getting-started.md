---
status: approved
issue: 1246
author: olafkfreund
---

# Intent: the site shows how to get started with gliff and Gliff-Manager, and its stale facts match the code

## Problem

gliff is installed by default (#1227), and Gliff-Manager is a default bar widget
(#1239). The site describes both as reference: `remote-desktop.md` has the
command, the two modes, what the target needs and `gliff-probe`, and
`plugins.md` lists what the widget does and how to turn it off. Nobody new to
either can follow those sections from nothing to a working session. Missing
are the steps before the first connect (an ssh key on the target, sshd
enabled there, how the target is reached), what the widget's statuses mean and
how to fix each, when to choose headless or mirror, and how to disconnect.
Getting Started never mentions gliff, Gliff-Manager or any default bar widget,
so a new user does not learn they are there.

A review of the whole site on 2026-10-12 also found facts that the code no
longer supports:

- **A command:** Getting Started and the front page tell users to run
  `omarchy bug-report`, which does not exist.
- **The offline ISO:** they say it needs no network, but its first rebuild
  does (#1218).
- **Numbers and pins:**
  - the garbage-collection threshold is given as 5 GiB, but the code uses 3,
    freeing up to 8;
  - the release pin `v4.0.1-1` is stale;
  - the page says 45 keymaps, but there are 43;
  - the ISO sizes disagree with the release files.
- **Plugins:** the opt-out list in `configuration.md` names 9 of the 16
  defaults.
- **Dead links:** two links on the live site are dead.
- **Small stale bits:** a handful of status notes and labels no longer hold.
- **Not on the site:** the services catalogue has no list, `llms.txt` omits
  nixi, and the README still calls ai-mirror "Coming".

Each of these is a user following the site and hitting a wall: a command that
fails, a number that is wrong, a link that 404s.

## Proposed outcome

- **gliff:** a reader with two nixarchy machines can follow one page from
  nothing to a gliff session, with Gliff-Manager or without it, and fix what
  the widget reports.
- **Getting Started:** a new user learns from it what is already on their
  desktop, gliff and the widgets included, with links to the pages that
  explain each.
- **Facts:** every fact in issue #1246's list matches the code or the
  published release. Each change cites the line in the code or the release
  that it rests on.

## Affected users and systems

- **Readers:** of the site, https://olafkfreund.github.io/nixarchy/, and of
  the README.
- **Pages:**
  - `docs/manual/`: `remote-desktop.md`, `plugins.md`, `getting-started.md`,
    `configuration.md`, `system-snapshots.md`, `try-it-first.md`,
    `the-iso.md`, `how-this-is-tested.md`, `index.md` and `other-packages.md`;
  - `docs/index.md` and `docs/llms.txt`;
  - `README.md`.
- **Code:** none changes.

## Constraints

- **Docs only.** No module, package or workflow changes.
- **The house style** in `docs/AGENTS.md` applies.
- **The three lists stay in agreement:** the sidebar, `manual/index.md` and
  `llms.txt`. CI enforces that.
- **README counts:** `readme-counts.sh` guards them, and must still pass.
- **Every factual claim is checked against the code** before it is written,
  not copied from the review: §12 says search for the behaviour.
- **Gliff-Manager's statuses** are described from the plugin's own source
  (`Panel.qml`, `gliff-manager.sh` at the pinned fork commit), not from memory.
- **Screenshots** of the widget would show private host names. None is taken
  here. Whether to add a scrubbed one later is an open question.

## Open questions

1. **Where the gliff getting-started section lives.** The choice is between
   inside `remote-desktop.md`, where gliff already is, and a new manual page
   such as `gliff.md`. A new page means changing the three lists. Proposed:
   keep it in `remote-desktop.md`, as a step-by-step "First session" section.
2. **The release to pin in the examples.** The choice is between v4.0.3-2,
   the newest that is not a pre-release, and v4.0.4-3, the newest tag, which
   is a pre-release. Proposed: v4.0.3-2, since the examples are for people
   who want stable.
3. **The services catalogue table,** which is the one item that adds content
   rather than fixing it. The choice is between including it here and filing
   it on its own. Proposed: include it, since it is a short table generated
   by hand from `data/services.nix`.
