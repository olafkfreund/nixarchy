---
status: draft
issue: 949
author: olafkfreund
---

# Intent: the Default Agent picker's rows do what they say

## Problem

Four rows in Setup > Default Agent cannot be selected. The generated menu
calls `omarchy-default-agent` with **14** ids; the script accepts **10**.

Read off the built tree rather than from the issue:

```
$ grep -o 'omarchy-default-agent [a-z-]*' \
    result/share/omarchy/default/omarchy/omarchy-menu.jsonc | sort -u
  ... antigravity claude codex copilot crush cursor-agent gemini grok
      hermes muse omp openclaw opencode pi
```

`cursor-agent`, `hermes`, `muse` and `openclaw` are absent from the `case`
in `pkgs/omarchy/nix-bin/omarchy-default-agent:86-102`, so they fall to `*)`,
print a usage line and exit 1. Picking one of those rows does nothing and says
nothing: menu actions run detached with no terminal, so the usage message goes
nowhere a user can see it.

`bin/omarchy-agent` supports all four, so the agent itself works — the file
can be written by hand. Only the menu route is dead.

**This is the shape section 2 names: we ship something that names something
else, and nothing asserts the something else exists.** The exact wording there
is *"anything we ship that names something else needs a list, or a check,
saying that something exists"*, and the script side of this repository has
carried such a list for a long time (`pkgs/omarchy/default.nix`'s runtime
list, asserted by `build.yml`).

**And there is already a check over these very rows, measuring the wrong
field.** `pkgs/omarchy/default.nix:1173` parses the generated menu, collects
every `setup.default.agent.*` key, and fails any whose `checked` expression
does not use `command -v`:

```python
agents = [k for k in d if k.startswith("setup.default.agent.") and k.count(".") == 3]
blind  = [k for k in agents if "command -v" not in d[k].get("checked", "")]
```

That is a real property and it holds. The defect is one field over, in
`action`, which nothing compares against the script's accepted ids. So this is
not a missing check so much as a check that stops one field short — and it
already has both halves in reach, since it has the parsed menu in hand and the
script is in the same derivation.

## Proposed outcome

- Every `setup.default.agent.*` row's `action` names an id
  `omarchy-default-agent` accepts. Picking any row in the picker records that
  agent.
- A row and a script that disagree **fail the build**, naming the offending
  ids — so the next agent added upstream cannot reintroduce this silently.
- No row is removed to satisfy the check. The four agents work; it is the
  script's list that is short.

## Affected users and systems

- Anyone using Setup > Default Agent to pick cursor-agent, hermes, muse or
  openclaw. On a machine with one of those installed, the picker is simply
  broken for it.
- `pkgs/omarchy/nix-bin/omarchy-default-agent` (ours) and the menu fragment in
  `pkgs/omarchy/default.nix` (ours). Both nixarchy's own, so no upstream
  routing question.

## Constraints

- **Must not** widen to the rest of #949. Bugs 2 and 4 in that issue live in
  `bin/omarchy-agent`, which is **upstream's** — it is not in
  `pkgs/omarchy/nix-bin/`. A fix carried here is re-applied at every source
  bump (section 11), so those belong upstream and are not in this scope. Bug 3
  (a menu pick starting a headless rebuild) is a different failure needing a
  live machine to characterise, and is also out of scope here.
- The accepted-id list is in a `case` statement that also maps each id to a
  display name; adding four means choosing four names.
- The existing check must keep asserting what it already asserts. Section 1
  read backwards: it is not failing, and it is not wrong.

## Open questions

1. **Answered while writing this, and it changes the fix.** The script has two
   install routes: `attr_for` (nixpkgs attributes, `:44-55`) and
   `mise_pkg_for` (mise backends for what nixpkgs lacks, `:59-64`). **Neither
   has an entry for cursor-agent, hermes, muse or openclaw.**

   So adding the four to the `case` alone would not fix the rows -- it would
   move the failure. The script would record the choice, find no command on
   PATH, get "" from both lookups, and fall through having installed nothing.
   A user would pick an agent and get silence, which is the same experience
   they have now with an extra file written.

   That leaves a real decision, which is yours:

   - **(a) Give the four an install route.** Find each in nixpkgs or as a mise
     backend and add it to the matching table. Makes the rows genuinely work.
     Cost: four packages to locate and verify, and any that exists in neither
     place cannot be done this way.
   - **(b) Hide the rows we cannot serve.** The menu fragment is ours; a row
     whose agent has no install route does not appear. Smaller, honest, and
     the picker stops lying. Cost: someone with cursor-agent already installed
     loses a way to select it -- though `omarchy-agent` still works and the
     file can be written by hand.
   - **(c) Accept the id, and say what to do.** Record the choice and print the
     declarative line to add. Menu actions have no terminal, so this needs the
     floating-terminal route the other rows use.

   I lean to **(a) where the agent is packaged and (b) where it is not**, which
   needs the four looked up before either can be promised. The check in
   question 2 is worth having under any of them, because it is what stops the
   next upstream agent from re-opening this.

2. **Where should the comparison live?** Extending the existing check in
   `pkgs/omarchy/default.nix` is the smallest diff and puts it where the menu
   is already parsed. A separate `checks.<name>` entry would be more visible
   but needs a workflow edit, which is a CI-gate change and needs a human
   (section 4, section 11). I lean to extending the existing one; say if you
   want it standalone.

## Not in scope

- `bin/omarchy-agent`'s antigravity/`agy` name mismatch and the `crush`/`pi`
  prompt-flag bug (upstream).
- The headless-rebuild path when an uninstalled agent is picked (#949 bug 3).
- Whether nixarchy should carry the four agents as packages at all.
