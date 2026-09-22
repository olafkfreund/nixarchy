---
status: draft
issue: 773
spec: spec/2026-09-22-773-ai-mirror-default.md
---

# Plan: ai-mirror ships with nixarchy, and no agent takes the desktop without a human saying yes

Branch `feat/773-ai-mirror-default`, which carries the approved intent and spec,
with `main` merged in. Step 0 is a PR in **ai-mirror** (the owner's repository).
Steps 1–6 are nixarchy, one commit each, citing `plan step N` and `(#773)`. A
deviation updates this file in the same commit as the code. The PR says
`closes #773`.

## Approved decisions

Copied from the spec so this file stands alone.

- **Decision A (owner): accept the CLI self-grant, and document it.** MCP and the
  API stay gated (`api.py:44-47`). An agent with a shell can run
  `ai-mirror control agent` and then `ai-mirror control confirm`. That is said in
  the manual and in the MCP option's description, with Sandboxes and MicroVMs
  named for untrusted agents. Grants stay audited (`request_by`, `enabled_by`).
  There is no ai-mirror code change for A. The one-time code is a rejected
  alternative, kept for if this is revisited.
- **Decision B (owner): watching gets a real sign, in ai-mirror.** Observation
  stays ungated.
- **The input:** `ai-mirror`, pinned to a commit like `nixarchy-voice`, with
  `nixpkgs.follows`, and `nixarchy-voice.inputs.ai-mirror.follows = "ai-mirror"`.
  Voice uses `ai-mirror-input` only.
- **On every machine:** the `ai-mirror` package, and the widget as a
  `defaultPluginSet` entry (`id = "olafkfreund.ai-mirror"`, no gate, right
  section), which `defaultPlugins.ai-mirror = false` turns off.
- **Upstream's Home Manager module is not enabled.** It installs the plugin twice
  (key `ai-mirror` against our id key), defaults `a11y.enable` to true, and
  writes a binds file that needs a hand edit.
- **The kill switch:** `SUPER + SHIFT + ESCAPE` → `ai-mirror control off`, in the
  **seed** `bindings.lua`'s default-plugin block. A dialog grant always has a
  stop, because the widget's click is one. A terminal self-grant in a home with
  neither is bounded by upstream's expiry (MCP server exit, or ten idle minutes)
  and by `ai-mirror control off`, and the manual says so.
- **MCP:** `programs.nixarchy.aiMirror.mcp`, default **false**, independent of
  `programs.nixarchy.mcp`. It registers with Claude, opencode and Codex through
  the same helpers.
- **Accessibility:** nixarchy sets none of `GTK_MODULES`,
  `QT_LINUX_ACCESSIBILITY_ALWAYS_ON` or `toolkit-accessibility`. ai-mirror
  switches it on only while control is granted.
- **Mode A:** everything is behind `programs.nixarchy.enable`.
- **Order:** the ai-mirror PR lands first. nixarchy pins a commit that contains it.

## Measured before planning, and the two deviations it produced

**Deviation 1: there is no "warning" colour.** The spec says the watching icon
takes "the bar's warning colour". The shell's palette (`Commons/Color.qml:19-23`)
has `foreground`, `background`, `accent`, `urgent` and `muted`, and nothing else.

- `accent` differs from `foreground` in **21 of the 22** themes. Tokyo Night, the
  default, has `#7aa2f7` against `#a9b1d6`.
- In **kanagawa** they are the same, so colour alone would change nothing there.

So watching is **`accent` plus a slow opacity pulse** (0.55 ↔ 1.0, about 1.2 s).
The pulse keeps it distinct in every theme. The colour makes it plain in 21 of
them. This needs the owner's approval with this plan.

**Deviation 2: turning the MCP opt-in off must remove what it added.**

- `mergeJson` (`home.nix:193`) is a recursive jq merge.
- `appendToml` (`:222`) appends once and never deletes.

Both are add-only, so on → off would leave ai-mirror registered, and "no agent
finds ai-mirror unless a person turned this on" would be false from that day. So
when the option is **off**, an activation step removes an `ai-mirror` server
entry, **only if its `command` is a nix store path ending in `/bin/ai-mirror`**,
which is what nixarchy writes. An entry the user wrote by hand is left alone.

Other facts:

- Voice's flake declares `ai-mirror.url = "github:olafkfreund/ai-mirror"` and uses
  only `packages.ai-mirror-input`, so `follows` is enough to make one build.
- The seed's default-plugin binds block is `pkgs/omarchy/default.nix:1970-1991`.
  It appends after an asserted last line.
- `plugins.md` already has an ai-mirror row ("coming", `:35`) and section (`:198`).
- `docs/index.md:75` says "Eight ship by default: five are always on, and three
  turn on with their feature". It becomes **nine / six / three**. #856's
  `readme-counts.sh` and its plugin-row step both go red until it does.

## Steps

**0. ai-mirror: the watching sign** (a PR in olafkfreund/ai-mirror).

- In `plugin/Widget.qml`, while `root.watching`, the `AgentMark` colour is
  `root.bar ? root.bar.accent : Color.accent`. If `bar` exposes no `accent`,
  read it from `Color.accent`, and say which one in the PR.
- Opacity runs a `SequentialAnimation` loop between 0.55 and 1.0 for as long as
  `watching` holds, and stops the moment it does not.
- *On* (urgent, 1.0) and *off* (foreground, 0.45) are unchanged.

→ verify:

- `nix flake check` in ai-mirror;
- a screenshot of the bar in a nested session, taken with ai-mirror itself
  (`screenshot` right after an `index` call), showing the accent colour, and a
  second one taken 11 s later showing it gone;
- in kanagawa, two screenshots 0.6 s apart differ in the icon's opacity.

Merge it. The resulting commit is the pin for step 1.

**1. The input.** In `flake.nix`, add `ai-mirror` pinned to step 0's commit, with
`inputs.nixpkgs.follows = "nixpkgs"`, and add
`inputs.ai-mirror.follows = "ai-mirror"` to `nixarchy-voice`. Then run
`nix flake lock`.

→ verify:

- `nix flake metadata --json | jq '.locks.nodes | keys'` shows **one** ai-mirror
  node;
- `nix eval .#…` for voice's `ai-mirror-input` resolves to the same store path
  as ai-mirror's.

**2. The binary and the widget, and the counts that see them.**

- In `modules/home.nix`: `home.packages` gains the ai-mirror package. A
  `defaultPluginSet.ai-mirror` entry gets `id = "olafkfreund.ai-mirror"` and
  `src = inputs.ai-mirror.packages.${system}.plugin`, with no `gate`.
- In the same commit:
  - `docs/index.md:75` → "Nine ship by default: six are always on, and three turn
    on with their feature".
  - The "ai-mirror is on its way" clause goes.
  - The `plugins.md` ai-mirror row becomes real, with *Status* **on by default**,
    *Open it* **bar (right) · Super+Shift+Escape stops it**, and
    `<!-- olafkfreund.ai-mirror -->` inside its last cell.

→ verify:

- `readme-counts.sh --check` passes with 31 quantities, and the plugin-row step
  passes;
- **break:** leave the index sentence at *Eight*, and both go red, naming it.

**3. The kill switch in the seed.** Append
`o.bind("SUPER + SHIFT + ESCAPE", "ai-mirror: stop agent control", "ai-mirror control off")`
to the default-plugin block in `pkgs/omarchy/default.nix`, under the existing
last-line assertion.

→ verify:

- `nix build .#omarchy`, and `grep -F 'ai-mirror control off'` finds it in the
  built seed `bindings.lua`;
- `checks.patched-files` is green.

**4. The MCP opt-in, and its removal.**

- In `modules/nixos.nix`: `aiMirror.mcp = lib.mkOption { type = bool; default =
  false; }`. Its description names Decision A in one sentence, and the containment
  options.
- In `modules/home.nix`:
  - **when on**, three activations mirroring `nixarchyMcp*`, under the server
    name `ai-mirror`, with `command = "${ai-mirror}/bin/ai-mirror"` and
    `args = [ "mcp" ]`, through `mergeJson` and `appendToml`
    (`table = "mcp_servers.ai-mirror"`);
  - **when off**, one activation that deletes those entries if and only if their
    `command` matches `/nix/store/*/bin/ai-mirror`: a jq `del` for the two JSON
    files, and a bounded `awk` for the TOML table and nixarchy's two-line header.

→ verify by step 6's options checks.

**5. The words.**

- Rewrite the `plugins.md` ai-mirror section:
  - what it is;
  - the dialog;
  - watching, and what the sign looks like;
  - the kill switch and the widget click;
  - **Decision A in plain words**: an agent with a shell can grant itself
    control. Put untrusted agents in [Sandboxes](sandboxes) or
    [MicroVMs](sandboxes). The expiry bounds a self-grant nobody sees.
  - `programs.nixarchy.aiMirror.mcp`, off.
- Mention the option in `docs/manual/ai.md` beside `programs.nixarchy.mcp`, one
  line saying they are independent.

→ verify:

- the manual-page step and the plugin-row step pass;
- Jekyll renders the section, checked with the kramdown GFM render used for #856.

**6. The checks.** Each is broken first and seen red, and the break is confirmed
in the file (AGENTS.md §1).

- `tests/options.nix`, both states:
  - `aiMirror.mcp` false: no `ai-mirror` in any generated MCP payload.
  - `aiMirror.mcp` true: present in all three.
  - The removal activation exists only when the option is false.
  - With `programs.nixarchy.enable` false: no ai-mirror package, plugin or bind
    (Mode A).
  - No `GTK_MODULES` and no `QT_LINUX_ACCESSIBILITY_ALWAYS_ON` in
    `home.sessionVariables` in any state.
  - Breaks: default the option to true, and add `GTK_MODULES` in one line.
- **The removal**, as a stubbed `runCommand` in the style of `installer-network`:
  - a Claude JSON with a nixarchy-written entry → removed;
  - a hand-written one (`command = "ai-mirror"`) → kept;
  - the same two cases for the TOML table.
  - Break: widen the match to any `ai-mirror`, and the hand-written case goes red.
- **`checks.session`**, in the running desktop:
  - the widget is loaded;
  - an MCP `control confirm` returns `not_owner` and the state stays `pending`;
  - an unanswered request lapses to `off` within 35 s;
  - `SUPER + SHIFT + ESCAPE` and a widget click each return `off`.
  - Break: MCP dispatch called with `by='human'`. That is a temporary patch on
    the pinned source in a local build, never committed.
- **Voice unconnected**, evaluation only: with `voice.enable = true`, no voice
  config names an MCP server `ai-mirror`, and the ai-mirror state file is not in
  voice's unit environment. The runtime half (state stays `off` through a voice
  command) is a `pkgs/verify.sh` row, because no VM here has a microphone
  (AGENTS.md §3: a documented hole).

## Tests

```bash
# ai-mirror (step 0)
nix flake check
# nixarchy, cheap first
bash .github/scripts/readme-counts.sh --check   # OMARCHY_TREE set
nix build .#checks.x86_64-linux.patched-files
nix build .#checks.x86_64-linux.<the removal check>
nix fmt -- --ci && statix check . && deadnix --fail .
# heavy, and only when gh run list shows no install in flight (§6)
nix build '<options drv>^*'      # pinned drvPath, 11.5 GB
nix build '<session drv>^*'      # a VM
```

`checks.options` and `checks.session` are the expensive two. Each is run once,
by pinned `drvPath` (§5), and only on a quiet host. Otherwise CI is their first
run, and the PR says which checks were proven locally and which were not.

## Rollback

- Before merge: leave the branch.
- After merge: `git revert` the squash. The input, the plugin, the bind and the
  options go.
- Homes keep what they already have:
  - The **seeded** bind stays in any `bindings.lua` created meanwhile. Pointing at
    a missing binary, it does nothing.
  - An **MCP entry** written while the option was on stays. The removal step went
    with the revert, so the rollback note in the PR tells the user to delete
    `mcpServers.ai-mirror`.
- ai-mirror's step 0 stands on its own and needs no rollback.
