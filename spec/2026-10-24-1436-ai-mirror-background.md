---
status: approved
issue: 1436
intent: intent/2026-10-24-1436-ai-mirror-background.md
---

# Spec: show ai-mirror's background accessibility work on the site and in the manual

## Design

### 1. Pin ai-mirror 3.0.0

`flake.nix:263-264` pins `github:olafkfreund/ai-mirror/044eb25…`. Pin the
commit `v3.0.0` points at, in the same full-hash style, and update the
comment above it (#1436, 3.0.0, the breaking `generation` change). Then run
`nix flake update ai-mirror`. nixarchy-voice's `inputs.ai-mirror.follows`
(`flake.nix:256`) means voice moves with it. Voice uses only
`ai-mirror-input`, which 3.0.0 did not change, and nothing in `modules/`,
`pkgs/` or `share/` calls a gated ai-mirror op (checked by grep).

### 2. Manual: `docs/manual/plugins.md#ai-mirror`

Add a **"Without your cursor."** paragraph after "The mark says what an agent
is doing". It says:

- An agent can click, fill, move a slider and pick a list item in a window
  you are not using, through the accessibility tree. Your pointer and
  keyboard focus stay where they are.
- This is still control: it needs your yes and the mark is red.
- Each action is read back. "Not confirmed" is honest, not a failure.
- What works in which app lives in ai-mirror's measured table, linked
  rather than copied (`src/ai_mirror/gotchas.md` at the tag).
- Firefox has to be on a visible workspace.

Add a second sentence for anyone scripting the CLI: since 3.0.0 every action
takes `--generation`. The showcase link under the section gets the new
recording next to the existing one.

### 3. Manual: `docs/manual/ai.md`

`ai.md:147-149` mentions ai-mirror in one sentence. Append a clause that
links the new paragraph: "...connects the same agents to it; it can also
[work in a window you are not using](plugins#ai-mirror)." No more than
that, since `plugins.md` is the ai-mirror page.

### 4. Site: `docs/index.md`

Add a new section, **"An agent that uses your desktop without taking it"**,
right after "An agent that knows this machine" (`docs/index.md:123`). It has
two short paragraphs in that section's voice:

1. The agent works through ai-mirror and asks before it touches anything.
2. It can now work in a window you are not looking at, while your cursor
   stays put.

Under them goes the GIF from ai-mirror#72, inline, and a link to the mp4,
following the hero video's pattern (`docs/index.md:20-23`, size in the
link text). The section ends with the opt-in line in a `nix` block, as the
section above it does:

```nix
programs.nixarchy.aiMirror.mcp = true;
```

### 5. Media

Copy `demo-background.gif` and `demo-background.mp4` from the ai-mirror
`v3.0.0` tree into `docs/video/` as `ai-mirror-background.gif` and
`ai-mirror-background.mp4`. Their size limits are set in ai-mirror's spec
(≤ 5 MB and ≤ 10 MB); the hero video is 3.9 MB.

### 6. README parity (#831)

The README gets a matching line wherever it already names ai-mirror, and
the build's "every manual page is in the sidebar" step stays green. No
manual page is added, so the sidebar, `llms.txt` and the manual index are
unchanged.

## Alternatives rejected

- **Hotlink the media from ai-mirror's release:** the site already hosts
  its own video, and a hotlink breaks if the release asset is renamed.
  Decided in the intent.
- **A new manual page for ai-mirror:** `plugins.md#ai-mirror` already is
  that page. A second one would split it, and would need sidebar,
  `llms.txt` and index entries for no reader benefit.
- **Copy the measured table into the manual:** it would go stale on the
  next measurement. Link it instead.

## Risks

- **Rebuild:** every machine gets ai-mirror 3.0.0. A user's own script
  calling `ai-mirror input` without `--generation` breaks. The manual says
  so, and so does the PR.
- **Repo size:** adding up to about 15 MB of media to `docs/video/` grows
  every clone. If the mp4 exceeds 5 MB, the site links ai-mirror's copy and
  hosts only the GIF.
- **`flake.lock` drift:** `nix flake update ai-mirror` must move only
  ai-mirror (and voice's follow). Check the lock diff.

## Verification

- `nix flake check` passes, including `ai-mirror-mcp-remove`.
- `git diff flake.lock` touches only the ai-mirror node.
- `nix eval .#nixosConfigurations.<a host>.config.home-manager.users.<u>.home.packages`,
  or a build of one host's `ai-mirror` path, shows 3.0.0.
- The site builds through the existing Jekyll job. The "every manual page
  is in the sidebar" step is unchanged and green.
- Links resolve: `plugins#ai-mirror` from `ai.md`, the gotchas link at the
  tag, and both media files.
- On a rebuilt machine: `ai-mirror status` works, and an `a11y-act` without
  `--generation` gives the documented error.
