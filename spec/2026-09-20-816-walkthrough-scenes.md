---
status: draft
issue: 816
intent: intent/2026-09-20-816-walkthrough-scenes.md
---

# Spec: three passes of scenes, and one panel that a gate says to leave still

## Design

New entries in `sceneDefs`, written the way the existing nine are: a `script`
from `segments`, `expects` as OCR regexes that only appear when the thing really
ran, a `minDistinct` floor, `online` where a network is needed, and `extraNode`
for what the base node lacks.

The intent's open questions are settled here, with the reasoning, because each
one changes what gets built.

### 1. Three passes, not one

Split by the node each group needs, since that is the real cost:

- **A — the panels that share a node.** Podman, herdr and the package manager.
  One `extraNode` with `virtualisation.podman.enable` and
  `services.boxes.enable`, `online` (an image pull), a bigger disk as the
  `boxes` scene already needs (its 1 GB root died staging blobs in `/var/tmp`).
  Three scenes, one node, one review.
- **B — the flows on the base node.** Adding a package, enabling a service, and
  MicroVM templates. These need no new services, only script.
- **C — the agents.** Nixi on `SUPER + H` and a terminal agent, both against
  the local model. Its own node, its own PR, and its own decision to make
  (below).

### 2. GitHub Actions and GitLab Pipelines stay stills — the gate says so

Not a judgement call in the end. Their first-run state is a panel displaying one
unchanging "authenticate first" message. `verify-frames.sh` enforces a
**diversity floor**, and the `plugin` scene's history is the precedent: its
first gated recording failed at *0 of 11 transitions* because eighteen frames in
which one tray icon appears "is a GIF of nothing", and the fix recorded in the
tree was **a scene that shows the command doing the work, not a lower bar**.

A motionless panel cannot clear that floor honestly, and lowering the floor to
admit it is the move that file explicitly refuses. So these two get stills, and
the page says they are shown still rather than implying otherwise.

### 3. The agent scene is measured before it is written

It goes last, and it is **gated on a measurement rather than an intention**:
record time-to-first-token for `qwen3:8b` on the recording host, and the wall
clock for one short exchange.

- If a useful exchange completes inside roughly 40 seconds of wall clock, the
  scene is written and the measurement goes in the PR.
- If it does not, the outcome is **a still of herdr with a real local-model
  session in it**, and the page says the agent is not shown moving.

**Nixi is part of this scene, and is the better half of it.** `SUPER + H` is
the desktop's own help agent: an overlay that reaches an agent through an ACP
adapter, which is why it has the same requirement as anything else here — a
working backend. It is also the one an ordinary reader would actually use,
because it is a keybinding rather than a terminal. So pass C records **nixi
answering a question about this machine**, with the terminal agent as the
supporting shot rather than the headline.

It sharpens the measurement in the same move: nixi's failure mode is already
documented in `docs/manual/ai.md` — with no adapter pinned, `SUPER + H` reports
*"Claude Code's ACP adapter (claude-agent-acp) is not on the system PATH"* and
the rebuild says nothing. The scene must therefore assert that an adapter is
pinned before recording, or it records that error message in good faith.

Either way no credential enters the VM: the agent is driven by `localAi`
(`qwen3:8b`), with `opencode` or `codex` from `data/apps.nix`. The node is
`vm-big`-shaped — 32 GB, 8 cores — because that is what the existing
configuration says 8b needs, not a number invented here.

This is the one scene whose runtime depends on the host, and the spec says so
rather than discovering it during review.

### 4. Nested virtualisation fails loudly

The MicroVM template scenes assert `/dev/kvm` inside the guest before recording
anything. Without it the panel lists templates and starting one does nothing —
a GIF of a list, which is the `plugin` failure again. The assert is the scene's
own, in the script, so it dies with a sentence rather than producing a green
recording of nothing.

## Alternatives rejected

- **One PR for everything.** Nine scenes, each needing its own red-then-green,
  against a recorder run by hand. A failure anywhere would strand the rest.
- **A single node with podman, boxes, nested KVM and 32 GB.** Every scene then
  pays for every other scene's requirements, and the agent's memory would make
  the quick scenes unrunnable on a smaller host.
- **Lowering `minDistinct` for the authenticate-first panels.** Refused above,
  on the tree's own precedent.
- **A real `gh`/`glab` login in the recording VM.** Ruled out by the intent, and
  by `docs/AGENTS.md`: a published recording of an authenticated session cannot
  be sanitised afterwards.
- **Recording the agent against a hosted model with a token.** Same reason, and
  it would also record whatever that session happened to contain.

## Risks

- **The pulls are network-dependent.** `boxes` already documents what that costs:
  a registry resolving AAAA first and hanging spent 900 s in silence, fixed by
  v4-only SLIRP. Pass A inherits that node's networking wholesale rather than
  rediscovering it.
- **Disk.** The `boxes` scene needed 16 GB for an image, its layers and the
  container. Podman's demo containers are additional, on the same node.
- **The agent scene may simply not be worth it**, which is why it is measured
  first and may end as a still.
- **Nothing here runs in CI.** `demo-record` is driven by hand, so these scenes
  rot silently if a panel changes. That is the existing bargain for all nine
  scenes and this change does not improve it; it is named so nobody reads the
  new GIFs as covered.

## Verification

Each scene, before its GIF is allowed to exist:

1. **Red first** — record with the feature broken or absent (the panel disabled,
   the container missing, `/dev/kvm` withheld) and show the gate refusing it,
   either on `expects` or on the diversity floor. Capture that output.
2. **Green** — record properly, and quote the frame-diversity number and the OCR
   hits.
3. Every GIF under 1 MB at 4 fps / 900 px per `tests/demo/encode-gif.sh`, palette
   capped where needed.
4. Every demo object named `demo-*` and removed by the scene.
5. `docs/manual/plugins.md` and the front page updated in the same PR, with any
   feature that is shown still rather than moving said so in words.
