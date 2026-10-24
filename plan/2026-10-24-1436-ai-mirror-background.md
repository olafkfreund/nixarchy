---
status: approved
issue: 1436
spec: spec/2026-10-24-1436-ai-mirror-background.md
---

# Plan: show ai-mirror's background accessibility work on the site and in the manual

Self-contained. Branch `docs/1436-ai-mirror-background` from `origin/main`,
in its own worktree. The checkout on `feat/1177-pi-mcp` is left alone.
**Starts only after ai-mirror `v3.0.0` exists** (ai-mirror#72 step 5).

## Approved decisions (from the spec)

1. **Pin the `v3.0.0` commit** in `flake.nix` in the full-hash style, and
   run `nix flake update ai-mirror`. Voice follows. Nothing in
   nixarchy calls a gated op.
2. **`plugins.md#ai-mirror`** gains a "**Without your cursor.**"
   paragraph and a scripting note (`--generation` since 3.0.0). It links
   the measured table at the tag rather than copying it, and adds the new
   recording next to the existing showcase link.
3. **`ai.md`** gets one clause linking that paragraph.
4. **`docs/index.md`**: a new section, "An agent that uses your desktop
   without taking it", after "An agent that knows this machine". It has
   two paragraphs, the GIF, an mp4 link with its size, and the
   `programs.nixarchy.aiMirror.mcp = true;` block.
5. **Media copied** into `docs/video/` as `ai-mirror-background.{gif,mp4}`.
   If the mp4 is over 5 MB, host only the GIF and link ai-mirror's mp4.
6. **README parity (#831):** the README's ai-mirror row
   (`README.md:505`) gains the matching clause. No manual page is added.

## Steps

1. **Pin.** At `flake.nix:259-264`, set the URL to
   `github:olafkfreund/ai-mirror/<v3.0.0 sha>` (from
   `git ls-remote https://github.com/olafkfreund/ai-mirror refs/tags/v3.0.0^{}`,
   falling back to `refs/tags/v3.0.0` for a lightweight tag). Add one
   comment line: "3.0.0 (#1436): every mutating call needs generation;
   a11y_act set_value/select, read back". Then `nix flake update
   ai-mirror`.
   → verify by:
   - `git diff flake.lock` changing only the `ai-mirror` node (`rev`,
     `narHash`, `lastModified`)
   - `nix eval --raw .#inputs.ai-mirror.packages.x86_64-linux.ai-mirror.version`,
     or a `nix build` of it, giving `3.0.0`
   **Deviation:** the input sits at `flake.nix:296-302` on `main`; the
   version eval ran against the pinned URL
   (`nix eval --raw github:olafkfreund/ai-mirror/77df700…#packages.x86_64-linux.ai-mirror.version`
   → `3.0.0`), since `.#inputs` is not a flake output; the existing "this one
   is v2.1.0" comment now says v3.0.0. Lock: only the `ai-mirror` node moved.
   Traps: don't run a bare `nix flake update`, which would move every input.

2. **Manual.**
   - In `docs/manual/plugins.md`, after the mark table (about line 350),
     add the paragraph from decision 2, at most about 8 lines, in the
     section's bold-lead voice ("**Without your cursor.** ..."). Link to
     `https://github.com/olafkfreund/ai-mirror/blob/v3.0.0/src/ai_mirror/gotchas.md`.
   - Next to the existing "Watch the nixarchy desktop showcase" line, add
     "**[Watch an agent work without your cursor](../video/ai-mirror-background.mp4)**".
   - In `docs/manual/ai.md:147-149`, append the clause: "; it can also
     [work in a window you are not using](plugins#ai-mirror)".
   → verify by `grep -n "Without your cursor" docs/manual/plugins.md` and
   the build step below.
   Traps: say it still needs the yes and that the mark is red. Claim no
   app beyond the table.

3. **Site and media.**
   - Copy ai-mirror `assets/demo-background.gif` and `.mp4` at the
     `v3.0.0` tag into `docs/video/ai-mirror-background.{gif,mp4}`, using
     `gh api` or `git show v3.0.0:assets/...` from the ai-mirror checkout.
   - In `docs/index.md`, after the "An agent that knows this machine"
     section (it ends with the `programs.nixarchy.localAi.enable` block,
     about line 140), add the section from decision 4:
     - `![An agent sets a slider, picks a list item and saves a form in Chrome while the cursor and the focused terminal never move](video/ai-mirror-background.gif)`
     - `[The same, as video (<size> MB)](video/ai-mirror-background.mp4)`
     - the `nix` block
   → verify by both files existing and `ls -l` sizes being within decision 5.
   Traps: write alt text that describes what happens; follow decision 5's
   rule if the mp4 is over 5 MB.

4. **README parity.** In the `README.md:505` row, after "it asks a human
   before it takes control", add "— and it can work in a window you are
   not using, without moving your cursor". → verify by grep.

5. **Check and PR (session model).**
   1. Run `nix flake check`.
   2. Run the docs build step locally if the repo offers one; otherwise
      rely on CI, which includes the "Every manual page is in the
      sidebar" step.
   3. Open a PR linking intent, spec and plan, saying which steps the
      coder did, and naming the breaking change for users' own scripts.
   4. Merge once CI is green.
   → verify by green CI.

## Execution

Steps 1-4 edit five files plus media: one `coder` agent in the worktree
does them in order. The session model commits each step. Step 5 is the
session model's. A fresh Opus review compares `git diff origin/main...HEAD`
with this plan before the PR.

## Tests

```sh
nix flake check
git diff --stat origin/main...HEAD
```

## Rollback

Revert the PR. The pin goes back to `044eb25` and the media and text are
removed together.
