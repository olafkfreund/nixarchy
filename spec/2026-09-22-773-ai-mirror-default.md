---
status: draft
issue: 773
intent: intent/2026-09-19-773-ai-mirror-default.md
---

# Spec: ai-mirror ships with nixarchy, and no agent takes the desktop without a human saying yes

Refs #773. Read against ai-mirror at `0104f70` (2026-09-21), cloned and read,
not recalled.

## What changed upstream since the intent

The intent (2026-09-19) listed four things ai-mirror had to fix. Three have
landed:

| the intent's requirement | ai-mirror today |
| --- | --- |
| An agent cannot grant itself control | **done** (#10). `set_owner` only ever writes `owner: pending` (`control.py:174-192`). Only `confirm_request` grants, and MCP's `control confirm` is refused with `not_owner` (`api.py:44-47`). A request lapses after 30 s (`control.py:89`). |
| Licence and notice in the package | **done**. Installed into all three outputs and asserted by `checks.licence` (`flake.nix:15-16, 119-120`). |
| Accessibility switched on correctly, and kept private | **done** (#12, #20). |
| Watching needs a grant, or a visible sign | **partly**. Every agent read (`OBSERVING`, `api.py:14`) calls `control.watch()`, and the widget has a *watching* state for 10 s (`Widget.qml:26`). |

Two findings from reading the code change what this spec has to decide.

### Finding 1: the command line can confirm its own request

The intent requires the confirm to hold "on every way in: MCP, the command line
and the API". It does not hold on the command line.

`cli.py:92` calls `api.run(op, args)` with no `by`, and `run` defaults to
`by='human'` (`api.py:33`). So an agent with a shell can run
`ai-mirror control agent` and then `ai-mirror control confirm`, and hold control
with no one having seen a dialog. Upstream documents this as a feature:
"`ai-mirror control confirm` from a terminal is the way out" (`docs/usage.md:109`).

A flag cannot close it. The dialog confirms by running **the same CLI** with
the request id (`AgentConfirmDialog.qml:25`, `AgentCommand.qml:12`). The id is
in a state file the agent can read. To ai-mirror, the human's dialog and a
same-user agent's shell are indistinguishable.

**The honest limit.** An agent running as the user, with a shell, can already
do anything the user can. No confirm inside the session is unforgeable against
it. What ai-mirror *can* guarantee is that an agent using its interfaces as
designed cannot self-grant, and that a shell agent has to go out of its way to.
Real isolation is running the agent somewhere else, which nixarchy already
offers: Sandboxes, MicroVMs.

### Finding 2: the watching sign is too faint to count as a sign

While an agent only looks, the icon's opacity goes from 0.45 to 0.8 in the same
colour (`Widget.qml:96`). The words, "An agent is reading the screen", appear
only on hover (`:107`). Someone not already looking at that icon will not see
it.

## Design

### Decision A (owner, 2026-09-22): accept the command-line confirm, and document it

**Decided: accept and document.** The confirm binds MCP and the API, where an
agent cannot answer its own request (`api.py:44-47`). The command line stays the
user's own tool, as upstream has it: an agent with a shell **can** grant itself
control with `ai-mirror control agent` and `ai-mirror control confirm`.

This relaxes the intent's constraint that the confirm holds "on every way in",
knowingly and at the owner's direction. It is not left implied:

- nixarchy's manual (the ai-mirror section of `docs/manual/plugins.md`) says in
  plain words that an agent with a shell can grant itself control, and that an
  agent you do not trust belongs in a Sandbox or a MicroVM, linking both;
- `programs.nixarchy.aiMirror.mcp`'s description says the same, since turning
  it on is the moment a person decides which agents reach the desktop;
- every grant is still audited, with `request_by` and `enabled_by`
  (`control.py:107-113, 209-217`), so a self-grant is visible after the fact.

No ai-mirror code changes for A.

### Decision B (owner, 2026-09-22): watching gets a real sign

**Decided (upstream):** while `watching` is set, the icon takes the bar's
**warning** colour, not the foreground colour, and stays that way until 10 s
after the last read. That is distinct from *on* (urgent colour) and from *off*
(dimmed). No new grant: observation stays ungated, as the intent's default
proposed.

The alternative is a **separate observation grant**, the same confirm flow for
reads. It is rejected as the default because every orientation call (`status`,
`windows`, `index`) would need a human, and agents orient before every action.
It stays available as a later option.

### nixarchy's side

**1. The input.** `flake.nix` gains `ai-mirror`, pinned to a commit like
`nixarchy-voice` (`flake.nix:226-229`), with `inputs.nixpkgs.follows`.
`nixarchy-voice.inputs.ai-mirror.follows = "ai-mirror"`, so the helper voice
uses (`ai-mirror-input`) and the one ai-mirror ships are one build, not two
versions.

**2. The binary and the widget: on every machine.**

- `ai-mirror` goes into `home.packages` from nixarchy's Home Manager module.
- The widget joins `defaultPluginSet` (`modules/home.nix`) as
  `ai-mirror = { id = "olafkfreund.ai-mirror"; src = …plugin; }`, with no gate,
  in the right section, as upstream's manifest says (`manifest.json:15`).
  `defaultPlugins.ai-mirror = false` turns it off like any other default.
- **Upstream's Home Manager module is not enabled.** It does three things, and
  nixarchy wants each differently:
  - It registers the plugin under the key `ai-mirror`, where nixarchy keys
    plugins by id, so both would install one plugin twice.
  - `a11y.enable` defaults to **true** (`flake.nix:79-82`), and the intent
    requires it off.
  - It writes a binds file that does nothing without a hand edit.

  So nixarchy writes the two lines it needs itself. This is less than overriding
  three behaviours of a module it would otherwise import.
- #856's checks see the new default at once: the count sentence becomes *nine*,
  and `plugins.md` needs an ai-mirror row with its marker. The ai-mirror row
  already there says "coming" and becomes the real row.

**3. The kill switch.** `SUPER + SHIFT + ESCAPE` → `ai-mirror control off`,
appended to the **seed** `bindings.lua` with the other default-plugin binds
(`pkgs/omarchy/default.nix:1970-1991`), so new homes get it and nobody's edited
file is touched.

**An existing home without the bind still has a working stop.** Clicking the
widget while an agent holds control runs `control off` (`Widget.qml:110`). The
confirm dialog is part of the same plugin (`AgentConfirmDialog.qml`), so **a
grant made through the dialog needs the plugin loaded, and a loaded plugin
carries the stop.**

Decision A leaves one path outside that: a terminal self-grant in a home that
has turned the widget off and predates the seeded bind. That grant has no stop
on screen. What bounds it is upstream's expiry: a grant ends when the asking MCP
server exits, and by itself after ten minutes with no input
(`docs/usage.md:14-15`). `ai-mirror control off` in any terminal also ends it.
The manual says this in the same paragraph as Decision A, and no runtime check
for the bind is added: it would guard only the dialog path, which already has
its stop.

**4. MCP: a separate opt-in, off.** A new `programs.nixarchy.aiMirror.mcp`,
default **false**, independent of `programs.nixarchy.mcp` (which defaults to
true, `modules/nixos.nix:676`). When on, it registers `ai-mirror mcp` with the
same three agents and through the same activation helpers
(`home.nix:1163-1187`). No agent finds ai-mirror unless a person turned this on.

**5. Accessibility off.** Nothing nixarchy writes sets `GTK_MODULES`,
`QT_LINUX_ACCESSIBILITY_ALWAYS_ON` or `toolkit-accessibility`. ai-mirror already
switches accessibility on only while control is granted, and restores what it
changed (`control.py:125-147`), so an agent with control still gets its a11y
tools. A user's own accessibility settings are never written.

**6. Mode A.** All of it is behind `programs.nixarchy.enable`, as
`defaultPluginSet` already is (`home.nix:377`). Importing the NixOS module
without enabling nixarchy installs nothing and sets no variable.

## Order

Decision B lands **first**, as a PR in ai-mirror (the owner's repository), and
nixarchy then pins the commit that contains it. The intent's constraint, "the
human confirm lands upstream before this ships as a default", is already met by
ai-mirror #10 for every path the owner kept gated (MCP and the API).

## Alternatives rejected

- **A one-time code for the CLI confirm.** Designed here first: a code shown in
  the dialog, passed over stdin, and required by `confirm_request`. It would
  have raised a same-user agent's bar from two commands to reading another
  process's memory, but not removed it. The owner chose to document the limit
  instead of carrying that mechanism.
- **Enable upstream's Home Manager module and override it.** Three overrides,
  one of them a duplicate-plugin key clash, against two lines of our own.
- **Put ai-mirror behind `programs.nixarchy.mcp`.** The intent forbids it: that
  option is on for everyone.
- **A runtime check that the kill-switch bind exists before a grant.** It isn't
  needed. The widget that shows the dialog is also a stop, and a home without
  the widget cannot be asked.
- **Gate the widget behind an option.** The owner's decision was on every
  machine. `defaultPlugins.ai-mirror = false` is the off switch every default
  plugin has.

## Risks

- **A shell agent can grant itself control (Decision A).** Accepted, not
  mitigated. The manual and the MCP option say so, and the audit log records
  who asked. If this is revisited, the one-time code above is the design.
- **One more default plugin** moves #856's counts to nine and adds a
  `plugins.md` row. Those checks are why it cannot be forgotten.
- **Voice and ai-mirror share one pin.** A bump to either moves the helper
  both use. That is intended, and `checks.options` evaluates both.

## Verification

Each check is broken first and seen red (AGENTS.md §1).

- **Upstream (ai-mirror's own tests):**
  - the watching colour is the warning colour for 10 s after an `OBSERVING`
    call and not after.
- **nixarchy, evaluation (`checks.options`, both states):**
  - `programs.nixarchy.aiMirror.mcp` false → no `ai-mirror` in any agent's MCP
    config;
  - true → present in all three;
  - with nixarchy disabled → no ai-mirror package, variable or plugin (Mode A);
  - no `GTK_MODULES` or `QT_LINUX_ACCESSIBILITY_ALWAYS_ON` in any state.
- **nixarchy, the seed:** the build asserts the kill-switch line is in the seed
  `bindings.lua`, beside the other default binds.
- **nixarchy, the running session (`checks.session`):**
  - the widget is loaded;
  - an MCP `control confirm` is refused with `not_owner`, and the state stays
    `pending`;
  - an unanswered request lapses to `off` after 30 s;
  - the kill switch and a widget click each return control to `off`.

  This is the intent's "tested at runtime" requirement. The break for the
  first is an MCP caller treated as human (`by='human'` in `mcp.py:189`),
  which must turn the check red.
- **Voice (runtime, a session with voice enabled):** voice's process holds no
  MCP connection to ai-mirror, and ai-mirror's state stays `off` throughout a
  voice command.
- **#856's checks** go red until the count says nine and `plugins.md` has the
  row. That is proof they see the new default, and it is fixed in the same PR.
