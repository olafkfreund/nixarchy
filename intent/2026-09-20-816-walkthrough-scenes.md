---
status: approved
issue: 816
author: olafkfreund
---

# Intent: everything the site claims can be watched happening

Closes #816.

## Problem

`tests/demo/` records nine gated scenes and the site publishes seven GIFs. The
front page describes roughly twice that many features, and for the rest a reader
has only the assertion that they exist.

The gap is not evenly spread. It is almost exactly the work of the last month:
**Podman, herdr, the package manager panel, GitHub Actions and GitLab
Pipelines** are all on by default since #770, #772, #803 and #804, and none of
them appears in a single moving picture. Confirmed in a fresh-install VM today —
all five nixarchy panels are enabled at first login, and every still on the site
predates every one of them.

Three ordinary things the page also only describes: **adding a package**,
**enabling a service**, and **more than one MicroVM template**. The MicroVM
panel exists to choose between templates and the one recording shows one.

And an agent working. The page says sixteen skills, a local model and ten things
you can click; it shows a menu.

## Proposed outcome

A scene for each, recorded the way the existing nine are: driving the real
desktop in a VM, gated by `verify-frames.sh` on both OCR text and a diversity
floor, under the 1 MB rule. A reader can watch every headline claim happen.

Where a scene cannot be recorded honestly, the page **says the feature is not
shown** rather than implying it with a still.

## Affected users and systems

Readers of the site and the manual. `tests/demo/` gains scenes and at least one
node variant; `docs/img/features/` gains GIFs. Nothing changes on an installed
machine, and no check in CI depends on any of this — `demo-record` is run by
hand.

## Constraints

- **No credentials in any VM that is recorded.** `gh` and `glab` included: those
  two panels record their "authenticate first" state, which is what a new user
  sees on first open anyway. This is the constraint that decides the agent scene
  below.
- **Demo data only**, created inside the VM and named `demo-*`.
- **Honest gates.** `expects` must be strings that only appear when the thing
  really ran — the `boxes` scene insists on the prompt *inside* the container
  rather than a word that scrolls past, and `microvm` had to allow `dev@de[mn]o`
  because tesseract misreads the guest prompt. A recording of the wrong thing
  must fail its own gate.
- **The demo node cannot host all of this as it stands.** It is 4 GB and 4 cores
  with neither `virtualisation.podman` nor `services.boxes`, which is precisely
  why those panels are gated off in it. Podman and the boxes work need an
  `extraNode`; the agent scene needs far more than a variant (below).
- **Online where it must be.** `boxes` and `microvm` already run unsandboxed
  because an image pull and a flake fetch need a real network. Anything pulling
  a container image joins them.

## The agent scene, and the reason it is the hard one

The obvious way to record an agent is to put a real auth token in the VM. That
is the one thing `docs/AGENTS.md` warns against: herdr lists real session names
and what each agent is doing, and a published recording of an authenticated
session cannot be sanitised afterwards.

It is also avoidable. `vm-big` already sets `programs.nixarchy.localAi` to
`qwen3:8b`, and `codex` and `opencode` are both packaged
(`data/apps.nix:361,369`). An agent driven by the **local model** needs no
login, gives herdr genuine sessions to show, and demonstrates `localAi.enable` —
which the front page advertises and no picture has ever shown.

The cost is real and should not be glossed: `vm-big` is 32 GB and 8 cores
*because* 8b is the smallest size shown to follow the skills rather than answer
from memory, and on a VM's CPU it is slow. A scene has to warm the model before
recording starts and show a short exchange. It is also the one scene whose
runtime depends on the host, which makes it the least reproducible thing here.

## Open questions

1. **One pass or several PRs?** Nine or so scenes is a large change and each has
   its own red-then-green. Podman, herdr and the pkg panel share a node and
   belong together; the agent scene is its own thing.
2. **Is the "authenticate first" state worth recording** for GitHub Actions and
   GitLab Pipelines, or is a still honest enough? It is a true first-run state
   and it is also thirty seconds of a panel saying no.
3. **Does the agent scene earn its cost** — a 32 GB node and a slow local model —
   against a still of the same panel with a session in it? The moving version
   proves the thing works; the still cannot.
4. **Nested virtualisation** is required for the MicroVM template scenes to show
   a guest doing anything. If the recording host cannot nest, the scene must fail
   loudly rather than record an empty list.
