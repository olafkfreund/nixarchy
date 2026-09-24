---
status: draft
issue: 949
spec: spec/2026-09-24-949-default-agent-ids.md
---

# Plan: every Default Agent row records the agent it names

## The approved decisions, carried over

Self-contained; nothing here needs the intent or spec open.

1. **Route (a), nixpkgs, and only `openclaw` qualifies.** Re-confirmed against
   *this flake's pinned nixpkgs*, not the unstable index: `openclaw 2026.6.33`,
   licence **MIT**. The licence is load-bearing -- section 1 records that an
   unfree entry in an unconditional list would break every machine with unfree
   off, `checks.options` included, which is why `cursor-cli` is out even setting
   aside that it ships no `cursor-agent` binary. `hermes` is absent, and `muse`
   in nixpkgs is a **MIDI sequencer**, so that name is worse than missing.

2. **llm-agents.nix is named, not added.** It has all four, and
   `lib.inputSources` collects every flake's `outPath` *and every input of
   theirs transitively*, which `installer/cd.nix` and `installer/host.nix` both
   carry onto the ISO and every installed host. It pins its own
   `nixpkgs-unstable` and documents being tested only against it, so `follows`
   is not safely available -- and one nixpkgs source tree measures **486 MB**
   here. `checks.iso-budget` exists to refuse that.

3. **The agents need not be installed, only ready to install**, which is what
   makes three of them a documentation answer rather than a packaging one.

4. **The check is a comparison, not a second list.** Both halves live in one
   derivation, so nothing is hand-maintained.

5. **No change to any row's `checked`.** Each runs `command -v <binary>`, so a
   user who installed `hermes` themselves still gets a correctly ticked row.

## Confirmed while writing this, not assumed

**The ordering works.** `nix-bin/*` is installed to `$out/share/omarchy/bin/` by
the loop at `pkgs/omarchy/default.nix:1030-1037`; the menu check runs at
`:1189`. So `omarchy-default-agent` is on disk, in the same derivation, before
the check reads it. The spec said "in the same derivation" without establishing
that the file exists at that point -- it does.

## Steps

1. **`pkgs/omarchy/nix-bin/omarchy-default-agent:44`** -- add
   `openclaw) echo openclaw ;;` to `attr_for`. The package's binary is
   `openclaw` (it also ships `clawdbot` and `moltbot`), which is what the
   script's existing `command -v "$agent"` checks, so nothing else changes for
   it.
   → verify by step 5's build and by the check in step 4.

2. **Same file, the `case` at `:86`** -- add all four ids with display names:
   `cursor-agent`/Cursor Agent, `hermes`/Hermes, `muse`/Muse, `openclaw`/OpenClaw.
   Rows stop exiting 1 with a usage line into a detached terminal nobody reads.
   → verify by step 4.

3. **Same file, after the mise branch** -- a third route for the three with no
   nixpkgs package. It records the choice, then says where the package is and
   why we do not carry it:

   > `<Name>` is not in nixpkgs. numtide/llm-agents.nix packages it as
   > `<attr>`. Add that flake as an input and the package to your
   > configuration. nixarchy does not carry it: it pins its own nixpkgs, and
   > `lib.inputSources` would put that whole source tree -- about 486 MB -- on
   > the ISO and on every installed host.

   Attributes: `cursor-agent`, `hermes-agent`, `muse-code`. The reason is not
   decoration: without it the next reader adds the input.

   **`cursor-agent` needs one extra line**: it is unfree wherever it comes from,
   so a machine with `allowUnfree = false` cannot have it at all. Saying so
   there is cheaper than a user discovering it after adding a flake input.
   → verify by step 4 and by reading the wording.

4. **`pkgs/omarchy/default.nix:1173`, in the existing menu check** -- add the
   missing half. It already collects `agents` and asserts each `checked` uses
   `command -v`; both assertions stay. It gains:

   ```python
   accepted = set(re.findall(r'^\s*([a-z0-9| -]+)\)\s*agent=', script, re.M))
   ```

   read from `$out/share/omarchy/bin/omarchy-default-agent`, and fails naming
   any row whose `action` argument is not in it.

   Parsing the `case` arms rather than maintaining a list is the point
   (section 4: a list naming things elsewhere wants a comparison). **The parse
   itself is the risk** -- a regex that matches nothing yields an empty set and
   flags every row, which is loud; a regex that over-matches yields a set that
   accepts everything, which is silent. So the check **refuses an implausible
   count**, the way `readme-counts.sh` refuses at zero: fewer than 10 accepted
   ids is a broken parse, not a finding.
   → verify by step 5, and by the break in the Tests section.

5. **`tests/AGENTS.md`** -- what this cannot reach: whether `openclaw` launches,
   and whether the three llm-agents.nix attribute names are still right. The
   first needs the agent installed; the second is a claim about another
   repository that can go stale with nothing here to notice.

## Tests

| command | expected |
|---|---|
| `nix build .#omarchy --print-build-logs` | builds; the check prints its `menu ok: N agent rows` line |
| `nix build .#checks.x86_64-linux.menu-verbs` | still passes |
| `nix build .#checks.x86_64-linux.options` | still passes |
| `nix fmt -- --ci`, statix, deadnix | clean |

**Section 1, two breaks, both required in the PR:**

- add a menu row whose action is `omarchy-default-agent nosuchagent` -> the
  build fails naming it;
- break the regex so `accepted` comes back empty -> the check **refuses** on the
  implausible count rather than flagging fourteen rows or passing.

The second is the one that matters: it proves the comparison cannot fail open.

## Rollback

`git revert`. Three `case` arms and one table entry disappear from a script; the
menu rows revert to exiting 1 as they do today; the check loses one assertion
and keeps the two it had. No state, no activation, no user file.
