---
status: draft
issue: 949
intent: intent/2026-09-24-949-default-agent-ids.md
---

# Spec: every Default Agent row records the agent it names

## What the approved intent settled

Route **(a)**, nixpkgs, and the four looked up. Re-confirmed against **this
flake's pinned nixpkgs** rather than the unstable index:

```
openclaw 2026.6.33 MIT
```

| id | nixpkgs | verdict |
|---|---|---|
| `openclaw` | `openclaw` 2026.6.33, **MIT** | route (a) |
| `cursor-agent` | only `cursor-cli`, **unfree**, ships no `cursor-agent` binary | no |
| `hermes` | absent (`vimPlugins.hermes-nvim` is a Neovim client) | no |
| `muse` | absent -- `muse` is a **MIDI sequencer** | no |

The MIT licence is load-bearing, not incidental: section 1 records that an
unfree package in an unconditional list "would have broken every machine with
unfree turned off, `checks.options` included". That is why `cursor-cli` is out
even setting aside the missing binary.

**llm-agents.nix has all four and cannot be an input.** `lib.inputSources`
(`flake.nix`) collects every flake's `outPath` **and every input of theirs,
transitively**, and both `installer/cd.nix` and `installer/host.nix` carry the
result -- so an input's source tree reaches the offline ISO and every installed
host whether or not anything references it. llm-agents.nix pins its own
`nixpkgs-unstable` and documents that it is only tested against it, so `follows`
is not safely available. One nixpkgs source tree measures **486 MB** here, and
`checks.iso-budget` exists to fail on exactly that.

**And the agents need not be installed -- only ready to install.** That is what
makes the absence of three of them a documentation problem rather than a
packaging one.

## Design

**Three routes, not two.**

1. **`openclaw` joins `attr_for`** (`pkgs/omarchy/nix-bin/omarchy-default-agent:44`),
   the existing nixpkgs table, mapping `openclaw -> openclaw`. Its binary is
   `openclaw` (verified: the package ships `openclaw`, `clawdbot`, `moltbot`),
   which is what the script's `command -v "$agent"` already checks.

2. **A third branch for `cursor-agent`, `hermes` and `muse`**, beside the
   existing mise one. That branch already sets the precedent of being honest
   about what a route costs -- *"has no nixpkgs package, so it is installed with
   mise instead... that is imperative"*. The new one records the choice and says
   where the package is:

   > `<Name>` is not in nixpkgs. It is packaged by numtide/llm-agents.nix as
   > `<attr>`. Add that flake as an input and the package to your
   > configuration; nixarchy does not carry it, because its own nixpkgs pin
   > would add about 486 MB to the ISO and every installed host.

   Naming the reason matters: without it the next person adds the input.

3. **All four ids join the `case`** (`:86`), so the rows stop failing with a
   usage line into a detached terminal nobody sees.

**The check.** `pkgs/omarchy/default.nix:1173` already parses the generated menu
and collects every `setup.default.agent.*` key. It asserts each row's `checked`
uses `command -v` -- a real property, currently true, one field away from this
bug. It gains the missing comparison: **every row's `action` names an id the
script accepts**, read out of `omarchy-default-agent` in the same derivation.

Both lists are in one build, so this is a comparison rather than a second
hand-maintained list -- section 4's "any list naming things that exist elsewhere
wants a comparison, not discipline".

## Alternatives rejected

| | why not |
|---|---|
| Add llm-agents.nix as an input | 486 MB of a second nixpkgs source tree on the ISO and every host, via `inputSources`, for four optional agents. `iso-budget` would refuse it. |
| Hide the three rows we cannot install | Considered, and worse: `omarchy-agent` supports all four, so a user with one installed can still select it by hand. Hiding the row hides a working agent. |
| Map `muse` to nixpkgs `muse` | It is a MIDI sequencer. Picking an AI agent would install music notation software -- the name being taken is worse than it being absent. |
| A hand-written list of valid ids in the check | The script is the list. A second copy drifts, which is the defect one level up. |

## Risks

- **`cursor-agent` remains unavailable on a no-unfree machine even via
  llm-agents.nix**, since `cursor-cli` is unfree wherever it comes from. The
  message must not imply otherwise.
- **The check will fail the build the moment upstream adds an agent row** whose
  id our script does not know. That is the point, and it is also a source-bump
  hazard: whoever bumps omarchy sees a build failure naming the id, which is the
  readable diff `pkgs/omarchy/default.nix` already argues for elsewhere.
- **Wording.** Three of these tell a user "no". The line between *"we chose not
  to carry this and here is why"* and *"this does not work"* is the whole value.

## Verification

- **The menu check itself**, extended: a row naming an id the script rejects
  fails the `omarchy` build. Section 1: seen failing by adding a row with a
  bogus id, and that output in the PR.
- **`checks.menu-verbs`** unchanged and still green -- it reads verbs out of
  commands and is the neighbouring guard.
- **`nix build .#omarchy`**, whose log prints the check's own line.
- **What no check here reaches:** whether `openclaw` actually launches, and
  whether the three messages are accurate about llm-agents.nix's attribute
  names. The first needs the agent installed; the second is a claim about
  another repository that can go stale. Both belong in `tests/AGENTS.md`.

## Open question

Should the three unavailable agents' rows carry a `checked` that can never be
true, or should they stay as they are? Today every agent row's `checked` runs
`command -v <binary>`, so a user who installed `hermes` themselves gets a
correctly ticked row -- which is the right behaviour and an argument for
changing nothing. I have specified no change to `checked`.
